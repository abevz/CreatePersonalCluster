#!/bin/bash

# Скрипт для исправления SSH доступа к VM
# Выполняем команды для всех трех VM
for VM_ID in 300 301 302; do
  echo "Настраиваем SSH для VM $VM_ID..."
  
  # Создаем директорию .ssh с правильными разрешениями
  sudo qm guest exec $VM_ID -- mkdir -p /home/abevz/.ssh
  sudo qm guest exec $VM_ID -- chmod 700 /home/abevz/.ssh
  
  # Создаем authorized_keys файл с нашим ключом
  sudo qm guest exec $VM_ID -- bash -c 'cat > /home/abevz/.ssh/authorized_keys << "SSHKEY"
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDZI60F9XVRiJ83dmcHbjXpTL3tNzCoUVknusRucbpKkkD1mWBkvJEOQaebFcgm2h+32dOaV6qod6dngXAHMBuJ9ZeKaQvcJiNZgbc1XImJIJ77ztx2tYTfwD96g26k0jvLN4NaDi6QIMH9W796b173WlJowRej16iNgqWr5l7w/F/wShitbauUW7Z6Hl3e0kaKAsignFBSauoyULW4a2GW4+I6WHRPrdMker144I4IIgXiI5e+O+Hi5zqXXji/p1JSFsWiLGxZ1FE8F1QCyKc/Gk/8zoYpkeXLHQJXS53qIs9T8dpGMqvzTzvkavT6kuq7/nPbdVg1/h/inj++z+aNxcYXDsgeVa15cZsVQJbpJlpwyJzNvkrFyW7LPii5y2IZlC6PAgvZDOpI2PU7et5/F5wb9kQ6Ifq9pGPVHuzXODuWLdPgs8e0uV05HidaAaphsIJLH0CtJFap4QK7iRcv8fxfy2bZP9/n37H/EuhrMWp5H3o1MjMiJMC0kJ2XUQnR57KjizPGTcaza1sCRcbpUTuTix+ddyqlmKwLtf8EL/LbEoNDn/osMUf+h8Kf+vLnlNQk4AQKlW1EJiZprhZmmezI2yKpdfQ+riHyCLaImktDNe7ZBAdxDWlLCZBbMFVk4QZHsE0CroZVbjccOUTCZuvwHxX0H2n9XJHDU/vqGw== aleksey.bevz@gmail.com
SSHKEY'

  # Устанавливаем правильные разрешения для authorized_keys
  sudo qm guest exec $VM_ID -- chmod 600 /home/abevz/.ssh/authorized_keys
  
  # Устанавливаем правильного владельца
  sudo qm guest exec $VM_ID -- chown -R abevz:abevz /home/abevz/.ssh
  
  echo "Настройка SSH для VM $VM_ID завершена"
done

echo "Все готово! Попробуйте подключиться по SSH: ssh abevz@10.10.10.69"
