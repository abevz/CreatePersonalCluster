#!/bin/bash
# =============================================================================
# CPC Cluster Operations Module (50_cluster_ops.sh)
# =============================================================================

# Ensure this module is not run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "Error: This module should not be run directly. Use the main cpc script." >&2
  exit 1
fi

cpc_cluster_ops() {
  local command="${1:-}"

  # If help for the entire module is requested, show it and exit
  if [[ "$command" == "-h" || "$command" == "--help" || -z "$command" ]]; then
    _cluster_ops_help
    return 0
  fi

  shift # Remove the main command (upgrade-addons/configure-coredns) from the argument list

  case "$command" in
  upgrade-addons)
    # Check if help was requested for this specific command
    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
      _cluster_ops_upgrade_addons_help # Show help specifically for upgrade-addons
      return 0
    fi
    cluster_ops_upgrade_addons "$@"
    ;;

  configure-coredns)
    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
      _cluster_ops_configure_coredns_help # Show help for configure-coredns
      return 0
    fi
    cluster_configure_coredns "$@"
    ;;

  *)
    log_error "Unknown cluster operations command: ${command}"
    _cluster_ops_help
    return 1
    ;;
  esac
}

# --- Help Functions ---

# General help for commands
_cluster_ops_help() {
  printf "${BLUE}Usage: cpc <command> [options]${ENDCOLOR}\n"
  printf "\n"
  printf "Manages cluster operations and maintenance tasks.\n"
  printf "\n"
  printf "${GREEN}Available Commands:${ENDCOLOR}\n"
  printf "  ${YELLOW}%-20s${ENDCOLOR} %s\n" "upgrade-addons" "Installs or upgrades cluster addons."
  printf "  ${YELLOW}%-20s${ENDCOLOR} %s\n" "configure-coredns" "Adds a custom host entry to the CoreDNS configuration."
  printf "\n"
  printf "${CYAN}Use 'cpc <command> --help' for more information on a specific command.${ENDCOLOR}\n"
}

# Help for upgrade-addons
_cluster_ops_upgrade_addons_help() {
  printf "${BLUE}Usage: cpc upgrade-addons [addon_name] [version]${ENDCOLOR}\n"
  printf "\n"
  printf "Installs or upgrades cluster addons. If 'addon_name' is not provided,\n"
  printf "an interactive menu will be displayed.\n"
  printf "\n"
  printf "${CYAN}Arguments:${ENDCOLOR}\n"
  printf "  ${ORANGE}%-15s${ENDCOLOR} %s\n" "[addon_name]" "(Optional) The name of the addon. Available:"
  printf "                  %-15s %s\n" "" "all, calico, coredns, metallb, metrics-server, cert-manager,"
  printf "                  %-15s %s\n" "" "kubelet-serving-cert-approver, argocd, ingress-nginx,"
  printf "                  %-15s %s\n" "" "traefik-gateway."
  printf "\n"
  printf "  ${ORANGE}%-15s${ENDCOLOR} %s\n" "[version]" "(Optional) A specific version for the addon (e.g., v1.2.3)."
}

# Help for configure-coredns
_cluster_ops_configure_coredns_help() {
  printf "${BLUE}Usage: cpc configure-coredns <domain> <ip>${ENDCOLOR}\n"
  printf "\n"
  printf "Adds a custom host entry to the CoreDNS configuration.\n"
  printf "\n"
  printf "${CYAN}Arguments:${ENDCOLOR}\n"
  printf "  ${ORANGE}%-15s${ENDCOLOR} %s\n" "<domain>" "The domain name to resolve (e.g., myapp.local)."
  printf "  ${ORANGE}%-15s${ENDCOLOR} %s\n" "<ip>" "The IP address the domain should resolve to."
}

# --- Command Implementations (remain unchanged) ---

cluster_ops_upgrade_addons() {
  local addon_name="${1:-}"
  local addon_version="${2:-}"

  if [[ -z "$addon_name" ]]; then
    echo -e "${BLUE}Select addon to install/upgrade:${ENDCOLOR}"
    echo ""
    echo "  1) all                          - Install/upgrade all addons"
    echo "  2) calico                       - Calico CNI networking"
    echo "  3) metallb                      - MetalLB load balancer"
    echo "  4) metrics-server               - Kubernetes Metrics Server"
    echo "  5) coredns                      - CoreDNS DNS server"
    echo "  6) cert-manager                 - Certificate manager"
    echo "  7) kubelet-serving-cert-approver  - Kubelet cert approver"
    echo "  8) argocd                       - ArgoCD GitOps"
    echo "  9) ingress-nginx                - NGINX Ingress Controller"
    echo " 10) traefik-gateway              - Traefik Gateway Controller"
    echo ""
    read -r -p "Enter your choice [1-10]: " choice

    case $choice in
    1) addon_name="all" ;;
    2) addon_name="calico" ;;
    3) addon_name="metallb" ;;
    4) addon_name="metrics-server" ;;
    5) addon_name="coredns" ;;
    6) addon_name="cert-manager" ;;
    7) addon_name="kubelet-serving-cert-approver" ;;
    8) addon_name="argocd" ;;
    9) addon_name="ingress-nginx" ;;
    10) addon_name="traefik-gateway" ;;
    *)
      log_error "Invalid choice: $choice"
      return 1
      ;;
    esac
  fi

  local allowed_addons=("all" "calico" "coredns" "metallb" "metrics-server" "cert-manager" "kubelet-serving-cert-approver" "argocd" "ingress-nginx" "traefik-gateway")
  if ! [[ " ${allowed_addons[*]} " =~ " ${addon_name} " ]]; then
    log_error "Invalid addon name: '$addon_name'."
    _cluster_ops_upgrade_addons_help
    return 1
  fi

  log_step "Preparing environment and loading secrets..."

  # Load secrets with error handling
  if ! load_secrets_cached; then
    error_handle "$ERROR_CONFIG" "Failed to load secrets. Aborting addon upgrade." "$SEVERITY_CRITICAL" "abort"
    return 1
  fi

  # Validate Cloudflare token if needed
  if [[ "$addon_name" == "traefik-gateway" || "$addon_name" == "all" ]]; then
    if [[ -z "${CLOUDFLARE_DNS_API_TOKEN}" ]]; then
      log_warning "CLOUDFLARE_DNS_API_TOKEN is not set in your environment or secrets file."
      log_warning "Traefik will be installed, but the cert-manager ClusterIssuer for Cloudflare will not be configured."
    else
      log_success "CLOUDFLARE_DNS_API_TOKEN loaded successfully."
    fi
  fi

  log_step "Running Ansible playbook 'pb_upgrade_addons_extended.yml' for addon: '$addon_name'..."

  local extra_vars="addon_name=${addon_name}"
  if [[ -n "$addon_version" ]]; then
    extra_vars="${extra_vars} addon_version=${addon_version}"
    log_info "Targeting specific version: ${addon_version}"
  else
    log_info "Using default version for the addon."
  fi

  # Execute Ansible playbook with recovery
  if ! recovery_execute \
       "cpc_ansible run-ansible 'pb_upgrade_addons_extended.yml' --extra-vars '$extra_vars'" \
       "upgrade_addon_$addon_name" \
       "log_warning 'Addon upgrade failed, manual cleanup may be needed'" \
       "validate_addon_installation '$addon_name'"; then
    error_handle "$ERROR_EXECUTION" "Ansible playbook execution failed for addon '$addon_name'" "$SEVERITY_HIGH"
    return 1
  fi

  log_success "Addon operation for '$addon_name' completed successfully."
}

cluster_configure_coredns() {
  # Initialize recovery for CoreDNS configuration
  recovery_checkpoint "coredns_config_start" "Starting CoreDNS configuration"

  # Parse command line arguments with error handling
  local dns_server=""
  local domains=""

  while [[ $# -gt 0 ]]; do
    case $1 in
    --dns-server)
      if [[ -n "$2" && "$2" != --* ]]; then
        dns_server="$2"
        shift 2
      else
        error_handle "$ERROR_VALIDATION" "Missing argument for --dns-server" "$SEVERITY_HIGH"
        return 1
      fi
      ;;
    --domains)
      if [[ -n "$2" && "$2" != --* ]]; then
        domains="$2"
        shift 2
      else
        error_handle "$ERROR_VALIDATION" "Missing argument for --domains" "$SEVERITY_HIGH"
        return 1
      fi
      ;;
    *)
      error_handle "$ERROR_VALIDATION" "Unknown option for configure-coredns: $1" "$SEVERITY_HIGH"
      _cluster_ops_configure_coredns_help
      return 1
      ;;
    esac
  done

  # Get DNS server from Terraform if not specified
  if [ -z "$dns_server" ]; then
    log_step "Getting DNS server from Terraform variables..."

    local repo_path
    if ! repo_path=$(get_repo_path); then
      error_handle "$ERROR_CONFIG" "Failed to determine repository path" "$SEVERITY_HIGH"
      return 1
    fi

    # Execute DNS server script with error handling
    if ! dns_server=$("$repo_path/scripts/get_dns_server.sh" 2>/dev/null); then
      log_warning "Could not extract DNS server from Terraform script"
      dns_server="10.10.10.100"
      log_warning "Using fallback DNS server: $dns_server"
    elif [ -z "$dns_server" ] || [ "$dns_server" = "null" ]; then
      dns_server="10.10.10.100"
      log_warning "DNS server not found in Terraform. Using fallback: $dns_server"
    else
      log_success "Found DNS server in Terraform: $dns_server"
    fi
  fi

  # Set default domains if not specified
  if [ -z "$domains" ]; then
    domains="bevz.net,bevz.dev,bevz.pl"
  fi

  log_step "Configuring CoreDNS for local domain resolution..."
  log_info "  DNS Server: $dns_server"
  log_info "  Domains: $domains"

  # Confirmation with timeout
  if ! timeout_execute \
       "read -r -t 30 -p 'Continue with CoreDNS configuration? [y/N] ' response && [[ \"\$response\" =~ ^([yY][eE][sS]|[yY])\$ ]]" \
       35 \
       "User confirmation" \
       ""; then
    log_info "Operation cancelled or timed out."
    return 0
  fi

  # Run the Ansible playbook with recovery
  log_step "Running CoreDNS configuration playbook..."

  # Validate domains format
  if ! [[ "$domains" =~ ^[a-zA-Z0-9.-]+(,[a-zA-Z0-9.-]+)*$ ]]; then
    error_handle "$ERROR_VALIDATION" "Invalid domains format: $domains" "$SEVERITY_HIGH"
    return 1
  fi

  # Pass variables to the playbook
  local extra_vars="pihole_dns_server=$dns_server local_domains='[\"$(echo "$domains" | sed 's/,/\",\"/g')\"]'"

  if ! recovery_execute \
       "cpc_ansible run-ansible 'configure_coredns_local_domains.yml' --extra-vars '$extra_vars'" \
       "configure_coredns" \
       "log_warning 'CoreDNS configuration failed, manual cleanup may be needed'" \
       "validate_coredns_configuration '$dns_server' '$domains'"; then
    error_handle "$ERROR_EXECUTION" "CoreDNS configuration failed" "$SEVERITY_HIGH"
    return 1
  fi

  recovery_checkpoint "coredns_config_complete" "CoreDNS configuration completed successfully"
  log_success "CoreDNS configured successfully!"
  log_info "Local domains ($domains) will now be forwarded to $dns_server"
}

# Helper function to validate addon installation
function validate_addon_installation() {
  local addon_name="$1"

  case "$addon_name" in
    "calico")
      # Validate Calico pods are running
      if timeout_kubectl_operation \
           "kubectl get pods -n kube-system -l k8s-app=calico-node --no-headers | grep -q Running" \
           "Validate Calico installation" \
           60; then
        log_debug "Calico addon validated successfully"
        return 0
      fi
      ;;
    "metallb")
      # Validate MetalLB pods are running
      if timeout_kubectl_operation \
           "kubectl get pods -n metallb-system -l app=metallb --no-headers | grep -q Running" \
           "Validate MetalLB installation" \
           30; then
        log_debug "MetalLB addon validated successfully"
        return 0
      fi
      ;;
    "metrics-server")
      # Validate Metrics Server is accessible
      if timeout_kubectl_operation \
           "kubectl top nodes --no-headers >/dev/null 2>&1" \
           "Validate Metrics Server" \
           30; then
        log_debug "Metrics Server addon validated successfully"
        return 0
      fi
      ;;
    "coredns")
      # Validate CoreDNS pods are running
      if timeout_kubectl_operation \
           "kubectl get pods -n kube-system -l k8s-app=kube-dns --no-headers | grep -q Running" \
           "Validate CoreDNS installation" \
           30; then
        log_debug "CoreDNS addon validated successfully"
        return 0
      fi
      ;;
    "cert-manager")
      # Validate cert-manager pods are running
      if timeout_kubectl_operation \
           "kubectl get pods -n cert-manager --no-headers | grep -q Running" \
           "Validate cert-manager installation" \
           30; then
        log_debug "cert-manager addon validated successfully"
        return 0
      fi
      ;;
    "argocd")
      # Validate ArgoCD pods are running
      if timeout_kubectl_operation \
           "kubectl get pods -n argocd --no-headers | grep -q Running" \
           "Validate ArgoCD installation" \
           30; then
        log_debug "ArgoCD addon validated successfully"
        return 0
      fi
      ;;
    *)
      log_debug "No specific validation for addon: $addon_name"
      return 0
      ;;
  esac

  log_warning "Validation failed for addon: $addon_name"
  return 1
}

# Helper function to validate CoreDNS configuration
function validate_coredns_configuration() {
  local dns_server="$1"
  local domains="$2"

  # Check if CoreDNS configmap exists and contains our configuration
  kubectl get configmap coredns -n kube-system >/dev/null 2>&1

  # Check if domains are properly configured
  local config
  config=$(kubectl get configmap coredns -n kube-system -o jsonpath='{.data.Corefile}' 2>/dev/null)

  # Basic validation - check if config contains our DNS server
  echo "$config" | grep -q "$dns_server"
}

export -f cpc_cluster_ops validate_addon_installation validate_coredns_configuration
