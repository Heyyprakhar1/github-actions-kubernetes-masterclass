markdown# SkillPulse — GitOps CI/CD on Kubernetes

SkillPulse is a three-tier web app for tracking skills and study hours.
The app is intentionally small — the point is the infrastructure around it:
a single `git push` builds, scans, and deploys to a live Kubernetes cluster
in under 90 seconds, with no human pressing any button after that.

---

## Stack

| Layer | Technology |
|---|---|
| Backend | Go 1.26 + Gin |
| Frontend | Nginx + vanilla HTML/CSS/JS |
| Database | MySQL 8.4 (StatefulSet) |
| Container runtime | Docker, distroless images |
| Orchestration | Kubernetes 1.35 on KinD v0.31 |
| CI | GitHub Actions |
| CD | Argo CD v3.0.0 + Argo CD Image Updater |
| Monitoring | kube-prometheus-stack v65.1.1 |
| Logging | Loki + Promtail (loki-stack v2.10.2) |
| Infra | AWS EC2 t3.medium (ap-northeast-1) |

---

## Architecture
git push (main)
│
▼
┌─────────────────────────────────────────┐
│  CI — GitHub Actions (~54s)             │
│                                         │
│  ┌──────────────┐  ┌─────────────────┐  │
│  │ Security Gate│  │   govulncheck   │  │
│  │ Gitleaks     │  │   (parallel)    │  │
│  │ Hadolint ×2  │  └────────┬────────┘  │
│  └──────┬───────┘           │           │
│         └─────────┬─────────┘           │
│                   ▼                     │
│  ┌──────────────────────────────────┐   │
│  │ Build backend + Build frontend   │   │
│  │ (parallel, GHA layer cache)      │   │
│  │ tag: sha-<short> + latest        │   │
│  └──────────────┬───────────────────┘   │
│                 ▼                       │
│  ┌──────────────────────────────────┐   │
│  │ Trivy scan backend + frontend    │   │
│  │ (parallel, blocks CRITICAL/HIGH) │   │
│  └──────────────┬───────────────────┘   │
└─────────────────┼───────────────────────┘
│ images pushed to DockerHub
▼
┌─────────────────────────────────────────┐
│  Argo CD Image Updater (polls 2m)       │
│                                         │
│  detects new sha-* tag on DockerHub     │
│  commits image tag to k8s/overlays/dev  │
│  "build: automatic update of skillpulse"│
└─────────────────┬───────────────────────┘
│ git commit to main
▼
┌─────────────────────────────────────────┐
│  Argo CD v3.0.0                         │
│                                         │
│  polls repo every 3 minutes             │
│  diffs cluster state vs Git             │
│  syncs automatically (prune + selfHeal) │
└─────────────────┬───────────────────────┘
│
▼
┌─────────────────────────────────────────┐
│  KinD Cluster — skillpulse namespace    │
│                                         │
│  backend  (Deployment, ClusterIP)       │
│  frontend (Deployment, NodePort 30080)  │
│  mysql    (StatefulSet, 1Gi PVC)        │
│  HPA      (backend 1→4 @ 80% CPU)      │
└─────────────────────────────────────────┘

No `kubectl` in CI. No SSH. No cluster credentials in GitHub.
The repo is the only source of truth — Image Updater commits, Argo CD syncs.

---

## CI Pipeline

File: `.github/workflows/ci.yml`

Five jobs, two parallel tracks, ~54 seconds on a warm cache.

**Security gate** (parallel with govulncheck):
- Gitleaks — scans full git history for leaked secrets
- Hadolint — lints both Dockerfiles

**govulncheck** — Go vulnerability check against the official vuln database, runs parallel to the security gate to save 18s off the critical path.

**Build** (parallel per image, after security gate passes):
- Multi-stage builds with GHA layer cache
- Backend: `distroless/static-debian12:nonroot` + `-ldflags="-s -w"` → 19 MB
- Frontend: `nginx-unprivileged:1.27-alpine` + `apk upgrade` → 38 MB
- Tagged `sha-<7-char>` + `latest`, pushed to DockerHub

**Trivy** (parallel per image, after build):
- CVE scan on the pushed image
- Blocks on CRITICAL or HIGH unfixed vulnerabilities

CI produces the artifact. CD consumes it. They never overlap.

---

## CD — GitOps with Argo CD Image Updater

File: `k8s/argocd-app.yaml`

No `cd.yml` workflow. No `sed` scripts. No manifest commits from GitHub Actions.

Image Updater polls DockerHub every 2 minutes, detects new `sha-*` tags, and commits directly to `k8s/overlays/dev/.argocd-source-skillpulse.yaml`:
build: automatic update of skillpulse
updates image heyyprakhar1/skillpulse-backend tag 'latest' to 'sha-edea777'
updates image heyyprakhar1/skillpulse-frontend tag 'latest' to 'sha-ef1d89a'

Argo CD picks up the commit on its next poll cycle and syncs. The full loop — push to running update — takes under 90 seconds.

Argo CD config:
- `prune: true` — removes resources deleted from Git
- `selfHeal: true` — reverts any manual cluster changes
- `ServerSideApply: true` — handles CRD field ownership cleanly

---

## Kubernetes

Cluster: KinD v0.31 on AWS EC2 t3.medium (ap-northeast-1), single node.
k8s/
├── base/
│   ├── 00-namespace.yaml      skillpulse namespace
│   ├── 10-mysql.yaml          StatefulSet + 1Gi PVC + init.sql ConfigMap + Secret
│   ├── 20-backend.yaml        Deployment + ClusterIP + probes + resource limits
│   ├── 30-frontend.yaml       Deployment + NodePort 30080 + probes
│   └── hpa.yml                HPA: backend 1→4 replicas at 80% CPU
└── overlays/
├── dev/                   kustomization + image patches (Image Updater writes here)
├── stg/                   kustomization + image patches
└── prd/                   kustomization + image patches

Three Argo CD applications watch the three overlay paths — `skillpulse-dev`, `skillpulse-stg`, `skillpulse-prd` — each in its own namespace.

Backend and frontend use liveness + readiness probes on `/healthz`. MySQL uses an init container to hold the backend until the DB is ready.

---

## Observability

All three components deployed via Argo CD — same GitOps loop as the app.

**Metrics — kube-prometheus-stack v65.1.1**

Prometheus scrapes:
- App pods — CPU, memory, network per container in `skillpulse` namespace
- Node Exporter — EC2 host: disk I/O, CPU, RAM, network
- kube-state-metrics — pod phase, HPA replica counts, rollout status

Grafana dashboards loaded:
- Kubernetes / Compute Resources / Cluster
- Kubernetes / Compute Resources / Namespace (Pods)
- Kubernetes / Compute Resources / Namespace (Workloads)
- Node Exporter / USE Method / Node

**Logs — Loki + Promtail (loki-stack v2.10.2)**

Promtail runs as a DaemonSet, tails `/var/log/pods/` — every container's stdout/stderr ships to Loki automatically. Query in Grafana → Explore:
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
| Human intervention in deploy | Required | Zero | Fully automated |

---

## Screenshots

CI pipeline, Argo CD dashboard, live cluster, Grafana dashboards, Loki logs, Image Updater auto-commits — all in [`docs/screenshots/`](docs/screenshots/).
