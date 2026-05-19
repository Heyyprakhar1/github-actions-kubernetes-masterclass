#!/usr/bin/env bash
set -euo pipefail

ARGOCD_NS="argocd"
IMAGE_UPDATER_VERSION="v0.15.1"
GITHUB_TOKEN="${1:-}"
GITHUB_USER="Heyyprakhar1"
GITHUB_EMAIL="your@email.com"

if [[ -z "$GITHUB_TOKEN" ]]; then
  echo "ERROR: Pass GitHub token as first argument"
  echo "Usage: $0 <GITHUB_TOKEN>"
  exit 1
fi

echo "==> Installing Argo CD Image Updater ${IMAGE_UPDATER_VERSION}"
kubectl apply -n "${ARGOCD_NS}" -f \
  "https://raw.githubusercontent.com/argoproj-labs/argocd-image-updater/${IMAGE_UPDATER_VERSION}/manifests/install.yaml"

echo "==> Waiting for pod to be ready..."
kubectl rollout status deployment/argocd-image-updater -n "${ARGOCD_NS}" --timeout=120s

echo "==> Creating git-creds secret"
kubectl create secret generic git-creds \
  -n "${ARGOCD_NS}" \
  --from-literal=username="${GITHUB_USER}" \
  --from-literal=password="${GITHUB_TOKEN}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "==> Patching Image Updater ConfigMap"
kubectl patch configmap argocd-image-updater-config \
  -n "${ARGOCD_NS}" \
  --type merge \
  -p "{
    \"data\": {
      \"git.user\": \"${GITHUB_USER}\",
      \"git.email\": \"${GITHUB_EMAIL}\",
      \"log.level\": \"info\"
    }
  }"

echo "==> Restarting Image Updater..."
kubectl rollout restart deployment/argocd-image-updater -n "${ARGOCD_NS}"
kubectl rollout status deployment/argocd-image-updater -n "${ARGOCD_NS}" --timeout=60s

echo ""
echo "✅ Image Updater installed successfully!"
echo ""
echo "To monitor logs:"
echo "kubectl logs -n argocd -l app.kubernetes.io/name=argocd-image-updater -f"
