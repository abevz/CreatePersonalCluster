#!/bin/bash

# Script to fix machine-id on Ubuntu VMs that have duplicates
# This should be run on the Proxmox host

VM_IDS=(301 302)  # Worker VMs that need machine-id regeneration
MOUNT_POINT="/mnt/vm_disk"

echo "Fixing machine-id on Ubuntu VMs..."

for VM_ID in "${VM_IDS[@]}"; do
    echo "Processing VM $VM_ID..."
    
    # Get the disk path for this VM
    DISK_PATH=$(qm config $VM_ID | grep "virtio0:" | cut -d: -f2 | cut -d, -f1)
    echo "Disk path for VM $VM_ID: $DISK_PATH"
    
    # Create mount point if it doesn't exist
    sudo mkdir -p $MOUNT_POINT
    
    # Try to mount the VM disk to modify machine-id
    if sudo mount -o loop $DISK_PATH $MOUNT_POINT 2>/dev/null; then
        echo "Mounted VM $VM_ID disk successfully"
        
        # Remove existing machine-id
        sudo rm -f $MOUNT_POINT/etc/machine-id
        sudo rm -f $MOUNT_POINT/var/lib/dbus/machine-id
        
        # Create empty machine-id files (will be regenerated on boot)
        sudo touch $MOUNT_POINT/etc/machine-id
        sudo touch $MOUNT_POINT/var/lib/dbus/machine-id
        
        echo "Cleared machine-id for VM $VM_ID"
        
        # Unmount
        sudo umount $MOUNT_POINT
        echo "Unmounted VM $VM_ID disk"
    else
        echo "Could not mount VM $VM_ID disk directly. Using qemu-nbd method..."
        
        # Try using qemu-nbd to mount the disk
        NBD_DEVICE="/dev/nbd0"
        
        # Load nbd module
        sudo modprobe nbd
        
        # Connect the disk to nbd device
        sudo qemu-nbd -c $NBD_DEVICE $DISK_PATH
        
        # Wait a bit for the device to be ready
        sleep 2
        
        # Try to mount the first partition
        if sudo mount ${NBD_DEVICE}p1 $MOUNT_POINT; then
            echo "Mounted VM $VM_ID via NBD successfully"
            
            # Remove existing machine-id
            sudo rm -f $MOUNT_POINT/etc/machine-id
            sudo rm -f $MOUNT_POINT/var/lib/dbus/machine-id
            
            # Create empty machine-id files
            sudo touch $MOUNT_POINT/etc/machine-id
            sudo touch $MOUNT_POINT/var/lib/dbus/machine-id
            
            echo "Cleared machine-id for VM $VM_ID via NBD"
            
            # Unmount and disconnect
            sudo umount $MOUNT_POINT
            sudo qemu-nbd -d $NBD_DEVICE
            echo "Unmounted and disconnected VM $VM_ID"
        else
            echo "Failed to mount VM $VM_ID even via NBD"
            sudo qemu-nbd -d $NBD_DEVICE
        fi
    fi
    
    echo "Finished processing VM $VM_ID"
    echo "---"
done

echo "Machine-id fix complete. VMs should generate new machine-ids on next boot."
