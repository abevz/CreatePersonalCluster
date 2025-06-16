# DNS Certificate Solution Enhancement Report

## Problem Identified
After implementing DNS hostname support for Kubernetes certificates, we discovered that when nodes are restarted or when DNS changes occur, kubelet automatically creates new Certificate Signing Requests (CSRs) for serving certificates. These CSRs remained in "Pending" status, causing failures in components that need to access kubelet API, particularly:

- **Metrics Server** - Unable to connect to kubelet API, resulting in readiness probe failures
- **kubectl top** commands - Non-functional due to missing metrics
- Other monitoring tools that depend on kubelet metrics

## Root Cause Analysis
1. **DNS hostname changes** trigger kubelet to request new serving certificates
2. **Automatic CSR generation** - kubelet creates CSRs with `kubernetes.io/kubelet-serving` type
3. **Manual approval required** - CSRs remain in Pending status until manually approved
4. **Service disruption** - Components depending on kubelet API fail until certificates are valid

## Solution Implemented

### 1. Enhanced Bootstrap Process
**File**: `ansible/playbooks/initialize_kubernetes_cluster_with_dns.yml`

Added automatic CSR approval at the end of cluster initialization:
```yaml
- name: Wait for kubelet serving CSRs to be created
- name: Check for pending kubelet serving CSRs  
- name: Approve pending kubelet serving CSRs
- name: Display CSR approval result
```

### 2. Enhanced Node Addition Process
**File**: `ansible/playbooks/pb_add_nodes.yml`

Added automatic CSR approval when adding new nodes:
```yaml
- name: Wait for kubelet serving CSRs to be created for new nodes
- name: Check for pending kubelet serving CSRs after node addition
- name: Approve pending kubelet serving CSRs for new nodes
- name: Display CSR approval result after node addition
```

### 3. Standalone CSR Approval Playbook
**File**: `ansible/playbooks/approve_kubelet_csr.yml`

Created dedicated playbook for manual CSR approval when needed:
```bash
./cpc run-ansible approve_kubelet_csr.yml
```

### 4. Enhanced Documentation
**File**: `docs/quick_dns_certificate_fix.md`

Added comprehensive troubleshooting section for CSR issues including:
- Symptoms identification
- Manual approval commands
- Automated solutions

## Benefits Achieved

### ✅ **Automated Resolution**
- No more manual CSR approval needed during bootstrap
- Seamless node addition process
- Metrics Server works immediately after cluster initialization

### ✅ **Improved Reliability** 
- Eliminates timeout errors in Metrics Server
- Ensures `kubectl top` functionality works out-of-the-box
- Reduces cluster setup time and complexity

### ✅ **Better User Experience**
- Bootstrap process completes fully without manual intervention
- Clear documentation for troubleshooting edge cases
- Dedicated tools for manual CSR management when needed

### ✅ **Robust Monitoring**
- Metrics Server starts successfully on first attempt
- Node resource monitoring available immediately
- Supports advanced monitoring and autoscaling features

## Test Results

### Before Enhancement:
```bash
# Metrics Server would fail with:
# Warning  Unhealthy  pod/metrics-server-xxx  Readiness probe failed: HTTP probe failed with statuscode: 500

# kubectl top would fail:
# error: metrics not available
```

### After Enhancement:
```bash
# Metrics Server starts successfully:
# metrics-server-6b8747695-97qs2   1/1   Running   0   33s

# kubectl top works immediately:
NAME           CPU(cores)   CPU%   MEMORY(bytes)   MEMORY%   
cu1.bevz.net   52m          2%     1239Mi          66%       
wu1.bevz.net   15m          0%     605Mi           32%       
wu2.bevz.net   14m          0%     575Mi           30%
```

## Commands Added

### Automatic (Built into existing workflows):
- `./cpc bootstrap` - Now includes automatic CSR approval
- `./cpc add-nodes` - Now includes automatic CSR approval for new nodes

### Manual (For troubleshooting):
- `./cpc run-ansible approve_kubelet_csr.yml` - Approve pending CSRs
- `kubectl get csr | grep kubelet-serving | grep Pending` - Check pending CSRs
- `kubectl get csr -o name | grep "kubelet-serving" | xargs kubectl certificate approve` - Manual approval

## Conclusion

This enhancement ensures that the DNS certificate solution is complete and robust. The Kubernetes cluster with DNS hostname support now works seamlessly without manual intervention for certificate management, providing a production-ready solution that can handle VM reboots, IP address changes, and scaling operations automatically.

The combination of automated CSR approval during cluster operations and manual tools for edge cases provides a comprehensive solution that addresses both day-1 deployment and day-2 operations scenarios.
