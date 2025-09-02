#!/bin/bash

# Script to fix machine-id on Ubuntu VMs that have duplicates
# Enhanced with error handling and recovery mechanisms
# This should be run on the Proxmox host

# Error handling constants
readonly ERROR_CONFIG=1
readonly ERROR_EXECUTION=2
readonly ERROR_INPUT=3
readonly SEVERITY_LOW=1
readonly SEVERITY_MEDIUM=2
readonly SEVERITY_HIGH=3
readonly SEVERITY_CRITICAL=4

# Logging functions
log_info() {
  echo "[INFO] $1"
}

log_error() {
  echo "[ERROR] $1" >&2
}

log_warning() {
  echo "[WARNING] $1"
}

log_success() {
  echo "[SUCCESS] $1"
}

# Error handling function
error_handle() {
  local error_code="$1"
  local error_message="$2"
  local severity="$3"
  local action="$4"

  log_error "$error_message (Error code: $error_code)"

  case "$action" in
    "abort")
      log_error "Aborting operation due to critical error"
      exit $error_code
      ;;
    "retry")
      log_warning "Will retry operation"
      ;;
    "continue")
      log_warning "Continuing despite error"
      ;;
    *)
      log_warning "Unknown error action: $action"
      ;;
  esac
}

# Recovery checkpoint function
recovery_checkpoint() {
  local checkpoint_name="$1"
  local description="$2"
  log_info "Recovery checkpoint: $checkpoint_name - $description"
}

# Validation functions
validate_dependencies() {
  local missing_deps=()

  if ! command -v qm &> /dev/null; then
    missing_deps+=("qm (Proxmox CLI)")
  fi

  if ! command -v qemu-nbd &> /dev/null; then
    missing_deps+=("qemu-nbd")
  fi

  if ! command -v mount &> /dev/null; then
    missing_deps+=("mount")
  fi

  if ! command -v umount &> /dev/null; then
    missing_deps+=("umount")
  fi

  if [ ${#missing_deps[@]} -gt 0 ]; then
    error_handle "$ERROR_CONFIG" "Missing required dependencies: ${missing_deps[*]}" "$SEVERITY_CRITICAL" "abort"
    return 1
  fi

  return 0
}

validate_vm_exists() {
  local vm_id="$1"

  if ! qm list 2>/dev/null | grep -q "^[[:space:]]*$vm_id[[:space:]]"; then
    error_handle "$ERROR_CONFIG" "VM with ID $vm_id does not exist" "$SEVERITY_HIGH" "abort"
    return 1
  fi

  return 0
}

# Cleanup function for mount operations
cleanup_mount() {
  local mount_point="$1"
  local nbd_device="$2"

  if mountpoint -q "$mount_point" 2>/dev/null; then
    log_info "Cleaning up mount point: $mount_point"
    if ! sudo umount "$mount_point" 2>/dev/null; then
      log_warning "Failed to unmount $mount_point"
    fi
  fi

  if [[ -n "$nbd_device" ]] && [[ -b "$nbd_device" ]]; then
    log_info "Cleaning up NBD device: $nbd_device"
    if ! sudo qemu-nbd -d "$nbd_device" 2>/dev/null; then
      log_warning "Failed to disconnect NBD device $nbd_device"
    fi
  fi
}

# Initialize recovery for machine-id fix
recovery_checkpoint "fix_machine_id_start" "Starting machine-id fix process"

# Validate dependencies
if ! validate_dependencies; then
  exit 1
fi

# Check if running as root or with sudo
if [[ $EUID -ne 0 ]]; then
  error_handle "$ERROR_CONFIG" "This script must be run as root or with sudo privileges" "$SEVERITY_CRITICAL" "abort"
  exit 1
fi

VM_IDS=(301 302)  # Worker VMs that need machine-id regeneration
MOUNT_POINT="/mnt/vm_disk"

echo "Fixing machine-id on Ubuntu VMs..."

for VM_ID in "${VM_IDS[@]}"; do
  log_info "Processing VM $VM_ID..."

  # Validate VM exists
  if ! validate_vm_exists "$VM_ID"; then
    continue
  fi

  # Get the disk path for this VM
  local disk_path
  if ! disk_path=$(qm config "$VM_ID" 2>/dev/null | grep "virtio0:" | cut -d: -f2 | cut -d, -f1 2>/dev/null); then
    error_handle "$ERROR_EXECUTION" "Failed to get disk path for VM $VM_ID" "$SEVERITY_HIGH" "continue"
    continue
  fi

  if [[ -z "$disk_path" ]]; then
    error_handle "$ERROR_EXECUTION" "No disk path found for VM $VM_ID" "$SEVERITY_HIGH" "continue"
    continue
  fi

  echo "Disk path for VM $VM_ID: $disk_path"

  # Validate disk file exists
  if [[ ! -f "$disk_path" ]]; then
    error_handle "$ERROR_CONFIG" "Disk file not found: $disk_path" "$SEVERITY_HIGH" "continue"
    continue
  fi

  # Create mount point if it doesn't exist
  if ! sudo mkdir -p "$MOUNT_POINT" 2>/dev/null; then
    error_handle "$ERROR_EXECUTION" "Failed to create mount point: $MOUNT_POINT" "$SEVERITY_HIGH" "continue"
    continue
  fi

  local mount_success=false

  # Try to mount the VM disk directly first
  log_info "Attempting direct mount for VM $VM_ID..."
  if sudo mount -o loop "$disk_path" "$MOUNT_POINT" 2>/dev/null; then
    log_success "Mounted VM $VM_ID disk successfully (direct mount)"
    mount_success=true
  else
    log_warning "Could not mount VM $VM_ID disk directly. Trying qemu-nbd method..."

    # Try using qemu-nbd to mount the disk
    local nbd_device="/dev/nbd0"

    # Load nbd module
    if ! sudo modprobe nbd 2>/dev/null; then
      error_handle "$ERROR_EXECUTION" "Failed to load nbd kernel module" "$SEVERITY_HIGH" "continue"
      continue
    fi

    # Check if nbd device is available
    if [[ ! -b "$nbd_device" ]]; then
      error_handle "$ERROR_EXECUTION" "NBD device not available: $nbd_device" "$SEVERITY_HIGH" "continue"
      continue
    fi

    # Connect the disk to nbd device
    if ! sudo qemu-nbd -c "$nbd_device" "$disk_path" 2>/dev/null; then
      error_handle "$ERROR_EXECUTION" "Failed to connect disk to NBD device" "$SEVERITY_HIGH" "continue"
      continue
    fi

    # Wait a bit for the device to be ready
    sleep 2

    # Try to mount the first partition
    if sudo mount "${nbd_device}p1" "$MOUNT_POINT" 2>/dev/null; then
      log_success "Mounted VM $VM_ID via NBD successfully"
      mount_success=true
    else
      error_handle "$ERROR_EXECUTION" "Failed to mount VM $VM_ID even via NBD" "$SEVERITY_HIGH" "continue"
      # Cleanup NBD device
      sudo qemu-nbd -d "$nbd_device" 2>/dev/null || true
      continue
    fi
  fi

  # If mount was successful, proceed with machine-id operations
  if [[ "$mount_success" == "true" ]]; then
    local machine_id_cleared=false

    # Remove existing machine-id files
    if sudo rm -f "$MOUNT_POINT/etc/machine-id" 2>/dev/null && \
       sudo rm -f "$MOUNT_POINT/var/lib/dbus/machine-id" 2>/dev/null; then

      # Create empty machine-id files (will be regenerated on boot)
      if sudo touch "$MOUNT_POINT/etc/machine-id" 2>/dev/null && \
         sudo touch "$MOUNT_POINT/var/lib/dbus/machine-id" 2>/dev/null; then

        log_success "Cleared machine-id for VM $VM_ID"
        machine_id_cleared=true
      else
        error_handle "$ERROR_EXECUTION" "Failed to create empty machine-id files for VM $VM_ID" "$SEVERITY_MEDIUM" "continue"
      fi
    else
      error_handle "$ERROR_EXECUTION" "Failed to remove existing machine-id files for VM $VM_ID" "$SEVERITY_MEDIUM" "continue"
    fi

    # Cleanup mount
    if [[ "$nbd_device" ]]; then
      cleanup_mount "$MOUNT_POINT" "$nbd_device"
    else
      cleanup_mount "$MOUNT_POINT"
    fi

    if [[ "$machine_id_cleared" == "true" ]]; then
      log_success "Successfully processed VM $VM_ID"
    else
      log_warning "Failed to clear machine-id for VM $VM_ID"
    fi
  else
    log_error "Failed to mount VM $VM_ID disk using any method"
  fi

  echo "---"
done

log_success "Machine-id fix process completed. VMs should generate new machine-ids on next boot."
