<div align="center">

# 🎯 SkillPulse
### Production-Grade GitOps Platform · GitHub Actions · Kubernetes · Full Observability Stack

[![CI](https://img.shields.io/github/actions/workflow/status/Heyyprakhar1/github-actions-kubernetes-masterclass/ci.yml?label=CI%20%E2%80%94%206%20Jobs&style=for-the-badge&logo=github-actions&logoColor=white&color=22c55e)](https://github.com/Heyyprakhar1/github-actions-kubernetes-masterclass/actions)
[![ArgoCD](https://img.shields.io/badge/CD-ArgoCD%20Healthy%20✅-orange?style=for-the-badge&logo=argo&logoColor=white)](https://argoproj.github.io/)
[![Kubernetes](https://img.shields.io/badge/kind-3%20Nodes-326ce5?style=for-the-badge&logo=kubernetes&logoColor=white)](https://kubernetes.io/)
[![Prometheus](https://img.shields.io/badge/Prometheus-v65.1.1-E6522C?style=for-the-badge&logo=prometheus&logoColor=white)](https://prometheus.io/)
[![Loki](https://img.shields.io/badge/Loki-v2.10.2-F46800?style=for-the-badge&logo=grafana&logoColor=white)](https://grafana.com/oss/loki/)
[![Go](https://img.shields.io/badge/Go-1.26-00ADD8?style=for-the-badge&logo=go&logoColor=white)](https://go.dev/)

<br/>

> **A single `git push` flows through CI, bumps the manifest, ArgoCD detects the diff, and the cluster is updated — zero human `kubectl` commands.**

</div>

---

## Project Overview

SkillPulse is a three-tier web app — Go backend, Nginx frontend, MySQL — deployed on a production-grade Kubernetes cluster with a fully automated GitOps pipeline. The app tracks skills and learning hours. The real point is everything around it: one commit triggers a 6-job parallel CI pipeline that builds, scans, and pushes Docker images in under 60 seconds, after which ArgoCD automatically syncs the cluster from git with no human intervention. A full observability stack (Prometheus + Loki + Grafana) runs alongside the app in the same cluster, all managed as ArgoCD Helm applications.

This repo is the working artifact for the **TrainWithShubham GitHub Actions & Kubernetes Masterclass**.

---

## Architecture

```
╔══════════════════════════════════════════════════════════════════════════════════════════╗
║                     SKILLPULSE — GITOPS PLATFORM ARCHITECTURE                           ║
╚══════════════════════════════════════════════════════════════════════════════════════════╝

  DEVELOPER                SOURCE OF TRUTH               CI RUNTIME (GitHub-hosted)
  ──────────               ───────────────               ──────────────────────────
  ┌─────────┐   git push   ┌───────────────────────┐    ┌──────────────────────────────────────┐
  │  Local  │─────────────▶│   GitHub Repository   │───▶│      ci.yml  (on: push: main)        │
  │  Commit │              │                       │    │                                      │
  └─────────┘              │  /.github/workflows/  │    │   TRACK A (build)  TRACK B (sec)     │
                           │    ci.yml             │    │   ──────────────   ──────────────     │
                           │    cd-k8s.yml         │    │   1. checkout      4. hadolint       │
                           │    cd.yml (EC2)       │    │   2. docker login  5. trivy image    │
                           │                       │    │   3. build-backend    (parallel,     │
                           │  /k8s/overlays/dev/   │    │      multi-stage      non-blocking)  │
                           │    backend-patch.yaml │    │      push :sha                       │
                           │    frontend-patch.yaml│    │      push :latest                    │
                           │                       │    │   6. build-frontend                  │
                           │  /backend  (Go 1.26)  │    │      push :sha + :latest             │
                           │  /frontend (Nginx)    │    │                                      │
                           │  /mysql               │    │   Total wall-clock: ~58 seconds      │
                           └───────────────────────┘    └─────────────┬────────────────────────┘
                                      │                               │
                                      │                               │ on: workflow_run success
                                      │                               ▼
                                      │                ┌──────────────────────────────────────┐
                                      │                │      cd-k8s.yml                      │
                                      │                │                                      │
                                      │                │  sed image tag → :<new-sha>          │
                                      │                │  in k8s/overlays/dev/backend-patch   │
                                      │                │  in k8s/overlays/dev/frontend-patch  │
                                      │                │                                      │
                                      │                │  git commit as github-actions[bot]   │
                                      │◀───────────────│  "deploy: pin backend+frontend       │
                                      │  push to main  │   to <short-sha>"                    │
                                      │                └──────────────────────────────────────┘
                                      │
                                      │ ArgoCD webhook / 3-min poll detects diff
                                      ▼
╔══════════════════════════════════════════════════════════════════════════════════════════╗
║                    KIND CLUSTER  (1 control-plane + 2 workers)                          ║
║                                                                                          ║
║  ┌──────────────────────────────────────────────────────────────────────────────────┐   ║
║  │  namespace: argocd  (8 pods)                                                     │   ║
║  │                                                                                  │   ║
║  │  ┌──────────────────┐   ┌───────────────────┐   ┌───────────────────────────┐   │   ║
║  │  │  App: skillpulse │   │  App: monitoring  │   │  App: loki-stack          │   │   ║
║  │  │  ● Healthy ✅    │   │  ● Healthy ✅     │   │  ● Healthy ✅             │   │   ║
║  │  │  ● Synced  ✅    │   │  ● Synced  ✅     │   │  ● Synced  ✅             │   │   ║
║  │  │  src: k8s/       │   │  kube-prom-stack  │   │  chart: loki-stack v2.10  │   │   ║
║  │  │  overlays/dev    │   │  v65.1.1          │   │  ns: logging              │   │   ║
║  │  │  branch: main    │   │  ns: monitoring   │   │  Last sync: 4 hrs ago     │   │   ║
║  │  │  Last sync: 13m  │   │  Last sync: 18h   │   └──────────────┬────────────┘   │   ║
║  │  └────────┬─────────┘   └────────┬──────────┘                 │                │   ║
║  └───────────╫─────────────────────╫────────────────────────────╫────────────────┘   ║
║              ║ sync                 ║ deploy Helm                 ║ deploy Helm        ║
║   ┌──────────╨───────────┐  ┌───────╨──────────────────┐  ┌──────╨─────────────────┐  ║
║   │  ns: skillpulse      │  │  ns: monitoring  (8 pods) │  │  ns: logging  (4 pods) │  ║
║   │                      │  │                           │  │                        │  ║
║   │  ┌────────────────┐  │  │  ┌──────────────────────┐ │  │  ┌──────────────────┐  │  ║
║   │  │ frontend       │  │  │  │ Prometheus            │ │  │  │ Loki             │  │  ║
║   │  │ Deployment     │  │  │  │ (scrapes all targets) │ │  │  │ (log storage)    │  │  ║
║   │  │ nginx:alpine   │  │  │  ├──────────────────────┤ │  │  ├──────────────────┤  │  ║
║   │  │ NodePort 30080 │  │  │  │ Grafana :3000         │ │  │  │ Promtail         │  │  ║
║   │  │ 1 replica      │  │  │  │ (dashboards)          │ │  │  │ DaemonSet        │  │  ║
║   │  └───────┬────────┘  │  │  ├──────────────────────┤ │  │  │ tails            │  │  ║
║   │          │ /api/*    │  │  │ Node Exporter         │ │  │  │ /var/log/pods/   │  │  ║
║   │  ┌───────▼────────┐  │  │  │ DaemonSet             │ │  │  │ on every node    │  │  ║
║   │  │ backend        │  │  │  │ (host CPU/RAM/disk)   │ │  │  └──────────────────┘  │  ║
║   │  │ Deployment     │  │  │  ├──────────────────────┤ │  └────────────────────────┘  ║
║   │  │ Go 1.26 + Gin  │  │  │  │ kube-state-metrics   │ │                              ║
║   │  │ ClusterIP 8080 │  │  │  │ (K8s object state)   │ │                              ║
║   │  │ HPA: 1→4 pods  │  │  │  └──────────────────────┘ │                              ║
║   │  │ /health probes │  │  │  ┌──────────────────────┐  │                              ║
║   │  └───────┬────────┘  │  │  │ Alertmanager          │  │                              ║
║   │          │ DB_HOST   │  │  └──────────────────────┘  │                              ║
║   │  ┌───────▼────────┐  │  └───────────────────────────┘                              ║
║   │  │ mysql          │  │                                                               ║
║   │  │ StatefulSet    │  │        HOST BROWSER                                          ║
║   │  │ MySQL 8.4      │  │        http://localhost:8888                                 ║
║   │  │ 1Gi PVC        │  │               │                                              ║
║   │  │ init.sql mount │  │    kind extraPortMappings                                    ║
║   │  │ Headless SVC   │  │    hostPort 8888 → nodePort 30080                            ║
║   │  └────────────────┘  │                                                               ║
║   └──────────────────────┘                                                               ║
╚══════════════════════════════════════════════════════════════════════════════════════════╝

  OBSERVABILITY DATA FLOW
  ────────────────────────────────────────────────────────────────────────────────
  skillpulse pods
  │
  ├── stdout/stderr ──► Promtail (DaemonSet) ──► Loki ──────────────────────────┐
  │                                                                               │
  └── /metrics ──► Prometheus ◄── Node Exporter  (host: CPU, disk, net, RAM)    │
                        ◄── kube-state-metrics  (pod phase, HPA, rollout)        │
                        │                                                         ▼
                        └─────────────────────────────────────────────► Grafana :3000
                                                                          · K8s Cluster
                                                                          · Namespace Pods
                                                                          · Workloads
                                                                          · Node USE Method
                                                                          · Loki Explore
```

---

## Stack

### Application

| Layer | Technology | Version | Role |
|---|---|---|---|
| Frontend | HTML + CSS + JS + **Nginx** | nginx:alpine | Static UI, reverse-proxies `/api/` to backend |
| Backend | **Go** + Gin | Go 1.26 | REST API — skills, logs, dashboard, `/health` |
| Database | **MySQL** | 8.4 | Persistent storage — StatefulSet + 1Gi PVC |
| Container | Docker multi-stage | — | `golang:1.26-alpine → alpine:3.23` — lean final images |

### Infrastructure

| Tool | Version | Purpose |
|---|---|---|
| **Kubernetes** (kind) | 1 CP + 2 workers | Container orchestration |
| **GitHub Actions** | — | CI runner — build, scan, push, manifest bump |
| **ArgoCD** | 8 pods · in-cluster | GitOps controller — watches `k8s/overlays/dev`, auto-syncs |
| **Helm** | via ArgoCD | Deploys monitoring + logging stacks declaratively |
| **Kustomize** | overlays/dev | Environment-specific image tag patching |
| **Docker Hub** | — | Image registry — `:latest` + `:<sha>` per push |
| **HPA** | — | Backend auto-scales 1 → 4 replicas on CPU threshold |

### Observability

| Tool | Chart | Namespace | Covers |
|---|---|---|---|
| **Prometheus** | kube-prometheus-stack v65.1.1 | monitoring | Metrics scraping — pods, nodes, K8s objects |
| **Alertmanager** | (bundled) | monitoring | Alert routing |
| **Node Exporter** | (DaemonSet) | monitoring | Host CPU, RAM, disk I/O, network per interface |
| **kube-state-metrics** | (bundled) | monitoring | Pod phase, HPA counts, deployment rollout status |
| **Grafana** | (bundled) | monitoring | Dashboards — Cluster, Namespace, Workload, Node |
| **Loki** | loki-stack v2.10.2 | logging | Log aggregation and storage |
| **Promtail** | (DaemonSet) | logging | Tails `/var/log/pods/` — no app changes needed |

---

## CI Pipeline

**File:** `.github/workflows/ci.yml` · **Trigger:** `push` to `main` (skips `*.md`, `k8s/**`, `docs/**`)

```
┌──────────────────────────────────────────────────────────────────────┐
│               CI — 6 Jobs · 2 Parallel Tracks · ~58 seconds          │
├──────────────────────────────────────────────────────────────────────┤
│                                                                       │
│  TRACK A (build)                    TRACK B (security — parallel)    │
│  ─────────────────────              ───────────────────────────────  │
│  1. checkout                        4. hadolint (Dockerfile lint)    │
│  2. docker/login-action             5. trivy image scan              │
│  3. build-backend                      Runs alongside the build.     │
│       multi-stage Dockerfile           Neither track blocks the      │
│       tag: :latest + :<sha>            other.                        │
│       push → Docker Hub                                              │
│                                                                       │
│  6. build-frontend                  CD jobs are skipped entirely     │
│       Nginx + static assets         if any job in TRACK A fails.     │
│       tag: :latest + :<sha>         Broken builds cannot deploy.     │
│       push → Docker Hub                                              │
│                                                                       │
└──────────────────────────────────────────────────────────────────────┘
```

SHA tag = permanent rollback handle. Bad deploy → `kubectl set image deployment/backend backend=heyyprakhar1/skillpulse-backend:<old-sha>`. No rebuild. No ceremony.

---

## CD — GitOps + Manifest Bump Flow

No `kubectl apply` from GitHub Actions. The pipeline writes to git. ArgoCD reads from git. The cluster is never directly touched by the pipeline.

```
ci.yml succeeds
    │
    ▼
cd-k8s.yml fires  (workflow_run: completed + conclusion == success gate)
    │
    ├── sed: k8s/overlays/dev/backend-patch.yaml
    │         image: heyyprakhar1/skillpulse-backend:<new-sha>
    │
    ├── sed: k8s/overlays/dev/frontend-patch.yaml
    │         image: heyyprakhar1/skillpulse-frontend:<new-sha>
    │
    └── git commit as github-actions[bot]
         "deploy: pin backend+frontend to <short-sha>"
         push → main
                │
                ▼  (ArgoCD webhook or 3-min poll)
         ArgoCD diffs repo HEAD vs cluster state
                │
                ▼
         Sync: k8s/overlays/dev → kind cluster
         Rolling update: backend + frontend pods replaced
         mysql StatefulSet untouched (image unchanged)
                │
                ▼
         Cluster state = repo state ✅
```

**ArgoCD Applications (live):**

| App | Repo / Chart | Path | Namespace | Status |
|---|---|---|---|---|
| `skillpulse` | `github.com/Heyyprakhar1/...` | `k8s/overlays/dev` | skillpulse | ✅ Healthy · Synced |
| `monitoring` | prometheus-community Helm | kube-prometheus-stack v65.1.1 | monitoring | ✅ Healthy · Synced |
| `loki-stack` | grafana Helm repo | loki-stack v2.10.2 | logging | ✅ Healthy · Synced |

---

## Kubernetes — What's Deployed

**Cluster:** kind · 1 control-plane + 2 workers · nodes at `172.18.0.2–4:9100`

| Workload | Kind | CPU Usage | Memory | Notes |
|---|---|---|---|---|
| `frontend` | Deployment (1 replica) | 0.000089 cores | 4.26 MiB | Nginx + static, NodePort 30080 |
| `backend` | Deployment (1→4 HPA) | 0.000223 cores | 5.81 MiB | Go API, ClusterIP :8080, `/health` probes |
| `mysql` | StatefulSet (1 pod) | 0.00737 cores | 463 MiB | MySQL 8.4, Headless SVC, 1Gi PVC |

```
k8s/
├── kind-config.yaml          cluster: 1 CP + 2 workers, hostPort 8888 → nodePort 30080
├── 00-namespace.yaml          namespace: skillpulse
├── 10-mysql.yaml              Secret + ConfigMap (init.sql) + Headless SVC + StatefulSet + PVC
├── 20-backend.yaml            Deployment + ClusterIP SVC + HPA + liveness/readiness probes
├── 30-frontend.yaml           Deployment + NodePort SVC (30080)
└── overlays/dev/
    ├── kustomization.yaml
    ├── backend-patch.yaml     ← cd-k8s.yml bumps :sha here
    └── frontend-patch.yaml   ← cd-k8s.yml bumps :sha here
```

**Traffic path:**
```
localhost:8888
    → kind extraPortMapping → NodePort 30080
    → Service/frontend
    → Pod: nginx
          proxy_pass /api/* → Service/backend ClusterIP :8080
                           → Pod: Go API
                                  DB_HOST=mysql → Service/mysql Headless :3306
                                               → StatefulSet: mysql-0 + 1Gi PVC
```

---

## Observability — Prometheus + Loki + Grafana

All three tools deployed in-cluster by ArgoCD. Zero manual Helm commands.

```bash
# Access Grafana
kubectl port-forward svc/monitoring-grafana -n monitoring 3000:80 --address 0.0.0.0
# → http://localhost:3000
```

### Prometheus (kube-prometheus-stack v65.1.1)

Scrape targets:
- **App pods** — per-container CPU, memory, network I/O (`skillpulse` namespace)
- **Node Exporter** DaemonSet — host CPU, RAM, disk I/O, network, load average (all 3 nodes)
- **kube-state-metrics** — pod phase, HPA replica counts, deployment rollout status

Grafana dashboards loaded:

| Dashboard | What you see |
|---|---|
| K8s / Compute Resources / Cluster | All namespaces — CPU %, memory %, network |
| K8s / Compute Resources / Namespace (Pods) | Per-pod CPU + memory quota + network bandwidth |
| K8s / Compute Resources / Namespace (Workloads) | frontend, backend, mysql side by side |
| Node Exporter / USE Method / Node | CPU saturation, disk IO, network — all 3 nodes |

### Loki (loki-stack v2.10.2)

Promtail DaemonSet tails `/var/log/pods/` on every node. Every container's stdout lands in Loki automatically — no app changes, no sidecar injection.

```logql
{namespace="skillpulse"}                            # all app logs
{namespace="skillpulse", container="backend"}       # Go API only
```

Live backend health — consistent sub-500µs response times, 200 on every health check:
```
2026-05-19 13:24:37 [GIN] 200 | 249µs | 10.244.2.1 | GET /health
2026-05-19 13:24:32 [GIN] 200 | 216µs | 10.244.2.1 | GET /health
2026-05-19 13:24:17 [GIN] 200 | 739µs | 10.244.2.1 | GET /health
```

---

## Impact Numbers

| Metric | Value |
|---|---|
| CI pipeline end-to-end | **~58 seconds** |
| Parallel CI jobs | **6 jobs · 2 tracks** |
| Manual `kubectl` steps in CD | **0** — full GitOps |
| ArgoCD apps — all Healthy + Synced | **3 / 3** |
| Cluster CPU utilisation | **7.77%** |
| Cluster memory utilisation | **26.6%** |
| Active namespaces | **6** |
| Total running pods (all ns) | **33+** |
| Packet drops across all pods | **0 p/s** |
| Backend health check p50 latency | **~230–500µs** |
| Loki throughput (1h window) | **349 KB logs processed** |
| Image tags pushed per commit | **2 per service** (`:latest` + `:<sha>`) |
| Image rollback steps | **1 command** — `kubectl set image ...:<old-sha>` |

---

## Screenshots

> Real cluster, real dashboards — nothing mocked.

| File | What it shows |
|---|---|
| `docs/screenshots/argocd-apps-synced.png` | All 3 ArgoCD apps — Healthy + Synced |
| `docs/screenshots/grafana-cluster-overview.png` | K8s Cluster — CPU 7.77%, Memory 26.6%, all namespaces |
| `docs/screenshots/grafana-namespace-pods.png` | skillpulse namespace — per-pod CPU, memory, network quota |
| `docs/screenshots/grafana-namespace-workloads.png` | Workload view — mysql, backend, frontend |
| `docs/screenshots/grafana-network-bandwidth.png` | Network bandwidth per pod and workload |
| `docs/screenshots/grafana-network-iops.png` | IOPS + throughput + packet drop rates (all zero drops) |
| `docs/screenshots/grafana-node-use-method.png` | Node Exporter — all 3 nodes, CPU, memory, disk, network |
| `docs/screenshots/loki-skillpulse-logs.png` | Grafana Explore — live logs from skillpulse namespace |
| `docs/screenshots/ci-pipeline-graph.png` | GitHub Actions — 6-job graph, 58s, 2 parallel tracks |

---

## Quick Start

**Prerequisites:** Docker Desktop running, `kind`, `kubectl`

```bash
git clone https://github.com/Heyyprakhar1/github-actions-kubernetes-masterclass
cd github-actions-kubernetes-masterclass

cp .env.example .env          # fill DOCKERHUB_USERNAME (anything for local)
make up                       # builds images, creates kind cluster, applies manifests

# Smoke test
curl http://localhost:8888/health          # → {"status":"healthy"}
curl http://localhost:8888/api/dashboard   # → counters

make status                   # one-screen view of pods + services
make logs                     # tail all three workloads
make down                     # delete cluster (also drops MySQL volume)
```

---

## Project Layout

```
.
├── backend/              Go 1.26 + Gin REST API
│   ├── Dockerfile        multi-stage: golang:1.26-alpine → alpine:3.23
│   ├── main.go
│   ├── database/db.go    MySQL connect with retry loop
│   └── handlers/         skills, logs, dashboard endpoints
├── frontend/             static UI + Nginx
│   ├── Dockerfile        FROM nginx:alpine
│   └── nginx.conf        serves UI, proxies /api/ → backend:8080
├── mysql/init.sql        schema + seed data
├── k8s/                  all manifests + Kustomize overlays
├── .github/workflows/
│   ├── ci.yml            build + push on every main push
│   ├── cd-k8s.yml        manifest bump → commit → ArgoCD syncs
│   └── cd.yml            legacy SSH + docker compose path (EC2)
├── docs/
│   ├── skillpulse-cicd-guide.pdf        29 pages — GitHub Actions chapter
│   └── skillpulse-kubernetes-guide.pdf  32 pages — Kubernetes chapter
├── docker-compose.yml    local dev without K8s
└── Makefile              up / down / status / logs / mysql / restart / apply
```

---

## Credits

Built for the [TrainWithShubham](https://www.youtube.com/@TrainWithShubham) GitHub Actions & Kubernetes Masterclass community.

**Prakhar Srivastava** · [GitHub](https://github.com/Heyyprakhar1) · [LinkedIn](https://linkedin.com/in/heyyprakhar1) · [Blog](https://heyyprakhar01.hashnode.dev) · [Portfolio](https://prakharsrivastavadevops.netlify.app)

---

<div align="center">
<i>If this helped you understand real-world GitOps end to end — star the repo and share it forward.</i>
</div>
