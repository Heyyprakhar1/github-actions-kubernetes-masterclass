# SkillPulse — GitOps CI/CD on Kubernetes

SkillPulse is a three-tier web app for tracking skills and study hours.
The app is intentionally small — the point is the infrastructure around it:
a single `git push` builds, scans, and deploys to a live Kubernetes cluster
in under 90 seconds, with zero human intervention after that.

---

## Stack

| Layer | Technology |
|---|---|
| Backend | Go 1.26 + Gin |
| Frontend | Nginx + vanilla HTML/CSS/JS |
| Database | MySQL 8.4 |
| Container runtime | Docker — distroless images |
| Orchestration | Kubernetes 1.35 on KinD v0.31 |
| CI | GitHub Actions |
| CD | Argo CD v3.0.0 + Argo CD Image Updater v0.15.1 |
| Monitoring | kube-prometheus-stack v65.1.1 |
| Logging | Loki + Promtail — loki-stack v2.10.2 |
| Infra | AWS EC2 t3.medium — ap-northeast-1 |

---

## Architecture

git push (main)
│
▼
── CI — GitHub Actions (~54s) ────────────────────────────
│                                                         │
│   Security gate          govulncheck                   │
│   Gitleaks               (runs parallel,               │
│   Hadolint ×2             saves 18s)                   │
│        │                      │                        │
│        └──────────┬───────────┘                        │
│                   ▼                                     │
│   Build backend + Build frontend                        │
│   (parallel, GHA layer cache)                           │
│   tag: sha-<short> + latest                             │
│                   │                                     │
│                   ▼                                     │
│   Trivy — backend + frontend                            │
│   (parallel, blocks CRITICAL/HIGH unfixed)              │
│                   │                                     │
│                   ▼                                     │
│        pushed to DockerHub                              │
──────────────────────────────────────────────────────────
│
▼
Argo CD Image Updater
polls DockerHub every 2 minutes
detects new sha-* tag
commits to k8s/overlays/dev/
"build: automatic update of skillpulse"
│
▼
Argo CD v3.0.0
polls repo every 3 minutes
diffs cluster state vs Git
syncs automatically — prune + selfHeal
│
▼
── KinD cluster — skillpulse namespace ───────────────────
│                                                         │
│   backend    Deployment + ClusterIP + probes            │
│   frontend   Deployment + NodePort 30080 + probes       │
│   mysql      StatefulSet + 1Gi PVC + init.sql           │
│   HPA        backend 1→4 replicas at 80% CPU            │
──────────────────────────────────────────────────────────
No kubectl in CI. No SSH. No cluster credentials in GitHub.
The repo is the only source of truth —
Image Updater commits, Argo CD syncs.

---

## CI pipeline

File: `.github/workflows/ci.yml`

Five jobs, two parallel tracks, ~54 seconds warm.

**Security gate** runs parallel to govulncheck — neither blocks the other:
- Gitleaks scans full git history for leaked secrets
- Hadolint lints both Dockerfiles against best practices
- govulncheck checks Go dependencies against the official vuln DB

**Build** kicks off after the security gate clears:
- Backend: `distroless/static-debian12:nonroot` + `-ldflags="-s -w"` → 19 MB
- Frontend: `nginx-unprivileged:1.27-alpine` + `apk upgrade` → 38 MB
- Both images tagged `sha-<7-char>` and `latest`, pushed to DockerHub
- GHA layer cache cuts rebuild time on unchanged layers

**Trivy** scans the pushed images in parallel — blocks the workflow on any CRITICAL or HIGH unfixed CVE.

CI produces the artifact. Image Updater consumes it. They never overlap.

---

## CD — GitOps with Argo CD Image Updater

File: `k8s/argocd-app.yaml`

No `cd.yml` workflow. No `sed` scripts. No manifest commits from GitHub Actions.

Image Updater polls DockerHub every 2 minutes, detects new `sha-*` tags, and writes back to `k8s/overlays/dev/.argocd-source-skillpulse.yaml`:
build: automatic update of skillpulse
updates image heyyprakhar1/skillpulse-backend tag 'latest' to 'sha-edea777'
updates image heyyprakhar1/skillpulse-frontend tag 'latest' to 'sha-ef1d89a'

Argo CD picks up the commit on its next poll and syncs the cluster. Full loop — push to running pods — under 90 seconds.

Argo CD config on the skillpulse app:
- `prune: true` — removes resources deleted from Git
- `selfHeal: true` — reverts any manual cluster changes
- `ServerSideApply: true` — handles CRD field ownership cleanly
- `retry.limit: 3` with exponential backoff

---

## Kubernetes

Single KinD cluster on EC2. Three Argo CD applications watch three overlay paths — dev, stg, prd — each in its own namespace.
k8s/
├── base/
│   ├── 00-namespace.yaml     skillpulse namespace
│   ├── 10-mysql.yaml         StatefulSet + 1Gi PVC + init.sql ConfigMap + Secret
│   ├── 20-backend.yaml       Deployment + ClusterIP + probes + resource limits
│   ├── 30-frontend.yaml      Deployment + NodePort 30080 + probes
│   └── hpa.yml               backend 1→4 replicas at 80% CPU
└── overlays/
├── dev/                  Image Updater writes sha tags here
├── stg/
└── prd/

Backend and frontend both have liveness and readiness probes on `/healthz`.
MySQL uses an init container that holds the backend until the DB accepts connections.
Secrets are mounted from Kubernetes Secrets — nothing hardcoded in manifests.

---

## Observability

All three components deployed via Argo CD — same GitOps loop as the app itself.

**Metrics — kube-prometheus-stack v65.1.1**

Prometheus scrapes three sources:
- App pods in the `skillpulse` namespace — CPU, memory, network per container
- Node Exporter DaemonSet — EC2 host metrics: disk I/O, CPU, RAM, network
- kube-state-metrics — pod phase, HPA replica counts, deployment rollout status

Grafana dashboards in use:
- Kubernetes / Compute Resources / Cluster
- Kubernetes / Compute Resources / Namespace (Pods)
- Kubernetes / Compute Resources / Namespace (Workloads)
- Node Exporter / USE Method / Node

**Logs — Loki + Promtail — loki-stack v2.10.2**

Promtail runs as a DaemonSet and tails `/var/log/pods/` on the node.
Every container's stdout/stderr ships to Loki automatically — no app changes needed.
{namespace="skillpulse"}                       # all app logs
{namespace="skillpulse", container="backend"}  # backend only
{namespace="skillpulse"} |= "ERROR"            # errors only

---

## Impact

| What | Before | After | Delta |
|---|---|---|---|
| Time to deploy | ~10 min manual | ~90 sec automated | −89% |
| CI warm build | ~3 min | ~54s | −70% |
| Backend image | 26.8 MB | 19 MB | −29% |
| Frontend image | 92.9 MB | 38 MB | −59% |
| Security checks per commit | 0 | 5 automated | 100% commits scanned |
| Human intervention in deploy | required | zero | fully automated |

---

## Screenshots

CI pipeline runs, Argo CD dashboard, Image Updater auto-commits, live cluster state, Grafana dashboards, Loki logs — [`docs/screenshots/`](docs/screenshots/)
