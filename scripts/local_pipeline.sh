#!/usr/bin/env bash
set -euo pipefail

image="${IMAGE_URI:-devops-task-service:local}"
run_optional() {
  local tool=$1
  shift
  if command -v "$tool" >/dev/null 2>&1; then
    "$tool" "$@"
  else
    printf '[INFO] %s is not installed; skipping optional check\n' "$tool"
  fi
}

echo '[1/5] Installing dependencies'
npm ci
echo '[2/5] Linting and testing'
npm run lint
npm test -- --coverage --runInBand
echo '[3/5] Static checks'
run_optional hadolint Dockerfile
run_optional shellcheck scripts/*.sh
echo '[4/5] Building image'
docker build --tag "$image" .
run_optional trivy image --exit-code 1 --ignore-unfixed --severity CRITICAL "$image"
echo '[5/5] Starting local smoke test'
container_name=devops-task-local
docker rm -f "$container_name" >/dev/null 2>&1 || true
docker run --detach --name "$container_name" --publish 18080:3000 \
  --env PORT=3000 --env LOG_LEVEL=info --env ENVIRONMENT=local --env APP_VERSION=local "$image" >/dev/null
trap 'docker rm -f "$container_name" >/dev/null 2>&1 || true' EXIT
for attempt in $(seq 1 20); do
  if curl --fail --silent http://127.0.0.1:18080/health >/dev/null; then
    echo 'Local smoke test passed.'
    exit 0
  fi
  sleep 2
done
echo 'Local smoke test failed.' >&2
docker logs "$container_name" >&2 || true
exit 1
