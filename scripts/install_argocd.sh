#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
RELEASE_NAME="${ARGOCD_RELEASE_NAME:-argocd}"
VALUES_FILE="${ARGOCD_VALUES_FILE:-deploy/k8s/argocd-values.yaml}"
HELM_REPO_NAME="argo"
HELM_REPO_URL="https://argoproj.github.io/argo-helm"
ROLLOUT_TIMEOUT="${ARGOCD_ROLLOUT_TIMEOUT:-300s}"

log() {
    printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

require_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "ERROR: required command not found: $1" >&2
        exit 1
    fi
}

log "Installing ArgoCD via Helm..."

require_cmd kubectl
require_cmd helm

if [[ ! -f "${VALUES_FILE}" ]]; then
    echo "ERROR: values file not found: ${VALUES_FILE}" >&2
    exit 1
fi

if ! kubectl cluster-info >/dev/null 2>&1; then
    echo "ERROR: kubectl cannot reach a Kubernetes cluster." >&2
    exit 1
fi

log "Ensuring namespace ${NAMESPACE} exists..."
kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1 || kubectl create namespace "${NAMESPACE}"

log "Configuring Helm repository ${HELM_REPO_NAME}..."
helm repo add "${HELM_REPO_NAME}" "${HELM_REPO_URL}" >/dev/null 2>&1 || true
helm repo update >/dev/null

log "Running Helm upgrade --install for ${RELEASE_NAME}..."
HELM_ARGS=(
    upgrade --install "${RELEASE_NAME}" "${HELM_REPO_NAME}/argo-cd"
    --namespace "${NAMESPACE}"
    --values "${VALUES_FILE}"
    --wait
    --timeout "${ROLLOUT_TIMEOUT}"
)

if [[ -n "${ARGOCD_CHART_VERSION:-}" ]]; then
    HELM_ARGS+=(--version "${ARGOCD_CHART_VERSION}")
fi

helm "${HELM_ARGS[@]}"

log "Waiting for ArgoCD control-plane readiness..."
kubectl wait --for=condition=Available deployment/argocd-server -n "${NAMESPACE}" --timeout="${ROLLOUT_TIMEOUT}"
kubectl wait --for=condition=Available deployment/argocd-repo-server -n "${NAMESPACE}" --timeout="${ROLLOUT_TIMEOUT}"
kubectl wait --for=condition=Available deployment/argocd-applicationset-controller -n "${NAMESPACE}" --timeout="${ROLLOUT_TIMEOUT}"
kubectl rollout status statefulset/argocd-application-controller -n "${NAMESPACE}" --timeout="${ROLLOUT_TIMEOUT}"

log "ArgoCD is installed. Bootstrap applications with:"
log "kubectl apply -f gitops/apps/root.yaml"
