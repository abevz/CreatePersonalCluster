#!/bin/bash

# =============================================================================
# DNS/SSL Module (70) - Certificate Management and DNS Operations
# =============================================================================
# 
# This module provides DNS and SSL certificate management functionality:
# - Certificate regeneration with DNS hostname support
# - DNS resolution testing and validation
# - SSL certificate verification and inspection
# - Certificate lifecycle management operations
#
# Functions exported:
# - cpc_dns_ssl() - Main command dispatcher for DNS/SSL operations
# - dns_ssl_regenerate_certificates() - Regenerate K8s certificates with DNS SANs
# - dns_ssl_test_resolution() - Test DNS resolution within cluster
# - dns_ssl_verify_certificates() - Verify SSL certificate validity and SANs
# - dns_ssl_check_cluster_dns() - Check cluster DNS functionality
# - dns_ssl_show_help() - Display available DNS/SSL commands
#
# =============================================================================

# DNS/SSL Module implementation

# Ensure this module is not run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "Error: This module should not be run directly. Use the main cpc script." >&2
  exit 1
fi

# Main DNS/SSL command dispatcher
cpc_dns_ssl() {
    local command="$1"
    shift

    # Initialize recovery for DNS/SSL operations
    recovery_checkpoint "dns_ssl_start" "Starting DNS/SSL operation: $command"

    case "$command" in
        "regenerate-certificates"|"regenerate-cert")
            dns_ssl_regenerate_certificates "$@"
            ;;
        "test-dns"|"test-resolution")
            dns_ssl_test_resolution "$@"
            ;;
        "verify-certificates"|"verify-cert"|"check-cert")
            dns_ssl_verify_certificates "$@"
            ;;
        "check-cluster-dns"|"test-cluster-dns")
            dns_ssl_check_cluster_dns "$@"
            ;;
        "inspect-cert"|"show-cert")
            dns_ssl_inspect_certificate "$@"
            ;;
        "help"|"--help"|"-h")
            dns_ssl_show_help
            ;;
        *)
            error_handle "$ERROR_INPUT" "Unknown DNS/SSL command: $command" "$SEVERITY_LOW" "abort"
            echo "Use 'cpc dns-ssl help' to see available commands."
            return 1
            ;;
    esac
}

# Regenerate Kubernetes certificates with DNS hostname support
dns_ssl_regenerate_certificates() {
    local target_node="$1"

    # Initialize recovery for certificate regeneration
    recovery_checkpoint "dns_ssl_regenerate_certificates_start" "Starting certificate regeneration"

    echo "🔐 Regenerating Kubernetes certificates with DNS hostname support..."
    echo

    if [[ -z "$target_node" ]]; then
        echo "Select target node for certificate regeneration:"
        echo "1) First control plane node (recommended)"
        echo "2) All control plane nodes"
        echo "3) Specific node"
        echo
        read -r -p "Enter your choice (1-3): " choice

        case "$choice" in
            1)
                target_node="control_plane[0]"
                ;;
            2)
                target_node="control_plane"
                ;;
            3)
                echo
                echo "Available nodes:"
                if command -v kubectl &> /dev/null; then
                    kubectl get nodes -o wide 2>/dev/null || echo "Kubectl not available or cluster not accessible"
                fi
                echo
                read -r -p "Enter target node name: " target_node
                if [[ -z "$target_node" ]]; then
                    error_handle "$ERROR_INPUT" "No target node specified" "$SEVERITY_LOW" "abort"
                    return 1
                fi
                ;;
            *)
                error_handle "$ERROR_INPUT" "Invalid choice for target node selection" "$SEVERITY_LOW" "abort"
                return 1
                ;;
        esac
    fi

    echo
    echo "⚠️  WARNING: This operation will cause temporary API server downtime!"
    echo "Target: $target_node"
    echo
    read -r -p "Are you sure you want to proceed? (yes/no): " confirm

    if [[ "$confirm" != "yes" ]]; then
        log_info "Certificate regeneration cancelled by user."
        return 0
    fi

    echo
    echo "🔄 Starting certificate regeneration..."

    # Check if regenerate certificates playbook exists
    local playbook_path="${REPO_ROOT}/ansible/playbooks/regenerate_certificates_with_dns.yml"
    if [[ ! -f "$playbook_path" ]]; then
        error_handle "$ERROR_CONFIG" "Certificate regeneration playbook not found at: $playbook_path" "$SEVERITY_HIGH" "abort"
        return 1
    fi

    # Load Ansible module functions
    if ! source "${SCRIPT_DIR}/modules/20_ansible.sh" 2>/dev/null; then
        error_handle "$ERROR_CONFIG" "Could not load Ansible module from ${SCRIPT_DIR}/modules/20_ansible.sh" "$SEVERITY_HIGH" "abort"
        return 1
    fi

    # Execute the playbook
    local extra_vars=""
    if [[ "$target_node" != "control_plane" && "$target_node" != "control_plane[0]" ]]; then
        extra_vars="--limit $target_node"
    fi

    echo "Executing certificate regeneration playbook..."
    if ansible_run_playbook "regenerate_certificates_with_dns.yml" "" "$extra_vars"; then
        echo
        echo "✅ Certificate regeneration completed successfully!"
        echo
        echo "🔍 Verifying new certificates..."
        if ! dns_ssl_verify_certificates; then
            error_handle "$ERROR_EXECUTION" "Certificate verification failed after regeneration" "$SEVERITY_MEDIUM" "continue"
        fi
        echo
        echo "📋 Next steps:"
        echo "1. Update your local kubeconfig if using hostnames"
        echo "2. Restart any applications that cache certificates"
        echo "3. Test cluster connectivity from external clients"
    else
        error_handle "$ERROR_EXECUTION" "Certificate regeneration failed" "$SEVERITY_CRITICAL" "abort"
        echo
        echo "❌ Certificate regeneration failed!"
        echo "Check the Ansible output above for details."
        echo "You may need to restore from backup if the cluster is inaccessible."
        return 1
    fi
}

# Test DNS resolution within the cluster
dns_ssl_test_resolution() {
    local domain="$1"
    local dns_server="$2"

    # Initialize recovery for DNS resolution test
    recovery_checkpoint "dns_ssl_test_resolution_start" "Starting DNS resolution test for domain: $domain"

    echo "🔍 Testing DNS resolution in Kubernetes cluster..."
    echo

    if [[ -z "$domain" ]]; then
        read -r -p "Enter domain to test (e.g., google.com, bevz.net): " domain
        if [[ -z "$domain" ]]; then
            error_handle "$ERROR_INPUT" "No domain specified for DNS test" "$SEVERITY_LOW" "abort"
            return 1
        fi
    fi

    if [[ -n "$dns_server" ]]; then
        echo "Testing resolution of '$domain' using DNS server: $dns_server"
    else
        echo "Testing resolution of '$domain' using cluster DNS"
    fi
    echo

    # Check if kubectl is available
    if ! command -v kubectl &> /dev/null; then
        error_handle "$ERROR_CONFIG" "kubectl not found. Please ensure kubectl is installed and cluster is accessible" "$SEVERITY_HIGH" "abort"
        return 1
    fi

    # Test cluster connectivity first
    if ! kubectl cluster-info &> /dev/null; then
        error_handle "$ERROR_EXECUTION" "Cannot connect to Kubernetes cluster. Please check your kubeconfig and cluster status" "$SEVERITY_HIGH" "abort"
        return 1
    fi

    echo "🔄 Creating temporary DNS test pod..."
    local test_pod_name="dns-test-$(date +%s)"
    local nslookup_cmd="nslookup $domain"

    if [[ -n "$dns_server" ]]; then
        nslookup_cmd="nslookup $domain $dns_server"
    fi

    # Run DNS test
    echo "Executing: $nslookup_cmd"
    echo

    local test_result
    if test_result=$(kubectl run "$test_pod_name" --image=busybox --restart=Never --rm -i --timeout=60s -- sh -c "$nslookup_cmd" 2>&1); then
        echo "✅ DNS test successful!"
        echo
        echo "Resolution result:"
        echo "==================="
        echo "$test_result"
        echo "==================="
    else
        error_handle "$ERROR_EXECUTION" "DNS test failed for domain: $domain" "$SEVERITY_MEDIUM" "continue"
        echo
        echo "❌ DNS test failed!"
        echo
        echo "Error output:"
        echo "==================="
        echo "$test_result"
        echo "==================="
        echo
        echo "💡 Troubleshooting tips:"
        echo "1. Check CoreDNS pods: kubectl get pods -n kube-system -l k8s-app=kube-dns"
        echo "2. Check CoreDNS logs: kubectl logs -n kube-system -l k8s-app=kube-dns"
        echo "3. Verify DNS configuration: kubectl get configmap coredns -n kube-system -o yaml"
        return 1
    fi

    # Additional DNS tests
    echo
    echo "🔄 Testing additional DNS functionality..."

    # Test internal cluster DNS
    echo "Testing internal cluster DNS (kubernetes.default.svc.cluster.local)..."
    if kubectl run "dns-test-internal-$(date +%s)" --image=busybox --restart=Never --rm -i --timeout=30s -- nslookup kubernetes.default.svc.cluster.local &> /dev/null; then
        echo "✅ Internal cluster DNS working"
    else
        error_handle "$ERROR_EXECUTION" "Internal cluster DNS test failed" "$SEVERITY_MEDIUM" "continue"
        echo "❌ Internal cluster DNS failed"
    fi

    # Test external DNS
    echo "Testing external DNS (8.8.8.8)..."
    if kubectl run "dns-test-external-$(date +%s)" --image=busybox --restart=Never --rm -i --timeout=30s -- nslookup google.com 8.8.8.8 &> /dev/null; then
        echo "✅ External DNS working"
    else
        error_handle "$ERROR_EXECUTION" "External DNS test failed" "$SEVERITY_MEDIUM" "continue"
        echo "❌ External DNS failed"
    fi

    echo
    echo "🔍 DNS test completed!"
}

# Verify SSL certificate validity and SANs
dns_ssl_verify_certificates() {
    local target_cert="$1"

    # Initialize recovery for certificate verification
    recovery_checkpoint "dns_ssl_verify_certificates_start" "Starting certificate verification"

    echo "🔐 Verifying Kubernetes SSL certificates..."
    echo

    # Check if we're on a control plane node or need to connect remotely
    local cert_dir="/etc/kubernetes/pki"
    local check_local=false

    if [[ -d "$cert_dir" ]]; then
        check_local=true
        echo "📋 Checking certificates on local control plane node..."
    else
        echo "📋 Checking certificates via kubectl and remote access..."
    fi

    echo

    if [[ "$check_local" == "true" ]]; then
        # Local certificate verification
        echo "🔍 Local certificate verification:"
        echo "======================================"

        local certs=(
            "apiserver.crt:API Server Certificate"
            "apiserver-kubelet-client.crt:API Server Kubelet Client"
            "apiserver-etcd-client.crt:API Server ETCD Client"
            "etcd/server.crt:ETCD Server Certificate"
            "front-proxy-client.crt:Front Proxy Client"
        )

        for cert_info in "${certs[@]}"; do
            local cert_file="${cert_info%%:*}"
            local cert_name="${cert_info##*:}"
            local cert_path="$cert_dir/$cert_file"

            if [[ -f "$cert_path" ]]; then
                echo
                echo "📄 $cert_name ($cert_file):"
                echo "   Path: $cert_path"

                # Check certificate validity
                local expiry
                if expiry=$(openssl x509 -in "$cert_path" -noout -enddate 2>/dev/null); then
                    echo "   Expiry: ${expiry#notAfter=}"

                    # Check if certificate is valid (not expired)
                    if openssl x509 -in "$cert_path" -noout -checkend 0 &>/dev/null; then
                        echo "   Status: ✅ Valid"
                    else
                        error_handle "$ERROR_EXECUTION" "Certificate expired: $cert_path" "$SEVERITY_HIGH" "continue"
                        echo "   Status: ❌ Expired"
                    fi
                else
                    error_handle "$ERROR_EXECUTION" "Cannot read certificate: $cert_path" "$SEVERITY_MEDIUM" "continue"
                    echo "   Status: ❌ Cannot read certificate"
                    continue
                fi

                # Show Subject Alternative Names for API server cert
                if [[ "$cert_file" == "apiserver.crt" ]]; then
                    echo "   Subject Alternative Names:"
                    if openssl x509 -in "$cert_path" -noout -text 2>/dev/null | grep -A 20 "Subject Alternative Name" | grep -E "DNS:|IP Address:" | sed 's/^[[:space:]]*/     /'; then
                        echo ""
                    else
                        error_handle "$ERROR_EXECUTION" "No SANs found or error reading certificate: $cert_path" "$SEVERITY_LOW" "continue"
                        echo "     (No SANs found or error reading certificate)"
                    fi
                fi
            else
                error_handle "$ERROR_CONFIG" "Certificate file not found: $cert_path" "$SEVERITY_MEDIUM" "continue"
                echo
                echo "📄 $cert_name ($cert_file): ❌ File not found"
            fi
        done
    fi

    # Remote verification via kubectl
    echo
    echo "🔍 Cluster connectivity verification:"
    echo "======================================="

    if command -v kubectl &> /dev/null; then
        # Test API server connectivity
        if kubectl cluster-info &> /dev/null; then
            echo "✅ Cluster API server accessible"

            # Get cluster info
            echo
            echo "📊 Cluster information:"
            kubectl cluster-info 2>/dev/null | head -n 5

            # Check certificate expiry via API
            echo
            echo "🕐 Certificate expiry check via API:"
            if kubectl get nodes &> /dev/null; then
                echo "✅ Node communication working (certificates valid)"
            else
                error_handle "$ERROR_EXECUTION" "Node communication failed - possible certificate issue" "$SEVERITY_HIGH" "continue"
                echo "❌ Node communication failed (possible certificate issue)"
            fi

        else
            error_handle "$ERROR_EXECUTION" "Cannot connect to cluster API server - possible certificate issues" "$SEVERITY_HIGH" "continue"
            echo "❌ Cannot connect to cluster API server"
            echo "   This could indicate certificate issues or cluster problems"
        fi
    else
        error_handle "$ERROR_CONFIG" "kubectl not available - cannot perform remote verification" "$SEVERITY_MEDIUM" "continue"
        echo "⚠️  kubectl not available - cannot perform remote verification"
    fi

    echo
    echo "🔍 Certificate verification completed!"
    echo
    echo "💡 For detailed certificate inspection, use: cpc dns-ssl inspect-cert [cert-path]"
}

# Check cluster DNS functionality comprehensively
dns_ssl_check_cluster_dns() {
    # Initialize recovery for cluster DNS check
    recovery_checkpoint "dns_ssl_check_cluster_dns_start" "Starting comprehensive cluster DNS check"

    echo "🔍 Comprehensive cluster DNS functionality check..."
    echo

    # Check if kubectl is available
    if ! command -v kubectl &> /dev/null; then
        error_handle "$ERROR_CONFIG" "kubectl not found. Please ensure kubectl is installed" "$SEVERITY_HIGH" "abort"
        return 1
    fi

    # Check cluster connectivity
    if ! kubectl cluster-info &> /dev/null; then
        error_handle "$ERROR_EXECUTION" "Cannot connect to Kubernetes cluster" "$SEVERITY_HIGH" "abort"
        return 1
    fi

    echo "📋 DNS System Status:"
    echo "======================"

    # Check CoreDNS pods
    echo "🔍 CoreDNS pods status:"
    if kubectl get pods -n kube-system -l k8s-app=kube-dns -o wide 2>/dev/null; then
        echo
        echo "✅ CoreDNS pods found and status shown above"
    else
        error_handle "$ERROR_EXECUTION" "CoreDNS pods not found or not accessible" "$SEVERITY_HIGH" "abort"
        return 1
    fi

    # Check CoreDNS service
    echo
    echo "🔍 CoreDNS service:"
    if kubectl get svc -n kube-system kube-dns 2>/dev/null; then
        echo "✅ CoreDNS service found"
    else
        error_handle "$ERROR_EXECUTION" "CoreDNS service not found" "$SEVERITY_HIGH" "continue"
        echo "❌ CoreDNS service not found"
    fi

    # Check CoreDNS configuration
    echo
    echo "🔍 CoreDNS configuration:"
    if kubectl get configmap coredns -n kube-system &> /dev/null; then
        echo "📄 Current Corefile configuration:"
        echo "-----------------------------------"
        kubectl get configmap coredns -n kube-system -o jsonpath='{.data.Corefile}' 2>/dev/null | head -n 20
        echo
        echo "-----------------------------------"
        echo "✅ CoreDNS configuration accessible"
    else
        error_handle "$ERROR_EXECUTION" "CoreDNS configuration not accessible" "$SEVERITY_MEDIUM" "continue"
        echo "❌ CoreDNS configuration not accessible"
    fi

    # Test DNS resolution
    echo
    echo "📋 DNS Resolution Tests:"
    echo "========================"

    # Test internal DNS
    echo "🔍 Testing internal service DNS..."
    if dns_ssl_test_resolution "kubernetes.default.svc.cluster.local" &> /dev/null; then
        echo "✅ Internal service DNS working"
    else
        error_handle "$ERROR_EXECUTION" "Internal service DNS test failed" "$SEVERITY_MEDIUM" "continue"
        echo "❌ Internal service DNS failed"
    fi

    # Test external DNS
    echo "🔍 Testing external DNS..."
    if dns_ssl_test_resolution "google.com" &> /dev/null; then
        echo "✅ External DNS working"
    else
        error_handle "$ERROR_EXECUTION" "External DNS test failed" "$SEVERITY_MEDIUM" "continue"
        echo "❌ External DNS failed"
    fi

    # Check for common issues
    echo
    echo "📋 Common Issues Check:"
    echo "======================="

    # Check if CoreDNS pods are ready
    local coredns_ready
    coredns_ready=$(kubectl get pods -n kube-system -l k8s-app=kube-dns --no-headers 2>/dev/null | awk '{print $2}' | grep -c "1/1" || echo "0")
    local coredns_total
    coredns_total=$(kubectl get pods -n kube-system -l k8s-app=kube-dns --no-headers 2>/dev/null | wc -l || echo "0")

    if [[ "$coredns_ready" -eq "$coredns_total" && "$coredns_total" -gt 0 ]]; then
        echo "✅ All CoreDNS pods are ready ($coredns_ready/$coredns_total)"
    else
        error_handle "$ERROR_EXECUTION" "Not all CoreDNS pods are ready ($coredns_ready/$coredns_total)" "$SEVERITY_MEDIUM" "continue"
        echo "❌ Not all CoreDNS pods are ready ($coredns_ready/$coredns_total)"
        echo "   Check pod logs: kubectl logs -n kube-system -l k8s-app=kube-dns"
    fi

    # Check for common networking issues
    echo "🔍 Checking for common networking issues..."

    # Check if kube-proxy is running
    if kubectl get ds -n kube-system kube-proxy &> /dev/null; then
        echo "✅ kube-proxy DaemonSet found"
    else
        error_handle "$ERROR_CONFIG" "kube-proxy DaemonSet not found - may affect service discovery" "$SEVERITY_MEDIUM" "continue"
        echo "⚠️  kube-proxy DaemonSet not found (may affect service discovery)"
    fi

    echo
    echo "🔍 Cluster DNS check completed!"
    echo
    echo "💡 For specific DNS testing, use: cpc dns-ssl test-dns [domain]"
}

# Inspect specific certificate file
dns_ssl_inspect_certificate() {
    local cert_path="$1"

    # Initialize recovery for certificate inspection
    recovery_checkpoint "dns_ssl_inspect_certificate_start" "Starting certificate inspection: $cert_path"

    if [[ -z "$cert_path" ]]; then
        echo "🔍 Certificate inspection utility"
        echo
        echo "Common Kubernetes certificate locations:"
        echo "- /etc/kubernetes/pki/apiserver.crt (API Server)"
        echo "- /etc/kubernetes/pki/apiserver-kubelet-client.crt (Kubelet Client)"
        echo "- /etc/kubernetes/pki/ca.crt (Cluster CA)"
        echo "- /etc/kubernetes/pki/etcd/ca.crt (ETCD CA)"
        echo
        read -r -p "Enter certificate path to inspect: " cert_path

        if [[ -z "$cert_path" ]]; then
            error_handle "$ERROR_INPUT" "No certificate path specified" "$SEVERITY_LOW" "abort"
            return 1
        fi
    fi

    if [[ ! -f "$cert_path" ]]; then
        error_handle "$ERROR_CONFIG" "Certificate file not found: $cert_path" "$SEVERITY_HIGH" "abort"
        return 1
    fi

    echo "🔐 Inspecting certificate: $cert_path"
    echo "========================================"
    echo

    # Basic certificate information
    echo "📄 Certificate Details:"
    if ! openssl x509 -in "$cert_path" -noout -text 2>/dev/null | grep -E "Subject:|Issuer:|Not Before|Not After|Public Key Algorithm|Signature Algorithm" | sed 's/^[[:space:]]*/  /'; then
        error_handle "$ERROR_EXECUTION" "Failed to read certificate details from: $cert_path" "$SEVERITY_MEDIUM" "abort"
        return 1
    fi

    echo
    echo "📄 Subject Alternative Names:"
    if ! openssl x509 -in "$cert_path" -noout -text 2>/dev/null | grep -A 20 "Subject Alternative Name" | grep -E "DNS:|IP Address:" | sed 's/^[[:space:]]*/  /'; then
        error_handle "$ERROR_EXECUTION" "No SANs found or error reading certificate: $cert_path" "$SEVERITY_LOW" "continue"
        echo "  (No SANs found)"
    fi

    echo
    echo "🕐 Validity Check:"
    if openssl x509 -in "$cert_path" -noout -checkend 0 &>/dev/null; then
        echo "  ✅ Certificate is currently valid"
    else
        error_handle "$ERROR_EXECUTION" "Certificate is expired or invalid: $cert_path" "$SEVERITY_HIGH" "continue"
        echo "  ❌ Certificate is expired or invalid"
    fi

    # Check expiry in different timeframes
    local timeframes=(86400 604800 2592000)  # 1 day, 1 week, 1 month
    local timeframe_names=("24 hours" "1 week" "1 month")

    echo
    echo "🕐 Expiry Warnings:"
    for i in "${!timeframes[@]}"; do
        local seconds="${timeframes[$i]}"
        local name="${timeframe_names[$i]}"

        if ! openssl x509 -in "$cert_path" -noout -checkend "$seconds" &>/dev/null; then
            error_handle "$ERROR_EXECUTION" "Certificate expires within $name: $cert_path" "$SEVERITY_MEDIUM" "continue"
            echo "  ⚠️  Certificate expires within $name"
        else
            echo "  ✅ Certificate valid for more than $name"
        fi
    done

    echo
    echo "🔍 Certificate inspection completed!"
}

# Show DNS/SSL help information
dns_ssl_show_help() {
    echo "DNS/SSL Module - Certificate Management and DNS Operations"
    echo "=========================================================="
    echo
    echo "Available commands:"
    echo
    echo "Certificate Management:"
    echo "  regenerate-certificates [node]  Regenerate Kubernetes certificates with DNS hostname support"
    echo "  verify-certificates            Verify SSL certificate validity and SANs"
    echo "  inspect-cert [cert-path]       Inspect specific certificate file details"
    echo
    echo "DNS Operations:"
    echo "  test-dns [domain]              Test DNS resolution within the cluster"
    echo "  check-cluster-dns              Comprehensive cluster DNS functionality check"
    echo
    echo "Examples:"
    echo "  cpc dns-ssl regenerate-certificates"
    echo "  cpc dns-ssl test-dns google.com"
    echo "  cpc dns-ssl verify-certificates"
    echo "  cpc dns-ssl check-cluster-dns"
    echo "  cpc dns-ssl inspect-cert /etc/kubernetes/pki/apiserver.crt"
    echo
    echo "Notes:"
    echo "- Certificate regeneration requires cluster downtime"
    echo "- DNS tests require a running Kubernetes cluster"
    echo "- Some operations require cluster admin privileges"
}
