# Cyber Security for Virtualisation Systems 
### $${\color{red}(Read \space the \space following \space file \space carefully! \space (Non Production))}$$

[![DevSecOps Pipeline](https://github.com/the-ancient-one/container-security/actions/workflows/devsecops.yml/badge.svg?branch=main)](https://github.com/the-ancient-one/container-security/actions/workflows/devsecops.yml)
[![CI/CD Pipeline](https://github.com/the-ancient-one/container-security/actions/workflows/ci_cd.yml/badge.svg?branch=main)](https://github.com/the-ancient-one/container-security/actions/workflows/ci_cd.yml)
[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.13341688.svg)](https://doi.org/10.5281/zenodo.13341688)

---

## Overview

This project implements a fully hardened, containerised PHP web application with a MariaDB database backend, built with a complete DevSecOps pipeline and GitOps deployment model. The stack covers security at every layer — from source code to runtime.

```
SECURITY LAYERS
─────────────────────────────────────────────────────────────────
1. TruffleHog    → secrets scanning on every push / PR
2. Trivy (fs)    → CVE scanning of source code and dependencies
3. Checkov       → IaC misconfiguration scanning (Dockerfile + K8s)
4. Trivy (image) → CVE scanning of built container images
────────────── DEPLOY GATE ──────────────────────────────────────
5. Kyverno       → admission control — blocks non-compliant pods
6. NetworkPolicy → restricts pod-to-pod and external traffic
────────────── GITOPS ───────────────────────────────────────────
7. ArgoCD        → auto-syncs cluster state from Git
─────────────────────────────────────────────────────────────────
```

---

##  Quick Start — Two Scripts, One Command Each

> All setup and teardown is managed through two scripts.
> No need to copy-paste individual `kubectl` or `helm` commands.

```bash
# Make scripts executable (one-time)
chmod +x scripts/setup.sh
chmod +x scripts/teardown.sh

# Full Kubernetes stack in one shot
bash scripts/setup.sh all

# Or tear everything down
bash scripts/teardown.sh all
```

---

## Folder Structure

| File/Folder | Description |
| --- | --- |
| `./` | Root directory of the project |
| `.env` | Environment variables for Docker Compose (image tags, ports, IPs) |
| `.git/` | Git repository config and objects |
| `.github/workflows/` | GitHub Actions CI/CD pipeline definitions |
| `docker-compose.yml` | Docker Compose configuration for local development |
| `scripts/` | Automation scripts for full stack lifecycle manage
| `webserver/` | Nginx + PHP-FPM web application (Dockerfile + config + webfiles) |
| `dbserver/` | MariaDB database server (Dockerfile + config + SQL init) |
| `seccomp/` | Custom seccomp profiles for Docker Compose containers |
| `test-cases/` | Shell scripts for integration test cases |
| `kubectl_dashboard/` | Kubernetes dashboard RBAC and ServiceAccount |
| `kubectl_yml/` | Kubernetes deployment manifests |
| `kubectl_yml/security/` | Kyverno admission policies and NetworkPolicies |

---

## Complete Folder Tree

```
.
├── README.md
├── VideoReadME.md
├── .env
├── .git/
├── .github/
│   └── workflows/
│       ├── devsecops.yml          # Security scanning pipeline (runs first)
│       └── ci_cd.yml              # Build and deploy pipeline (runs after devsecops)
├── docker-compose.yml
├── dbserver/
│   ├── Dockerfile
│   ├── db_password.txt             
│   ├── db_root_password.txt        
│   ├── mysqld.cnf                 # MariaDB server configuration
│   └── sqlconfig/
│       └── csvs23db.sql           # DB init: CREATE DATABASE, CREATE USER, GRANT
├── webserver/
│   ├── Dockerfile
│   ├── configfiles/
│   │   ├── docker-entrypoint.sh
│   │   ├── nginx.conf
│   │   ├── php-fpm.conf
│   │   ├── php.ini
│   │   └── www.conf
│   └── webfiles/
│       ├── index.php
│       ├── action.php
│       └── style.css
├── seccomp/
│   ├── webapp.json                # Seccomp profile for Nginx + PHP-FPM container
│   └── mariadb.json               # Seccomp profile for MariaDB container
├── test-cases/
│   └── test-case.sh
├── kubectl_dashboard/
│   ├── service-acc.yaml           # ServiceAccount for K8s dashboard
│   └── cluster-rbac.yaml          # ClusterRoleBinding for dashboard access
└── kubectl_yml/
    ├── db-data-persistentvolumeclaim.yaml
    ├── csvs-dbserver-claim1-persistentvolumeclaim.yaml
    ├── db-password-secret.yaml             
    ├── csvs_dbserver-service.yaml         # ClusterIP service for MariaDB
    ├── csvs_webserver-service.yaml        # NodePort service for Nginx
    ├── csvs-dbserver-deployment.yaml      # MariaDB deployment (hardened)
    ├── csvs-webserver-deployment.yaml     # Nginx + PHP deployment (hardened)
    └── security/
        ├── kyverno-policies.yaml          # Admission control policies
        └── networkpolicy.yaml             # Pod-to-pod traffic rules
```

---

## Architecture

```
EXTERNAL USER
      │
      │ HTTP :30080 (NodePort)
      ▼
┌─────────────────────────────────────────────────────────────────┐
│  namespace: csvs                                                │
│                                                                 │
│  ┌───────────────────────┐          ┌───────────────────────┐  │
│  │  csvs-webserver pod   │          │  csvs-dbserver pod    │  │
│  │  Nginx + PHP-FPM      │─:3306───▶│  MariaDB 10.11        │  │
│  │                       │          │                       │  │
│  │  runAsUser: 101        │          │  runAsUser: 999        │  │
│  │  drop: ALL caps        │          │  drop: ALL caps        │  │
│  │  seccomp: Runtime      │          │  seccomp: Runtime      │  │
│  └───────────────────────┘          └───────────────────────┘  │
│                                                                 │
│  NetworkPolicy: default-deny-all + explicit allow rules        │
│  Kyverno: enforces securityContext, probes, namespace, caps     │
└─────────────────────────────────────────────────────────────────┘
         ▲
         │ GitOps sync (every 3 min or webhook)
         │
┌────────┴────────┐
│   ArgoCD        │◀── Git repo: kubectl_yml/
│   (argocd ns)   │    single source of truth
└─────────────────┘
         ▲
         │ Admission webhook
         │
┌────────┴────────┐
│   Kyverno       │◀── kubectl_yml/security/kyverno-policies.yaml
│   (kyverno ns)  │    blocks non-compliant pods
└─────────────────┘
```

---

## Prerequisites

### Homebrew
```bash
# Install required tools
brew install docker minikube kubectl helm argocd

# Verify versions
minikube version
kubectl version --client
helm version
argocd version --client
```

### Make Scripts Executable (one-time)
```bash
chmod +x scripts/setup.sh
chmod +x scripts/teardown.sh
```

### Start Minikube
```bash
minikube start \
  --driver=docker \
  --cpus=2 \
  --memory=6000mb \
  --kubernetes-version=v1.31.0

# Verify cluster is healthy
minikube status
kubectl config current-context    # should show: minikube
kubectl cluster-info
```

> ⚠️ **Docker Desktop must be running** before `minikube start`.
> Allocate at least **2 CPUs** and **6 GB RAM** in Docker Desktop → Settings → Resources.

---

## `scripts/setup.sh` — Command Reference

> All Kubernetes setup is now managed through a single script.
> Run `bash scripts/setup.sh help` at any time to see all available commands.

```
Usage: bash scripts/setup.sh <command>

Commands:
  minikube    Start minikube with correct resource settings
  k8s         Deploy all Kubernetes resources to csvs namespace
  kyverno     Install Kyverno and apply admission policies (Audit mode)
  enforce     Switch Kyverno policies from Audit → Enforce mode
  argocd      Install ArgoCD and create the GitOps application
  all         Run all steps in order (minikube → k8s → kyverno → argocd)
  status      Show live status of every component
  help        Show this help message
```

---

## `scripts/teardown.sh` — Command Reference

> All cleanup is now managed through a single teardown script.
> Destructive operations require confirmation before executing.

```
Usage: bash scripts/teardown.sh <command>

Commands:
  app         Remove app resources in 'csvs' namespace (keeps minikube)
  kyverno     Remove Kyverno and all ClusterPolicies
  argocd      Remove ArgoCD application and installation
  all         Remove app + Kyverno + ArgoCD (keeps minikube running)
  minikube    Delete the entire minikube cluster and all data
  help        Show this help message
```

---

## 1. Docker Compose (Local Development)

Docker Compose is used for local development and testing only.
All production-equivalent deployment uses the Kubernetes path below.

### Running the Application

```bash
# Build and start containers
docker-compose up --build -d

# Force recreate containers (use after config changes)
docker-compose up --force-recreate -d

# View running containers
docker-compose ps

# View logs
docker-compose logs -f

# Teardown
docker-compose down

# Full clean (remove images and cached layers)
docker rmi -f $(docker images -a -q)
docker buildx prune -f
```

> Run commands in order. `--build` is required on first run or after Dockerfile changes.
> **Note:** Image tag and version are controlled via the `.env` file.
> Update `DB_IMAGE_TAG` and `WEB_IMAGE_TAG` there — not in the Compose file directly.

## 2. DevSecOps Pipeline (GitHub Actions)

The pipeline runs in two stages, chained via `workflow_run`:

```
git push / pull_request to main
        │
        ▼
devsecops.yml (Stage 1 — Security Scanning)
        │
        ├── Job 1: Secrets Scanning (TruffleHog)
        │         Scans git diff for leaked credentials
        │
        ├── Job 2: SAST/SCA (Trivy filesystem)
        │         Scans source code for CVEs (CRITICAL/HIGH)
        │
        ├── Job 3: IaC Scanning (Checkov)
        │         Scans Dockerfiles + K8s manifests
        │         Findings uploaded to GitHub Security tab
        │         Pipeline continues regardless (soft gate)
        │
        └── Job 4: Container Image Scan (Trivy)
                  Builds both images, scans for CVEs
                  Findings uploaded to GitHub Security tab
        │
        │ (only if devsecops passes)
        ▼
ci_cd.yml (Stage 2 — Build and Deploy)
        └── Runs after devsecops workflow completes successfully
```

### Viewing Security Findings

All SARIF reports are uploaded to the **GitHub Security tab**:
```
GitHub Repo → Security → Code Scanning
```

Four separate scan categories visible:
| Category | Tool | What it scans |
|---|---|---|
| `trivy-fs` | Trivy | Source code + dependencies |
| `checkov-iac` | Checkov | Dockerfiles + K8s manifests |
| `trivy-webapp` | Trivy | Nginx + PHP container image |
| `trivy-mariadb` | Trivy | MariaDB container image |

---

## 3. Kubernetes Deployment

> **[CHANGED]** Use `scripts/setup.sh` instead of running `kubectl` commands manually.
> The script handles ordering, waiting, and error checking automatically.

### Option A: Full Automated Setup (Recommended)

```bash
# Runs all steps in correct order:
# minikube start → build images → create namespace + secrets
# → apply manifests → install Kyverno → install ArgoCD
bash scripts/setup.sh all
```

### Option B: Step-by-Step Setup

```bash
# Step 1: Start minikube (2 CPUs, 6GB RAM, K8s v1.31.0)
bash scripts/setup.sh minikube

# Step 2: Deploy application to csvs namespace
#         Handles: namespace, secrets, PVCs, services, deployments
#         in the correct dependency order automatically
bash scripts/setup.sh k8s

# Step 3: Install Kyverno + apply admission policies (Audit mode)
bash scripts/setup.sh kyverno

# Step 4: Switch Kyverno from Audit → Enforce
#         Run ONLY after verifying audit reports show clean
bash scripts/setup.sh enforce

# Step 5: Install ArgoCD + create csvs-app GitOps application
bash scripts/setup.sh argocd
```

### Check Live Status of Everything

```bash
bash scripts/setup.sh status
```

This shows:
- Minikube node status
- Pods in `csvs` namespace
- Kyverno pods and ClusterPolicies
- ArgoCD pods and application sync status
- Application URL

### Access the Application

```bash
# Get URL (required on macOS — do NOT use localhost:30080 directly)
minikube service csvs-webserver --url -n csvs

# Or open directly in browser
minikube service csvs-webserver -n csvs
```

> ⚠️ **macOS with Docker driver:** The minikube node is not directly routable.
> Always use `minikube service` to get the correct tunnel URL.

### Kubernetes Dashboard (Optional)

```bash
# Open dashboard in browser (macOS opens automatically)
bash scripts/setup.sh dashboard

# Get login token
kubectl -n kubernetes-dashboard create token admin-user
```

---

## 4. Security Policies

> **[CHANGED]** Kyverno install and policy application are now handled inside
> `bash scripts/setup.sh kyverno`. The commands below are for reference and
> manual verification only.

### Kyverno Admission Control

Kyverno runs as an admission webhook — every `kubectl apply` or ArgoCD sync
passes through it before any pod is scheduled.

```
git push / ArgoCD sync
        │
        ▼
kubectl apply / ArgoCD sync
        │
        ▼
Kyverno Admission Webhook
        │
        ├── AUDIT mode:   logs violation, pod starts anyway
        └── ENFORCE mode: BLOCKS non-compliant pod entirely
```

#### Policies Enforced

| Policy | Checkov Check | What It Enforces |
|---|---|---|
| `require-namespace` | CKV_K8S_21 | Resources must not use `default` namespace |
| `require-run-as-non-root` | CKV_K8S_23 | Containers must not run as root |
| `require-pod-security-context` | CKV_K8S_29 | Pod-level securityContext required |
| `require-container-security-context` | CKV_K8S_30 | Container-level securityContext required |
| `require-drop-all-capabilities` | CKV_K8S_37/28 | Must drop ALL Linux capabilities |
| `disallow-automount-service-account-token` | CKV_K8S_38 | SA token must not be automounted |
| `require-liveness-probe` | CKV_K8S_8 | Liveness probe required on all containers |
| `require-readiness-probe` | CKV_K8S_9 | Readiness probe required on all containers |

#### Audit → Enforce Workflow

```bash
# 1. Install Kyverno and apply policies in Audit mode
bash scripts/setup.sh kyverno

# 2. Check audit report — verify your pods pass all policies
kubectl get policyreport -n csvs
kubectl describe policyreport -n csvs

# 3. If all policies pass — switch to Enforce
bash scripts/setup.sh enforce

# 4. Verify enforcement — this pod should be BLOCKED
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: bad-pod-test
  namespace: csvs
spec:
  containers:
    - name: bad
      image: nginx
EOF
# Expected: Error from server — blocked by Kyverno

# Clean up test
kubectl delete pod bad-pod-test -n csvs --ignore-not-found
```

### Network Policies

> **[NEW]** Network policies now live in `kubectl_yml/security/networkpolicy.yaml`
> and are applied automatically by `bash scripts/setup.sh k8s`.

Traffic rules enforced:

```
EXTERNAL  ──:80──►  csvs-webserver  ──:3306──►  csvs-dbserver
                         │                           │
                       :53 DNS ✅                  :53 DNS ✅
                     all else ❌                  all else ❌
```

| Policy | What It Does |
|---|---|
| `default-deny-all` | Blocks ALL ingress and egress by default |
| `allow-webserver-ingress` | Allows external HTTP to webserver on :80 |
| `allow-webserver-egress-to-db` | Allows webserver outbound to DB on :3306 |
| `allow-webserver-to-db` | Allows DB to receive from webserver on :3306 |
| `allow-dns-egress` | Allows all pods to resolve DNS on :53 UDP/TCP |

---

## 5. ArgoCD — GitOps Deployment

> **[CHANGED]** ArgoCD install and application creation are now handled inside
> `bash scripts/setup.sh argocd`. The commands below are for reference,
> UI access, and GitOps workflow guidance.

ArgoCD watches `kubectl_yml/` in Git and automatically syncs any changes
to the `csvs` namespace. After ArgoCD is active, **never run `kubectl apply`
directly** — ArgoCD will revert manual changes within ~30 seconds.

```
Git repo (kubectl_yml/)
        │
        │ ArgoCD polls every 3 minutes
        ▼
ArgoCD detects drift between Git and cluster
        │
        ▼
Kyverno validates the manifest        ← admission gate
        │
        ├── PASS → ArgoCD applies to csvs namespace
        └── FAIL → sync fails, visible in ArgoCD UI
```

### Access the ArgoCD UI

```bash
# Forward ArgoCD to localhost:8080 — keep this terminal open
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Open in browser (new terminal for all other commands)
open https://localhost:8080
```

> ⚠️ You will see a TLS certificate warning — this is expected.
> Click **Advanced** → **Proceed to localhost** to continue.

### CLI Reference

```bash
# Check application status
argocd app get csvs-app --insecure

# Trigger a manual sync
argocd app sync csvs-app --insecure

# Watch sync in real time
argocd app wait csvs-app --health --insecure

# List all resources managed by ArgoCD
argocd app resources csvs-app --insecure
```

### GitOps Workflow — Correct Way to Make Changes

```
⚠️  With ArgoCD active — NEVER use kubectl apply directly
    Changes made with kubectl are reverted by ArgoCD within ~30 seconds

CORRECT WORKFLOW
─────────────────────────────────────────────────────────────
1. Edit YAML files locally in kubectl_yml/
2. git add → git commit → git push
3. ArgoCD detects change (within 3 minutes or on webhook)
4. Kyverno validates the manifest
5. ArgoCD applies the change to the cluster automatically
─────────────────────────────────────────────────────────────
```

### Verify the GitOps Loop

```bash
# 1. Make a change — add a label to webserver deployment
#    metadata.labels.version: "1.6"

# 2. Commit and push
git add kubectl_yml/csvs-webserver-deployment.yaml
git commit -m "test: add version label to verify ArgoCD sync"
git push origin main

# 3. Watch ArgoCD detect and sync
argocd app get csvs-app --insecure
# Briefly shows: OutOfSync → then returns to: Synced

# 4. Test self-heal — ArgoCD reverts manual changes
kubectl label deployment csvs-webserver -n csvs test=manual-change
# Wait ~30 seconds
kubectl get deployment csvs-webserver -n csvs \
  -o jsonpath='{.metadata.labels}' && echo
# test=manual-change should be GONE — reverted by ArgoCD
```

---

## 6. Teardown

> **[CHANGED]** All cleanup is managed through `scripts/teardown.sh`.

```bash
# Remove application resources only (keeps minikube, Kyverno, ArgoCD)
bash scripts/teardown.sh app

# Remove Kyverno and all policies
bash scripts/teardown.sh kyverno

# Remove ArgoCD application and installation
bash scripts/teardown.sh argocd

# Remove app + Kyverno + ArgoCD (keeps minikube running)
bash scripts/teardown.sh all

# Full wipe — delete entire minikube cluster
bash scripts/teardown.sh minikube
```

> ⚠️ All teardown commands that delete data require typing a confirmation
> before executing. `teardown minikube` destroys all cluster data permanently.

---

## Security Implementation Summary

| Layer | Tool | Mode | What It Does |
|---|---|---|---|
| Secrets scanning | TruffleHog | Block on verified secrets | Scans git diff on push/PR |
| SAST/SCA | Trivy | Block on CRITICAL/HIGH | Scans source + dependencies |
| IaC scanning | Checkov | Soft gate — logs findings | Scans Dockerfiles + K8s manifests |
| Image scanning | Trivy | Logs findings | Scans built container images |
| Admission control | Kyverno | Audit → Enforce | Blocks non-compliant pods at API server |
| Network control | NetworkPolicy | Enforce | Default-deny + 4 explicit allow rules |
| GitOps | ArgoCD | Auto-sync + self-heal | Git = single source of truth |
| Seccomp | Custom profiles | Enforce (Compose) | Restricts container syscalls |
| Capabilities | drop: ALL | Enforce | Removes all Linux capabilities |

---

## Known Limitations and Future Improvements

| Item | Current State | Improvement |
|---|---|---|
| Image tags | Hardcoded in deployment YAML | Convert to Helm chart with `values.yaml` |
| Secret management | Manually created via `kubectl create secret` | Sealed Secrets or External Secrets Operator |
| Single environment | minikube only | Kustomize overlays for dev/staging/prod |
| Container registry | `imagePullPolicy: Never` (local only) | Push to GHCR for full GitOps CI/CD |
| Runtime security | Not yet implemented | Add Falco for syscall-level intrusion detection |
| Service mesh | Not yet implemented | Add Cilium + Hubble for L7 NetworkPolicy |
| In-cluster CI | Not yet implemented | Tekton pipelines replacing GitHub Actions build |

---

## Troubleshooting Quick Reference

```bash
# Pod stuck in ImagePullBackOff
eval $(minikube docker-env)
docker images | grep u123456        # verify image exists in minikube
eval $(minikube docker-env --unset)

# Pod stuck in Pending
kubectl describe pod <pod-name> -n csvs | grep -A10 "Events:"
# Look for: Insufficient memory / hostPort conflict / PVC not found

# Service has no endpoints
kubectl get endpoints -n csvs
kubectl get service csvs-webserver -n csvs \
  -o jsonpath='{.spec.selector}' && echo
kubectl get pods -n csvs --show-labels   # selector must match pod labels

# ArgoCD shows OutOfSync
argocd app sync csvs-app --insecure
argocd app wait csvs-app --health --insecure

# Kyverno blocking a pod unexpectedly
kubectl describe pod <pod-name> -n csvs | grep -A5 "Events:"
# Shows which policy is blocking and which field is missing

# Database crash loop
kubectl logs <dbserver-pod> -n csvs --previous
# Common causes: wrong secret key name, corrupt PVC, PID limit

# NodePort not reachable on macOS
minikube service csvs-webserver --url -n csvs
# Do NOT use localhost:30080 — use the URL from this command

# Full status overview
bash scripts/setup.sh status
```

---

## Script Design Principles

Both `setup.sh` and `teardown.sh` follow these conventions:

| Convention | Detail |
|---|---|
| **Single argument dispatch** | `bash scripts/setup.sh <command>` — one argument controls everything |
| **Coloured output** | `[INFO]` blue / `[OK]` green / `[WARN]` yellow / `[ERROR]` red |
| **Idempotent** | Safe to re-run — checks resource existence before creating |
| **Prerequisite checks** | Fails fast with a clear message if `docker`, `minikube`, `helm`, or `argocd` are missing |
| **Confirmation prompts** | Destructive operations require explicit `y` confirmation |
| **Pod readiness waits** | Scripts wait for pods to be `Ready` before proceeding to next step |
| **Error on failure** | `set -euo pipefail` — any unhandled error stops the script immediately |