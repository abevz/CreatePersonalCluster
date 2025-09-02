#!/bin/bash

# CPC Release Preparation Script
# This script prepares the project for release by cleaning up development artifacts

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_ROOT"

echo "🧹 CPC Release Cleanup Starting..."
echo "Project root: $PROJECT_ROOT"

# =============================================================================
# 1. Remove Development Documentation
# =============================================================================
echo ""
echo "📝 Removing development documentation..."

# List of files to remove
files_to_remove=(
    "docs/phase2_error_handling_plan.md"
    "docs/documentation_cleanup_report.md"
    "docs/final_completion_status.md"
    "docs/project_status_report.md"
    "docs/project_status_summary.md"
    "docs/core_functions_migration_completion_report.md"
    "docs/proxmox_module_10_completion_report.md"
    "docs/ansible_module_20_completion_report.md"
    "docs/k8s_cluster_module_30_completion_report.md"
    "docs/k8s_nodes_module_40_completion_report.md"
    "docs/cluster_ops_module_50_completion_report.md"
    "docs/dns_ssl_module_70_completion_report.md"
    "docs/addon_installation_completion_report.md"
    "docs/dns_certificate_solution_completion_report.md"
    "docs/bootstrap_implementation_summary.md"
    "docs/final_upgrade_addons_report.md"
    "docs/cpc_upgrade_addons_enhancement_summary.md"
    "docs/vm_template_reorganization_final.md"
    "docs/documentation_update_report.md"
    "docs/documentation_status_report.md"
    "docs/cleanup_completion_report.md"
    "docs/cluster_status_kubeconfig_implementation_report.md"
)

removed_count=0
for file in "${files_to_remove[@]}"; do
    if [[ -f "$file" ]]; then
        echo "  Removing: $file"
        rm "$file"
        removed_count=$((removed_count + 1))
    fi
done

echo "  ✅ Removed $removed_count development documentation files"

# =============================================================================
# 2. Clean Temporary Files
# =============================================================================
echo ""
echo "🗑️  Cleaning temporary files..."

temp_removed=0

# Remove .backup files
while IFS= read -r -d '' file; do
    echo "  Removing backup: $file"
    rm "$file"
    temp_removed=$((temp_removed + 1))
done < <(find . -name "*.backup" -type f -print0 2>/dev/null)

# Remove .tmp files
while IFS= read -r -d '' file; do
    echo "  Removing temp: $file"
    rm "$file"
    temp_removed=$((temp_removed + 1))
done < <(find . -name "*.tmp" -type f -print0 2>/dev/null)

# Remove .log files (except important ones)
while IFS= read -r -d '' file; do
    echo "  Removing log: $file"
    rm "$file"
    temp_removed=$((temp_removed + 1))
done < <(find . -name "*.log" -not -path "./logs/*" -type f -print0 2>/dev/null)

echo "  ✅ Cleaned $temp_removed temporary files"

# =============================================================================
# 3. Update .gitignore for Release
# =============================================================================
echo ""
echo "📝 Updating .gitignore..."

if [[ ! -f .gitignore ]]; then
    echo "  Creating .gitignore..."
    cat > .gitignore << 'EOF'
# CPC Generated Files
*.tmp
*.backup
*.log
.terraform/
terraform.tfstate*
.sops.yaml
secrets.enc.yaml
terraform_state.json

# Environment Files
.env
*.env
!*.env.example

# Cache
.cache/
.terraform.lock.hcl

# IDE
.vscode/
.idea/
*.swp
*.swo

# Python
__pycache__/
*.pyc
*.pyo
*.pyd
.Python
build/
develop-eggs/
dist/
downloads/
eggs/
.eggs/
lib/
lib64/
parts/
sdist/
var/
wheels/
*.egg-info/
.installed.cfg
*.egg

# Testing
.pytest_cache/
.coverage
htmlcov/
.tox/

# macOS
.DS_Store

# Windows
Thumbs.db
ehthumbs.db
Desktop.ini
EOF
else
    echo "  .gitignore already exists"
fi

# =============================================================================
# 4. Organize Documentation
# =============================================================================
echo ""
echo "📚 Organizing documentation..."

# Create docs index if it doesn't exist
if [[ ! -f docs/index.md ]]; then
    echo "  Creating documentation index..."
    cat > docs/index.md << 'EOF'
# CPC Documentation Index

Welcome to the Create Personal Cluster (CPC) documentation!

## 🚀 Getting Started
- [Project Setup Guide](project_setup_guide.md) - Initial setup and configuration
- [Complete Cluster Creation Guide](complete_cluster_creation_guide.md) - End-to-end cluster deployment
- [Complete Workflow Guide](complete_workflow_guide.md) - Full workflow overview

## 📖 User Guides
- [Cluster Deployment Guide](cluster_deployment_guide.md) - Step-by-step deployment
- [Bootstrap Command Guide](bootstrap_command_guide.md) - Bootstrap process
- [CPC Commands Reference](cpc_commands_reference.md) - All available commands
- [CPC Template Variables Guide](cpc_template_variables_guide.md) - Template configuration

## 🔧 Configuration
- [Hostname Configuration](hostname_configuration_update.md) - Hostname settings
- [DNS and Certificate Configuration](dns_certificate_csr_enhancement_report.md) - DNS/SSL setup
- [CoreDNS Configuration Examples](coredns_configuration_examples.md) - CoreDNS setup

## 🏗️ Architecture
- [Architecture Overview](architecture.md) - System architecture
- [Modular Workspace System](modular_workspace_system.md) - Workspace structure
- [Node Naming Convention](node_naming_convention.md) - Naming standards

## 🔍 Operations
- [Cluster Monitoring and Kubeconfig Management](cluster_monitoring_and_kubeconfig_management.md)
- [Cluster Troubleshooting Commands](cluster_troubleshooting_commands.md)
- [Kubeconfig Context Troubleshooting](kubeconfig_context_troubleshooting.md)

## 🆙 Upgrades and Addons
- [CPC Upgrade Addons Reference](cpc_upgrade_addons_reference.md) - Addon management

## 🤝 Contributing
- [Contributing Guidelines](../CONTRIBUTING.md) - How to contribute
- [Commands Comparison](cpc_commands_comparison.md) - Command differences

## 📋 Reference
- [DNS LAN Suffix Configuration](dns_lan_suffix_problem_solution.md)
- [Kubernetes DNS Certificate Solution](kubernetes_dns_certificate_solution.md)
- [CoreDNS Local Domain Configuration](coredns_local_domain_configuration.md)
EOF
fi

echo "  ✅ Documentation organized"

# =============================================================================
# 5. Final Checks
# =============================================================================
echo ""
echo "🔍 Running final checks..."

# Check for remaining Russian text
echo "  Checking for Russian text..."
russian_files=""
while IFS= read -r -d '' file; do
    if grep -q "[а-яё]" "$file" 2>/dev/null; then
        russian_files="$russian_files$file"$'\n'
    fi
done < <(find docs/ -name "*.md" -type f -print0 2>/dev/null)

if [[ -n "$russian_files" ]]; then
    echo "  ⚠️  Found Russian text in:"
    echo "$russian_files" | sed 's/^/    /'
    echo "  Consider translating or removing these files"
else
    echo "  ✅ No Russian text found"
fi

# Check for development artifacts
echo "  Checking for development artifacts..."
dev_artifacts=""
while IFS= read -r -d '' file; do
    dev_artifacts="$dev_artifacts$file"$'\n'
done < <(find . -name "*completion_report*" -o -name "*status_report*" -o -name "*implementation_summary*" -type f -print0 2>/dev/null)

if [[ -n "$dev_artifacts" ]]; then
    echo "  ⚠️  Found development artifacts:"
    echo "$dev_artifacts" | sed 's/^/    /'
else
    echo "  ✅ No development artifacts found"
fi

# Verify key files exist
echo "  Checking key files..."
key_files=(
    "README.md"
    "CHANGELOG.md"
    "RELEASE_NOTES.md"
    "LICENSE"
    "CONTRIBUTING.md"
    "cpc"
    "docs/index.md"
)

missing_files=()
for file in "${key_files[@]}"; do
    if [[ ! -f "$file" ]]; then
        missing_files+=("$file")
    fi
done

if [[ ${#missing_files[@]} -gt 0 ]]; then
    echo "  ⚠️  Missing key files:"
    printf '    %s\n' "${missing_files[@]}"
else
    echo "  ✅ All key files present"
fi

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "🎉 Release Preparation Complete!"
echo ""
echo "📊 Summary:"
echo "  • Removed $removed_count development documentation files"
echo "  • Cleaned $temp_removed temporary files"
echo "  • Updated .gitignore"
echo "  • Organized documentation"
echo "  • Verified project structure"
echo ""
echo "🚀 Project ready for release!"
echo ""
echo "Next steps:"
echo "1. Review remaining files in docs/ directory"
echo "2. Test all functionality: python tests/run_tests.py all"
echo "3. Update version numbers if needed"
echo "4. Create release tag: git tag v1.0.0"
echo "5. Push to repository: git push origin v1.0.0"
