#!/bin/bash
# Пункт 2. Автозапуск MongoDB после перезагрузки виртуальной машины.
# Запуск от root: ./02_autostart.sh
set -e

if [ "$(id -u)" -ne 0 ]; then
  echo "Запустите скрипт от root (su -)"; exit 1
fi

systemctl enable mongod

echo "Автозапуск: $(systemctl is-enabled mongod)"
echo "Для проверки выполните: reboot"
