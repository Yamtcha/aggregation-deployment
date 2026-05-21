#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────
# FinTrack Helm Validate Script
# Lints and template-renders all charts
# Usage: ./scripts/validate.sh
# ──────────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  FinTrack Helm Validate"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

PASS=0
FAIL=0

run_check() {
  local label="$1"
  shift
  echo ""
  echo "▶  ${label}"
  if "$@"; then
    echo "   ✅ Passed"
    ((PASS++))
  else
    echo "   ❌ Failed"
    ((FAIL++))
  fi
}

CHARTS=(
  "fintrack-service"
  "transaction-aggregator-service"
  "database"
  "rabbitmq"
)

SECRET_FLAGS=(
  --set "externalSecrets.aws.accessKeyId=test-key"
  --set "externalSecrets.aws.secretAccessKey=test-secret"
)

# ── Lint ───────────────────────────────────────
for chart in "${CHARTS[@]}"; do
  run_check "Lint ${chart}" \
    helm lint "${ROOT_DIR}/charts/${chart}" "${SECRET_FLAGS[@]}"
done

# ── Template render ────────────────────────────
for chart in "${CHARTS[@]}"; do
  run_check "Template render — ${chart}" \
    helm template "fintrack-${chart}-test" \
      "${ROOT_DIR}/charts/${chart}" \
      "${SECRET_FLAGS[@]}" > /dev/null
done

# ── Dry run (requires cluster connection) ──────
if kubectl cluster-info &>/dev/null; then
  for chart in "${CHARTS[@]}"; do
    run_check "Dry run — ${chart}" \
      helm upgrade --install "fintrack-${chart}-dryrun" \
        "${ROOT_DIR}/charts/${chart}" \
        --namespace fintrack \
        "${SECRET_FLAGS[@]}" \
        --dry-run --generate-name > /dev/null
  done
else
  echo ""
  echo "⚠️  No cluster connection — skipping dry-run checks"
fi

# ── Summary ────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Results: ${PASS} passed, ${FAIL} failed"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

[[ $FAIL -eq 0 ]] && exit 0 || exit 1
