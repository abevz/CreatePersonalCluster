# Kubernetes Certificate DNS Hostname Issue and Solution

## Проблема

При создании кластера Kubernetes с помощью kubeadm, API-сервер создает самоподписанные сертификаты, которые включают только IP-адреса узлов в качестве Subject Alternative Names (SAN). Это создает проблему, когда:

1. **DHCP выдает разные IP-адреса** при перезагрузке серверов
2. **DNS-имена серверов остаются постоянными** (например, cu1.bevz.net, wu1.bevz.net)
3. **Сертификаты становятся невалидными** при изменении IP-адресов

## Техническая причина

В текущем `initialize_kubernetes_cluster.yml` используется:

```yaml
kubeadm init \
  --apiserver-advertise-address={{ ansible_default_ipv4.address }} \
  --control-plane-endpoint={{ ansible_default_ipv4.address }}
```

Это приводит к созданию сертификатов, которые содержат только IP-адреса в SAN, но не DNS-имена.

## Решение

### 1. Новый Playbook для создания кластера с DNS-поддержкой

Создан файл `initialize_kubernetes_cluster_with_dns.yml`, который:

- Использует **kubeadm configuration file** вместо командной строки
- Добавляет **DNS-имена в certSANs** API-сервера
- Устанавливает **control-plane-endpoint** как FQDN вместо IP

**Ключевые улучшения:**
```yaml
apiServer:
  certSANs:
  - {{ ansible_default_ipv4.address }}     # IP-адрес
  - {{ ansible_hostname }}                 # Короткое имя
  - {{ ansible_fqdn }}                     # Полное DNS-имя
  - localhost                              # Локальный доступ
  - 127.0.0.1                             
  - kubernetes                             # Стандартные имена
  - kubernetes.default
  - kubernetes.default.svc
  - kubernetes.default.svc.cluster.local
controlPlaneEndpoint: "{{ ansible_fqdn }}:6443"  # Использует FQDN
```

### 2. Playbook для обновления существующих кластеров

Создан файл `regenerate_certificates_with_dns.yml` для кластеров, которые уже развернуты:

**Процесс:**
1. Создает резервную копию существующих сертификатов
2. Останавливает kubelet и containerd
3. Удаляет старые сертификаты API-сервера
4. Генерирует новые сертификаты с DNS-именами
5. Обновляет kubeconfig файлы
6. Перезапускает сервисы

### 3. Улучшенная функция get-kubeconfig

Создан скрипт `enhanced_get_kubeconfig.sh`, который:

- **Приоритизирует DNS-имена** над IP-адресами
- **Проверяет DNS-резолюцию** перед использованием hostname
- **Тестирует подключение** к API-серверу
- **Автоматически откатывается** на IP при проблемах с DNS

## Преимущества решения

### ✅ Устойчивость к изменениям IP
- Кластер остается доступным при изменении IP-адресов DHCP
- DNS-имена серверов остаются постоянными

### ✅ Лучшая интеграция с DNS
- Возможность использования внутренней DNS инфраструктуры
- Поддержка сложных сетевых топологий

### ✅ Совместимость
- Поддерживает как DNS-имена, так и IP-адреса
- Автоматический fallback на IP при проблемах с DNS

### ✅ Безопасность
- Сертификаты содержат все необходимые SAN
- Нет предупреждений о недоверенных сертификатах

## Использование

### Для новых кластеров

```bash
# Используйте новый playbook вместо стандартного
ansible-playbook -i ansible/inventory/tofu_inventory.py \
  ansible/playbooks/initialize_kubernetes_cluster_with_dns.yml
```

### Для существующих кластеров

```bash
# Обновите сертификаты с DNS-поддержкой
ansible-playbook -i ansible/inventory/tofu_inventory.py \
  ansible/playbooks/regenerate_certificates_with_dns.yml
```

### Получение kubeconfig с DNS-поддержкой

```bash
# Используйте улучшенную функцию
source scripts/enhanced_get_kubeconfig.sh
enhanced_get_kubeconfig --use-hostname
```

## Проверка результата

После применения решения:

```bash
# Проверить SAN в сертификате
openssl x509 -in /etc/kubernetes/pki/apiserver.crt -text -noout | grep -A 10 "Subject Alternative Name"

# Проверить доступ через DNS-имя
kubectl --server=https://cu1.bevz.net:6443 get nodes

# Проверить kubeconfig
kubectl config view --minify --flatten -o jsonpath='{.clusters[0].cluster.server}'
```

## Важные замечания

1. **DNS должен быть настроен** корректно для всех узлов кластера
2. **Backup сертификатов** создается автоматически при обновлении
3. **Временное прерывание** API-сервера возможно при обновлении сертификатов
4. **Worker nodes** будут переподключены автоматически после обновления

## Интеграция с CPC

Для интеграции с основным инструментом CPC:

1. Замените вызов `initialize_kubernetes_cluster.yml` на `initialize_kubernetes_cluster_with_dns.yml` в bootstrap функции
2. Добавьте команду для обновления сертификатов: `cpc regenerate-certificates`
3. Обновите `get-kubeconfig` функцию для использования DNS-имен

Это обеспечит полную поддержку DNS-имен в вашей инфраструктуре Kubernetes!
