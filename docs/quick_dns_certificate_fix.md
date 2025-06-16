# Быстрое решение проблемы с DNS-именами в сертификатах Kubernetes

## Симптомы проблемы
- ❌ Кластер недоступен при изменении IP-адресов после перезагрузки VM
- ❌ Сертификаты содержат только IP-адреса, а не DNS-имена (cu1.bevz.net)
- ❌ `kubectl` выдает ошибки сертификатов при использовании hostname

## Быстрое решение

### Для НОВОГО кластера

```bash
# DNS поддержка УЖЕ ВСТРОЕНА в CPC!
cd /home/abevz/Projects/kubernetes/my-kthw

# 1. Развернуть VM
./cpc deploy apply

# 2. Инициализировать кластер с DNS поддержкой (автоматически)
./cpc bootstrap

# 3. Получить kubeconfig с DNS endpoint
./cpc get-kubeconfig --force

# 4. Проверить результат
kubectl get nodes
```

### Для СУЩЕСТВУЮЩЕГО кластера

```bash
# 1. Создайте backup кластера
kubectl get all --all-namespaces > cluster-backup.yaml

# 2. Примените патч сертификатов
cd /home/abevz/Projects/kubernetes/my-kthw
./cpc run-ansible regenerate_certificates_with_dns.yml

# 3. Получите обновленный kubeconfig
./cpc get-kubeconfig --force

# 4. Проверьте работоспособность
kubectl get nodes
```

## Проверка результата

```bash
# 1. Проверить SAN в сертификате
ssh abevz@cu1.bevz.net "sudo openssl x509 -in /etc/kubernetes/pki/apiserver.crt -text -noout | grep -A 10 'Subject Alternative Name'"

# Должно показать:
# DNS:cu1.bevz.net, DNS:cu1, IP Address:10.10.10.116, ...

# 2. Проверить доступ через DNS
kubectl --server=https://cu1.bevz.net:6443 get nodes

# 3. Проверить kubeconfig endpoint
kubectl config view --minify --flatten -o jsonpath='{.clusters[0].cluster.server}'
# Должно показать: https://cu1.bevz.net:6443
```

## Что изменится

### ✅ БЫЛО (проблема):
```yaml
# Сертификат содержал только:
IP Address:10.10.10.116

# kubeconfig использовал:
server: https://10.10.10.116:6443
```

### ✅ СТАЛО (решение):
```yaml
# Сертификат содержит:
DNS:cu1.bevz.net, DNS:cu1, IP Address:10.10.10.116

# kubeconfig использует:
server: https://cu1.bevz.net:6443
```

## Восстановление при проблемах

Если что-то пошло не так:

```bash
# 1. Восстановить из backup (создается автоматически)
sudo cp /root/k8s-cert-backup-*/pki/* /etc/kubernetes/pki/
sudo cp /root/k8s-cert-backup-*/admin.conf /etc/kubernetes/

# 2. Перезапустить kubelet
sudo systemctl restart kubelet

# 3. Получить kubeconfig с IP
./cpc get-kubeconfig --use-ip --force
```

## Дополнительная настройка CPC

Для автоматического использования DNS в новых кластерах, отредактируйте `cpc`:

```bash
# Найдите строку 819 в файле cpc:
sed -i 's/initialize_kubernetes_cluster.yml/initialize_kubernetes_cluster_with_dns.yml/g' cpc
```

Теперь все новые кластеры будут создаваться с поддержкой DNS-имен!

## Поддержка

Полная документация: `docs/kubernetes_dns_certificate_solution.md`
