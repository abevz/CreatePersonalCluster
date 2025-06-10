# CPC upgrade-addons - Справочное Руководство

## 📋 **ОБЗОР**

Команда `./cpc upgrade-addons` предназначена для установки и обновления дополнительных компонентов Kubernetes кластера.

⚠️ **ВАЖНО:** Команда теперь **ВСЕГДА** показывает интерактивное меню для выбора addon'а, если не указан параметр `--addon`!

## 🔧 **СИНТАКСИС**

```bash
./cpc upgrade-addons [--addon <name>] [--version <version>]
```

## 📋 **ПАРАМЕТРЫ**

| Параметр | Описание | По умолчанию |
|----------|----------|--------------|
| `--addon <name>` | Принудительно выбрать addon (пропускает меню) | Показывается интерактивное меню |
| `--version <version>` | Версия addon | Из переменных окружения |

## 🧩 **ДОСТУПНЫЕ ADDONS**

| Addon | Описание | Назначение |
|-------|----------|------------|
| `calico` | Calico CNI networking | Сетевая подсистема кластера |
| `metallb` | MetalLB load balancer | Load Balancer для bare-metal |
| `metrics-server` | Kubernetes Metrics Server | Метрики ресурсов |
| `coredns` | CoreDNS DNS server | DNS сервер кластера |
| `cert-manager` | Certificate manager | Управление сертификатами |
| `kubelet-serving-cert-approver` | Automatic cert approval | Автоматическое одобрение сертификатов |
| `argocd` | ArgoCD GitOps | GitOps continuous delivery |
| `ingress-nginx` | NGINX Ingress Controller | Входящий трафик |
| `all` | Все вышеперечисленные | Полная установка |

## 💡 **ПРИМЕРЫ ИСПОЛЬЗОВАНИЯ**

### **Показать справку**
```bash
./cpc upgrade-addons --help
```

### **Интерактивное меню (новое поведение по умолчанию)**
```bash
# Показывает меню выбора addon'а:
./cpc upgrade-addons
```

### **Прямая установка (пропуск меню)**
```bash
# Установить все addons напрямую
./cpc upgrade-addons --addon all

# Установить конкретный addon без меню
./cpc upgrade-addons --addon metallb
```

### **Установить конкретный addon**
```bash
# MetalLB Load Balancer
./cpc upgrade-addons --addon metallb

# Cert-Manager
./cpc upgrade-addons --addon cert-manager

# NGINX Ingress
./cpc upgrade-addons --addon ingress-nginx

# ArgoCD
./cpc upgrade-addons --addon argocd
```

### **Установить addon с конкретной версией**
```bash
./cpc upgrade-addons --addon metallb --version v0.14.8
./cpc upgrade-addons --addon cert-manager --version v1.16.2
./cpc upgrade-addons --addon ingress-nginx --version v1.12.0
```

## 🔄 **РЕКОМЕНДУЕМЫЙ WORKFLOW**

### **После создания базового кластера:**

```bash
# 1. Создать и настроить кластер
./cpc bootstrap
./cpc add-nodes --target-hosts "workers"

# 2. Получить доступ к кластеру
./cpc get-kubeconfig

# 3. Установить основные addons поэтапно
./cpc upgrade-addons --addon metallb      # Load Balancer
./cpc upgrade-addons --addon cert-manager # Certificate management
./cpc upgrade-addons --addon ingress-nginx # Ingress Controller

# 4. (Опционально) GitOps
./cpc upgrade-addons --addon argocd
```

### **Или установить все сразу:**
```bash
./cpc upgrade-addons --addon all
```

## 🚨 **ВАЖНЫЕ ЗАМЕЧАНИЯ**

### **⚠️ Новое поведение команды**
```bash
# ТЕПЕРЬ ЭТА КОМАНДА ПОКАЖЕТ ИНТЕРАКТИВНОЕ МЕНЮ!
./cpc upgrade-addons
```

Для автоматической установки всех addons используйте:
```bash
./cpc upgrade-addons --addon all
```

Для выборочной установки конкретного addon:
```bash
./cpc upgrade-addons --addon metallb
```

### **📋 Зависимости**
- Кластер должен быть инициализирован (`./cpc bootstrap`)
- Worker nodes должны быть присоединены (`./cpc add-nodes`)
- kubectl доступ должен быть настроен (`./cpc get-kubeconfig`)

### **🔍 Проверка установки**
```bash
# Проверить все pods
kubectl get pods --all-namespaces

# Конкретные компоненты:
kubectl get pods -n metallb-system    # MetalLB
kubectl get pods -n cert-manager       # Cert-Manager  
kubectl get pods -n ingress-nginx      # NGINX Ingress
kubectl get pods -n argocd            # ArgoCD
```

## 🛠️ **УСТРАНЕНИЕ НЕПОЛАДОК**

### **Addon не устанавливается**
```bash
# Проверить статус кластера
kubectl get nodes
kubectl get pods --all-namespaces

# Проверить логи playbook
# (логи показываются в процессе выполнения команды)
```

### **Неправильная версия addon**
```bash
# Переустановить с правильной версией
./cpc upgrade-addons --addon <name> --version <correct-version>
```

### **Конфликт addons**
```bash
# Проверить существующие установки
kubectl get namespaces
kubectl get pods --all-namespaces | grep <addon-name>

# При необходимости удалить и переустановить
kubectl delete namespace <addon-namespace>
./cpc upgrade-addons --addon <name>
```

## 📚 **СВЯЗАННЫЕ КОМАНДЫ**

```bash
# Создание кластера
./cpc bootstrap

# Добавление узлов
./cpc add-nodes --target-hosts "workers"

# Получение доступа
./cpc get-kubeconfig

# Проверка состояния
kubectl get nodes -o wide
kubectl get pods --all-namespaces
```

---
*Справочник создан на основе анализа CPC команды upgrade-addons*  
*Дата: 10 июня 2025*
