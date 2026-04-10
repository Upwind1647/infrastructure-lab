#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${ROOT_DIR}/terraform/cloudflare"
OUTPUT_FILE="${ROOT_DIR}/gitops/secrets/cloudflare-tunnel-credentials-sealedsecret.yaml"

KUBE_CONTEXT="${KUBE_CONTEXT:-}"
TUNNEL_NAMESPACE="${TUNNEL_NAMESPACE:-cloudflare-tunnel}"
SECRET_NAME="${SECRET_NAME:-cloudflare-tunnel-credentials}"
SEALED_SECRETS_NAMESPACE="${SEALED_SECRETS_NAMESPACE:-kube-system}"
SEALED_SECRETS_NAME="${SEALED_SECRETS_NAME:-sealed-secrets}"
APPLY_NOW="${APPLY_NOW:-false}"

log() {
  printf '[INFO] %s\n' "$*"
}

die() {
  printf '[ERROR] %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

read_tfvar_string() {
  local key="$1"
  local tfvars_file="${TF_DIR}/terraform.tfvars"

  [ -f "${tfvars_file}" ] || return 0

  sed -n -E "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*\"(.*)\"[[:space:]]*$/\1/p" "${tfvars_file}" | head -n1
}

build_kube_context_args() {
  local -n args_ref=$1
  args_ref=()
  if [ -n "${KUBE_CONTEXT}" ]; then
    args_ref+=(--context "${KUBE_CONTEXT}")
  fi
}

require_cmd tofu
require_cmd jq
require_cmd kubectl
require_cmd kubeseal

ACCOUNT_ID="${CF_ACCOUNT_ID:-$(read_tfvar_string cloudflare_account_id)}"
TUNNEL_SECRET="${CF_TUNNEL_SECRET:-$(read_tfvar_string tunnel_secret)}"

[ -n "${ACCOUNT_ID}" ] || die "CF_ACCOUNT_ID is required (env) or cloudflare_account_id must exist in terraform/cloudflare/terraform.tfvars."
[ -n "${TUNNEL_SECRET}" ] || die "CF_TUNNEL_SECRET is required (env) or tunnel_secret must exist in terraform/cloudflare/terraform.tfvars."

if ! printf '%s' "${TUNNEL_SECRET}" | grep -Eq '^[A-Za-z0-9+/]+={0,2}$'; then
  die "CF_TUNNEL_SECRET must be base64-encoded."
fi

TUNNEL_ID="$(tofu -chdir="${TF_DIR}" output -raw tunnel_id 2>/dev/null || true)"
[ -n "${TUNNEL_ID}" ] || die "Unable to read tunnel_id from terraform/cloudflare outputs. Run tofu init/plan/apply there first."

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

CREDENTIALS_FILE="${TMP_DIR}/credentials.json"

jq -n \
  --arg account "${ACCOUNT_ID}" \
  --arg tunnel_secret "${TUNNEL_SECRET}" \
  --arg tunnel_id "${TUNNEL_ID}" \
  '{AccountTag: $account, TunnelSecret: $tunnel_secret, TunnelID: $tunnel_id}' > "${CREDENTIALS_FILE}"

build_kube_context_args KUBE_ARGS

log "Sealing credentials for tunnel ${TUNNEL_ID}"
kubectl "${KUBE_ARGS[@]}" create secret generic "${SECRET_NAME}" \
  --namespace "${TUNNEL_NAMESPACE}" \
  --from-file=credentials.json="${CREDENTIALS_FILE}" \
  --dry-run=client -o json | \
kubeseal "${KUBE_ARGS[@]}" \
  --controller-name "${SEALED_SECRETS_NAME}" \
  --controller-namespace "${SEALED_SECRETS_NAMESPACE}" \
  --format yaml > "${OUTPUT_FILE}"

log "Wrote ${OUTPUT_FILE}"

if [ "${APPLY_NOW}" = "true" ]; then
  log "Applying sealed secret and restarting cloudflare-tunnel deployment"
  kubectl "${KUBE_ARGS[@]}" apply -f "${OUTPUT_FILE}"
  kubectl "${KUBE_ARGS[@]}" -n "${TUNNEL_NAMESPACE}" rollout restart deploy/cloudflare-tunnel
fi

log "Done. Commit ${OUTPUT_FILE} so ArgoCD can reconcile the updated credentials."
