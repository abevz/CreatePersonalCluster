#!/bin/bash

# Script to migrate VM disk to MyStorage and convert to template

VM_ID="941"
SOURCE_STORAGE="local-lvm"
TARGET_STORAGE="MyStorage"
VM_NAME="tpl-suse-15-k8s"

echo "Converting VM $VM_ID to template and migrating disk from $SOURCE_STORAGE to $TARGET_STORAGE..."

# Stop VM if it's running
echo "Stopping VM $VM_ID if running..."
qm stop $VM_ID 2>/dev/null || true

# Wait a moment for VM to stop
sleep 5

# Move disk from local-lvm to MyStorage
echo "Moving disk from $SOURCE_STORAGE to $TARGET_STORAGE..."
qm move-disk $VM_ID virtio0 $TARGET_STORAGE --format qcow2

# Convert VM to template
echo "Converting VM $VM_ID to template..."
qm template $VM_ID

echo "Successfully converted VM $VM_ID ($VM_NAME) to template and moved disk to $TARGET_STORAGE"

# Verify the template
echo "Template configuration:"
cat /etc/pve/qemu-server/${VM_ID}.conf
