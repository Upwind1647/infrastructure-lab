#!/usr/bin/env bash
set -euo pipefail

# Generates SealedSecrets required for Phase 14 rollout + DORA wiring.
# Usage examples:
#   DEPLOY_EVENT_TOKEN=... \
#   STATUS_API_DB_URL=postgresql+psycopg://... \
#   ./scripts/generate_phase14_sealed_secrets.sh --profile aws --status-api-namespace production
#
#   DEPLOY_EVENT_TOKEN=... \
#   GRAFANA_POSTGRES_HOST=postgresql.monitoring.svc.cluster.local \
#   GRAFANA_POSTGRES_PORT=5432 \
#   GRAFANA_POSTGRES_DATABASE=appdb \
#   GRAFANA_POSTGRES_USERNAME=grafana_reader \
#   GRAFANA_POSTGRES_PASSWORD=... \
#   ./scripts/generate_phase14_sealed_secrets.sh --profile lab --status-api-namespace default

PROFILE=""
KUBE_CONTEXT=""
STATUS_API_NAMESPACE="default"
MONITORING_NAMESPACE="monitoring"
OUTPUT_DIR="gitops/secrets"
CONTROLLER_NAME="sealed-secrets"
CONTROLLER_NAMESPACE="kube-system"

usage() {
  cat <<EOF
Generate Phase 14 SealedSecrets.

Required:
  --profile <lab|aws>               Profile suffix for output file names.

Optional:
  --kube-context <context>          kubectl context to use.
  --status-api-namespace <ns>       Namespace for status-api secrets. Default: default.
  --monitoring-namespace <ns>       Namespace for Grafana datasource secret. Default: monitoring.
  --output-dir <path>               Output directory for manifests. Default: gitops/secrets.
  --controller-name <name>          Sealed Secrets controller name. Default: sealed-secrets.
  --controller-namespace <ns>       Sealed Secrets controller namespace. Default: kube-system.

Environment variables:
  Required:
    DEPLOY_EVENT_TOKEN

  Optional:
    STATUS_API_DB_URL
    GRAFANA_POSTGRES_HOST
    GRAFANA_POSTGRES_PORT
    GRAFANA_POSTGRES_DATABASE
    GRAFANA_POSTGRES_USERNAME
    GRAFANA_POSTGRES_PASSWORD
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --profile)
      PROFILE="$2"
      shift 2
      ;;
    --kube-context)
      KUBE_CONTEXT="$2"
      shift 2
      ;;
    --status-api-namespace)
      STATUS_API_NAMESPACE="$2"
      shift 2
      ;;
    --monitoring-namespace)
      MONITORING_NAMESPACE="$2"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --controller-name)
      CONTROLLER_NAME="$2"
      shift 2
      ;;
    --controller-namespace)
      CONTROLLER_NAMESPACE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [ -z "$PROFILE" ]; then
  echo "--profile is required" >&2
  usage
  exit 1
fi

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl is required" >&2
  exit 1
fi

if ! command -v kubeseal >/dev/null 2>&1; then
  echo "kubeseal is required" >&2
  exit 1
fi

if [ -z "${DEPLOY_EVENT_TOKEN:-}" ]; then
  echo "DEPLOY_EVENT_TOKEN is required" >&2
  exit 1
fi

KUBECTL_CMD=(kubectl)
if [ -n "$KUBE_CONTEXT" ]; then
  KUBECTL_CMD+=(--context "$KUBE_CONTEXT")
fi

mkdir -p "$OUTPUT_DIR"

seal_literal_secret() {
  local secret_name="$1"
  local namespace="$2"
  local key="$3"
  local value="$4"
  local output_file="$5"

  "${KUBECTL_CMD[@]}" create secret generic "$secret_name" \
    --namespace "$namespace" \
    --from-literal "$key=$value" \
    --dry-run=client -o json \
  | kubeseal \
      --controller-name "$CONTROLLER_NAME" \
      --controller-namespace "$CONTROLLER_NAMESPACE" \
      --format yaml \
  > "$output_file"
}

echo "Generating status-api deployment-event token SealedSecret..."
seal_literal_secret \
  "status-api-deploy-event-token" \
  "$STATUS_API_NAMESPACE" \
  "token" \
  "$DEPLOY_EVENT_TOKEN" \
  "$OUTPUT_DIR/status-api-deploy-event-token-${PROFILE}.yaml"

if [ -n "${STATUS_API_DB_URL:-}" ]; then
  echo "Generating status-api database URL SealedSecret..."
  seal_literal_secret \
    "status-api-db" \
    "$STATUS_API_NAMESPACE" \
    "url" \
    "$STATUS_API_DB_URL" \
    "$OUTPUT_DIR/status-api-db-${PROFILE}.yaml"
else
  echo "Skipping status-api database URL secret (STATUS_API_DB_URL not set)."
fi

if [ -n "${GRAFANA_POSTGRES_HOST:-}" ] && [ -n "${GRAFANA_POSTGRES_PORT:-}" ] && [ -n "${GRAFANA_POSTGRES_DATABASE:-}" ] && [ -n "${GRAFANA_POSTGRES_USERNAME:-}" ] && [ -n "${GRAFANA_POSTGRES_PASSWORD:-}" ]; then
  echo "Generating Grafana PostgreSQL datasource SealedSecret..."
  "${KUBECTL_CMD[@]}" create secret generic "grafana-postgres-datasource" \
    --namespace "$MONITORING_NAMESPACE" \
    --from-literal "host=$GRAFANA_POSTGRES_HOST" \
    --from-literal "port=$GRAFANA_POSTGRES_PORT" \
    --from-literal "database=$GRAFANA_POSTGRES_DATABASE" \
    --from-literal "username=$GRAFANA_POSTGRES_USERNAME" \
    --from-literal "password=$GRAFANA_POSTGRES_PASSWORD" \
    --dry-run=client -o json \
  | kubeseal \
      --controller-name "$CONTROLLER_NAME" \
      --controller-namespace "$CONTROLLER_NAMESPACE" \
      --format yaml \
  > "$OUTPUT_DIR/grafana-postgres-datasource-${PROFILE}.yaml"
else
  echo "Skipping Grafana datasource secret (one or more GRAFANA_POSTGRES_* variables are missing)."
fi

echo "Done. Generated files:"
ls -1 "$OUTPUT_DIR"/*"-${PROFILE}.yaml"
