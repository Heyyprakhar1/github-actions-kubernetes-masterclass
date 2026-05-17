# SkillPulse — DevSecOps GitOps Pipeline on Kubernetes

> **One `git push` → security-scanned, CVE-free, SHA-pinned image live on Kubernetes in under 2 minutes. Zero manual steps. Zero kubectl in CI.**

---

## Impact Numbers (STAT)

| What | Before | After | Delta |
|------|--------|-------|-------|
| Time to deploy a code change | Manual SSH + docker pull (~10 min) | 54s CI + ~30s Argo CD sync | **−89% TTM** |
| CI time with Docker layer cache (warm) | ~3 min (cold build) | ~54s | **−70% build time** |
| Backend image size | 26.8 MB | 19 MB | **−29% attack surface** |
| Frontend image size | 92.9 MB | 38 MB | **−59% attack surface** |
| Security checks per commit | 0 | 5 automated scans | **100% of commits scanned** |
| Human intervention to deploy | Required (SSH + manual commands) | 0 | **Fully automated** |
| CVEs blocked before production | Not tracked | CRITICAL/HIGH blocked at CI gate | **0 known unfixed CVEs ship** |

---

## STAR Summary

**Situation**
A three-tier Go/Nginx/MySQL application with no automated pipeline. Deploys were manual SSH sessions. Images were unscanned, unoptimized, and ran as root. No visibility into cluster health post-deploy.

**Task**
Build a production-grade DevSecOps pipeline: automate build, scan, push, deploy, and observe — with security embedded at every stage, not bolted on at the end.

**Action**
Designed and implemented a full GitOps pipeline:
- 6-job parallel CI workflow with 5 security gates (Gitleaks, Hadolint ×2, Trivy ×2, govulncheck)
- Docker layer caching reducing warm-build time by 70%
- GitOps CD via Argo CD — manifest bump in Git triggers cluster sync via GitHub webhook (instant, no polling)
- Hardened images: distroless nonroot backend (19 MB), nginx-unprivileged frontend (38 MB)
- Full observability: Prometheus + Grafana + Loki + Promtail — all deployed GitOps via Argo CD
- HorizontalPodAutoscaler: backend auto-scales 1→4 replicas at 80% CPU

**Result**
- Time-to-deploy reduced from ~10 minutes (manual) to **~90 seconds** (fully automated)
- **100% of commits** pass through 5 security scans before any image is pushed
- **0 known unfixed CVEs** reach the cluster — pipeline blocks deployment on CRITICAL/HIGH findings
- Image sizes reduced **29–59%** — smaller attack surface, faster pulls, lower bandwidth
- Full cluster observability: CPU, memory, network, logs — all in Grafana, zero manual setup

---

## Architecture

```
git push
    │
    ▼
┌─────────────────────────────────────────────────────────────┐
│                   GitHub Actions CI  (~54s)                  │
│                                                             │
│  ┌──────────────────────────────┐  ┌─────────────────────┐  │
│  │      Security Gate           │  │    govulncheck       │  │
│  │  Gitleaks (secrets)          │  │  Go CVE audit on     │  │
│  │  Hadolint (backend Docker)   │  │  entire module graph │  │
│  │  Hadolint (frontend Docker)  │  │                     │  │
│  └──────────────┬───────────────┘  └─────────────────────┘  │
│                 │ (parallel)                                  │
│        ┌────────┴────────┐                                   │
│        ▼                 ▼                                    │
│  Build Backend      Build Frontend                           │
│  (cache hit: ~5s)   (cache hit: ~5s)                        │
│  push sha-<commit>  push sha-<commit>                        │
│        │                 │                                    │
│        ▼                 ▼                                    │
│  Trivy Backend      Trivy Frontend                           │
│  (CVE scan)         (CVE scan)                               │
│  blocks CRITICAL    blocks CRITICAL                          │
└─────────────────────────────────────────────────────────────┘
    │
    ▼ workflow_run: success
┌─────────────────────────────────────────────────────────────┐
│               GitHub Actions CD  (~8s)                       │
│  sed: image tag → sha-<commit> in k8s/20-backend.yaml       │
│  sed: image tag → sha-<commit> in k8s/30-frontend.yaml      │
│  git commit "deploy: pin backend+frontend to sha-<commit>"  │
│  git push → triggers GitHub webhook                         │
└─────────────────────────────────────────────────────────────┘
    │
    ▼ webhook (instant — no 3-min poll)
┌─────────────────────────────────────────────────────────────┐
│                   Argo CD on EC2                             │
│  Detects new commit in k8s/ → kubectl apply                 │
│  Rolling update: new pods up before old pods down           │
│  selfHeal: true — manual edits reverted automatically       │
└─────────────────────────────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────────────────────────────┐
│              KinD Cluster  (AWS EC2 t3.medium)              │
│                                                             │
│  skillpulse ns    │  monitoring ns     │  logging ns        │
│  backend (HPA)    │  Prometheus        │  Loki              │
│  frontend         │  Grafana           │  Promtail          │
│  mysql (PVC)      │  AlertManager      │  (DaemonSet)       │
│                   │  Node Exporter     │                    │
└─────────────────────────────────────────────────────────────┘
```

---

## Security — 5 Gates, Every Commit

```
Commit
  │
  ├─► Gitleaks          — scans full git history for secrets, tokens, API keys
  │                        Blocks: hardcoded credentials before they reach Docker Hub
  │
  ├─► Hadolint          — lints both Dockerfiles against best practices
  │   (backend)           Blocks: running as root, wrong base images, missing USER
  │
  ├─► Hadolint          — same for frontend Dockerfile
  │   (frontend)
  │
  ├─► Trivy             — scans pushed backend image for OS + library CVEs
  │   (backend image)     Blocks: any unfixed CRITICAL or HIGH finding
  │                        Result: 0 unfixed CRITICAL/HIGH CVEs in production
  │
  ├─► Trivy             — same for frontend image
  │   (frontend image)
  │
  └─► govulncheck       — audits Go module graph against OSV vulnerability database
                          Runs parallel to Security Gate (not sequential)
                          Blocks: any known CVE in Go dependencies
```

**What this means in numbers:**
- 5 independent security checks on every single commit
- Pipeline **exits non-zero and blocks the CD workflow** on any finding
- 0 images with known unfixed CVEs have ever reached the cluster
- No credentials exist in any commit — Gitleaks enforces this on full git history, not just the diff

---

## CI Performance — Layer Caching Impact

Docker builds are expensive. GHA cache (`type=gha`) makes them cheap.

| Scenario | Time (Backend) | Time (Frontend) | Why |
|----------|---------------|-----------------|-----|
| Cold build (first run / deps changed) | ~22s | ~23s | Downloads Go modules, base images |
| Warm build (code change only) | ~5–8s | ~5–8s | Layer cache hit — only app layer rebuilt |
| Cache savings per warm run | ~17s | ~15s | **−70% build time** |

**How it works:**
```yaml
cache-from: type=gha,scope=backend   # pull cached layers from GHA cache
cache-to:   type=gha,scope=backend,mode=max  # push all layers back after build
```

The Go module download step (`go mod download`) is also cached via `setup-go cache: true` — `go.sum` is the cache key. Module downloads only happen when dependencies change.

**govulncheck parallelization:**
Moving govulncheck off the `security-gate` sequential chain saved **~18s** from the critical path:

```
Before:  security-gate(12s) → govulncheck(22s) → [builds blocked] = 34s before builds start
After:   security-gate(12s) [builds start immediately]
         govulncheck(22s)   [runs in parallel]
         Critical path: 12s → builds start
```

Total pipeline: **~54 seconds** wall-clock time.

---

## Image Hardening — Size & Security

### Backend — `heyyprakhar1/skillpulse-backend`

```dockerfile
# Stage 1 — Build (thrown away after)
FROM golang:1.26-alpine AS builder
RUN go build -ldflags="-s -w" -o skillpulse .
#                      ↑↑↑↑↑
#   -s: strip symbol table  (-w: strip DWARF debug info)
#   Result: binary ~30% smaller than default Go build

# Stage 2 — Run (what ships)
FROM gcr.io/distroless/static-debian12:nonroot
#         ↑↑↑↑↑↑↑↑↑↑
#   Zero OS: no shell, no package manager, no coreutils
#   nonroot: runs as UID 65532 — never root
```

| Metric | Value |
|--------|-------|
| Final image size | **19 MB** (was 26.8 MB — −29%) |
| OS packages | 0 |
| Shell | None |
| Runs as | UID 65532 (nonroot) |
| CVEs (unfixed CRITICAL/HIGH) | 0 |

### Frontend — `heyyprakhar1/skillpulse-frontend`

```dockerfile
FROM nginxinc/nginx-unprivileged:1.27-alpine
USER root
RUN apk upgrade --no-cache   # patches all OS packages to latest
USER 101                     # back to unprivileged nginx user
```

| Metric | Value |
|--------|-------|
| Final image size | **38 MB** (was 92.9 MB — −59%) |
| Runs as | UID 101 (unprivileged) |
| OS packages | Patched via `apk upgrade` |
| CVEs (unfixed CRITICAL/HIGH) | 0 (Trivy-verified) |

---

## GitOps — Why No `kubectl` in CI

Traditional CD: CI SSHes into the server, runs `kubectl apply`. Problems:
- CI needs cluster credentials
- Cluster must be reachable from GitHub
- No audit trail of what's actually running
- Manual rollback requires SSH again

GitOps approach used here:
- CI only writes to Git (bumps image tag in manifest)
- Argo CD watches Git and applies changes — CI never touches the cluster
- `selfHeal: true` — if someone manually edits the cluster, Argo CD reverts it
- `prune: true` — resources deleted from Git are deleted from the cluster
- Full audit trail: every deploy is a git commit with the exact SHA that was deployed
- Rollback = `git revert` + push

```
Cluster credentials: stored only on EC2 (never in GitHub)
GitHub secrets needed for CD: 0 (only DockerHub for CI)
```

---

## Observability Stack (all GitOps via Argo CD)

Three Argo CD Applications — `Healthy + Synced`:

| App | Helm Chart | Namespace | What it provides |
|-----|-----------|-----------|-----------------|
| `skillpulse` | This repo (k8s/) | `skillpulse` | The app |
| `monitoring` | kube-prometheus-stack v65.1.1 | `monitoring` | Prometheus + Grafana + AlertManager + Node Exporter |
| `loki-stack` | loki-stack v2.10.2 | `logging` | Loki + Promtail (DaemonSet on all nodes) |

**Grafana dashboards available out-of-the-box:**
- Kubernetes / Compute Resources / Cluster — namespace-level CPU, memory, network
- Kubernetes / Compute Resources / Pod — per-pod drill-down
- Node Exporter / Nodes — EC2 host metrics (CPU, disk, memory, network)
- Prometheus / Overview — scrape targets, TSDB stats

**HPA — Auto-scaling:**
```yaml
backend: minReplicas: 1 → maxReplicas: 4 at 80% CPU
```
Prometheus metrics feed the HPA — scales automatically under load.

---

## Kubernetes Manifests

| Manifest | Key features |
|----------|-------------|
| `10-mysql.yaml` | StatefulSet + 1Gi PVC + headless Service + init.sql via ConfigMap |
| `20-backend.yaml` | SHA-pinned image, liveness + readiness probes on `/health`, CPU/memory limits, HPA target |
| `30-frontend.yaml` | SHA-pinned image, NodePort 30080→8888, liveness + readiness probes on `/` port 8080 |
| `hpa.yml` | Scale backend 1→4 replicas, CPU target 80% |
| `argocd-app.yaml` | `prune: true`, `selfHeal: true`, `kind-config.yaml` excluded from sync |

---

## Infrastructure

| Component | Detail |
|-----------|--------|
| Cloud | AWS EC2 t3.medium (2 vCPU, 4 GB RAM) |
| OS | Ubuntu 22.04 |
| Cluster | KinD v0.31.0 |
| Kubernetes | v1.35.1 |
| Nodes | 1 control-plane + 2 workers |
| Argo CD | v3.0.0 |
| Docker | v29.4.3 |

**One-command bootstrap:** `bash bootstrap-ec2.sh`
Installs Docker → kubectl → KinD → creates cluster → installs Argo CD → applies SkillPulse Application CRD. Fresh EC2 to running app in ~10 minutes.

---

## Project Structure

```
.
├── .github/workflows/
│   ├── ci.yml              6 jobs, parallel security + build
│   └── cd-k8s.yml          GitOps manifest bump
├── backend/
│   ├── Dockerfile          distroless nonroot, -ldflags="-s -w"
│   └── ...                 Go 1.26 + Gin
├── frontend/
│   ├── Dockerfile          nginx-unprivileged, apk upgrade, UID 101
│   └── ...                 HTML/CSS/JS + nginx.conf
├── k8s/
│   ├── 00-namespace.yaml
│   ├── 10-mysql.yaml
│   ├── 20-backend.yaml
│   ├── 30-frontend.yaml
│   ├── argocd-app.yaml
│   ├── hpa.yml
│   ├── install_argocd.sh
│   ├── kind-config.yaml
│   ├── monitoring/argocd-app.yaml
│   └── logging/argocd-loki-app.yaml
├── bootstrap-ec2.sh        Fresh EC2 → running cluster in ~10 min
└── docker-compose.yml      Local dev
```

---

## Secrets & Variables

| Secret | Purpose |
|--------|---------|
| `DOCKERHUB_USERNAME` | Docker Hub account name |
| `DOCKERHUB_TOKEN` | PAT with read+write scope |

| Variable | Value |
|----------|-------|
| `DEPLOY_ENABLED` | `true` — gates all pushes and CD |
