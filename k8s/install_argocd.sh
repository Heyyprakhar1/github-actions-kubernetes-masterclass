set -euo pipefail

ARGOCD_VERSION="v2.14.9"
CONTEXT="kind-practice-cluster"

echo "==> Switching to context: ${CONTEXT}"
kubectl config use-context "${CONTEXT}"

echo "==> Creating argocd namespace"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

echo "==> Installing Argo CD ${ARGOCD_VERSION}"
kubectl apply -n argocd \
  -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

echo "==> Waiting for Argo CD server to be ready (up to 3 min)..."
kubectl rollout status deployment/argocd-server -n argocd --timeout=180s

echo "==> Patching argocd-server service → NodePort 30088"
kubectl patch svc argocd-server -n argocd \
  -p '{"spec":{"type":"NodePort","ports":[{"port":443,"targetPort":8080,"nodePort":30088}]}}'

echo ""
echo " Argo CD installed!"
echo ""
echo "──────────────────────────────────────────────────"
echo "  UI:       https://localhost:30088  (accept the self-signed cert)"
echo "  Username: admin"
echo -n "  Password: "
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
echo ""
echo "──────────────────────────────────────────────────"
echo ""
echo "==> Applying SkillPulse Application CRD..."
kubectl apply -f k8s/argocd-app.yaml

echo ""
echo " Done! Argo CD is now watching your repo."
echo "    Open the UI, login, and you'll see the skillpulse app syncing."
