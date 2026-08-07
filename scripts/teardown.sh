#!/usr/bin/env bash
# =============================================================================
# teardown.sh — Full Stack Teardown Orchestrator
# Cyber Security for Virtualisation Systems 
#
# Usage:
#   bash scripts/teardown.sh <command>
#
# Commands:
#   compose     Stop and remove Docker Compose stack
#   app         Remove application resources from csvs namespace only
#   kyverno     Remove Kyverno policies and uninstall Kyverno
#   argocd      Remove ArgoCD application and uninstall ArgoCD
#   k8s         Remove all csvs namespace resources (keeps minikube)
#   all         Remove everything except minikube
#   nuke        Full wipe — delete minikube cluster entirely
#   help        Show this help message
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
NAMESPACE="csvs"
ARGOCD_APP_NAME="csvs-app"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ── Utility ───────────────────────────────────────────────────────────────────
confirm() {
  echo -e "\n${YELLOW}${BOLD}⚠️  WARNING:${NC} $1"
  read -r -p "    Type 'yes' to confirm: " response
  [[ "${response}" == "yes" ]] || { info "Aborted — nothing was deleted"; exit 0; }
}

require_binary() {
  command -v "$1" >/dev/null 2>&1 || \
    error "'$1' not found. Install with: brew install $1"
}

resource_exists() {
  local kind=$1 name=$2 namespace=${3:-""}
  if [[ -n "${namespace}" ]]; then
    kubectl get "${kind}" "${name}" -n "${namespace}" >/dev/null 2>&1
  else
    kubectl get "${kind}" "${name}" >/dev/null 2>&1
  fi
}

# ── Teardown: Docker Compose ──────────────────────────────────────────────────
teardown_compose() {
  section "Teardown: Docker Compose Stack"

  require_binary docker
  docker info >/dev/null 2>&1 || error "Docker Desktop is not running."

  [[ -f "${REPO_ROOT}/docker-compose.yml" ]] || \
    error "docker-compose.yml not found. Run from the project root."

  cd "${REPO_ROOT}"

  info "Stopping and removing containers..."
  docker compose down --remove-orphans
  success "Containers removed"

  confirm "Remove ALL Docker images and build cache? This affects ALL Docker images on this machine."

  info "Removing all Docker images..."
  # shellcheck disable=SC2046
  docker rmi -f $(docker images -a -q) 2>/dev/null || \
    info "No images to remove"

  info "Pruning build cache..."
  docker buildx prune -f
  success "Docker Compose stack fully cleaned"

  echo ""
  info "To rebuild from scratch:"
  echo "       bash scripts/setup.sh compose up"
}

# ── Teardown: App resources only (keeps Kyverno + ArgoCD) ────────────────────
teardown_app() {
  section "Teardown: Application Resources (namespace: ${NAMESPACE})"

  require_binary kubectl
  kubectl cluster-info >/dev/null 2>&1 || \
    error "Cluster is unreachable. Is minikube running?"

  confirm "Remove all application resources from namespace '${NAMESPACE}'? (PVCs, secrets, deployments, services, network policies)"

  # Stop ArgoCD managing the app first to prevent it re-syncing resources back
  if command -v argocd >/dev/null 2>&1; then
    if argocd app get "${ARGOCD_APP_NAME}" --insecure >/dev/null 2>&1; then
      warn "ArgoCD is managing this app — pausing auto-sync to prevent re-creation..."
      argocd app patch "${ARGOCD_APP_NAME}" \
        --patch '{"spec":{"syncPolicy":null}}' \
        --type merge \
        --insecure 2>/dev/null \
        && step "Auto-sync paused" \
        || warn "Could not pause ArgoCD sync — resources may be recreated"
    fi
  fi

  step "Removing Deployments..."
  kubectl delete deployment --all -n "${NAMESPACE}" --ignore-not-found
  step "Removing Services..."
  kubectl delete service --all -n "${NAMESPACE}" --ignore-not-found
  step "Removing NetworkPolicies..."
  kubectl delete networkpolicy --all -n "${NAMESPACE}" --ignore-not-found
  step "Removing Secrets..."
  kubectl delete secret --all -n "${NAMESPACE}" --ignore-not-found
  step "Removing PVCs..."
  kubectl delete pvc --all -n "${NAMESPACE}" --ignore-not-found

  info "Waiting for pods to terminate..."
  kubectl wait pod \
    --all \
    --for=delete \
    --namespace="${NAMESPACE}" \
    --timeout=60s 2>/dev/null || true

  echo ""
  info "Remaining resources in '${NAMESPACE}':"
  kubectl get all -n "${NAMESPACE}" 2>/dev/null || echo "  (none)"
  success "Application resources removed from '${NAMESPACE}'"

  echo ""
  info "To redeploy:"
  echo "       bash scripts/setup.sh k8s"
}

# ── Teardown: Kyverno ─────────────────────────────────────────────────────────
teardown_kyverno() {
  section "Teardown: Kyverno"

  require_binary kubectl
  require_binary helm

  kubectl cluster-info >/dev/null 2>&1 || \
    error "Cluster is unreachable. Is minikube running?"

  confirm "Remove all Kyverno policies and uninstall Kyverno? Admission control will be DISABLED."

  # Remove policies first
  info "Removing ClusterPolicies..."
  kubectl delete clusterpolicy --all --ignore-not-found 2>/dev/null \
    && success "ClusterPolicies removed" \
    || warn "No ClusterPolicies found"

  info "Removing PolicyReports..."
  kubectl delete policyreport --all -n "${NAMESPACE}" --ignore-not-found 2>/dev/null || true
  kubectl delete clusterpolicyreport --all --ignore-not-found 2>/dev/null || true

  # Uninstall via Helm
  if helm status kyverno -n kyverno >/dev/null 2>&1; then
    info "Uninstalling Kyverno Helm release..."
    helm uninstall kyverno -n kyverno
    success "Kyverno Helm release removed"
  else
    warn "Kyverno Helm release not found — skipping Helm uninstall"
  fi

  info "Removing Kyverno CRDs..."
  kubectl delete crd \
    clusterpolicies.kyverno.io \
    policies.kyverno.io \
    clusteradmissionreports.kyverno.io \
    admissionreports.kyverno.io \
    policyexceptions.kyverno.io \
    --ignore-not-found 2>/dev/null || true
  success "Kyverno CRDs removed"

  info "Removing Kyverno namespace..."
  kubectl delete namespace kyverno --ignore-not-found
  success "Kyverno namespace removed"

  info "Removing admission webhook configurations..."
  kubectl delete validatingwebhookconfiguration \
    --selector=webhook.kyverno.io/managed-by=kyverno \
    --ignore-not-found 2>/dev/null || true
  kubectl delete mutatingwebhookconfiguration \
    --selector=webhook.kyverno.io/managed-by=kyverno \
    --ignore-not-found 2>/dev/null || true
  success "Webhooks removed — admission control is now DISABLED"

  echo ""
  warn "Kyverno has been removed. Pods are no longer gated on admission."
  info "To reinstall: bash scripts/setup.sh kyverno"
}

# ── Teardown: ArgoCD ──────────────────────────────────────────────────────────
teardown_argocd() {
  section "Teardown: ArgoCD"

  require_binary kubectl
  require_binary helm

  kubectl cluster-info >/dev/null 2>&1 || \
    error "Cluster is unreachable. Is minikube running?"

  confirm "Remove ArgoCD application '${ARGOCD_APP_NAME}' and uninstall ArgoCD? Cluster will no longer be GitOps-managed."

  # Kill port-forward if running
  pkill -f "kubectl port-forward.*argocd.*8080" 2>/dev/null || true
  step "ArgoCD port-forward stopped"

  # Remove the application via CLI if available
  if command -v argocd >/dev/null 2>&1; then
    if argocd app get "${ARGOCD_APP_NAME}" --insecure >/dev/null 2>&1; then
      info "Removing ArgoCD application '${ARGOCD_APP_NAME}'..."
      argocd app delete "${ARGOCD_APP_NAME}" \
        --yes \
        --insecure 2>/dev/null \
        && success "Application removed" \
        || warn "Could not remove via CLI — removing via kubectl..."
    fi
  fi

  # Remove via kubectl as fallback
  kubectl delete application "${ARGOCD_APP_NAME}" \
    -n argocd \
    --ignore-not-found 2>/dev/null || true

  # Uninstall Helm release
  if helm status argocd -n argocd >/dev/null 2>&1; then
    info "Uninstalling ArgoCD Helm release..."
    helm uninstall argocd -n argocd
    success "ArgoCD Helm release removed"
  else
    warn "ArgoCD Helm release not found — skipping"
  fi

  info "Removing ArgoCD CRDs..."
  kubectl delete crd \
    applications.argoproj.io \
    applicationsets.argoproj.io \
    appprojects.argoproj.io \
    --ignore-not-found 2>/dev/null || true
  success "ArgoCD CRDs removed"

  info "Removing ArgoCD namespace..."
  kubectl delete namespace argocd --ignore-not-found
  success "ArgoCD namespace removed"

  echo ""
  warn "ArgoCD has been removed. Cluster is no longer GitOps-managed."
  warn "Manual kubectl apply is required for future deployments."
  info "To reinstall: bash scripts/setup.sh argocd"
}

# ── Teardown: Full K8s (keep minikube) ────────────────────────────────────────
teardown_k8s() {
  section "Teardown: Full Kubernetes Stack (keeps minikube)"

  require_binary kubectl
  kubectl cluster-info >/dev/null 2>&1 || \
    error "Cluster is unreachable. Is minikube running?"

  confirm "Remove ArgoCD + Kyverno + all application resources? Minikube cluster will remain running."

  teardown_argocd
  teardown_kyverno
  teardown_app

  info "Removing csvs namespace..."
  kubectl delete namespace "${NAMESPACE}" --ignore-not-found
  success "Namespace '${NAMESPACE}' removed"

  echo ""
  info "Remaining namespaces:"
  kubectl get namespaces

  success "Full Kubernetes stack removed — minikube is still running"
  info "To redeploy everything: bash scripts/setup.sh all"
}

# ── Teardown: All (keep minikube) ─────────────────────────────────────────────
teardown_all() {
  section "Teardown: All Components (keeps minikube)"

  confirm "Remove ALL components: Docker Compose stack + ArgoCD + Kyverno + all K8s resources? Minikube will remain running."

  teardown_argocd
  teardown_kyverno
  teardown_app

  info "Removing csvs namespace..."
  kubectl delete namespace "${NAMESPACE}" --ignore-not-found

  info "Stopping Docker Compose stack..."
  if [[ -f "${REPO_ROOT}/docker-compose.yml" ]]; then
    cd "${REPO_ROOT}"
    docker compose down --remove-orphans 2>/dev/null || true
  fi

  success "All components removed — minikube is still running"
  info "To rebuild everything: bash scripts/setup.sh all"
}

# ── Nuke: Full wipe including minikube ────────────────────────────────────────
teardown_nuke() {
  section "NUKE: Full Wipe Including Minikube"

  confirm "PERMANENTLY DELETE the entire minikube cluster, all K8s resources, Docker Compose stack, and all Docker images? This CANNOT be undone."

  # Docker Compose
  if [[ -f "${REPO_ROOT}/docker-compose.yml" ]]; then
    info "Removing Docker Compose stack..."
    cd "${REPO_ROOT}"
    docker compose down --remove-orphans 2>/dev/null || true
    success "Docker Compose removed"
  fi

  # Minikube delete
  if command -v minikube >/dev/null 2>&1; then
    info "Deleting minikube cluster..."
    minikube delete --all --purge
    success "Minikube fully deleted"
  else
    warn "minikube not found — skipping"
  fi

  # Docker images
  if docker info >/dev/null 2>&1; then
    info "Removing all Docker images..."
    # shellcheck disable=SC2046
    docker rmi -f $(docker images -a -q) 2>/dev/null || \
      info "No Docker images to remove"

    info "Pruning build cache..."
    docker buildx prune -f 2>/dev/null || true
    success "Docker images and cache cleared"
  fi

  echo ""
  success "Full nuke complete — clean slate"
  info "To rebuild from scratch:"
  echo ""
  echo "  Docker Compose:  bash scripts/setup.sh compose up"
  echo "  Kubernetes:      bash scripts/setup.sh all"
  echo ""
}

# ── Usage / Help ──────────────────────────────────────────────────────────────
usage() {
  echo ""
  echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════════════════╗${NC}"
  echo -e "${CYAN}${BOLD}║   CSVS23 Teardown Script — Usage Guide              ║${NC}"
  echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════════════╝${NC}"
  echo ""
  echo -e "${BOLD}Usage:${NC}"
  echo "  bash scripts/teardown.sh <command>"
  echo ""
  echo -e "${BOLD}── Targeted Teardown ─────────────────────────────────────────${NC}"
  echo "  compose     Stop Docker Compose stack + remove images"
  echo "  app         Remove app resources from csvs namespace only"
  echo "              (keeps minikube, Kyverno, ArgoCD running)"
  echo "  kyverno     Remove Kyverno policies + uninstall Kyverno"
  echo "              (admission control will be DISABLED)"
  echo "  argocd      Remove ArgoCD application + uninstall ArgoCD"
  echo "              (cluster will no longer be GitOps-managed)"
  echo ""
  echo -e "${BOLD}── Full Teardown ─────────────────────────────────────────────${NC}"
  echo "  k8s         Remove all K8s resources + Kyverno + ArgoCD"
  echo "              (minikube cluster stays running)"
  echo "  all         Remove everything — compose + k8s + kyverno + argocd"
  echo "              (minikube cluster stays running)"
  echo "  nuke        FULL WIPE — delete minikube + all images + everything"
  echo "              ⚠️  This CANNOT be undone"
  echo ""
  echo -e "${BOLD}── Safety ────────────────────────────────────────────────────${NC}"
  echo "  All destructive commands require typing 'yes' to confirm"
  echo "  Partial teardown commands are safe to run selectively"
  echo "  ArgoCD sync is paused before removing app resources"
  echo "  to prevent auto-recreation during teardown"
  echo ""
  echo -e "${BOLD}── Order of Operations ───────────────────────────────────────${NC}"
  echo ""
  echo "  Recommended teardown order (most to least destructive):"
  echo ""
  echo "  Full wipe:"
  echo "  bash scripts/teardown.sh nuke"
  echo ""
  echo "  Preserve minikube:"
  echo "  bash scripts/teardown.sh all"
  echo ""
  echo "  Just redeploy the app:"
  echo "  1. bash scripts/teardown.sh app"
  echo "  2. bash scripts/setup.sh k8s"
  echo ""
  echo "  Just reset Kyverno policies:"
  echo "  1. bash scripts/teardown.sh kyverno"
  echo "  2. bash scripts/setup.sh kyverno"
  echo ""
  echo -e "${BOLD}── What Each Command Removes ─────────────────────────────────${NC}"
  echo ""
  echo "  compose │ Containers, images, build cache"
  echo "  app     │ Deployments, services, secrets, PVCs, network policies"
  echo "  kyverno │ ClusterPolicies, Kyverno pods, CRDs, webhooks"
  echo "  argocd  │ ArgoCD application, ArgoCD pods, CRDs"
  echo "  k8s     │ argocd + kyverno + app + csvs namespace"
  echo "  all     │ k8s + compose (minikube stays)"
  echo "  nuke    │ all + minikube cluster + Docker images"
  echo ""
  echo -e "${BOLD}── After Teardown ────────────────────────────────────────────${NC}"
  echo "  To rebuild: bash scripts/setup.sh all"
  echo "  For help:   bash scripts/setup.sh help"
  echo ""
}

# ── Entry point ───────────────────────────────────────────────────────────────
case "${1:-help}" in
  compose)  teardown_compose ;;
  app)      teardown_app ;;
  kyverno)  teardown_kyverno ;;
  argocd)   teardown_argocd ;;
  k8s)      teardown_k8s ;;
  all)      teardown_all ;;
  nuke)     teardown_nuke ;;
  help|*)   usage ;;
esac
