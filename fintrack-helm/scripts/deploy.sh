#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

NAMESPACE="fintrack"

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

: "${AWS_ACCESS_KEY_ID:?required}"
: "${AWS_SECRET_ACCESS_KEY:?required}"

BASE_FLAGS=(--namespace "$NAMESPACE")
[[ "$DRY_RUN" == true ]] && BASE_FLAGS+=(--dry-run=client)

echo "▶ FinTrack Deploy (namespace=$NAMESPACE, dry-run=$DRY_RUN)"

kubectl get ns "$NAMESPACE" >/dev/null 2>&1 || kubectl create ns "$NAMESPACE"

echo "▶ Deploying secrets..."
kubectl create secret generic aws-credentials \
  --namespace "$NAMESPACE" \
  --from-literal=access-key-id="$AWS_ACCESS_KEY_ID" \
  --from-literal=secret-access-key="$AWS_SECRET_ACCESS_KEY" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "▶ Deploying fintrack-service..."
helm upgrade --install fintrack-service \
  "$ROOT_DIR/charts/fintrack-service" \
  "${BASE_FLAGS[@]}"

echo "⏳ Waiting for ExternalSecret..."
kubectl wait externalsecret fintrack-external-secret \
  -n "$NAMESPACE" --for=condition=Ready --timeout=120s || true

echo "▶ Deploying infrastructure..."
helm upgrade --install fintrack-database \
  "$ROOT_DIR/charts/database" "${BASE_FLAGS[@]}"

helm upgrade --install fintrack-rabbitmq \
  "$ROOT_DIR/charts/rabbitmq" "${BASE_FLAGS[@]}"

echo "⏳ Waiting for infrastructure..."
kubectl rollout status statefulset/postgres -n "$NAMESPACE" --timeout=120s || true
kubectl rollout status statefulset/rabbitmq -n "$NAMESPACE" --timeout=120s || true

echo "▶ Deploying applications..."
helm upgrade --install fintrack-aggregator \
  "$ROOT_DIR/charts/transaction-aggregator-service" \
  "${BASE_FLAGS[@]}"

echo "✅ Deploy complete"