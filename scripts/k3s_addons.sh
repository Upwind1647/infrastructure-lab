#!/usr/bin/env bash
set -euo pipefail

CERT_MANAGER_VERSION="v1.20.0"
CLUSTER_ISSUER_MANIFEST="deploy/k8s/cluster-issuer.yaml"

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
kubectl apply -f "https://github.com/cert-manager/cert-manager/releases/download/${CERT_MANAGER_VERSION}/cert-manager.yaml"

# 3. Wait for Webhooks and Controllers to be available
log "Waiting for cert-manager deployments to become available..."
kubectl wait --namespace cert-manager \
    --for=condition=Available deployment \
    --all \
    --timeout=300s

# 4. Apply the ClusterIssuer
if [[ -f "${CLUSTER_ISSUER_MANIFEST}" ]]; then
    log "Applying ClusterIssuer manifest: ${CLUSTER_ISSUER_MANIFEST}"
    kubectl apply -f "${CLUSTER_ISSUER_MANIFEST}"
else
    log "WARNING: ClusterIssuer manifest not found at ${CLUSTER_ISSUER_MANIFEST}; skipping."
fi

log "K3s addons installed successfully."
