#!/bin/bash

set -a # automatically export all variables
source /etc/cpc.env
set +a # stop automatically exporting

# Function to detect OS and package manager
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$NAME
        VER=$VERSION_ID
    elif type lsb_release >/dev/null 2>&1; then
        OS=$(lsb_release -si)
        VER=$(lsb_release -sr)
    elif [ -f /etc/lsb-release ]; then
        . /etc/lsb-release
        OS=$DISTRIB_ID
        VER=$DISTRIB_RELEASE
    elif [ -f /etc/debian_version ]; then
        OS=Debian
        VER=$(cat /etc/debian_version)
    elif [ -f /etc/SuSe-release ]; then
        OS=openSUSE
    elif [ -f /etc/redhat-release ]; then
        OS=RedHat
    else
        OS=$(uname -s)
        VER=$(uname -r)
    fi
}

# Function to install packages based on OS
install_packages() {
    detect_os
    
    case "$OS" in
        *"Ubuntu"*|*"Debian"*)
            echo "Detected Debian/Ubuntu system, using APT package manager"
            /root/apt-packages.sh
            ;;
        *"Rocky"*|*"Red Hat"*|*"CentOS"*|*"Fedora"*)
            echo "Detected RedHat-based system, using YUM/DNF package manager"
            /root/rpm-packages.sh
            ;;
        *"openSUSE"*|*"SUSE"*)
            echo "Detected SUSE system, using Zypper package manager"
            /root/suse-packages.sh
            ;;
        *)
            echo "Unknown OS: $OS. Attempting to use APT as fallback"
            /root/apt-packages.sh
            ;;
    esac
}

# Make package scripts executable
chmod +x /root/*.sh

# Install packages based on detected OS
install_packages
