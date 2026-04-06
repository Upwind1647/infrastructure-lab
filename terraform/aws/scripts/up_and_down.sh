#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TMP_DIR="$(mktemp -d)"

EKS_CONTEXT="${EKS_CONTEXT:-aws-eks-prod}"
ARGOCD_CLUSTER_NAME="${ARGOCD_CLUSTER_NAME:-aws-eks-prod}"
EKS_CLUSTER_NAME="${EKS_CLUSTER_NAME:-infrastructure-lab-eks-prod}"
WORKLOAD_NAMESPACE="${WORKLOAD_NAMESPACE:-production}"
AWS_REGION="${AWS_REGION:-eu-central-1}"
ALLOW_NON_EPHEMERAL_PV_DESTROY="${ALLOW_NON_EPHEMERAL_PV_DESTROY:-false}"
BUDGET_ALERT_EMAIL="${BUDGET_ALERT_EMAIL:-}"

FAILED_STEP=""

log() {
  printf '[INFO] %s\n' "$*"
}

warn() {
  printf '[WARN] %s\n' "$*" >&2
}

die() {
  printf '[ERROR] %s\n' "$*" >&2
  exit 1
}

cleanup() {
  local exit_code=$?
  rm -rf "${TMP_DIR}"

  if [ "${exit_code}" -ne 0 ]; then
    warn "Script failed during step: ${FAILED_STEP:-unknown}"
    warn "Re-run the command after fixing the failed dependency."
  fi
}

trap cleanup EXIT

require_cmd() {
  local cmd="$1"
  command -v "${cmd}" >/dev/null 2>&1 || die "Required command not found: ${cmd}"
}

run_step() {
  local step="$1"
  shift
  FAILED_STEP="${step}"
  "$@"
  FAILED_STEP=""
}

tofu_init() {
  if [ -n "${TF_BACKEND_BUCKET:-}" ]; then
    log "Initializing with S3 backend config..."
    tofu -chdir="${TF_DIR}" init -input=false \
      -backend-config="bucket=${TF_BACKEND_BUCKET}" \
      -backend-config="key=${TF_BACKEND_KEY:-aws/terraform.tfstate}" \
      -backend-config="region=${AWS_REGION:-eu-central-1}" \
      -backend-config="dynamodb_table=${TF_BACKEND_LOCK_TABLE}" \
      -backend-config="encrypt=true"
  else
    log "Initializing with local/default backend..."
    tofu -chdir="${TF_DIR}" init -input=false
  fi
}

tofu_phase12_args() {
  [ -n "${BUDGET_ALERT_EMAIL}" ] || die "BUDGET_ALERT_EMAIL must be set for FinOps budget alerts."

  printf '%s\n' \
    "-var=enable_cost_budget=true" \
    "-var=enable_eks=true" \
    "-var=budget_alert_email=${BUDGET_ALERT_EMAIL}"
}

argocd_deregister_cluster() {
  if ! command -v argocd >/dev/null 2>&1; then
    warn "argocd CLI is not installed. Skipping cluster deregistration."
    return 0
  fi

  if argocd cluster rm "${ARGOCD_CLUSTER_NAME}" --yes --grpc-web >/dev/null 2>&1; then
    log "Deregistered cluster ${ARGOCD_CLUSTER_NAME} from ArgoCD."
  else
    warn "ArgoCD cluster deregistration skipped or cluster not found: ${ARGOCD_CLUSTER_NAME}."
  fi
}

check_non_ephemeral_pvs() {
  if ! kubectl config get-contexts "${EKS_CONTEXT}" >/dev/null 2>&1; then
    warn "Kube context ${EKS_CONTEXT} not found. Skipping PV pre-check."
    return 0
  fi

  local report_file="${TMP_DIR}/pv-report.txt"
  kubectl --context="${EKS_CONTEXT}" get pv \
    -o jsonpath='{range .items[*]}{.metadata.name}{"|"}{.spec.persistentVolumeReclaimPolicy}{"|"}{.status.phase}{"\n"}{end}' \
    >"${report_file}" || true

  local flagged
  flagged="$(awk -F'|' '$2 != "Delete" && ($3 == "Bound" || $3 == "Released") {print}' "${report_file}")"

  if [ -n "${flagged}" ]; then
    warn "Detected non-ephemeral PVs (reclaimPolicy != Delete):"
    printf '%s\n' "${flagged}" >&2

    if [ "${ALLOW_NON_EPHEMERAL_PV_DESTROY}" != "true" ]; then
      die "Set ALLOW_NON_EPHEMERAL_PV_DESTROY=true to continue with destroy."
    fi
  fi
}

cordon_and_drain_nodes() {
  local nodes
  nodes="$(kubectl --context="${EKS_CONTEXT}" get nodes -o name 2>/dev/null || true)"

  if [ -z "${nodes}" ]; then
    warn "No nodes found for context ${EKS_CONTEXT}. Skipping cordon/drain."
    return 0
  fi

  while IFS= read -r node; do
    [ -z "${node}" ] && continue
    kubectl --context="${EKS_CONTEXT}" cordon "${node}" || true
    kubectl --context="${EKS_CONTEXT}" drain "${node}" \
      --ignore-daemonsets \
      --delete-emptydir-data \
      --force \
      --grace-period=30 \
      --timeout=180s || true
  done <<<"${nodes}"
}

delete_ephemeral_workloads() {
  kubectl --context="${EKS_CONTEXT}" -n "${WORKLOAD_NAMESPACE}" delete pvc --all --ignore-not-found

  local lb_services
  lb_services="$(kubectl --context="${EKS_CONTEXT}" get svc -A \
    -o jsonpath='{range .items[?(@.spec.type=="LoadBalancer")]}{.metadata.namespace}{"/"}{.metadata.name}{"\n"}{end}')"

  if [ -z "${lb_services}" ]; then
    log "No LoadBalancer services found."
    return 0
  fi

  while IFS='/' read -r namespace name; do
    [ -z "${namespace}" ] && continue
    [ -z "${name}" ] && continue
    kubectl --context="${EKS_CONTEXT}" -n "${namespace}" delete svc "${name}" --ignore-not-found
  done <<<"${lb_services}"
}

wait_for_elb_cleanup() {
  local retries=40
  local sleep_seconds=15

  for _ in $(seq 1 "${retries}"); do
    local count
    count="$(aws resourcegroupstaggingapi get-resources \
      --region "${AWS_REGION}" \
      --resource-type-filters elasticloadbalancing:loadbalancer \
      --tag-filters "Key=kubernetes.io/cluster/${EKS_CLUSTER_NAME}" \
      --query 'length(ResourceTagMappingList)' \
      --output text 2>/dev/null || echo 0)"

    if [ "${count}" = "0" ]; then
      log "No cluster-tagged ELB resources remain."
      return 0
    fi

    log "Waiting for ELB cleanup (${count} remaining)..."
    sleep "${sleep_seconds}"
  done

  die "Timed out waiting for ELB cleanup. Resolve ELB dependencies before destroy."
}

command_up() {
  local -a tf_args
  mapfile -t tf_args < <(tofu_phase12_args)

  run_step "tofu init" tofu_init
  run_step "tofu apply" tofu -chdir="${TF_DIR}" apply -auto-approve "${tf_args[@]}"
}

command_down() {
  local -a tf_args
  mapfile -t tf_args < <(tofu_phase12_args)

  run_step "tofu init" tofu_init
  run_step "ArgoCD deregistration" argocd_deregister_cluster
  run_step "PV pre-destroy checks" check_non_ephemeral_pvs
  run_step "cordon and drain" cordon_and_drain_nodes
  run_step "delete PVCs and LoadBalancers" delete_ephemeral_workloads
  run_step "wait for ELB cleanup" wait_for_elb_cleanup
  run_step "tofu destroy" tofu -chdir="${TF_DIR}" destroy -auto-approve "${tf_args[@]}"
}

usage() {
  cat <<EOF
Usage: $(basename "$0") <up|down>

Environment overrides:
  EKS_CONTEXT=aws-eks-prod
  ARGOCD_CLUSTER_NAME=aws-eks-prod
  EKS_CLUSTER_NAME=infrastructure-lab-eks-prod
  WORKLOAD_NAMESPACE=production
  AWS_REGION=eu-central-1
  ALLOW_NON_EPHEMERAL_PV_DESTROY=false
  BUDGET_ALERT_EMAIL=operator@example.com
EOF
}

main() {
  [ "$#" -eq 1 ] || { usage; exit 1; }

  require_cmd tofu
  require_cmd kubectl
  require_cmd aws

  case "$1" in
    up)
      command_up
      ;;
    down)
      command_down
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"
