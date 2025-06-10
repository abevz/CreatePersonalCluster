# Полное Руководство по Созданию Kubernetes Кластера с CPC

## 📋 **ОБЗОР**

Это руководство описывает правильную последовательность создания Kubernetes кластера с помощью CPC (Cluster Provisioning Control) на базе нашего успешного опыта развертывания.

**Дата обновления:** 10 июня 2025  
**Статус:** Проверено и работает  
**Версия Kubernetes:** v1.31.9  

## 🎯 **ЦЕЛЬ**

Создать полностью функциональный 3-узловой Kubernetes кластер:
- 1 Control Plane node
- 2 Worker nodes
- Calico CNI
- Все системные компоненты

## 🚀 **ПОШАГОВОЕ РУКОВОДСТВО**

### **Шаг 1: Подготовка и настройка**

```bash
# Настройка CPC (если еще не сделано)
./cpc setup-cpc

# Установка контекста (например, ubuntu)
./cpc ctx ubuntu

# Загрузка секретов
./cpc load_secrets
```

**Проверка:**
```bash
# Должны увидеть загруженные секреты и переменные
Loading secrets from secrets.sops.yaml...
Successfully loaded secrets (PROXMOX_HOST: homelab.bevz.net, VM_USERNAME: abevz)
```

### **Шаг 2: Создание инфраструктуры**

```bash
# Планирование изменений (опционально, но рекомендуется)
./cpc deploy plan

# Создание VM
./cpc deploy apply -auto-approve

# Проверка созданных VM
./cpc deploy output k8s_node_ips
```

**Ожидаемый результат:**
```
control_plane_ips = ["10.10.10.116"]
worker_ips = ["10.10.10.101", "10.10.10.29"]
```

### **Шаг 3: Подготовка узлов**

```bash
# Установка Kubernetes компонентов на всех узлах
./cpc run-ansible install_kubernetes_cluster.yml
```

**Что происходит:**
- Установка containerd с правильной CRI конфигурацией
- Установка kubelet, kubeadm, kubectl
- Настройка системных параметров для Kubernetes

### **Шаг 4: Инициализация кластера**

```bash
# Полная инициализация кластера (control plane + Calico CNI)
./cpc bootstrap
```

**Что происходит:**
- Инициализация control plane с kubeadm
- Установка Calico CNI
- Настройка сети кластера

### **Шаг 5: Добавление worker nodes**

```bash
# Присоединение worker узлов к кластеру
./cpc add-nodes --target-hosts "workers"
```

**Что происходит:**
- Генерация join token
- Присоединение worker nodes к кластеру
- Проверка статуса узлов

### **Шаг 6: Получение доступа к кластеру**

```bash
# Получение kubeconfig
./cpc get-kubeconfig

# Проверка статуса кластера
kubectl get nodes -o wide
kubectl get pods --all-namespaces
```

## 🔧 **УПРАВЛЕНИЕ ДОПОЛНИТЕЛЬНЫМИ КОМПОНЕНТАМИ**

### **Команда upgrade-addons**

✨ **НОВОЕ:** Команда `./cpc upgrade-addons` теперь показывает **интерактивное меню** для выбора компонентов!

**Правильное использование:**

```bash
# Показать справку и доступные addons
./cpc upgrade-addons --help

# Интерактивное меню (новое поведение по умолчанию)
./cpc upgrade-addons
# Покажет меню:
# 1) all - Install/upgrade all addons
# 2) calico - Calico CNI networking
# 3) metallb - MetalLB load balancer
# ... и т.д.

# Прямая установка всех addons (пропуск меню)
./cpc upgrade-addons --addon all

# Установить конкретный addon (пропуск меню)
./cpc upgrade-addons --addon metallb
./cpc upgrade-addons --addon cert-manager
./cpc upgrade-addons --addon ingress-nginx

# Установить addon с конкретной версией
./cpc upgrade-addons --addon metallb --version v0.14.8
```

**Доступные addons:**
- `calico` - Calico CNI networking
- `metallb` - MetalLB load balancer  
- `metrics-server` - Kubernetes Metrics Server
- `coredns` - CoreDNS DNS server
- `cert-manager` - Certificate manager
- `kubelet-serving-cert-approver` - Automatic certificate approval
- `argocd` - ArgoCD GitOps
- `ingress-nginx` - NGINX Ingress Controller
- `all` - Все вышеперечисленные

## 🔄 **ПОЛНЫЙ WORKFLOW ДЛЯ НОВОГО КЛАСТЕРА**

```bash
# 1. Полная очистка (если нужно пересоздать)
./cpc stop-vms                           # Остановить VM
./cpc deploy destroy -auto-approve       # Удалить инфраструктуру
./cpc clear-ssh-hosts && ./cpc clear-ssh-maps  # Очистить SSH cache

# 2. Создание новой инфраструктуры
./cpc deploy apply -auto-approve

# 3. Установка компонентов
./cpc run-ansible install_kubernetes_cluster.yml

# 4. Инициализация кластера
./cpc bootstrap

# 5. Добавление worker nodes
./cpc add-nodes --target-hosts "workers"

# 6. Получение доступа
./cpc get-kubeconfig

# 7. Установка дополнительных компонентов (опционально)
./cpc upgrade-addons  # Покажет интерактивное меню
# или прямая установка:
./cpc upgrade-addons --addon metallb
./cpc upgrade-addons --addon cert-manager

# 8. Финальная проверка
kubectl get nodes -o wide
kubectl get pods --all-namespaces
```

## ⚠️ **ВАЖНЫЕ ИСПРАВЛЕНИЯ**

### **1. Containerd CRI конфигурация**

**Проблема:** Containerd не настраивался правильно для CRI.

**Исправление в `install_kubernetes_cluster.yml` (строка ~133):**
```yaml
# УБРАЛИ эту строку для перегенерации конфигурации:
# args:
#   creates: /etc/containerd/config.toml
```

### **2. Рекурсивная ошибка в pb_add_nodes.yml**

**Проблема:** Переменная `control_plane_endpoint` ссылалась сама на себя.

**Исправление:**
```yaml
# Добавили сбор facts для control plane
- name: Gather facts from control plane
  setup:
  delegate_to: "{{ groups['control_plane'][0] }}"
  delegate_facts: yes
  run_once: true

# Динамическое определение endpoint
- name: Set control plane endpoint
  set_fact:
    control_plane_endpoint: "{{ hostvars[groups['control_plane'][0]]['ansible_default_ipv4']['address'] + ':6443' }}"
```

## ✅ **ПРОВЕРКА УСПЕШНОСТИ**

После выполнения всех шагов должно быть:

**Статус узлов:**
```bash
$ kubectl get nodes -o wide
NAME           STATUS   ROLES           AGE   VERSION   INTERNAL-IP    EXTERNAL-IP   OS-IMAGE             KERNEL-VERSION     CONTAINER-RUNTIME
cu1.bevz.net   Ready    control-plane   13m   v1.31.9   10.10.10.116   <none>        Ubuntu 24.04.2 LTS   6.8.0-60-generic   containerd://1.7.27
wu1.bevz.net   Ready    <none>          90s   v1.31.9   10.10.10.101   <none>        Ubuntu 24.04.2 LTS   6.8.0-60-generic   containerd://1.7.27
wu2.bevz.net   Ready    <none>          90s   v1.31.9   10.10.10.29    <none>        Ubuntu 24.04.2 LTS   6.8.0-60-generic   containerd://1.7.27
```

**Системные pods:**
```bash
$ kubectl get pods --all-namespaces
NAMESPACE          NAME                                       READY   STATUS    RESTARTS   AGE
calico-system      calico-kube-controllers-8448d764cc-2p65v   1/1     Running   0          13m
calico-system      calico-node-chpz4                          1/1     Running   0          112s
calico-system      calico-node-pbwtd                          1/1     Running   0          112s
calico-system      calico-node-pd5h7                          1/1     Running   0          13m
kube-system        coredns-7c65d6cfc9-4f6tl                   1/1     Running   0          13m
kube-system        coredns-7c65d6cfc9-mvm6r                   1/1     Running   0          13m
kube-system        etcd-cu1.bevz.net                          1/1     Running   0          13m
kube-system        kube-apiserver-cu1.bevz.net                1/1     Running   0          13m
kube-system        kube-controller-manager-cu1.bevz.net       1/1     Running   0          13m
kube-system        kube-proxy-fgl5n                           1/1     Running   0          112s
kube-system        kube-proxy-l28bk                           1/1     Running   0          13m
kube-system        kube-proxy-vfnfp                           1/1     Running   0          112s
kube-system        kube-scheduler-cu1.bevz.net                1/1     Running   0          13m
```

## 🚨 **РАСПРОСТРАНЕННЫЕ ОШИБКИ И РЕШЕНИЯ**

### **Ошибка 1: "recursive template loop"**
```
FAILED! => {"msg": "The task includes an option with an undefined variable.. recursive template loop."}
```
**Решение:** Проверьте, что `pb_add_nodes.yml` использует исправленную версию с правильным сбором facts.

### **Ошибка 2: "CRI not enabled"**
```
[ERROR CRI]: container runtime is not running
```
**Решение:** Убедитесь, что в `install_kubernetes_cluster.yml` удалена строка `creates: /etc/containerd/config.toml`.

### **Ошибка 3: Worker nodes не присоединяются**
```
[ERROR] Failed to connect to API server
```
**Решение:** 
1. Проверьте, что bootstrap выполнен успешно
2. Проверьте сетевую связность между узлами
3. Убедитесь, что control plane готов

## 📚 **ДОПОЛНИТЕЛЬНЫЕ КОМАНДЫ**

```bash
# Проверка статуса VM
./cpc deploy output k8s_node_ips

# Прямое подключение к узлам
ssh abevz@<node-ip> "kubectl get nodes"

# Сброс кластера (если нужно переустановить)
./cpc reset-all-nodes

# Остановка и запуск VM
./cpc stop-vms
./cpc start-vms

# Очистка SSH кеша (после пересоздания VM)
./cpc clear-ssh-hosts
./cpc clear-ssh-maps
```

## 🎉 **ЗАКЛЮЧЕНИЕ**

Следуя этому руководству, вы получите полностью работающий Kubernetes кластер с:
- ✅ 3 узла (1 control plane + 2 workers)
- ✅ Calico CNI
- ✅ Все системные компоненты
- ✅ Готовность к установке дополнительных компонентов

**Время развертывания:** ~10-15 минут  
**Совместимость:** Ubuntu 24.04, Kubernetes v1.31.9  

---
*Документ создан на основе успешного опыта развертывания кластера 10 июня 2025*
