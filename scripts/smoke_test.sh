#!/usr/bin/env bash
# Confirms the new build is the one actually serving traffic.
set -euo pipefail
URL="http://${K8S_PRIVATE_IP}:30080"
for i in $(seq 1 20); do
  if curl -fsS "$URL/healthz" >/dev/null; then
    info=$(curl -fsS "$URL/api/info")
    echo "$info"
    echo "$info" | grep -q "\"build\":\"${BUILD_NUMBER}\"" && { echo "Smoke test passed"; exit 0; }
  fi
  sleep 3
done
echo "Smoke test failed: build ${BUILD_NUMBER} not serving at $URL"; exit 1
