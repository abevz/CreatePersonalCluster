#!/bin/bash
# This script ensures each VM has a unique machine-id
# It should be copied to /var/lib/cloud/scripts/per-instance/ensure-unique-machine-id.sh
# during VM creation

# Log beginning of script execution
echo "Starting machine-id regeneration script at $(date)" > /var/log/machine-id-setup.log

# Get some unique data
HOSTNAME=$(hostname)
MAC_ADDRESS=$(cat /sys/class/net/$(ip route show default | awk '/default/ {print $5}')/address 2>/dev/null || echo "unknown")
RANDOM_DATA=$(dd if=/dev/urandom bs=512 count=1 2>/dev/null | md5sum)
TIMESTAMP=$(date +%s%N)

# Generate a truly random UUID using multiple sources of entropy
UNIQUE_ID="${HOSTNAME}-${MAC_ADDRESS}-${RANDOM_DATA}-${TIMESTAMP}-$(uuidgen)"
MACHINE_ID=$(echo $UNIQUE_ID | md5sum | cut -c1-32)

# Log what we're doing
echo "Generated new unique machine-id using hostname, MAC, random data and timestamp" >> /var/log/machine-id-setup.log
echo "Hostname: $HOSTNAME" >> /var/log/machine-id-setup.log
echo "MAC Address: $MAC_ADDRESS" >> /var/log/machine-id-setup.log
echo "Timestamp: $TIMESTAMP" >> /var/log/machine-id-setup.log
echo "New machine-id: $MACHINE_ID" >> /var/log/machine-id-setup.log

# Remove any existing machine-id files
if [ -f /etc/machine-id ]; then
    echo "Previous machine-id: $(cat /etc/machine-id)" >> /var/log/machine-id-setup.log
    rm -f /etc/machine-id
fi

if [ -f /var/lib/dbus/machine-id ]; then
    rm -f /var/lib/dbus/machine-id
fi

# Write the new machine ID
echo $MACHINE_ID > /etc/machine-id
chmod 444 /etc/machine-id

# Make sure dbus machine-id is also set
mkdir -p /var/lib/dbus
cp /etc/machine-id /var/lib/dbus/machine-id
chmod 444 /var/lib/dbus/machine-id

# Apply hostname and hostid changes
hostnamectl apply || true

# Restart network services to apply with new machine-id for DHCP
if command -v netplan >/dev/null 2>&1; then
    echo "Applying netplan configuration..." >> /var/log/machine-id-setup.log
    netplan apply || true
else 
    echo "Restarting networking services..." >> /var/log/machine-id-setup.log
    systemctl restart networking || true
fi

# Additional restart of network manager if present
if systemctl is-active NetworkManager >/dev/null 2>&1; then
    echo "Restarting NetworkManager..." >> /var/log/machine-id-setup.log
    systemctl restart NetworkManager || true
fi

# Restart systemd-networkd which handles DHCP
echo "Restarting systemd-networkd..." >> /var/log/machine-id-setup.log
systemctl restart systemd-networkd || true

# Restart systemd-resolved for DNS changes
echo "Restarting systemd-resolved..." >> /var/log/machine-id-setup.log
systemctl restart systemd-resolved || true

echo "Machine-ID regeneration completed at $(date)" >> /var/log/machine-id-setup.log
echo "Final machine-id: $(cat /etc/machine-id)" >> /var/log/machine-id-setup.log
