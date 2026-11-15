#!/usr/bin/env bash
# Deploys the scanned image (pinned by digest) to k3s, with automatic rollback.
# Needs: IMAGE_DIGEST_REF IMAGE_TAG BUILD_NUMBER GIT_COMMIT ECR_REGISTRY AWS_REGION
set -euo pipefail
NS=shipguard
RENDERED=reports/deployment.rendered.yaml

kubectl apply -f k8s/namespace.yaml

# Fresh ECR pull secret (tokens last 12h; the node also refreshes it every 6h via cron)
kubectl -n "$NS" create secret docker-registry ecr-pull \
  --docker-server="$ECR_REGISTRY" --docker-username=AWS \
  --docker-password="$(aws ecr get-login-password --region "$AWS_REGION")" \
  --dry-run=client -o yaml | kubectl apply -f -

# Scan results the app shows on its dashboard
kubectl -n "$NS" create configmap scan-summary \
  --from-file=scan-summary.json=reports/scan-summary.json \
  --dry-run=client -o yaml | kubectl apply -f -

sed -e "s#image: placeholder/shipguard@sha256:[0-9a-f]*#image: ${IMAGE_DIGEST_REF}#" \
    -e "s#BUILD_NUMBER_VALUE#${BUILD_NUMBER}#" \
    -e "s#GIT_COMMIT_VALUE#${GIT_COMMIT}#" \
    -e "s#IMAGE_TAG_VALUE#${IMAGE_TAG}#" \
    -e "s#DEPLOYED_AT_VALUE#$(date -u +%Y-%m-%dT%H:%M:%SZ)#" \
    k8s/deployment.yaml > "$RENDERED"

grep -q "image: ${IMAGE_DIGEST_REF}" "$RENDERED" || { echo "image substitution failed"; exit 1; }

kubectl apply -f k8s/service.yaml -f k8s/networkpolicy.yaml -f k8s/pdb.yaml -f "$RENDERED"

if ! kubectl -n "$NS" rollout status deployment/shipguard --timeout=180s; then
  echo "Rollout unhealthy — rolling back"
  kubectl -n "$NS" describe pods -l app=shipguard | tail -40 || true
  kubectl -n "$NS" rollout undo deployment/shipguard
  exit 1
fi
kubectl -n "$NS" get pods -o wide
