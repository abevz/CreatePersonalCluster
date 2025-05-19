# Автоматизация создания VM в Proxmox с помощью Terraform и SOPS

## Структура
- Все Terraform-файлы находятся в директории `terraform/`
- Чувствительные данные (пароли, токены) хранятся в зашифрованном файле `secrets.sops.yaml` в корне проекта

## Использование SOPS для хранения секретов

### Установка SOPS

Для Linux:
```sh
sudo apt install -y sops
```
или
```sh
brew install sops
```

### Генерация ключа для шифрования (пример для age):
```sh
age-keygen -o ~/.config/sops/age/keys.txt
```

### Пример структуры файла secrets.sops.yaml
```yaml
pm_api_url: https://proxmox.example.com:8006/api2/json
pm_user: root@pam
pm_password: supersecret
```

### Шифрование файла
```sh
sops -e -i secrets.sops.yaml
```

### Расшифровка файла (для просмотра/редактирования)
```sh
sops secrets.sops.yaml
```

## Использование Terraform

1. Выберите workspace:
   ```sh
   terraform -chdir=terraform workspace select debian # или rocky, ubuntu
   ```
   Если workspace еще не существует, создайте его:
   ```sh
   terraform -chdir=terraform workspace new debian # или rocky, ubuntu
   ```
2. Примените конфигурацию:
   ```sh
   terraform -chdir=terraform apply -var-file="terraform.debian.tfvars"
   ```

## Важно
- Никогда не коммитьте расшифрованный secrets.sops.yaml в git!
- Для новых участников проекта — передайте ключ для расшифровки (например, age или gpg).

## Полезные ссылки
- Документация SOPS: https://github.com/mozilla/sops
- Документация terraform-provider-sops: https://github.com/carlpett/terraform-provider-sops
