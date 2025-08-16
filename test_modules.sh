#!/bin/bash
# =============================================================================
# CPC Test Script - Testing Modular Architecture
# =============================================================================
# This script tests the new modular structure alongside the existing cpc

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=== Testing CPC Modular Architecture ==="

# Load configuration and modules
echo "Loading configuration..."
source ./config.conf

echo "Loading libraries..."
source ./lib/logging.sh
source ./lib/ssh_utils.sh  
source ./lib/pihole_api.sh

echo "Loading core module..."
source ./modules/00_core.sh

echo "Loading proxmox module..."
source ./modules/10_proxmox.sh

echo "Loading tofu module..."
source ./modules/60_tofu.sh

echo "Loading ansible module..."
source ./modules/20_ansible.sh

# Set REPO_PATH for modules
export REPO_PATH="$SCRIPT_DIR"

echo "Testing logging functions..."
log_info "This is an info message"
log_success "This is a success message" 
log_warning "This is a warning message"
log_error "This is an error message"
log_debug "This is a debug message (only shown if CPC_DEBUG=true)"

echo ""
echo "Testing core functions..."

# Test get_repo_path
repo_path=$(get_repo_path)
log_info "Repository path: $repo_path"

# Test context functions
current_ctx=$(get_current_cluster_context)
log_info "Current context: $current_ctx"

echo ""
echo "Testing Pi-hole DNS functions..."
log_info "Available Pi-hole actions:"
cpc_dns_pihole "" 2>/dev/null || log_warning "DNS functions need proper arguments (this is expected)"

echo ""
echo "Testing SSH utilities..."
log_info "Available SSH actions:"
cpc_ssh_utils "invalid" 2>&1 || true

echo ""
echo "Testing Tofu module functions..."
log_info "Testing tofu help functions:"
echo "Deploy help:"
cpc_tofu deploy --help | head -5
echo ""
echo "Start VMs help:"
cpc_tofu start-vms --help | head -3
echo ""
echo "Generate hostnames help:"
cpc_tofu generate-hostnames --help | head -3

echo ""
echo "Testing Ansible module functions..."
log_info "Testing ansible help functions:"
echo "Run-ansible help:"
cpc_ansible run-ansible --help | head -5

echo ""
echo "Testing Proxmox module functions..."
log_info "Testing proxmox help functions:"
echo "Add VM help:"
cpc_proxmox add-vm --help | head -5
echo ""
echo "Remove VM help:"
cpc_proxmox remove-vm --help | head -5

echo ""
log_success "Modular architecture test completed!"
log_info "All modules loaded successfully. Ready for integration with main cpc script."
