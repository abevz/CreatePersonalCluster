#!/bin/bash

# Setup MinIO environment variables for Terraform S3 backend
# This script extracts MinIO credentials from secrets.sops.yaml and sets them as environment variables

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SECRETS_FILE="$PROJECT_ROOT/terraform/secrets.sops.yaml"

if [[ ! -f "$SECRETS_FILE" ]]; then
    echo "Error: secrets.sops.yaml not found at $SECRETS_FILE"
    exit 1
fi

if ! command -v sops &> /dev/null; then
    echo "Error: sops command not found. Please install SOPS first."
    exit 1
fi

echo "Loading MinIO credentials from $SECRETS_FILE..."

# Extract MinIO credentials using sops
MINIO_ACCESS_KEY=$(sops -d "$SECRETS_FILE" | grep "minio_access_key:" | cut -d: -f2 | xargs)
MINIO_SECRET_KEY=$(sops -d "$SECRETS_FILE" | grep "minio_secret_key:" | cut -d: -f2 | xargs)

if [[ -z "$MINIO_ACCESS_KEY" ]] || [[ -z "$MINIO_SECRET_KEY" ]]; then
    echo "Error: Failed to extract MinIO credentials from secrets file."
    exit 1
fi

# Export environment variables
export AWS_ACCESS_KEY_ID="$MINIO_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$MINIO_SECRET_KEY"
export AWS_DEFAULT_REGION="us-east-1"

echo "Successfully set MinIO environment variables:"
echo "  AWS_ACCESS_KEY_ID: ${AWS_ACCESS_KEY_ID:0:10}..."
echo "  AWS_SECRET_ACCESS_KEY: ${AWS_SECRET_ACCESS_KEY:0:10}..."
echo "  AWS_DEFAULT_REGION: $AWS_DEFAULT_REGION"

# If script is sourced, the environment variables will be available in the parent shell
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo ""
    echo "Note: To use these environment variables in your current shell, run:"
    echo "  source $0"
fi
