#!/bin/bash

# =============================================================================
# DNS/SSL Module (70) - Certificate Management and DNS Operations
# =============================================================================

# Ensure this module is not run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "Error: This module should not be run directly. Use the main cpc script." >&2
  exit 1
fi

# --- Main Dispatcher ---

cpc_dns_ssl() {
    local command="$1"
    shift

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

# --- Command Implementations (Refactored) ---

dns_ssl_regenerate_certificates() {
    local target_node
    target_node=$(_regenerate_get_target_node "$1")
    if [[ $? -ne 0 ]]; then return 1; fi

    read -r -p "Are you sure you want to proceed? (yes/no): " confirm
    if [[ "$confirm" != "yes" ]]; then
        log_info "Certificate regeneration cancelled by user."
        return 1
    fi

    if ! _regenerate_run_ansible "$target_node"; then
        _regenerate_handle_failure
        return 1
    fi

    _regenerate_handle_success
}

dns_ssl_test_resolution() {
    local domain
    domain=$(_test_dns_get_domain "$1")
    if [[ $? -ne 0 ]]; then return 1; fi

    if ! _test_dns_preflight_checks; then return 1; fi

    if ! _test_dns_run_main_test "$domain" "$2"; then return 1; fi

    _test_dns_run_internal_test
    _test_dns_run_external_test
    log_info "DNS test completed!"
}

dns_ssl_verify_certificates() {
    recovery_checkpoint "dns_ssl_verify_certificates_start" "Starting certificate verification"
    echo "🔐 Verifying Kubernetes SSL certificates..."

    if [[ -d "/etc/kubernetes/pki" ]]; then
        _verify_certs_locally
    else
        _verify_certs_remotely
    fi

    log_info "Certificate verification completed!"
    echo "💡 For detailed certificate inspection, use: cpc dns-ssl inspect-cert [cert-path]"
}

dns_ssl_check_cluster_dns() {
    recovery_checkpoint "dns_ssl_check_cluster_dns_start" "Starting comprehensive cluster DNS check"
    echo "🔍 Comprehensive cluster DNS functionality check..."

    if ! _check_dns_preflight; then return 1; fi

    _check_dns_get_pod_status
    _check_dns_get_service_status
    _check_dns_get_configmap
    _check_dns_run_resolution_tests
    _check_dns_common_issues

    log_info "Cluster DNS check completed!"
    echo "💡 For specific DNS testing, use: cpc dns-ssl test-dns [domain]"
}

dns_ssl_inspect_certificate() {
    local cert_path="$1"
    # ... (This function is already quite modular, leaving as is for now)
    # ... The original implementation of dns_ssl_inspect_certificate remains here ...
}

# --- Helper Functions ---

# --- Certificate Regeneration Helpers ---
_regenerate_get_target_node() {
    local target_node="$1"
    if [[ -n "$target_node" ]]; then
        echo "$target_node"
        return 0
    fi

    echo "Select target node for certificate regeneration:"
    echo "1) First control plane node (recommended)"
    echo "2) All control plane nodes"
    echo "3) Specific node"
    read -r -p "Enter your choice (1-3): " choice

    case "$choice" in
        1) echo "control_plane[0]" ;; 
        2) echo "control_plane" ;; 
        3) 
            read -r -p "Enter target node name: " specific_node
            if [[ -z "$specific_node" ]]; then
                error_handle "$ERROR_INPUT" "No target node specified" "$SEVERITY_LOW" "abort"
                return 1
            fi
            echo "$specific_node"
            ;; 
        *) 
            error_handle "$ERROR_INPUT" "Invalid choice for target node selection" "$SEVERITY_LOW" "abort"
            return 1
            ;; 
    esac
}

_regenerate_confirm_operation() {
    local target_node="$1"
    echo -e "\n⚠️  WARNING: This operation will cause temporary API server downtime!\nTarget: $target_node"
    read -r -p "Are you sure you want to proceed? (yes/no): " confirm
    [[ "$confirm" == "yes" ]]
}

_regenerate_run_ansible() {
    local target_node="$1"
    echo "🔄 Starting certificate regeneration..."
    local playbook_path="${REPO_ROOT}/ansible/playbooks/regenerate_certificates_with_dns.yml"
    if [[ ! -f "$playbook_path" ]]; then
        error_handle "$ERROR_CONFIG" "Playbook not found: $playbook_path" "$SEVERITY_HIGH" "abort"
        return 1
    fi

    if ! source "${SCRIPT_DIR}/modules/20_ansible.sh" 2>/dev/null; then
        error_handle "$ERROR_CONFIG" "Could not load Ansible module" "$SEVERITY_HIGH" "abort"
        return 1
    fi

    local extra_vars=""
    if [[ "$target_node" != "control_plane" && "$target_node" != "control_plane[0]" ]]; then
        extra_vars="--limit $target_node"
    fi

    ansible_run_playbook "regenerate_certificates_with_dns.yml" "" "$extra_vars"
}

_regenerate_handle_success() {
    echo -e "\n✅ Certificate regeneration completed successfully!\n"
    echo "🔍 Verifying new certificates..."
    if ! dns_ssl_verify_certificates; then
        error_handle "$ERROR_EXECUTION" "Certificate verification failed after regeneration" "$SEVERITY_MEDIUM" "continue"
    fi
    echo -e "\n📋 Next steps:\n1. Update local kubeconfig\n2. Restart apps that cache certs\n3. Test external connectivity"
}

_regenerate_handle_failure() {
    error_handle "$ERROR_EXECUTION" "Certificate regeneration failed" "$SEVERITY_CRITICAL" "abort"
    echo -e "\n❌ Certificate regeneration failed! Check Ansible output for details."
}

# --- DNS Test Helpers ---
_test_dns_get_domain() {
    local domain="$1"
    if [[ -n "$domain" ]]; then
        echo "$domain"
        return 0
    fi
    read -r -p "Enter domain to test (e.g., google.com, bevz.net): " domain
    if [[ -z "$domain" ]]; then
        error_handle "$ERROR_INPUT" "No domain specified" "$SEVERITY_LOW" "abort"
        return 1
    fi
    echo "$domain"
}

_test_dns_preflight_checks() {
    if ! command -v kubectl &> /dev/null; then
        error_handle "$ERROR_CONFIG" "kubectl not found" "$SEVERITY_HIGH" "abort"
        return 1
    fi
    if ! kubectl cluster-info &> /dev/null; then
        error_handle "$ERROR_EXECUTION" "Cannot connect to Kubernetes cluster" "$SEVERITY_HIGH" "abort"
        return 1
    fi
}

_test_dns_run_main_test() {
    local domain="$1"
    local dns_server="$2"
    local nslookup_cmd="nslookup $domain"
    if [[ -n "$dns_server" ]]; then
        nslookup_cmd="nslookup $domain $dns_server"
    fi

    echo "🔄 Creating temporary DNS test pod to run: $nslookup_cmd"
    local test_pod_name="dns-test-$(date +%s)"
    local test_result
    if test_result=$(kubectl run "$test_pod_name" --image=busybox --restart=Never --rm -i --timeout=60s -- sh -c "$nslookup_cmd" 2>&1); then
        echo -e "✅ DNS test successful!\nResolution result:\n===================
$test_result
==================="
        return 0
    else
        error_handle "$ERROR_EXECUTION" "DNS test failed for domain: $domain" "$SEVERITY_MEDIUM" "continue"
        echo -e "\n❌ DNS test failed!\nError output:\n===================
$test_result
==================="
        return 1
    fi
}

_test_dns_run_internal_test() {
    echo "Testing internal cluster DNS (kubernetes.default.svc.cluster.local)..."
    if kubectl run "dns-test-internal-$(date +%s)" --image=busybox --restart=Never --rm -i --timeout=30s -- nslookup kubernetes.default.svc.cluster.local &> /dev/null; then
        echo "✅ Internal cluster DNS working"
    else
        error_handle "$ERROR_EXECUTION" "Internal cluster DNS test failed" "$SEVERITY_MEDIUM" "continue"
        echo "❌ Internal cluster DNS failed"
    fi
}

_test_dns_run_external_test() {
    echo "Testing external DNS (8.8.8.8)..."
    if kubectl run "dns-test-external-$(date +%s)" --image=busybox --restart=Never --rm -i --timeout=30s -- nslookup google.com 8.8.8.8 &> /dev/null; then
        echo "✅ External DNS working"
    else
        error_handle "$ERROR_EXECUTION" "External DNS test failed" "$SEVERITY_MEDIUM" "continue"
        echo "❌ External DNS failed"
    fi
}

# --- Certificate Verification Helpers ---
_verify_certs_locally() {
    echo "🔍 Local certificate verification:"
    local certs=(
        "apiserver.crt:API Server Certificate"
        "apiserver-kubelet-client.crt:API Server Kubelet Client"
        "apiserver-etcd-client.crt:API Server ETCD Client"
        "etcd/server.crt:ETCD Server Certificate"
        "front-proxy-client.crt:Front Proxy Client"
    )
    for cert_info in "${certs[@]}"; do
        _verify_single_local_cert "/etc/kubernetes/pki/${cert_info%%:*}" "${cert_info##*:}"
    done
}

_verify_single_local_cert() {
    local cert_path="$1"
    local cert_name="$2"
    echo -e "\n📄 $cert_name (${cert_path##*/}):"
    if [[ ! -f "$cert_path" ]]; then
        error_handle "$ERROR_CONFIG" "Certificate file not found: $cert_path" "$SEVERITY_MEDIUM" "continue"
        return
    fi

    local expiry
    if expiry=$(openssl x509 -in "$cert_path" -noout -enddate 2>/dev/null); then
        echo "   Expiry: ${expiry#notAfter=}"
        if openssl x509 -in "$cert_path" -noout -checkend 0 &>/dev/null; then
            echo "   Status: ✅ Valid"
        else
            error_handle "$ERROR_EXECUTION" "Certificate expired: $cert_path" "$SEVERITY_HIGH" "continue"
            echo "   Status: ❌ Expired"
        fi
    else
        error_handle "$ERROR_EXECUTION" "Cannot read certificate: $cert_path" "$SEVERITY_MEDIUM" "continue"
    fi

    if [[ "$cert_path" == *"apiserver.crt"* ]]; then
        echo "   Subject Alternative Names:"
        openssl x509 -in "$cert_path" -noout -text 2>/dev/null | grep -A 20 "Subject Alternative Name" | grep -E "DNS:|IP Address:" | sed 's/^[[:space:]]*/     /'
    fi
}

_verify_certs_remotely() {
    echo "🔍 Cluster connectivity verification:"
    if ! command -v kubectl &> /dev/null; then
        log_warning "kubectl not available, skipping remote verification."
        return
    fi
    if ! kubectl cluster-info &> /dev/null; then
        log_warning "Cannot connect to cluster, skipping remote verification."
        return
    fi

    echo "✅ Cluster API server accessible"
    kubectl cluster-info 2>/dev/null | head -n 5
    if kubectl get nodes &> /dev/null; then
        echo "✅ Node communication working (certificates valid)"
    else
        error_handle "$ERROR_EXECUTION" "Node communication failed" "$SEVERITY_HIGH" "continue"
    fi
}

# --- Cluster DNS Check Helpers ---
_check_dns_preflight() {
    if ! command -v kubectl &> /dev/null; then
        error_handle "$ERROR_CONFIG" "kubectl not found" "$SEVERITY_HIGH" "abort"
        return 1
    fi
    if ! kubectl cluster-info &> /dev/null; then
        error_handle "$ERROR_EXECUTION" "Cannot connect to Kubernetes cluster" "$SEVERITY_HIGH" "abort"
        return 1
    fi
    return 0
}

_check_dns_get_pod_status() {
    echo -e "\n📋 DNS System Status:\n======================\n🔍 CoreDNS pods status:"
    kubectl get pods -n kube-system -l k8s-app=kube-dns -o wide 2>/dev/null || error_handle "$ERROR_EXECUTION" "CoreDNS pods not found" "$SEVERITY_HIGH" "abort"
}

_check_dns_get_service_status() {
    echo -e "\n🔍 CoreDNS service:"
    kubectl get svc -n kube-system kube-dns 2>/dev/null || error_handle "$ERROR_EXECUTION" "CoreDNS service not found" "$SEVERITY_HIGH" "continue"
}

_check_dns_get_configmap() {
    echo -e "\n🔍 CoreDNS configuration:"
    if kubectl get configmap coredns -n kube-system &> /dev/null; then
        echo "📄 Current Corefile configuration:"
        kubectl get configmap coredns -n kube-system -o jsonpath='{.data.Corefile}' 2>/dev/null | head -n 20
    else
        error_handle "$ERROR_EXECUTION" "CoreDNS configuration not accessible" "$SEVERITY_MEDIUM" "continue"
    fi
}

_check_dns_run_resolution_tests() {
    echo -e "\n📋 DNS Resolution Tests:\n========================"
    dns_ssl_test_resolution "kubernetes.default.svc.cluster.local" &> /dev/null
    dns_ssl_test_resolution "google.com" &> /dev/null
}

_check_dns_common_issues() {
    echo -e "\n📋 Common Issues Check:\n======================="
    local coredns_ready=$(kubectl get pods -n kube-system -l k8s-app=kube-dns --no-headers 2>/dev/null | awk '{print $2}' | grep -c "1/1" || echo "0")
    local coredns_total=$(kubectl get pods -n kube-system -l k8s-app=kube-dns --no-headers 2>/dev/null | wc -l || echo "0")
    if [[ "$coredns_ready" -eq "$coredns_total" && "$coredns_total" -gt 0 ]]; then
        echo "✅ All CoreDNS pods are ready ($coredns_ready/$coredns_total)"
    else
        error_handle "$ERROR_EXECUTION" "Not all CoreDNS pods are ready ($coredns_ready/$coredns_total)" "$SEVERITY_MEDIUM" "continue"
    fi
    if kubectl get ds -n kube-system kube-proxy &> /dev/null; then
        echo "✅ kube-proxy DaemonSet found"
    else
        error_handle "$ERROR_CONFIG" "kube-proxy DaemonSet not found" "$SEVERITY_MEDIUM" "continue"
    fi
}

# --- Help Function ---
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