#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TMP_DIR="$(mktemp -d)"

if [ -f "${TF_DIR}/.env" ]; then
  source "${TF_DIR}/.env"
fi

EKS_CONTEXT="${EKS_CONTEXT:-aws-eks-prod}"
ARGOCD_CLUSTER_NAME="${ARGOCD_CLUSTER_NAME:-aws-eks-prod}"
EKS_CLUSTER_NAME="${EKS_CLUSTER_NAME:-infrastructure-lab-eks-prod}"
SOURCE_K3S_CONTEXT="${SOURCE_K3S_CONTEXT:-}"
WORKLOAD_NAMESPACE="${WORKLOAD_NAMESPACE:-production}"
AWS_REGION="${AWS_REGION:-eu-central-1}"
ALLOW_NON_EPHEMERAL_PV_DESTROY="${ALLOW_NON_EPHEMERAL_PV_DESTROY:-false}"
BUDGET_ALERT_EMAIL="${BUDGET_ALERT_EMAIL:-}"

FAILED_STEP=""
BOOTSTRAP_CONTEXT=""

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
    tofu -chdir="${TF_DIR}" init -force-copy -input=false \
      -backend-config="bucket=${TF_BACKEND_BUCKET}" \
      -backend-config="key=${TF_BACKEND_KEY:-aws/terraform.tfstate}" \
      -backend-config="region=${AWS_REGION:-eu-central-1}" \
      -backend-config="dynamodb_table=${TF_BACKEND_LOCK_TABLE}" \
      -backend-config="encrypt=true"
  else
    log "Initializing with local/default backend..."
    tofu -chdir="${TF_DIR}" init -force-copy -input=false
  fi
}

tofu_phase12_args() {
  [ -n "${BUDGET_ALERT_EMAIL}" ] || die "BUDGET_ALERT_EMAIL must be set for FinOps budget alerts."
  [ -n "${TF_BACKEND_BUCKET}" ] || die "TF_BACKEND_BUCKET must be set."
  [ -n "${TF_BACKEND_LOCK_TABLE}" ] || die "TF_BACKEND_LOCK_TABLE must be set."

  printf '%s\n' \
    "-var=enable_cost_budget=true" \
    "-var=enable_eks=true" \
    "-var=enable_tofu_state_backend=true" \
    "-var=enable_github_actions_oidc=true" \
    "-var=tofu_state_bucket_name=${TF_BACKEND_BUCKET}" \
    "-var=tofu_state_lock_table_name=${TF_BACKEND_LOCK_TABLE}" \
    "-var=eks_node_instance_type=t3.micro" \
    "-var=eks_node_desired_size=2" \
    "-var=eks_node_max_size=3" \
    "-var=eks_endpoint_private_access=true" \
    "-var=budget_alert_email=${BUDGET_ALERT_EMAIL}"
}

ensure_kubeconfig_context() {
  log "Updating kubeconfig context ${EKS_CONTEXT} for cluster ${EKS_CLUSTER_NAME}..."
  aws eks update-kubeconfig \
    --name "${EKS_CLUSTER_NAME}" \
    --region "${AWS_REGION}" \
    --alias "${EKS_CONTEXT}" >/dev/null

  kubectl config get-contexts "${EKS_CONTEXT}" >/dev/null 2>&1 || \
    die "Kubeconfig context ${EKS_CONTEXT} was not created successfully."
}

ensure_argocd_cluster_registration() {
  require_cmd argocd

  kubectl config get-contexts "${EKS_CONTEXT}" >/dev/null 2>&1 || \
    die "Kubeconfig context ${EKS_CONTEXT} is missing. Run kubeconfig setup first."

  if argocd cluster get "${ARGOCD_CLUSTER_NAME}" --grpc-web >/dev/null 2>&1; then
    log "ArgoCD cluster ${ARGOCD_CLUSTER_NAME} already registered."
    return 0
  fi

  log "Registering ${EKS_CONTEXT} in ArgoCD as ${ARGOCD_CLUSTER_NAME}..."
  argocd cluster add "${EKS_CONTEXT}" \
    --name "${ARGOCD_CLUSTER_NAME}" \
    --yes \
    --upsert \
    --grpc-web >/dev/null
}

resolve_source_k3s_context() {
  if [ -n "${SOURCE_K3S_CONTEXT}" ]; then
    printf '%s\n' "${SOURCE_K3S_CONTEXT}"
    return 0
  fi

  if [ -n "${BOOTSTRAP_CONTEXT}" ] && [ "${BOOTSTRAP_CONTEXT}" != "${EKS_CONTEXT}" ]; then
    printf '%s\n' "${BOOTSTRAP_CONTEXT}"
    return 0
  fi

  local current_context
  current_context="$(kubectl config current-context 2>/dev/null || true)"

  [ -n "${current_context}" ] || \
    die "Unable to detect source K3s context. Set SOURCE_K3S_CONTEXT explicitly."

  [ "${current_context}" != "${EKS_CONTEXT}" ] || \
    die "SOURCE_K3S_CONTEXT resolved to ${EKS_CONTEXT}. Set SOURCE_K3S_CONTEXT to your local K3s context."

  printf '%s\n' "${current_context}"
}

discover_source_key_secret() {
  local source_context="$1"
  local -a secret_names=()

  mapfile -t secret_names < <(
    kubectl --context="${source_context}" -n kube-system get secret \
      -l sealedsecrets.bitnami.com/sealed-secrets-key=active \
      -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null | sed '/^$/d'
  )

  if [ "${#secret_names[@]}" -eq 0 ]; then
    mapfile -t secret_names < <(
      kubectl --context="${source_context}" -n kube-system get secret \
        -l sealedsecrets.bitnami.com/sealed-secrets-key \
        -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | sed '/^$/d'
    )
  fi

  case "${#secret_names[@]}" in
    0)
      die "No Sealed Secrets key found in source context ${source_context}."
      ;;
    1)
      printf '%s\n' "${secret_names[0]}"
      ;;
    *)
      die "Expected exactly one Sealed Secrets key in ${source_context}, found ${#secret_names[@]}: ${secret_names[*]}"
      ;;
  esac
}

migrate_sealed_secrets_key() {
  local source_context source_secret key_file source_tls_crt target_tls_crt applied_tls_crt
  source_context="$(resolve_source_k3s_context)"

  kubectl config get-contexts "${source_context}" >/dev/null 2>&1 || \
    die "Source context ${source_context} not found in kubeconfig."
  kubectl config get-contexts "${EKS_CONTEXT}" >/dev/null 2>&1 || \
    die "Target context ${EKS_CONTEXT} not found in kubeconfig."

  source_secret="$(discover_source_key_secret "${source_context}")"
  key_file="${TMP_DIR}/sealed-secrets-master-key.yaml"

  source_tls_crt="$(kubectl --context="${source_context}" -n kube-system get secret "${source_secret}" -o jsonpath='{.data.tls\.crt}')"
  [ -n "${source_tls_crt}" ] || \
    die "Source secret ${source_secret} in ${source_context} is missing tls.crt data."

  target_tls_crt="$(kubectl --context="${EKS_CONTEXT}" -n kube-system get secret "${source_secret}" -o jsonpath='{.data.tls\.crt}' 2>/dev/null || true)"

  if [ -n "${target_tls_crt}" ] && [ "${target_tls_crt}" = "${source_tls_crt}" ]; then
    log "Sealed Secrets key ${source_secret} is already present on ${EKS_CONTEXT}; skipping transfer."
    return 0
  fi

  kubectl --context="${source_context}" -n kube-system get secret "${source_secret}" -o json \
    | jq 'del(.metadata.resourceVersion,.metadata.uid,.metadata.creationTimestamp,.metadata.generation,.metadata.managedFields,.status)' \
    >"${key_file}"
  kubectl --context="${EKS_CONTEXT}" -n kube-system apply -f "${key_file}" >/dev/null

  applied_tls_crt="$(kubectl --context="${EKS_CONTEXT}" -n kube-system get secret "${source_secret}" -o jsonpath='{.data.tls\.crt}' 2>/dev/null || true)"

  [ "${applied_tls_crt}" = "${source_tls_crt}" ] || \
    die "Sealed Secrets key transfer verification failed for ${source_secret}."

  log "Sealed Secrets key ${source_secret} migrated from ${source_context} to ${EKS_CONTEXT}."
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
  run_step "update kubeconfig context" ensure_kubeconfig_context
  run_step "ArgoCD cluster registration" ensure_argocd_cluster_registration
  run_step "migrate Sealed Secrets key" migrate_sealed_secrets_key
}

command_down() {
  local -a tf_args
  mapfile -t tf_args < <(tofu_phase12_args)

  run_step "tofu init" tofu_init
  run_step "ArgoCD deregistration" argocd_deregister_cluster
  run_step "PV pre-destroy checks" check_non_ephemeral_pvs
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
  SOURCE_K3S_CONTEXT=<local-k3s-context>
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
  require_cmd jq

  BOOTSTRAP_CONTEXT="$(kubectl config current-context 2>/dev/null || true)"

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
