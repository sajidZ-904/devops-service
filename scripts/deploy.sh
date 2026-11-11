#!/usr/bin/env bash
set -euo pipefail

: "${IMAGE:?IMAGE must be set}"
container=devops-task-service
previous="$(docker inspect --format '{{.Config.Image}}' "$container" 2>/dev/null || true)"
docker pull "$IMAGE"
docker rm -f "$container" 2>/dev/null || true
docker run -d --name "$container" --restart unless-stopped -p 3000:3000 \
  -e PORT=3000 -e LOG_LEVEL="${LOG_LEVEL:-info}" \
  -e ENVIRONMENT="${ENVIRONMENT:-production}" -e APP_VERSION="${APP_VERSION:-unknown}" "$IMAGE"
if ! curl --fail --silent --show-error --retry 12 --retry-delay 2 http://127.0.0.1:3000/health >/dev/null; then
  docker rm -f "$container" || true
  if [[ -n "$previous" ]]; then
    docker run -d --name "$container" --restart unless-stopped -p 3000:3000 \
      -e PORT=3000 -e LOG_LEVEL=info -e ENVIRONMENT=production -e APP_VERSION=rollback "$previous"
  fi
  exit 1
fi
