#!/bin/bash
# Security Check Script for CPC Project
# Run this before committing to ensure no secrets are exposed

set -e

echo "🔒 Running security checks..."

# Check for gitleaks
if ! command -v gitleaks &> /dev/null; then
    echo "❌ gitleaks not found. Install it from: https://github.com/gitleaks/gitleaks"
    exit 1
fi

echo "🔍 Scanning for exposed secrets with gitleaks..."
if gitleaks detect --source . --verbose; then
    echo "✅ No secrets found in repository"
else
    echo "❌ Secrets detected! Do not commit until resolved."
    exit 1
fi

# Check for common secret files that shouldn't be committed
SECRET_FILES=(
    "secrets_temp.yaml"
    "secrets.yaml"
    "*.key"
    "*.pem"
    "*_secret*"
    "*_key*"
)

echo "🔍 Checking for sensitive files..."
for pattern in "${SECRET_FILES[@]}"; do
    if find . -name "$pattern" -not -path "./.git/*" -not -path "./.venv/*" | grep -q .; then
        echo "⚠️  Found potential sensitive files matching: $pattern"
        find . -name "$pattern" -not -path "./.git/*" -not -path "./.venv/*"
    fi
done

echo "✅ Security checks completed successfully"
