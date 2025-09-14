#!/bin/bash
# =============================================================================
# CPC Cluster Operations Module (50_cluster_ops.sh)
# =============================================================================

# Ensure this module is not run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "Error: This module should not be run directly. Use the main cpc script." >&2
  exit 1
fi

# Initialize addon discovery system if available
if [[ -f "$REPO_PATH/ansible/addons/addon_discovery.sh" ]]; then
  source "$REPO_PATH/ansible/addons/addon_discovery.sh"
  addon_discover_all
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
  # Load addon discovery if available
  if [[ -f "$REPO_PATH/ansible/addons/addon_discovery.sh" ]]; then
    source "$REPO_PATH/ansible/addons/addon_discovery.sh"
    addon_discover_all
  fi

  printf "${BLUE}Usage: cpc upgrade-addons [addon_name] [version]${ENDCOLOR}\n"
  printf "\n"
  printf "Installs or upgrades cluster addons. If 'addon_name' is not provided,\n"
  printf "an interactive menu will be displayed.\n"
  printf "\n"
  printf "${CYAN}Arguments:${ENDCOLOR}\n"
  printf "  ${ORANGE}%-15s${ENDCOLOR} %s\n" "[addon_name]" "(Optional) The name of the addon. Available:"
  
  # Show discovered addons if available, otherwise show legacy list
  if [[ -n "${DISCOVERED_ADDONS:-}" ]] && [[ ${#DISCOVERED_ADDONS[@]} -gt 0 ]]; then
    printf "                  %-15s %s\n" "" "all, $(addon_list_all simple | tr '\n' ',' | sed 's/,$//' | sed 's/,/, /g')."
  else
    printf "                  %-15s %s\n" "" "all, calico, coredns, metallb, metrics-server, cert-manager,"
    printf "                  %-15s %s\n" "" "kubelet-serving-cert-approver, argocd, ingress-nginx,"
    printf "                  %-15s %s\n" "" "traefik-gateway."
  fi
  
  printf "\n"
  printf "  ${ORANGE}%-15s${ENDCOLOR} %s\n" "[version]" "(Optional) A specific version for the addon (e.g., v1.2.3)."
  
  # Show detailed addon list if discovered
  if [[ -n "${DISCOVERED_ADDONS:-}" ]] && [[ ${#DISCOVERED_ADDONS[@]} -gt 0 ]]; then
    printf "\n${CYAN}Available Addons by Category:${ENDCOLOR}\n"
    addon_list_all detailed
  fi
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

# --- Command Implementations (Refactored) ---

cluster_ops_upgrade_addons() {
  local addon_name="${1:-}"
  local addon_version="${2:-}"

  source "$REPO_PATH/ansible/addons/addon_discovery.sh"
  addon_discover_all

  if [[ -z "$addon_name" ]]; then
    addon_name=$(_upgrade_addons_get_user_selection)
    if [[ $? -ne 0 ]]; then return 1; fi
  fi

  if ! _upgrade_addons_validate_selection "$addon_name"; then
    return 1
  fi

  if ! _upgrade_addons_prepare_environment "$addon_name"; then
    return 1
  fi

  local extra_vars
  extra_vars=$(_upgrade_addons_build_ansible_vars "$addon_name" "$addon_version")

  local playbook_to_use
  playbook_to_use=$(_upgrade_addons_determine_playbook "$addon_name")

  log_step "Running Ansible playbook '$playbook_to_use' for addon: '$addon_name' ભા"
  if ! cpc_ansible run-ansible "$playbook_to_use" --extra-vars "$extra_vars"; then
    _upgrade_addons_handle_failure "$addon_name" "Ansible playbook execution failed"
    return 1
  fi
  
  log_info "Ansible playbook completed successfully"

  # Check for Kubeconfig before attempting validation
  local kubeconfig_path="${KUBECONFIG:-$HOME/.kube/config}"
  if [[ ! -f "$kubeconfig_path" ]]; then
    log_warning "Kubeconfig not found at $kubeconfig_path. Skipping addon validation."
    log_success "Addon operation for '$addon_name' completed."
    return 0
  fi

  if ! validate_addon_installation "$addon_name"; then
    _upgrade_addons_handle_failure "$addon_name" "Addon validation failed"
    return 1
  fi

  log_success "Addon operation for '$addon_name' completed and validated successfully."
}

cluster_configure_coredns() {
  recovery_checkpoint "coredns_config_start" "Starting CoreDNS configuration"

  # These variables will be modified by _coredns_parse_args in the same shell scope.
  local dns_server=""
  local domains=""
  
  _coredns_parse_args "$@"
  if [[ $? -ne 0 ]]; then return 1; fi

  dns_server=$(_coredns_get_dns_server "$dns_server")
  if [[ $? -ne 0 ]]; then return 1; fi

  domains=$(_coredns_get_domains "$domains")

  if ! _coredns_confirm_operation "$dns_server" "$domains"; then
    log_info "Operation cancelled or timed out."
    return 0
  fi

  if ! _coredns_run_ansible "$dns_server" "$domains"; then
    error_handle "$ERROR_EXECUTION" "CoreDNS configuration failed" "$SEVERITY_HIGH"
    return 1
  fi

  recovery_checkpoint "coredns_config_complete" "CoreDNS configuration completed successfully"
  log_success "CoreDNS configured successfully!"
  log_info "Local domains ($domains) will now be forwarded to $dns_server"
}

validate_addon_installation() {
  local addon_name="$1"

  if ! _validate_preflight_checks; then
    return 1
  fi

  # Export helpers so the sub-shell can see them
  export -f _validate_addon_metallb
  export -f _validate_addon_metrics_server
  export -f _validate_addon_default

  timeout 30s bash -c "
    # KUBECONFIG is already set and exported by _validate_preflight_checks
    case "$addon_name" in
      metallb) _validate_addon_metallb ;; 
      metrics-server) _validate_addon_metrics_server ;; 
      *) _validate_addon_default "$addon_name" ;; 
    esac
  "

  local exit_code=$?
  if [[ $exit_code -eq 0 ]]; then
    return 0
  else
    return 1
  fi
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

# --- Helper Functions ---

# --- Addon Upgrade Helpers ---

_upgrade_addons_get_user_selection() {
  local selection
  selection=$(addon_display_interactive_menu)
  if [[ $? -ne 0 || -z "$selection" ]]; then
    log_error "No addon selected or invalid choice"
    return 1
  fi
  echo "$selection"
  return 0
}

_upgrade_addons_validate_selection() {
  local addon_name="$1"
  if ! addon_validate_exists "$addon_name"; then
    _cluster_ops_upgrade_addons_help
    return 1
  fi
  return 0
}

_upgrade_addons_prepare_environment() {
  local addon_name="$1"
  log_step "Preparing environment and loading secrets..."
  if ! load_secrets_cached; then
    error_handle "$ERROR_CONFIG" "Failed to load secrets. Aborting addon upgrade." "$SEVERITY_CRITICAL" "abort"
    return 1
  fi

  if [[ "$addon_name" == "traefik-gateway" || "$addon_name" == "all" ]]; then
    if [[ -z "${CLOUDFLARE_DNS_API_TOKEN}" ]]; then
      log_warning "CLOUDFLARE_DNS_API_TOKEN is not set in your environment or secrets file."
      log_warning "Traefik will be installed, but the cert-manager ClusterIssuer for Cloudflare will not be configured."
    else
      log_success "CLOUDFLARE_DNS_API_TOKEN loaded successfully."
    fi
  fi
  return 0
}

_upgrade_addons_build_ansible_vars() {
  local addon_name="$1"
  local addon_version="$2"
  local extra_vars="addon_name=${addon_name}"
  if [[ -n "$addon_version" ]]; then
    extra_vars="${extra_vars} addon_version=${addon_version}"
    log_info "Targeting specific version: ${addon_version}"
  else
    log_info "Using default version for the addon."
  fi
  echo "$extra_vars"
}

_upgrade_addons_determine_playbook() {
  local addon_name="$1"
  if [[ -f "$REPO_PATH/ansible/playbooks/pb_upgrade_addons_modular.yml" ]] && [[ -n "${DISCOVERED_ADDONS[$addon_name]}" || "$addon_name" == "all" ]]; then
    echo "pb_upgrade_addons_modular.yml"
  else
    echo "pb_upgrade_addons_extended.yml"
  fi
}

_upgrade_addons_handle_failure() {
  local addon_name="$1"
  local message="$2"
  log_error "$message for addon '$addon_name'"
  log_warning "Addon upgrade failed, manual cleanup may be needed"
  error_handle "$ERROR_EXECUTION" "$message for addon '$addon_name'" "$SEVERITY_HIGH"
}

# --- CoreDNS Helpers ---

_coredns_parse_args() {
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
}

_coredns_get_dns_server() {
  local current_dns_server="$1"
  if [ -n "$current_dns_server" ]; then
    echo "$current_dns_server"
    return 0
  fi

  log_step "Getting DNS server from Terraform variables..." >&2
  local repo_path
  if ! repo_path=$(get_repo_path); then
    error_handle "$ERROR_CONFIG" "Failed to determine repository path" "$SEVERITY_HIGH"
    return 1
  fi

  local new_dns_server
  if ! new_dns_server=$("$repo_path/scripts/get_dns_server.sh" 2>/dev/null); then
    log_warning "Could not extract DNS server from Terraform script"
    new_dns_server="10.10.10.100"
    log_warning "Using fallback DNS server: $new_dns_server"
  elif [ -z "$new_dns_server" ] || [ "$new_dns_server" = "null" ]; then
    new_dns_server="10.10.10.100"
    log_warning "DNS server not found in Terraform. Using fallback: $new_dns_server"
  else
    log_success "Found DNS server in Terraform: $new_dns_server"
  fi
  echo "$new_dns_server"
}

_coredns_get_domains() {
  local current_domains="$1"
  if [ -z "$current_domains" ]; then
    echo "bevz.net,bevz.dev,bevz.pl"
  else
    echo "$current_domains"
  fi
}

_coredns_confirm_operation() {
  local dns_server="$1"
  local domains="$2"
  log_step "Configuring CoreDNS for local domain resolution..."
  log_info "  DNS Server: $dns_server"
  log_info "  Domains: $domains"

  read -r -t 30 -p 'Continue with CoreDNS configuration? [y/N] ' response
  if [[ ! "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    return 1
  fi
}

_coredns_run_ansible() {
  local dns_server="$1"
  local domains="$2"
  log_step "Running CoreDNS configuration playbook..."

  if ! [[ "$domains" =~ ^[a-zA-Z0-9.-]+(,[a-zA-Z0-9.-]+)*$ ]]; then
    error_handle "$ERROR_VALIDATION" "Invalid domains format: $domains" "$SEVERITY_HIGH"
    return 1
  fi

  local extra_vars="pihole_dns_server=$dns_server local_domains_str=$domains"

  recovery_execute \
       "cpc_ansible run-ansible 'configure_coredns_local_domains.yml' --extra-vars '$extra_vars'" \
       "configure_coredns" \
       "log_warning 'CoreDNS configuration failed, manual cleanup may be needed'" \
       "validate_coredns_configuration '$dns_server' '$domains'"
}

# --- Validation Helpers ---

_validate_preflight_checks() {
  local kubeconfig="${KUBECONFIG:-$HOME/.kube/config}"
  kubeconfig="${kubeconfig/#\\\${HOME\}/${HOME}}"
  kubeconfig="${kubeconfig/#\$HOME/${HOME}}"
  export KUBECONFIG="$kubeconfig"

  if ! command -v kubectl >/dev/null 2>&1; then
    echo "kubectl command not found. Cannot validate addon installation." >&2
    return 1
  fi

  if [[ ! -f "$kubeconfig" ]]; then
    echo "Kubeconfig file not found: $kubeconfig" >&2
    return 1
  fi

  if ! kubectl cluster-info >/dev/null 2>&1; then
    echo "Cannot connect to Kubernetes cluster. Cannot validate addon installation." >&2
    return 1
  fi
  return 0
}

_validate_addon_metallb() {
  if kubectl get pods -n metallb-system --no-headers -o custom-columns=":.status.phase" | grep -q 'Running'; then
    exit 0
  else
    echo 'MetalLB pods not ready' >&2
    exit 1
  fi
}

_validate_addon_metrics_server() {
  if kubectl get pods -n kube-system -l k8s-app=metrics-server --no-headers -o custom-columns=":.status.phase" | grep -q 'Running'; then
    exit 0
  else
    echo 'Metrics Server pods not ready' >&2
    exit 1
  fi
}

_validate_addon_default() {
  local addon_name="$1"
  echo "Unknown addon: $addon_name" >&2
  exit 1
}
