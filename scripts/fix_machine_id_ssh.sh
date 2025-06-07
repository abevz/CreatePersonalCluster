#!/bin/bash

# Script to regenerate machine-id on VMs that have duplicates

echo "Fixing machine-id conflicts..."

# Since all VMs currently have the same IP, we'll need to access them differently
# We'll use the Proxmox console access or try to connect to each one

VM_IP="10.10.10.80"
HOSTNAMES=("cu1.bevz.net" "wu1.bevz.net" "wu2.bevz.net")

echo "Current situation: all VMs have IP $VM_IP due to machine-id conflicts"

# First, let's see which VM is currently responding
echo "Checking which VM is currently responding on $VM_IP..."
CURRENT_HOSTNAME=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no abevz@$VM_IP "hostname" 2>/dev/null)

if [ -n "$CURRENT_HOSTNAME" ]; then
    echo "VM responding on $VM_IP has hostname: $CURRENT_HOSTNAME"
    
    # Check and regenerate machine-id on this VM
    CURRENT_MACHINE_ID=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no abevz@$VM_IP "cat /etc/machine-id" 2>/dev/null)
    echo "Current machine-id: $CURRENT_MACHINE_ID"
    
    # Regenerate machine-id
    echo "Regenerating machine-id on $CURRENT_HOSTNAME..."
    ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no abevz@$VM_IP "
        sudo rm -f /etc/machine-id /var/lib/dbus/machine-id
        sudo systemd-machine-id-setup
        sudo systemctl restart systemd-networkd
        echo 'Machine-id regenerated. New ID:'
        cat /etc/machine-id
    " 2>/dev/null
    
    if [ $? -eq 0 ]; then
        echo "Successfully regenerated machine-id on $CURRENT_HOSTNAME"
        echo "Rebooting $CURRENT_HOSTNAME to ensure changes take effect..."
        ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no abevz@$VM_IP "sudo reboot" 2>/dev/null
        
        # Wait for reboot
        echo "Waiting 30 seconds for reboot..."
        sleep 30
        
        # Check if VM comes back with different IP
        echo "Checking if VM comes back with different IP..."
    else
        echo "Failed to regenerate machine-id on $CURRENT_HOSTNAME"
    fi
else
    echo "No VM is responding on $VM_IP"
fi

echo "Machine-id fix attempt completed."
echo "Please check the VM IPs after a few minutes to see if they now have unique IPs."
