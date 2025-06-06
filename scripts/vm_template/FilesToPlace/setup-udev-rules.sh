#!/bin/bash

# Script to setup udev rules in the correct location for different distributions

UDEV_RULE_FILE="80-hotplug-cpu.rules"
UDEV_RULE_CONTENT='SUBSYSTEM=="cpu", ACTION=="add", TEST=="online", ATTR{online}=="0", ATTR{online}="1"'

# Function to detect the distribution
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo $ID
    elif [ -f /etc/redhat-release ]; then
        echo "rhel"
    elif [ -f /etc/debian_version ]; then
        echo "debian"
    else
        echo "unknown"
    fi
}

# Function to get the correct udev rules directory
get_udev_rules_dir() {
    local distro=$(detect_distro)
    
    case $distro in
        "debian"|"ubuntu")
            echo "/lib/udev/rules.d"
            ;;
        "rhel"|"centos"|"rocky"|"almalinux"|"fedora")
            # Check which directory exists
            if [ -d "/usr/lib/udev/rules.d" ]; then
                echo "/usr/lib/udev/rules.d"
            elif [ -d "/lib/udev/rules.d" ]; then
                echo "/lib/udev/rules.d"
            else
                echo "/usr/lib/udev/rules.d"  # Default for newer RHEL systems
            fi
            ;;
        "opensuse"|"opensuse-leap"|"opensuse-tumbleweed"|"sles"|"suse")
            if [ -d "/usr/lib/udev/rules.d" ]; then
                echo "/usr/lib/udev/rules.d"
            elif [ -d "/etc/udev/rules.d" ]; then
                echo "/etc/udev/rules.d"
            else
                echo "/usr/lib/udev/rules.d"  # Default for SUSE systems
            fi
            ;;
        *)
            # Try to find any existing udev rules directory
            for dir in "/usr/lib/udev/rules.d" "/lib/udev/rules.d" "/etc/udev/rules.d"; do
                if [ -d "$dir" ]; then
                    echo "$dir"
                    return
                fi
            done
            echo "/usr/lib/udev/rules.d"  # Fallback default
            ;;
    esac
}

# Main execution
UDEV_DIR=$(get_udev_rules_dir)

echo "Detected distribution: $(detect_distro)"
echo "Using udev rules directory: $UDEV_DIR"

# Create the directory if it doesn't exist
mkdir -p "$UDEV_DIR"

# Create the udev rule file
echo "$UDEV_RULE_CONTENT" > "$UDEV_DIR/$UDEV_RULE_FILE"

echo "Successfully created udev rule: $UDEV_DIR/$UDEV_RULE_FILE"

# Reload udev rules
if command -v udevadm >/dev/null 2>&1; then
    udevadm control --reload-rules
    echo "Reloaded udev rules"
else
    echo "Warning: udevadm not found, udev rules may not be reloaded"
fi
