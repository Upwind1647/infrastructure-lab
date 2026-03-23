#!/usr/bin/env bash
set -euo pipefail

CERT_MANAGER_VERSION="v1.20.0"
CERT_MANAGER_MANIFEST_URL="https://github.com/cert-manager/cert-manager/releases/download/${CERT_MANAGER_VERSION}/cert-manager.yaml"
NETWORK_CONNECT_TIMEOUT="10"
NETWORK_MAX_TIME="60"
ROLLOUT_TIMEOUT="300s"
CLUSTER_ISSUER_MANIFEST="deploy/k8s/cluster-issuer-dns.yaml"

cleanup() {
    if [[ -n "${CERT_MANAGER_TMP_FILE:-}" && -f "${CERT_MANAGER_TMP_FILE}" ]]; then
        rm -f "${CERT_MANAGER_TMP_FILE}"
    fi
}

trap cleanup EXIT

log() {
    printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

log "Installing K3s addons..."

# 1. Pre-Flight Check
if ! kubectl cluster-info >/dev/null 2>&1; then
    echo "ERROR: kubectl cannot reach a Kubernetes cluster." >&2
    exit 1
fi

# 2. Install cert-manager
log "Applying cert-manager manifest (${CERT_MANAGER_VERSION})..."
CERT_MANAGER_TMP_FILE="$(mktemp)"
curl --fail --location --silent --show-error \
    --connect-timeout "${NETWORK_CONNECT_TIMEOUT}" \
    --max-time "${NETWORK_MAX_TIME}" \
    --retry 3 \
    --retry-all-errors \
    --output "${CERT_MANAGER_TMP_FILE}" \
    "${CERT_MANAGER_MANIFEST_URL}"
kubectl apply -f "${CERT_MANAGER_TMP_FILE}"

# 3. Wait for Webhooks and Controllers to be available
log "Waiting for cert-manager deployments to become available..."
for deploy in cert-manager cert-manager-cainjector cert-manager-webhook; do
    kubectl rollout status deployment/"${deploy}" -n cert-manager --timeout="${ROLLOUT_TIMEOUT}"
done

# 4. Check for Cloudflare Secret
log "Checking for Cloudflare API token secret..."
if ! kubectl get secret cloudflare-api-token-secret -n cert-manager >/dev/null 2>&1; then
    echo "ERROR: Cloudflare API Token Secret not found in namespace cert-manager"
    echo "kubectl create secret generic cloudflare-api-token-secret \\"
    echo "  --namespace=cert-manager \\"
    echo "  --from-literal=api-token='CLOUDFLARE_API_TOKEN'"
    exit 1
fi

# 5. Apply the ClusterIssuer
if [[ -f "${CLUSTER_ISSUER_MANIFEST}" ]]; then
    log "Applying ClusterIssuer manifest: ${CLUSTER_ISSUER_MANIFEST}"
    kubectl apply -f "${CLUSTER_ISSUER_MANIFEST}"
else
    log "WARNING: ClusterIssuer manifest not found at ${CLUSTER_ISSUER_MANIFEST}; skipping."
fi

log "K3s addons installed successfully."
