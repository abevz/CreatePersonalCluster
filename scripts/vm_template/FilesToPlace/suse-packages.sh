#!/bin/bash

set -a # automatically export all variables
source /etc/cpc.env
set +a # stop automatically exporting

# Set non-interactive mode for zypper commands
export ZYPPER_NON_INTERACTIVE=1

# install essential packages
zypper install -y \
  glibc-locale \
  gpg2 \
  bc

# Set up locale
echo -e "export LANGUAGE=en_US\nexport LANG=en_US.UTF-8\nexport LC_ALL=en_US.UTF-8\nexport LC_CTYPE=en_US.UTF-8" >> /etc/environment
source /etc/environment

# Update system
zypper refresh
zypper update -y

# Install packages from zypper
zypper install -y \
bash \
curl \
grep \
git \
open-iscsi \
lsscsi \
multipath-tools \
nfs-client \
sg3_utils \
jq \
apparmor-parser \
apparmor-utils \
iperf \
ca-certificates \
gnupg2 \
ipvsadm \
apache2-utils \
python3-kubernetes \
python3-pip \
conntrack-tools \
unzip \
ceph-common \
cron \
iproute2 \
intel-gpu-tools \
helm \
qemu-guest-agent \
cloud-init \
etcd

# Add Kubernetes repository
cat <<EOF | tee /etc/zypp/repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v$KUBERNETES_SHORT_VERSION/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v$KUBERNETES_SHORT_VERSION/rpm/repodata/repomd.xml.key
EOF

# Import GPG key
rpm --import https://pkgs.k8s.io/core:/stable:/v$KUBERNETES_SHORT_VERSION/rpm/repodata/repomd.xml.key

# Refresh repositories
zypper refresh

# Install Kubernetes packages
zypper install -y \
kubelet-$KUBERNETES_LONG_VERSION \
kubeadm-$KUBERNETES_LONG_VERSION \
kubectl-$KUBERNETES_LONG_VERSION

# Lock Kubernetes packages
zypper addlock kubelet kubeadm kubectl

# Enable and start services
systemctl enable kubelet
systemctl enable iscsid
systemctl enable multipathd
systemctl enable apparmor

# Install and configure containerd
zypper install -y containerd

# Configure containerd
mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

systemctl enable containerd
systemctl start containerd

# Disable swap
swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Configure kernel modules
modprobe overlay
modprobe br_netfilter

# Enable IP forwarding
echo '1' > /proc/sys/net/ipv4/ip_forward
echo '1' > /proc/sys/net/ipv6/conf/all/forwarding

# Configure firewall
systemctl disable firewalld || true
systemctl stop firewalld || true

# Enable and start necessary services
systemctl enable qemu-guest-agent
systemctl start qemu-guest-agent
