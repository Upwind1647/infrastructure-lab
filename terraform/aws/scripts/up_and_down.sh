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

  local current_ip
  current_ip="$(curl -s4 ifconfig.me 2>/dev/null || curl -s4 api.ipify.org 2>/dev/null || true)"
  [ -n "${current_ip}" ] || die "Failed to determine your public IP address. Check your internet connection."
  log "Detected current public IP: ${current_ip} - Securing EKS API..." >&2

  printf '%s\n' \
    "-var=enable_cost_budget=true" \
    "-var=enable_eks=true" \
    "-var=enable_tofu_state_backend=true" \
    "-var=enable_github_actions_oidc=true" \
    "-var=tofu_state_bucket_name=${TF_BACKEND_BUCKET}" \
    "-var=tofu_state_lock_table_name=${TF_BACKEND_LOCK_TABLE}" \
    "-var=eks_node_instance_type=t3.medium" \
    "-var=eks_node_desired_size=2" \
    "-var=eks_node_max_size=3" \
    "-var=eks_endpoint_public_access=true" \
    "-var=eks_endpoint_private_access=true" \
    "-var=home_ip=${current_ip}/32" \
    "-var=budget_alert_email=${BUDGET_ALERT_EMAIL}"
}

current_aws_caller_arn() {
  local caller_arn
  caller_arn="$(aws sts get-caller-identity --query Arn --output text 2>/dev/null || true)"

  [ -n "${caller_arn}" ] || return 1
  [ "${caller_arn}" != "None" ] || return 1
  [ "${caller_arn}" != "null" ] || return 1

  printf '%s\n' "${caller_arn}"
}

use_terraform_eks_admin_credentials() {
  log "Switching to Terraform EKS admin credentials..."
  export ORIG_AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-}"
  export ORIG_AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-}"
  export ORIG_AWS_SESSION_TOKEN="${AWS_SESSION_TOKEN:-}"

  local access_key secret_key
  access_key="$(tofu -chdir="${TF_DIR}" output -raw eks_admin_access_key 2>/dev/null || true)"
  secret_key="$(tofu -chdir="${TF_DIR}" output -raw eks_admin_secret_key 2>/dev/null || true)"

  [ -n "${access_key}" ] || return 1
  [ -n "${secret_key}" ] || return 1
  [ "${access_key}" != "None" ] || return 1
  [ "${secret_key}" != "None" ] || return 1
  [ "${access_key}" != "null" ] || return 1
  [ "${secret_key}" != "null" ] || return 1

  export AWS_ACCESS_KEY_ID="${access_key}"
  export AWS_SECRET_ACCESS_KEY="${secret_key}"
  unset AWS_SESSION_TOKEN
}

restore_original_credentials() {
  log "Restoring original AWS credentials..."
  if [ -n "${ORIG_AWS_ACCESS_KEY_ID:-}" ]; then
    export AWS_ACCESS_KEY_ID="${ORIG_AWS_ACCESS_KEY_ID}"
    export AWS_SECRET_ACCESS_KEY="${ORIG_AWS_SECRET_ACCESS_KEY}"
    export AWS_SESSION_TOKEN="${ORIG_AWS_SESSION_TOKEN:-}"
  else
    unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
  fi
}

wait_for_eks_kubectl_auth() {
  local retries="${1:-24}"
  local sleep_seconds="${2:-5}"
  local attempt=1

  while [ "${attempt}" -le "${retries}" ]; do
    if kubectl --context "${EKS_CONTEXT}" get namespace kube-system >/dev/null 2>&1; then
      return 0
    fi

    sleep "${sleep_seconds}"
    attempt=$((attempt + 1))
  done

  return 1
}

update_eks_kubeconfig_alias() {
  aws eks update-kubeconfig \
    --name "${EKS_CLUSTER_NAME}" \
    --region "${AWS_REGION}" \
    --alias "${EKS_CONTEXT}" >/dev/null

  kubectl config get-contexts "${EKS_CONTEXT}" >/dev/null 2>&1 || \
    die "Kubeconfig context ${EKS_CONTEXT} was not created successfully."
}

ensure_kubeconfig_context() {
  local caller_arn

  log "Updating kubeconfig context ${EKS_CONTEXT} for cluster ${EKS_CLUSTER_NAME}..."
  caller_arn="$(current_aws_caller_arn || true)"
  if [ -n "${caller_arn}" ]; then
    log "Current AWS caller ARN: ${caller_arn}"
  else
    warn "Unable to determine current AWS caller ARN."
  fi

  update_eks_kubeconfig_alias

  if wait_for_eks_kubectl_auth 6 5; then
    return 0
  fi

  warn "Kubernetes auth for ${EKS_CONTEXT} failed with current AWS identity. Falling back to Terraform EKS admin credentials."

  if ! use_terraform_eks_admin_credentials; then
    die "Authentication failed and Terraform outputs eks_admin_access_key or eks_admin_secret_key are missing/empty. Run tofu apply first or export an AWS identity authorized for cluster ${EKS_CLUSTER_NAME}."
  fi

  caller_arn="$(current_aws_caller_arn || true)"
  if [ -n "${caller_arn}" ]; then
    log "Current AWS caller ARN after Terraform credential switch: ${caller_arn}"
  else
    warn "Unable to determine AWS caller ARN after Terraform credential switch."
  fi

  update_eks_kubeconfig_alias
  wait_for_eks_kubectl_auth 24 5 || \
    die "Still unauthenticated to ${EKS_CONTEXT} after Terraform EKS admin credential fallback. Wait for IAM access propagation and verify the EKS access entry/policy association for the terraform-created admin IAM user."
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

ensure_argocd_cluster_registration() {
  log "Registering EKS cluster in ArgoCD via declarative Kubernetes Secret..."
  local source_context
  source_context="$(resolve_source_k3s_context)"

  kubectl --context "${source_context}" get namespace argocd >/dev/null 2>&1 || \
    die "Source context ${source_context} cannot access namespace argocd. Ensure ArgoCD is installed and your credentials for that context can reach the namespace."

  log "Creating argocd-manager ServiceAccount in EKS (${EKS_CONTEXT})..."
  kubectl --context "${EKS_CONTEXT}" apply --validate=false -f - >/dev/null <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: argocd-manager
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: argocd-manager-admin-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: argocd-manager
  namespace: kube-system
---
apiVersion: v1
kind: Secret
metadata:
  name: argocd-manager-long-lived-token
  namespace: kube-system
  annotations:
    kubernetes.io/service-account.name: argocd-manager
type: kubernetes.io/service-account-token
EOF

  log "Waiting for token controller to populate argocd-manager-long-lived-token..."
  local retries=0
  until kubectl --context "${EKS_CONTEXT}" -n kube-system \
    get secret argocd-manager-long-lived-token \
    -o jsonpath='{.data.token}' 2>/dev/null | grep -q .; do
    retries=$((retries + 1))
    [[ $retries -ge 15 ]] && \
      die "Timed out waiting for argocd-manager token to be populated after 30s."
    sleep 2
  done
  log "Token populated (${retries} retries)."

  local eks_server eks_ca eks_token
  eks_server=$(kubectl --context "${EKS_CONTEXT}" config view --minify --raw -o jsonpath='{.clusters[0].cluster.server}')
  eks_ca=$(kubectl --context "${EKS_CONTEXT}" config view --minify --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')
  eks_token=$(kubectl --context "${EKS_CONTEXT}" -n kube-system \
    get secret argocd-manager-long-lived-token \
    -o jsonpath='{.data.token}' | base64 -d)

  [[ -z "$eks_server" || -z "$eks_ca" || -z "$eks_token" ]] && \
    die "Failed to extract EKS cluster credentials. Check kubeconfig and EKS connectivity."

  log "Creating ArgoCD Cluster Secret in Hub (${source_context})..."
  kubectl --context "${source_context}" -n argocd apply -f - >/dev/null <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ${ARGOCD_CLUSTER_NAME}-cluster
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: cluster
type: Opaque
stringData:
  name: ${ARGOCD_CLUSTER_NAME}
  server: ${eks_server}
  config: |
    {
      "bearerToken": "${eks_token}",
      "tlsClientConfig": {
        "insecure": false,
        "caData": "${eks_ca}"
      }
    }
EOF
  log "EKS cluster '${ARGOCD_CLUSTER_NAME}' successfully registered in ArgoCD."
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
  local source_context source_secret source_tls_crt source_tls_key source_type target_tls_crt applied_tls_crt
  source_context="$(resolve_source_k3s_context)"

  kubectl config get-contexts "${source_context}" >/dev/null 2>&1 || \
    die "Source context ${source_context} not found in kubeconfig."
  kubectl config get-contexts "${EKS_CONTEXT}" >/dev/null 2>&1 || \
    die "Target context ${EKS_CONTEXT} not found in kubeconfig."

  source_secret="$(discover_source_key_secret "${source_context}")"

  source_tls_crt="$(kubectl --context="${source_context}" -n kube-system get secret "${source_secret}" -o jsonpath='{.data.tls\.crt}')"
  source_tls_key="$(kubectl --context="${source_context}" -n kube-system get secret "${source_secret}" -o jsonpath='{.data.tls\.key}')"
  source_type="$(kubectl --context="${source_context}" -n kube-system get secret "${source_secret}" -o jsonpath='{.type}')"

  [ -n "${source_tls_crt}" ] && [ -n "${source_tls_key}" ] || \
    die "Source secret ${source_secret} in ${source_context} is missing tls.crt or tls.key data."

  target_tls_crt="$(kubectl --context="${EKS_CONTEXT}" -n kube-system get secret "${source_secret}" -o jsonpath='{.data.tls\.crt}' 2>/dev/null || true)"

  if [ -n "${target_tls_crt}" ] && [ "${target_tls_crt}" = "${source_tls_crt}" ]; then
    log "Sealed Secrets key ${source_secret} is already present on ${EKS_CONTEXT}; skipping transfer."
    return 0
  fi

  cat <<EOF | kubectl --context="${EKS_CONTEXT}" apply -f - >/dev/null
apiVersion: v1
kind: Secret
metadata:
  name: ${source_secret}
  namespace: kube-system
  labels:
    sealedsecrets.bitnami.com/sealed-secrets-key: "active"
type: ${source_type}
data:
  tls.crt: ${source_tls_crt}
  tls.key: ${source_tls_key}
EOF

  applied_tls_crt="$(kubectl --context="${EKS_CONTEXT}" -n kube-system get secret "${source_secret}" -o jsonpath='{.data.tls\.crt}' 2>/dev/null || true)"

  [ "${applied_tls_crt}" = "${source_tls_crt}" ] || \
    die "Sealed Secrets key transfer verification failed for ${source_secret}."

  log "Sealed Secrets key ${source_secret} migrated cleanly from ${source_context} to ${EKS_CONTEXT}."
}

argocd_deregister_cluster() {
  local source_context
  source_context="$(resolve_source_k3s_context)"

  if kubectl --context="${source_context}" -n argocd delete secret "${ARGOCD_CLUSTER_NAME}-cluster" --ignore-not-found >/dev/null 2>&1; then
    log "Deregistered cluster ${ARGOCD_CLUSTER_NAME} from ArgoCD (deleted declarative secret)."
  else
    warn "Failed to deregister cluster ${ARGOCD_CLUSTER_NAME} from ArgoCD."
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
  run_step "tofu apply" tofu -chdir="${TF_DIR}" apply -auto-approve -lock=false "${tf_args[@]}"

  run_step "update kubeconfig context" ensure_kubeconfig_context
  run_step "ArgoCD cluster registration" ensure_argocd_cluster_registration
  run_step "migrate Sealed Secrets key" migrate_sealed_secrets_key

  run_step "restore AWS credentials" restore_original_credentials
}

command_down() {
  local -a tf_args
  mapfile -t tf_args < <(tofu_phase12_args)

  run_step "tofu init" tofu_init

  run_step "setup EKS admin credentials" use_terraform_eks_admin_credentials

  run_step "ArgoCD deregistration" argocd_deregister_cluster
  run_step "PV pre-destroy checks" check_non_ephemeral_pvs
  run_step "delete PVCs and LoadBalancers" delete_ephemeral_workloads

  run_step "restore AWS credentials" restore_original_credentials

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
