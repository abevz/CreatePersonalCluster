#!/bin/bash

# Script to fix machine-id on remote worker nodes

echo "Generating new machine-id for $(hostname)..."
echo "Old machine-id: $(cat /etc/machine-id)"

# Get some unique data
HOSTNAME=$(hostname)
MAC_ADDRESS=$(cat /sys/class/net/$(ip route show default | awk '/default/ {print $5}')/address 2>/dev/null || echo "unknown")
RANDOM_DATA=$(dd if=/dev/urandom bs=512 count=1 2>/dev/null | md5sum)
TIMESTAMP=$(date +%s%N)

# Generate a truly random UUID using multiple sources of entropy
UNIQUE_ID="${HOSTNAME}-${MAC_ADDRESS}-${RANDOM_DATA}-${TIMESTAMP}-$(uuidgen)"
MACHINE_ID=$(echo $UNIQUE_ID | md5sum | cut -c1-32)

# Remove any existing machine-id files
if [ -f /etc/machine-id ]; then
    sudo rm -f /etc/machine-id
fi

if [ -f /var/lib/dbus/machine-id ]; then
    sudo rm -f /var/lib/dbus/machine-id
fi

# Write the new machine ID
echo $MACHINE_ID | sudo tee /etc/machine-id
sudo chmod 444 /etc/machine-id

# Make sure dbus machine-id is also set
sudo mkdir -p /var/lib/dbus
sudo cp /etc/machine-id /var/lib/dbus/machine-id
sudo chmod 444 /var/lib/dbus/machine-id

echo "New machine-id: $(cat /etc/machine-id)"

# Restart network services to apply with new machine-id for DHCP
echo "Restarting network services..."
sudo systemctl restart systemd-networkd || true
sudo systemctl restart systemd-resolved || true

if sudo systemctl is-active NetworkManager >/dev/null 2>&1; then
    sudo systemctl restart NetworkManager || true
fi

sudo netplan apply || true

echo "Machine-ID fix completed. New IP should be assigned shortly."
echo "You may need to reconnect to this host with the new IP."
