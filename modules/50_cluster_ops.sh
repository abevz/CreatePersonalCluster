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
  load_secrets
  if [[ $? -ne 0 ]]; then
    log_error "Failed to load secrets. Aborting addon upgrade."
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

  log_step "Running Ansible playbook 'pb_upgrade_addons_extended.yml' for addon: '$addon_name'..."

  local extra_vars="addon_name=${addon_name}"
  if [[ -n "$addon_version" ]]; then
    extra_vars="${extra_vars} addon_version=${addon_version}"
    log_info "Targeting specific version: ${addon_version}"
  else
    log_info "Using default version for the addon."
  fi

  if ! cpc_ansible run-ansible "pb_upgrade_addons_extended.yml" --extra-vars "$extra_vars"; then
    log_error "Ansible playbook execution failed for addon '$addon_name'."
    return 1
  fi

  local playbook_exit_code=$?

  if [[ $playbook_exit_code -ne 0 ]]; then
    log_error "Ansible playbook execution failed for addon '$addon_name'."
    return 1
  fi

  log_success "Addon operation for '$addon_name' completed successfully."
}

cluster_configure_coredns() {
  # Parse command line arguments
  local dns_server=""
  local domains=""

  while [[ $# -gt 0 ]]; do
    case $1 in
    --dns-server)
      dns_server="$2"
      shift 2
      ;;
    --domains)
      domains="$2"
      shift 2
      ;;
    *)
      log_error "Unknown option for configure-coredns: $1"
      _cluster_ops_configure_coredns_help
      return 1
      ;;
    esac
  done

  # Get DNS server from Terraform if not specified
  if [ -z "$dns_server" ]; then
    log_step "Getting DNS server from Terraform variables..."
    local repo_path
    repo_path=$(get_repo_path) || return 1
    # We assume that the get_dns_server.sh script exists and works
    dns_server=$("$repo_path/scripts/get_dns_server.sh")

    if [ -n "$dns_server" ] && [ "$dns_server" != "null" ]; then
      log_success "Found DNS server in Terraform: $dns_server"
    else
      # Set a fallback if not able to get from Terraform
      dns_server="10.10.10.100"
      log_warning "Could not extract DNS server from Terraform. Using fallback: $dns_server"
    fi
  fi

  # Set default domains if not specified
  if [ -z "$domains" ]; then
    domains="bevz.net,bevz.dev,bevz.pl"
  fi

  log_step "Configuring CoreDNS for local domain resolution..."
  log_info "  DNS Server: $dns_server"
  log_info "  Domains: $domains"

  # Confirmation
  read -r -p "Continue with CoreDNS configuration? [y/N] " response
  if [[ ! "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    log_info "Operation cancelled."
    return 0
  fi

  # Run the Ansible playbook
  log_step "Running CoreDNS configuration playbook..."

  # Pass variables to the playbook
  local extra_vars="pihole_dns_server=$dns_server local_domains='[\"$(echo "$domains" | sed 's/,/","/g')\"]'"

  if ! cpc_ansible run-ansible "configure_coredns_local_domains.yml" --extra-vars "$extra_vars"; then
    log_error "Error configuring CoreDNS"
    return 1
  fi

  log_success "CoreDNS configured successfully!"
  log_info "Local domains ($domains) will now be forwarded to $dns_server"
}

export -f cpc_cluster_ops
