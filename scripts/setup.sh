#!/usr/bin/env bash
# =============================================================================
# setup.sh — Full Stack Setup Orchestrator
# Cyber Security for Virtualisation Systems  
#
# Usage:
#   bash scripts/setup.sh <command>
#
# Commands:
#   compose     Build and start the Docker Compose stack (local dev)
#   minikube    Start minikube with correct resource settings
#   k8s         Deploy all Kubernetes resources to csvs namespace
#   kyverno     Install Kyverno and apply admission policies (Audit mode)
#   enforce     Switch Kyverno policies from Audit → Enforce mode
#   argocd      Install ArgoCD and create the GitOps application
#   all         Run all Kubernetes steps in order
#   status      Show live status of every component
#   dashboard   Open the Kubernetes dashboard
#   test        Run integration test cases against the running stack
#
# Requirements (macOS):
#   brew install docker minikube kubectl helm argocd
#   Docker Desktop must be running with >= 2 CPUs and 6 GB RAM
#
# Stack overview:
#
#   git push
#       │
#       ▼
#   GitHub Actions (devsecops.yml → ci_cd.yml)
#   TruffleHog → Trivy → Checkov → Image Scan
#       │
#       ▼
#   Kyverno Admission Webhook  ← GATE: blocks non-compliant pods
#       │
#       ▼
#   csvs namespace
#   ├── csvs-webserver  (Nginx + PHP-FPM)
#   └── csvs-dbserver   (MariaDB 10.11)
#       │
#       ▼
#   ArgoCD  ← GitOps: auto-syncs cluster state from Git
#       │
#       ▼
#   NetworkPolicy  ← default-deny-all + 4 explicit allow rules
#
# =============================================================================

set -euo pipefail

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

# ── Logging helpers ───────────────────────────────────────────────────────────
info()    { echo -e "${BLUE}${BOLD}[INFO]${NC}    $1"; }
success() { echo -e "${GREEN}${BOLD}[OK]${NC}      $1"; }
warn()    { echo -e "${YELLOW}${BOLD}[WARN]${NC}    $1"; }
error()   { echo -e "${RED}${BOLD}[ERROR]${NC}   $1"; exit 1; }
step()    { echo -e "  ${MAGENTA}→${NC} $1"; }
section() {
  echo -e "\n${CYAN}${BOLD}══════════════════════════════════════════${NC}"
  echo -e "${CYAN}${BOLD}  $1${NC}"
  echo -e "${CYAN}${BOLD}══════════════════════════════════════════${NC}\n"
}

# ── Config ────────────────────────────────────────────────────────────────────
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KUBECTL_YML="${REPO_ROOT}/kubectl_yml"
NAMESPACE="csvs"
MINIKUBE_CPUS=2
MINIKUBE_MEMORY=6000
MINIKUBE_K8S_VERSION="v1.31.0"
KYVERNO_VERSION="3.2.0"
ARGOCD_APP_NAME="csvs-app"
GITHUB_REPO="https://github.com/the-ancient-one/container-security"
DB_IMAGE="u123456_csvs_dbserver_i:1.5"
WEB_IMAGE="u123456_csvs_webserver_i:1.5"

# Source image names from .env if available
if [[ -f "${REPO_ROOT}/.env" ]]; then
  source "${REPO_ROOT}/.env" 2>/dev/null || true
  DB_IMAGE="${SID:-u123456}_${DB_NAME:-csvs_dbserver}_i:${DB_IMAGE_TAG:-1.5}"
  WEB_IMAGE="${SID:-u123456}_${WEB_NAME:-csvs_webserver}_i:${WEB_IMAGE_TAG:-1.5}"
fi

# ── Utility functions ─────────────────────────────────────────────────────────

# Confirm binary is installed
require_binary() {
  command -v "$1" >/dev/null 2>&1 || \
    error "'$1' not found. Install with: brew install $1"
}

# Wait for pods matching a label selector to become Ready
wait_for_pods() {
  local namespace=$1 selector=$2 timeout=${3:-180}
  info "Waiting for pods [${selector}] in '${namespace}' (timeout: ${timeout}s)..."
  kubectl wait pod \
    --namespace "${namespace}" \
    --for=condition=Ready \
    --selector="${selector}" \
    --timeout="${timeout}s" \
    || error "Pods did not become ready. Check: kubectl get pods -n ${namespace}"
  success "Pods ready: ${selector}"
}

# Wait for a PVC to reach Bound status
wait_for_pvc() {
  local name=$1 namespace=$2 retries=20
  info "Waiting for PVC '${name}' to bind..."
  for i in $(seq 1 "${retries}"); do
    local status
    status=$(kubectl get pvc "${name}" -n "${namespace}" \
             -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
    if [[ "${status}" == "Bound" ]]; then
      success "PVC '${name}' is Bound"
      return 0
    fi
    echo -n "."
    sleep 3
  done
  echo ""
  error "PVC '${name}' did not bind. Run: kubectl describe pvc ${name} -n ${namespace}"
}

# Check if a K8s resource already exists
resource_exists() {
  local kind=$1 name=$2 namespace=${3:-""}
  if [[ -n "${namespace}" ]]; then
    kubectl get "${kind}" "${name}" -n "${namespace}" >/dev/null 2>&1
  else
    kubectl get "${kind}" "${name}" >/dev/null 2>&1
  fi
}

# Confirm prompt for destructive actions
confirm() {
  read -r -p "${1} [y/N]: " response
  [[ "${response}" =~ ^[Yy]$ ]] || { info "Aborted"; exit 0; }
}

# ── Docker Compose ────────────────────────────────────────────────────────────
setup_compose() {
  local subcmd="${1:-up}"
  section "Docker Compose — ${subcmd}"

  require_binary docker

  # Check Docker Desktop is running
  docker info >/dev/null 2>&1 || error "Docker Desktop is not running. Start it and retry."

  [[ -f "${REPO_ROOT}/.env" ]] || \
    error ".env file not found. Run from the project root."
  [[ -f "${REPO_ROOT}/docker-compose.yml" ]] || \
    error "docker-compose.yml not found."
  [[ -f "${REPO_ROOT}/dbserver/db_password.txt" ]] || \
    error "dbserver/db_password.txt not found."
  [[ -f "${REPO_ROOT}/dbserver/db_root_password.txt" ]] || \
    error "dbserver/db_root_password.txt not found."

  cd "${REPO_ROOT}"

  case "${subcmd}" in
    up)
      info "Building images and starting containers..."
      docker compose up --build --force-recreate -d

      info "Waiting for containers to be healthy..."
      local retries=10 count=0
      until docker compose ps | grep -q "healthy" || [[ ${count} -ge ${retries} ]]; do
        sleep 5
        count=$((count + 1))
        step "Waiting... (${count}/${retries})"
      done

      echo ""
      docker compose ps
      success "Stack is up."
      WEB_PORT=$(grep WEB_SERVER_PORT .env | cut -d= -f2)
      info "Access the app at: http://localhost:${WEB_PORT}"
      ;;

    down)
      info "Stopping containers..."
      docker compose down
      success "Stack stopped."
      ;;

    clean)
      confirm "This will remove ALL Docker images and cached layers. Continue?"
      docker compose down --remove-orphans
      # shellcheck disable=SC2046
      docker rmi -f $(docker images -a -q) 2>/dev/null || true
      docker buildx prune -f
      success "Full clean complete. Run 'compose up' to rebuild."
      ;;

    test)
      [[ -f "${REPO_ROOT}/test-cases/test-case.sh" ]] || \
        error "test-cases/test-case.sh not found."
      docker compose ps | grep -q "Up" || \
        error "Stack is not running. Run: bash scripts/setup.sh compose up"
      cd "${REPO_ROOT}/test-cases/"
      bash test-case.sh
      cd "${REPO_ROOT}"
      success "Test cases complete."
      ;;

    logs)
      info "Tailing logs (Ctrl+C to stop)..."
      docker compose logs -f
      ;;

    status)
      docker compose ps
      echo ""
      info "Container health:"
      docker inspect --format='{{.Name}} → {{.State.Health.Status}}' \
        $(docker compose ps -q) 2>/dev/null || docker compose ps
      ;;

    *)
      error "Unknown compose subcommand: '${subcmd}'. Use: up | down | clean | test | logs | status"
      ;;
  esac
}

# ── Minikube ──────────────────────────────────────────────────────────────────
setup_minikube() {
  section "Step 1: Minikube Setup"

  require_binary minikube
  require_binary kubectl
  require_binary helm

  info "Checking Docker Desktop is running..."
  docker info >/dev/null 2>&1 || \
    error "Docker Desktop is not running. Start it and retry."
  success "Docker Desktop is running"

  if minikube status 2>/dev/null | grep -q "Running"; then
    warn "Minikube is already running"
    local current_mem
    current_mem=$(minikube config get memory 2>/dev/null || echo "unknown")
    info "Current memory allocation: ${current_mem}MB"
    if [[ "${current_mem}" != "${MINIKUBE_MEMORY}" ]]; then
      warn "Memory is not ${MINIKUBE_MEMORY}MB"
      warn "To fix: minikube stop && bash scripts/setup.sh minikube"
    fi
  else
    info "Starting minikube (CPUs=${MINIKUBE_CPUS}, Memory=${MINIKUBE_MEMORY}MB, K8s=${MINIKUBE_K8S_VERSION})..."
    minikube start \
      --driver=docker \
      --cpus="${MINIKUBE_CPUS}" \
      --memory="${MINIKUBE_MEMORY}mb" \
      --kubernetes-version="${MINIKUBE_K8S_VERSION}"
  fi

  info "Verifying cluster health..."
  kubectl cluster-info >/dev/null 2>&1 || error "Cluster is not reachable after start"
  local node_status
  node_status=$(kubectl get node minikube -o jsonpath='{.status.conditions[-1].type}' 2>/dev/null)
  [[ "${node_status}" == "Ready" ]] || error "Node is not Ready: ${node_status}"
  success "Cluster is healthy"

  echo ""
  info "Allocated resources:"
  kubectl describe node minikube | grep -A6 "Allocated resources" | tail -6 || true

  echo ""
  success "Minikube is ready"
  info "Context: $(kubectl config current-context)"
}

# ── Kubernetes Resources ──────────────────────────────────────────────────────
setup_k8s() {
  section "Step 2: Kubernetes Resources"

  require_binary kubectl
  minikube status 2>/dev/null | grep -q "Running" || \
    error "Minikube is not running. Run: bash scripts/setup.sh minikube"

  # ── Build images inside minikube daemon ──
  info "Pointing Docker CLI to minikube's daemon..."
  eval "$(minikube docker-env)"

  info "Building webserver image: ${WEB_IMAGE}"
  docker build -t "${WEB_IMAGE}" "${REPO_ROOT}/webserver/" \
    || error "Webserver build failed. Check Dockerfile in webserver/"
  success "Webserver image built: ${WEB_IMAGE}"

  info "Building dbserver image: ${DB_IMAGE}"
  docker build -t "${DB_IMAGE}" "${REPO_ROOT}/dbserver/" \
    || error "DBserver build failed. Check Dockerfile in dbserver/"
  success "DBserver image built: ${DB_IMAGE}"

  info "Verifying images inside minikube..."
  minikube image ls | grep -E "csvs_webserver|csvs_dbserver" || \
    warn "Images not listed — check: minikube image ls"

  eval "$(minikube docker-env --unset)"

  # ── Namespace ──
  if resource_exists namespace "${NAMESPACE}"; then
    warn "Namespace '${NAMESPACE}' already exists — skipping creation"
  else
    kubectl create namespace "${NAMESPACE}"
    success "Namespace '${NAMESPACE}' created"
  fi

  # ── Secrets ──
  info "Checking secret files..."
  local db_pass="${REPO_ROOT}/dbserver/db_password.txt"
  local db_root="${REPO_ROOT}/dbserver/db_root_password.txt"
  [[ -f "${db_pass}" ]]  || error "Missing: dbserver/db_password.txt"
  [[ -f "${db_root}" ]]  || error "Missing: dbserver/db_root_password.txt"

  if resource_exists secret db-password "${NAMESPACE}"; then
    warn "Secret 'db-password' already exists — deleting and recreating"
    kubectl delete secret db-password -n "${NAMESPACE}"
  fi
  kubectl create secret generic db-password \
    --from-file=db-password="${db_pass}" \
    -n "${NAMESPACE}"
  success "Secret 'db-password' created (key: db-password)"

  if resource_exists secret db-root-password "${NAMESPACE}"; then
    warn "Secret 'db-root-password' already exists — deleting and recreating"
    kubectl delete secret db-root-password -n "${NAMESPACE}"
  fi
  kubectl create secret generic db-root-password \
    --from-file=db-root-password="${db_root}" \
    -n "${NAMESPACE}"
  success "Secret 'db-root-password' created (key: db-root-password)"

  # ── PVCs ──
  info "Applying PersistentVolumeClaims..."
  kubectl apply -f "${KUBECTL_YML}/db-data-persistentvolumeclaim.yaml"
  kubectl apply -f "${KUBECTL_YML}/csvs-dbserver-claim1-persistentvolumeclaim.yaml"
  wait_for_pvc "db-data" "${NAMESPACE}"
  success "PVCs bound"

  # ── Services ──
  info "Applying Services..."
  kubectl apply -f "${KUBECTL_YML}/csvs_dbserver-service.yaml"
  kubectl apply -f "${KUBECTL_YML}/csvs_webserver-service.yaml"
  success "Services applied"

  # ── Network Policies ──
  info "Applying Network Policies..."
  kubectl apply -f "${KUBECTL_YML}/security/networkpolicy.yaml"
  success "Network Policies applied"

  # ── Deployments ──
  info "Applying Deployments..."
  kubectl apply -f "${KUBECTL_YML}/csvs-dbserver-deployment.yaml"
  kubectl apply -f "${KUBECTL_YML}/csvs-webserver-deployment.yaml"

  info "Waiting for DB pod (MariaDB needs up to 3 min on first init)..."
  wait_for_pods "${NAMESPACE}" "io.kompose.service=csvs-dbserver" 180

  info "Waiting for webserver pod..."
  wait_for_pods "${NAMESPACE}" "io.kompose.service=csvs-webserver" 120

  # ── Dashboard RBAC ──
  info "Applying Kubernetes Dashboard RBAC..."
  kubectl apply -f "${REPO_ROOT}/kubectl_dashboard/service-acc.yaml"
  kubectl apply -f "${REPO_ROOT}/kubectl_dashboard/cluster-rbac.yaml"
  success "Dashboard RBAC applied"

  echo ""
  success "All Kubernetes resources deployed to namespace '${NAMESPACE}'"
  echo ""
  info "Get app URL:"
  echo "       minikube service csvs-webserver -n ${NAMESPACE} --url"
}

# ── Kyverno ───────────────────────────────────────────────────────────────────
setup_kyverno() {
  section "Step 3: Kyverno Admission Control"

  require_binary helm
  require_binary kubectl

  info "Adding Kyverno Helm repo..."
  helm repo add kyverno https://kyverno.github.io/kyverno/ 2>/dev/null || true
  helm repo update

  if helm status kyverno -n kyverno >/dev/null 2>&1; then
    warn "Kyverno already installed — upgrading to v${KYVERNO_VERSION}..."
    helm upgrade kyverno kyverno/kyverno \
      --namespace kyverno \
      --version "${KYVERNO_VERSION}" \
      --set replicaCount=1 \
      --set admissionController.replicas=1 \
      --set backgroundController.replicas=1 \
      --set cleanupController.replicas=1 \
      --set reportsController.replicas=1
  else
    info "Installing Kyverno v${KYVERNO_VERSION}..."
    helm install kyverno kyverno/kyverno \
      --namespace kyverno \
      --create-namespace \
      --version "${KYVERNO_VERSION}" \
      --set replicaCount=1 \
      --set admissionController.replicas=1 \
      --set backgroundController.replicas=1 \
      --set cleanupController.replicas=1 \
      --set reportsController.replicas=1
  fi

  info "Waiting for Kyverno pods to be ready..."
  kubectl wait pod \
    --namespace kyverno \
    --for=condition=Ready \
    --all \
    --timeout=180s \
    || error "Kyverno pods not ready. Run: kubectl get pods -n kyverno"
  success "All Kyverno pods are ready"

  info "Verifying admission webhooks are registered..."
  local webhook_count
  webhook_count=$(kubectl get validatingwebhookconfigurations 2>/dev/null \
    | grep -c kyverno || echo 0)
  [[ "${webhook_count}" -gt 0 ]] || \
    warn "Webhooks not yet registered — wait 30s then check:"
  echo "       kubectl get validatingwebhookconfigurations | grep kyverno"
  success "Kyverno webhooks: ${webhook_count} found"

  # Apply policies
  local policy_file="${KUBECTL_YML}/security/kyverno-policies.yaml"
  [[ -f "${policy_file}" ]] || \
    error "Policy file not found: kubectl_yml/security/kyverno-policies.yaml"

  info "Applying Kyverno policies in AUDIT mode..."
  kubectl apply -f "${policy_file}"
  success "Policies applied"

  echo ""
  info "Policy status:"
  kubectl get clusterpolicy \
    -o custom-columns="NAME:.metadata.name,ACTION:.spec.validationFailureAction,READY:.status.ready" \
    2>/dev/null || true

  echo ""
  info "Checking audit report for namespace '${NAMESPACE}'..."
  sleep 5
  kubectl get policyreport -n "${NAMESPACE}" 2>/dev/null || \
    info "Report not ready yet. Check in 30s: kubectl get policyreport -n ${NAMESPACE}"

  echo ""
  success "Kyverno installed — policies running in AUDIT mode"
  warn "Switch to ENFORCE mode after verifying no violations:"
  echo "       bash scripts/setup.sh enforce"
}

# ── Kyverno: Audit → Enforce ──────────────────────────────────────────────────
enforce_kyverno() {
  section "Kyverno: Switching to ENFORCE Mode"

  info "Checking for existing violations in '${NAMESPACE}'..."
  local violations
  violations=$(kubectl get policyreport -n "${NAMESPACE}" \
    -o jsonpath='{.items[*].summary.fail}' 2>/dev/null \
    | tr ' ' '\n' | awk '{s+=$1} END {print s+0}')

  if [[ "${violations}" -gt 0 ]]; then
    warn "Found ${violations} violation(s) — enforcing will block pods on next rollout"
    kubectl get policyreport -n "${NAMESPACE}" -o wide 2>/dev/null || true
    confirm "Violations exist. Switch to Enforce anyway?"
  else
    success "No violations found — safe to enforce"
  fi

  local policies=(
    require-namespace
    require-run-as-non-root
    require-pod-security-context
    require-container-security-context
    require-drop-all-capabilities
    disallow-automount-service-account-token
    require-liveness-probe
    require-readiness-probe
    require-resource-limits
  )

  for policy in "${policies[@]}"; do
    if kubectl get clusterpolicy "${policy}" >/dev/null 2>&1; then
      kubectl patch clusterpolicy "${policy}" \
        --type='json' \
        -p='[{"op":"replace","path":"/spec/validationFailureAction","value":"Enforce"}]' \
        && step "Enforced: ${policy}" \
        || warn "Could not patch: ${policy}"
    else
      warn "Policy not found (skipping): ${policy}"
    fi
  done

  echo ""
  info "Policy enforcement status:"
  kubectl get clusterpolicy \
    -o custom-columns="NAME:.metadata.name,ACTION:.spec.validationFailureAction"

  # Smoke test
  echo ""
  info "Smoke test — deploying non-compliant pod (should be BLOCKED)..."
  result=$(kubectl apply -f - <<'EOF' 2>&1 || true
apiVersion: v1
kind: Pod
metadata:
  name: kyverno-enforce-test
  namespace: csvs
spec:
  containers:
    - name: bad
      image: nginx:latest
EOF
)
  if echo "${result}" | grep -qi "blocked\|denied\|webhook"; then
    success "Enforcement confirmed — non-compliant pod was BLOCKED"
  else
    warn "Pod was not blocked — check Kyverno logs:"
    echo "       kubectl logs -n kyverno -l app.kubernetes.io/component=admission-controller"
    echo "${result}"
  fi

  kubectl delete pod kyverno-enforce-test -n "${NAMESPACE}" --ignore-not-found >/dev/null 2>&1 || true
  success "Kyverno is now in ENFORCE mode"
}

# ── ArgoCD ────────────────────────────────────────────────────────────────────
setup_argocd() {
  section "Step 4: ArgoCD GitOps"

  require_binary kubectl
  require_binary helm

  # Install argocd CLI if not present
  if ! command -v argocd >/dev/null 2>&1; then
    warn "argocd CLI not found — installing via Homebrew..."
    brew install argocd
  fi

  info "Adding ArgoCD Helm repo..."
  helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true
  helm repo update

  if helm status argocd -n argocd >/dev/null 2>&1; then
    warn "ArgoCD already installed — upgrading..."
    helm upgrade argocd argo/argo-cd \
      --namespace argocd \
      --set server.service.type=ClusterIP \
      --set "configs.params.server\.insecure=true" \
      --set controller.replicas=1 \
      --set server.replicas=1 \
      --set repoServer.replicas=1
  else
    info "Installing ArgoCD via Helm..."
    helm install argocd argo/argo-cd \
      --namespace argocd \
      --create-namespace \
      --set server.service.type=ClusterIP \
      --set "configs.params.server\.insecure=true" \
      --set controller.replicas=1 \
      --set server.replicas=1 \
      --set repoServer.replicas=1
  fi

  info "Waiting for ArgoCD pods (2-3 minutes)..."
  kubectl wait pod \
    --namespace argocd \
    --for=condition=Ready \
    --all \
    --timeout=240s \
    || error "ArgoCD pods not ready. Run: kubectl get pods -n argocd"
  success "All ArgoCD pods are ready"

  # Get initial admin password
  local argocd_pass=""
  argocd_pass=$(kubectl get secret argocd-initial-admin-secret \
    -n argocd \
    -o jsonpath='{.data.password}' 2>/dev/null | base64 --decode || true)

  # Port-forward in background
  info "Starting port-forward to ArgoCD UI on localhost:8080..."
  pkill -f "kubectl port-forward.*argocd.*8080" 2>/dev/null || true
  sleep 1
  kubectl port-forward svc/argocd-server -n argocd 8080:80 &>/dev/null &
  local pf_pid=$!
  sleep 3

  kill -0 "${pf_pid}" 2>/dev/null || \
    error "Port-forward failed. Start manually: kubectl port-forward svc/argocd-server -n argocd 8080:80"
  success "Port-forward running (PID: ${pf_pid})"

  # CLI login
  if [[ -n "${argocd_pass}" ]]; then
    info "Logging into ArgoCD CLI..."
    argocd login localhost:8080 \
      --username admin \
      --password "${argocd_pass}" \
      --insecure \
      || warn "CLI login failed — log in manually: argocd login localhost:8080 --username admin --insecure"
    success "ArgoCD CLI authenticated"

    echo ""
    warn "Change the default admin password now:"
    argocd account update-password \
      --current-password "${argocd_pass}" \
      --insecure \
      || warn "Password change skipped — update it in the UI: http://localhost:8080"
  else
    warn "Initial admin secret not found — may have been changed already"
    warn "Log in manually: argocd login localhost:8080 --username admin --insecure"
  fi

  # Connect repo
  info "Connecting GitHub repo to ArgoCD..."
  if argocd repo list --insecure 2>/dev/null | grep -q "${GITHUB_REPO}"; then
    warn "Repo already connected — skipping"
  else
    argocd repo add "${GITHUB_REPO}" --insecure \
      || warn "Could not add repo. Add it manually: UI → Settings → Repositories"
  fi

  # Create application
  info "Creating ArgoCD Application '${ARGOCD_APP_NAME}'..."
  if argocd app get "${ARGOCD_APP_NAME}" --insecure >/dev/null 2>&1; then
    warn "Application '${ARGOCD_APP_NAME}' already exists — syncing..."
    argocd app sync "${ARGOCD_APP_NAME}" --insecure || \
      warn "Sync triggered — check UI for status"
  else
    argocd app create "${ARGOCD_APP_NAME}" \
      --repo "${GITHUB_REPO}" \
      --path kubectl_yml \
      --dest-server https://kubernetes.default.svc \
      --dest-namespace "${NAMESPACE}" \
      --sync-policy automated \
      --auto-prune \
      --self-heal \
      --revision HEAD \
      --insecure \
      || error "Failed to create ArgoCD application"
    success "Application '${ARGOCD_APP_NAME}' created"

    info "Waiting for initial sync to complete..."
    argocd app wait "${ARGOCD_APP_NAME}" \
      --health \
      --timeout 120 \
      --insecure \
      || warn "App not yet healthy — check the ArgoCD UI at http://localhost:8080"
  fi

  echo ""
  argocd app get "${ARGOCD_APP_NAME}" --insecure 2>/dev/null || true

  echo ""
  success "ArgoCD is running"
  echo ""
  echo -e "  ${GREEN}${BOLD}UI:${NC}        http://localhost:8080"
  echo -e "  ${GREEN}${BOLD}Username:${NC}  admin"
  [[ -n "${argocd_pass}" ]] && \
    echo -e "  ${GREEN}${BOLD}Password:${NC}  ${argocd_pass}  ${YELLOW}← change this!${NC}"
  echo ""
  warn "Port-forward must stay running. To restart it later:"
  echo "       kubectl port-forward svc/argocd-server -n argocd 8080:80"
}

# ── Full stack ────────────────────────────────────────────────────────────────
setup_all() {
  section "Full Kubernetes Stack Setup"
  info "Running all steps: minikube → k8s → kyverno → argocd"
  echo ""
  setup_minikube
  setup_k8s
  setup_kyverno
  setup_argocd
  echo ""
  section "Setup Complete"
  show_status
}

# ── Status ────────────────────────────────────────────────────────────────────
show_status() {
  section "Stack Status"

  echo -e "${BOLD}── Minikube ──────────────────────────────${NC}"
  minikube status 2>/dev/null || echo "  Not running"

  echo -e "\n${BOLD}── Nodes ─────────────────────────────────${NC}"
  kubectl get nodes 2>/dev/null || echo "  Cluster unreachable"

  echo -e "\n${BOLD}── Application Pods (${NAMESPACE}) ──────────${NC}"
  kubectl get pods -n "${NAMESPACE}" 2>/dev/null || echo "  No pods found"

  echo -e "\n${BOLD}── Services (${NAMESPACE}) ───────────────────${NC}"
  kubectl get service -n "${NAMESPACE}" 2>/dev/null || echo "  No services"

  echo -e "\n${BOLD}── Network Policies (${NAMESPACE}) ──────────${NC}"
  kubectl get networkpolicy -n "${NAMESPACE}" 2>/dev/null || echo "  No policies"

  echo -e "\n${BOLD}── Kyverno Pods ──────────────────────────${NC}"
  kubectl get pods -n kyverno 2>/dev/null || echo "  Not installed"

  echo -e "\n${BOLD}── Kyverno Policies ──────────────────────${NC}"
  kubectl get clusterpolicy \
    -o custom-columns="NAME:.metadata.name,ACTION:.spec.validationFailureAction,READY:.status.ready" \
    2>/dev/null || echo "  No policies found"

  echo -e "\n${BOLD}── ArgoCD Pods ───────────────────────────${NC}"
  kubectl get pods -n argocd 2>/dev/null || echo "  Not installed"

  echo -e "\n${BOLD}── ArgoCD Application ────────────────────${NC}"
  kubectl get application "${ARGOCD_APP_NAME}" \
    -n argocd \
    -o custom-columns="NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status" \
    2>/dev/null || echo "  Application not found"

  echo -e "\n${BOLD}── App Access ────────────────────────────${NC}"
  minikube service csvs-webserver -n "${NAMESPACE}" --url 2>/dev/null || \
    echo "  Service not available yet"
  echo ""
}

# ── Dashboard ─────────────────────────────────────────────────────────────────
open_dashboard() {
  section "Kubernetes Dashboard"

  minikube status 2>/dev/null | grep -q "Running" || \
    error "Minikube is not running. Run: bash scripts/setup.sh minikube"

  info "Generating dashboard token..."
  local token
  token=$(kubectl -n kubernetes-dashboard create token admin-user 2>/dev/null || \
    kubectl -n kube-system create token default 2>/dev/null || echo "")

  if [[ -n "${token}" ]]; then
    echo ""
    echo -e "  ${GREEN}${BOLD}Dashboard Token:${NC}"
    echo "${token}"
    echo ""
    info "Copy the token above to log into the dashboard"
  else
    warn "Could not generate token — apply dashboard RBAC first:"
    echo "       kubectl apply -f kubectl_dashboard/service-acc.yaml"
    echo "       kubectl apply -f kubectl_dashboard/cluster-rbac.yaml"
  fi

  info "Opening Kubernetes dashboard..."
  minikube dashboard
}

# ── Test cases ────────────────────────────────────────────────────────────────
run_tests() {
  section "Integration Test Cases"

  [[ -f "${REPO_ROOT}/test-cases/test-case.sh" ]] || \
    error "test-cases/test-case.sh not found"

  # Confirm stack is running
  kubectl get pods -n "${NAMESPACE}" 2>/dev/null | grep -q "Running" || \
    error "No running pods in '${NAMESPACE}'. Deploy first: bash scripts/setup.sh k8s"

  info "Running integration tests against namespace '${NAMESPACE}'..."
  cd "${REPO_ROOT}/test-cases/"
  bash test-case.sh
  cd "${REPO_ROOT}"
  success "Test cases complete"
}

# ── Usage / Help ──────────────────────────────────────────────────────────────
usage() {
  echo ""
  echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════════════════╗${NC}"
  echo -e "${CYAN}${BOLD}║   CSVS23 Setup Script — Usage Guide                 ║${NC}"
  echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════════════╝${NC}"
  echo ""
  echo -e "${BOLD}Usage:${NC}"
  echo "  bash scripts/setup.sh <command> [subcommand]"
  echo ""
  echo -e "${BOLD}── Docker Compose (local dev) ────────────────────────────────${NC}"
  echo "  compose up      Build images and start all containers"
  echo "  compose down    Stop and remove containers"
  echo "  compose clean   Full wipe: containers + images + build cache"
  echo "  compose test    Run integration test cases"
  echo "  compose logs    Tail logs from all containers"
  echo "  compose status  Show running containers and health"
  echo ""
  echo -e "${BOLD}── Kubernetes ────────────────────────────────────────────────${NC}"
  echo "  minikube    Start minikube (CPUs=2, Memory=6GB, K8s=v1.31.0)"
  echo "  k8s         Build images + deploy all resources to csvs namespace"
  echo "  kyverno     Install Kyverno + apply policies in Audit mode"
  echo "  enforce     Switch Kyverno policies from Audit → Enforce"
  echo "  argocd      Install ArgoCD + create GitOps application"
  echo "  all         Run: minikube → k8s → kyverno → argocd"
  echo ""
  echo -e "${BOLD}── Utilities ─────────────────────────────────────────────────${NC}"
  echo "  status      Live status of all components"
  echo "  dashboard   Open Kubernetes dashboard (generates token)"
  echo "  test        Run integration test cases against running K8s stack"
  echo ""
  echo -e "${BOLD}── Recommended Order ─────────────────────────────────────────${NC}"
  echo ""
  echo "  Local development:"
  echo "  1. bash scripts/setup.sh compose up"
  echo "  2. bash scripts/setup.sh compose test"
  echo "  3. bash scripts/setup.sh compose down"
  echo ""
  echo "  Full Kubernetes stack:"
  echo "  1. bash scripts/setup.sh minikube     # start cluster"
  echo "  2. bash scripts/setup.sh k8s          # deploy app"
  echo "  3. bash scripts/setup.sh kyverno      # add admission control"
  echo "  4. bash scripts/setup.sh enforce      # enforce policies"
  echo "  5. bash scripts/setup.sh argocd       # enable GitOps"
  echo "  6. bash scripts/setup.sh status       # verify everything"
  echo ""
  echo "  Or in one command:"
  echo "  bash scripts/setup.sh all"
  echo ""
  echo -e "${BOLD}── Stack Architecture ────────────────────────────────────────${NC}"
  echo ""
  echo "  git push → GitHub Actions (TruffleHog → Trivy → Checkov)"
  echo "           → Kyverno (admission gate)"
  echo "           → csvs namespace"
  echo "               ├── csvs-webserver (Nginx + PHP-FPM)"
  echo "               └── csvs-dbserver  (MariaDB 10.11)"
  echo "           → ArgoCD (GitOps sync from Git)"
  echo "           → NetworkPolicy (default-deny + 4 allow rules)"
  echo ""
  echo -e "${BOLD}── Requirements ──────────────────────────────────────────────${NC}"
  echo "  brew install minikube kubectl helm argocd"
  echo "  Docker Desktop running with >= 2 CPUs and 6 GB RAM"
  echo "  dbserver/db_password.txt      (create manually, gitignored)"
  echo "  dbserver/db_root_password.txt (create manually, gitignored)"
  echo ""
}

# ── Entry point ───────────────────────────────────────────────────────────────
case "${1:-help}" in
  compose)   setup_compose "${2:-up}" ;;
  minikube)  setup_minikube ;;
  k8s)       setup_k8s ;;
  kyverno)   setup_kyverno ;;
  enforce)   enforce_kyverno ;;
  argocd)    setup_argocd ;;
  all)       setup_all ;;
  status)    show_status ;;
  dashboard) open_dashboard ;;
  test)      run_tests ;;
  help|*)    usage ;;
esac
