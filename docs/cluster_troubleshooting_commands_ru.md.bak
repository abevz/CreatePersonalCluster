# Cluster Troubleshooting Commands

Этот документ содержит набор команд для диагностики и устранения проблем с Kubernetes кластером, созданным через CPC.

## Общие команды диагностики

### Проверка статуса CPC
```bash
# Проверить текущий контекст кластера
./cpc ctx

# Проверить загруженные переменные среды
./cpc load_secrets
```

### Проверка инфраструктуры Tofu/Terraform
```bash
# Проверить план изменений
./cpc deploy plan

# Проверить состояние ресурсов
./cpc deploy show

# Получить outputs
./cpc deploy output

# Получить IP-адреса узлов
./cpc deploy output k8s_node_ips
```

### Проверка connectivity
```bash
# Проверить подключение к VMs
ansible all -i ansible/inventory/hosts -m ping

# Проверить подключение с автоматическим принятием SSH ключей
ansible all -i ansible/inventory/hosts -m ping --ssh-extra-args="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
```

## SSH диагностика

### Управление SSH соединениями
```bash
# Очистить SSH known_hosts
./cpc clear-ssh-hosts

# Очистить SSH control sockets
./cpc clear-ssh-maps

# Проверить SSH подключение к control plane
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null abevz@<control_plane_ip>
```

### Проверка SSH ключей
```bash
# Проверить SSH ключи в secrets
grep -A5 -B5 ssh_public_key secrets.sops.yaml

# Проверить загруженные SSH ключи
./cpc load_secrets | grep -i ssh
```

## Диагностика контейнеров и Kubernetes

### Проверка containerd
```bash
# Проверить статус containerd на узле
ssh -o StrictHostKeyChecking=no abevz@<node_ip> "sudo systemctl status containerd"

# Проверить конфигурацию containerd
ssh -o StrictHostKeyChecking=no abevz@<node_ip> "sudo cat /etc/containerd/config.toml | grep -A5 -B5 cri"

# Проверить containerd CRI plugin (должен НЕ быть отключен)
ssh -o StrictHostKeyChecking=no abevz@<node_ip> "sudo cat /etc/containerd/config.toml | grep disabled_plugins"

# Перезапустить containerd если нужно
ssh -o StrictHostKeyChecking=no abevz@<node_ip> "sudo systemctl restart containerd"
```

### Проверка kubelet
```bash
# Проверить статус kubelet
ssh -o StrictHostKeyChecking=no abevz@<node_ip> "sudo systemctl status kubelet"

# Посмотреть логи kubelet
ssh -o StrictHostKeyChecking=no abevz@<node_ip> "sudo journalctl -u kubelet -f --no-pager"

# Перезапустить kubelet
ssh -o StrictHostKeyChecking=no abevz@<node_ip> "sudo systemctl restart kubelet"
```

### Проверка control plane компонентов
```bash
# Проверить контейнеры через crictl
ssh -o StrictHostKeyChecking=no abevz@<control_plane_ip> "sudo crictl ps -a"

# Проверить конкретные компоненты
ssh -o StrictHostKeyChecking=no abevz@<control_plane_ip> "sudo crictl ps -a | grep kube-apiserver"
ssh -o StrictHostKeyChecking=no abevz@<control_plane_ip> "sudo crictl ps -a | grep etcd"
ssh -o StrictHostKeyChecking=no abevz@<control_plane_ip> "sudo crictl ps -a | grep kube-controller-manager"
ssh -o StrictHostKeyChecking=no abevz@<control_plane_ip> "sudo crictl ps -a | grep kube-scheduler"

# Посмотреть логи контейнеров
ssh -o StrictHostKeyChecking=no abevz@<control_plane_ip> "sudo crictl logs <container_id>"
```

### Проверка API server
```bash
# Проверить доступность API server локально на control plane
ssh -o StrictHostKeyChecking=no abevz@<control_plane_ip> "sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes"

# Проверить доступность API server снаружи
kubectl cluster-info --context cluster-<workspace>

# Проверить порты
ssh -o StrictHostKeyChecking=no abevz@<control_plane_ip> "sudo netstat -tlnp | grep 6443"
```

## Kubeconfig диагностика

### Проверка kubeconfig
```bash
# Показать все контексты
kubectl config get-contexts

# Показать текущий контекст
kubectl config current-context

# Проверить подключение
kubectl cluster-info

# Проверить server IP в контексте
kubectl config view --minify --flatten -o jsonpath='{.clusters[0].cluster.server}' --context cluster-<workspace>

# Переключиться на контекст
kubectl config use-context cluster-<workspace>
```

### Получение kubeconfig через CPC
```bash
# Получить kubeconfig (автоматически перезапишет существующий)
./cpc get-kubeconfig

# Получить kubeconfig с кастомным именем контекста  
./cpc get-kubeconfig --context-name my-cluster

# Форсировать перезапись
./cpc get-kubeconfig --force
```

## Диагностика сети и CNI

### Проверка сетевых настроек
```bash
# Проверить network bridges
ssh -o StrictHostKeyChecking=no abevz@<node_ip> "sudo sysctl net.bridge.bridge-nf-call-iptables"
ssh -o StrictHostKeyChecking=no abevz@<node_ip> "sudo sysctl net.ipv4.ip_forward"

# Проверить iptables правила
ssh -o StrictHostKeyChecking=no abevz@<node_ip> "sudo iptables -L -n"

# Проверить Calico pods
kubectl get pods -n calico-system --context cluster-<workspace>
kubectl get pods -n kube-system --context cluster-<workspace> | grep calico
```

### Проверка DNS
```bash
# Проверить CoreDNS
kubectl get pods -n kube-system --context cluster-<workspace> | grep coredns

# Протестировать DNS внутри кластера
kubectl run test-dns --image=busybox --rm -it --restart=Never --context cluster-<workspace> -- nslookup kubernetes.default
```

## Диагностика bootstrap процесса

### Проверка этапов bootstrap
```bash
# Проверить готовность VMs
./cpc deploy output k8s_node_ips

# Запустить bootstrap с verbose выводом
./cpc bootstrap

# Проверить состояние после bootstrap
kubectl get nodes --context cluster-<workspace>
kubectl get pods --all-namespaces --context cluster-<workspace>
```

### Анализ проблем bootstrap
```bash
# Проверить kubeadm логи
ssh -o StrictHostKeyChecking=no abevz@<control_plane_ip> "sudo journalctl -u kubelet --no-pager | grep -i error"

# Проверить cloud-init логи
ssh -o StrictHostKeyChecking=no abevz@<node_ip> "sudo tail -f /var/log/cloud-init-output.log"

# Проверить системные ресурсы
ssh -o StrictHostKeyChecking=no abevz@<node_ip> "free -h && df -h && systemctl status"
```

## Команды для сброса и пересоздания

### Полный сброс кластера
```bash
# Остановить VMs
./cpc stop-vms

# Удалить инфраструктуру  
./cpc deploy destroy -auto-approve

# Очистить kubeconfig
kubectl config delete-context cluster-<workspace> 2>/dev/null || true
kubectl config delete-cluster cluster-<workspace>-cluster 2>/dev/null || true  
kubectl config delete-user cluster-<workspace>-admin 2>/dev/null || true

# Очистить SSH
./cpc clear-ssh-hosts
./cpc clear-ssh-maps
```

### Пересоздание кластера
```bash
# Создать новую инфраструктуру
./cpc deploy apply -auto-approve

# Дождаться готовности VMs (2-3 минуты)
./cpc deploy output k8s_node_ips

# Запустить bootstrap
./cpc bootstrap

# Получить kubeconfig
./cpc get-kubeconfig

# Проверить результат
kubectl get nodes --context cluster-<workspace>
```

## Полезные алиасы

Добавьте эти алиасы в ваш `.bashrc` или `.zshrc`:

```bash
# CPC алиасы
alias cpc-ctx='./cpc ctx'
alias cpc-deploy='./cpc deploy'
alias cpc-bootstrap='./cpc bootstrap'
alias cpc-kubeconfig='./cpc get-kubeconfig'

# Kubernetes алиасы для troubleshooting
alias k='kubectl'
alias kgp='kubectl get pods'
alias kgs='kubectl get services'  
alias kgn='kubectl get nodes'
alias kdp='kubectl describe pod'
alias kds='kubectl describe service'
alias kdn='kubectl describe node'
alias klogs='kubectl logs'
```

## Примеры конкретных сценариев

### Сценарий 1: API server не отвечает
```bash
# 1. Проверить IP-адрес в kubeconfig
kubectl config view --minify --flatten -o jsonpath='{.clusters[0].cluster.server}' --context cluster-ubuntu

# 2. Проверить реальный IP control plane
./cpc deploy output k8s_node_ips

# 3. Если IP отличаются - получить новый kubeconfig
./cpc get-kubeconfig

# 4. Проверить статус kubelet на control plane
ssh -o StrictHostKeyChecking=no abevz@<control_plane_ip> "sudo systemctl status kubelet"

# 5. Перезапустить kubelet если нужно
ssh -o StrictHostKeyChecking=no abevz@<control_plane_ip> "sudo systemctl restart kubelet"
```

### Сценарий 2: Узлы в статусе NotReady
```bash
# 1. Проверить статус узлов
kubectl get nodes --context cluster-<workspace>

# 2. Проверить CNI pods
kubectl get pods -n calico-system --context cluster-<workspace>

# 3. Проверить containerd CRI на всех узлах
for ip in $(./cpc deploy output k8s_node_ips | jq -r '.[]'); do
  echo "=== Node $ip ==="
  ssh -o StrictHostKeyChecking=no abevz@$ip "sudo cat /etc/containerd/config.toml | grep disabled_plugins"
done

# 4. Исправить CRI конфигурацию если нужно
for ip in $(./cpc deploy output k8s_node_ips | jq -r '.[]'); do
  ssh -o StrictHostKeyChecking=no abevz@$ip "sudo sed -i 's/disabled_plugins = \[\"cri\"\]/disabled_plugins = []/g' /etc/containerd/config.toml && sudo systemctl restart containerd"
done
```

### Сценарий 3: Bootstrap прерывается на SSH
```bash
# 1. Очистить SSH кэш
./cpc clear-ssh-hosts
./cpc clear-ssh-maps

# 2. Проверить SSH подключение вручную
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null abevz@<node_ip>

# 3. Запустить bootstrap снова - SSH ключи будут приняты автоматически
./cpc bootstrap
```

---

**Примечание**: Замените `<workspace>`, `<node_ip>`, `<control_plane_ip>`, `<container_id>` на реальные значения для вашего кластера.
