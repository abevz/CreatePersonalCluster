#!/bin/bash

set -a # automatically export all variables
source /etc/cpc.env
set +a # stop automatically exporting

# install essential packages
dnf install -y \
  glibc-langpack-en \
  gnupg2 \
  bc

# Set up locale
echo -e "export LANGUAGE=en_US\nexport LANG=en_US.UTF-8\nexport LC_ALL=en_US.UTF-8\nexport LC_CTYPE=en_US.UTF-8" >> /etc/environment
source /etc/environment

# Update system
dnf update -y

# Install EPEL repository
dnf install -y epel-release

# Install packages from dnf
dnf install -y \
bash \
curl \
grep \
git \
iscsi-initiator-utils \
lsscsi \
device-mapper-multipath \
nfs-utils \
sg3_utils \
jq \
iperf3 \
ca-certificates \
gnupg2 \
ipvsadm \
httpd-tools \
python3-kubernetes \
python3-pip \
conntrack-tools \
unzip \
ceph-common \
cronie \
iproute \
intel-gpu-tools \
qemu-guest-agent \
cloud-init

# Install Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Add Kubernetes repository
cat <<EOF | tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v$KUBERNETES_SHORT_VERSION/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v$KUBERNETES_SHORT_VERSION/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF

# Import GPG key
rpm --import https://pkgs.k8s.io/core:/stable:/v$KUBERNETES_SHORT_VERSION/rpm/repodata/repomd.xml.key

# Install Kubernetes packages
dnf install -y --disableexcludes=kubernetes \
kubelet-$KUBERNETES_LONG_VERSION \
kubeadm-$KUBERNETES_LONG_VERSION \
kubectl-$KUBERNETES_LONG_VERSION

# Lock Kubernetes packages
dnf versionlock kubelet kubeadm kubectl || echo "versionlock plugin not available"

# Enable and start services
systemctl enable kubelet
systemctl enable iscsid
systemctl enable multipathd

# Install and configure containerd
dnf install -y containerd.io

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

# Disable SELinux
setenforce 0
sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config

# Enable and start necessary services
systemctl enable qemu-guest-agent
systemctl start qemu-guest-agent
