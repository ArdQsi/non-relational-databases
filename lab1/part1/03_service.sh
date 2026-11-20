#!/bin/bash
# Пункт 3. Запуск, остановка и перезапуск сервера.
# Использование от root: ./03_service.sh start | stop | restart
if [ "$(id -u)" -ne 0 ]; then
  echo "Запустите скрипт от root (su -)"; exit 1
fi

case "$1" in
  start)
    systemctl start mongod
    echo "Сервер запущен" ;;
  stop)
    systemctl stop mongod
    echo "Сервер остановлен" ;;
  restart)
    systemctl restart mongod
    echo "Сервер перезапущен" ;;
  *)
    echo "Использование: $0 start | stop | restart"
    exit 1 ;;
esac

sleep 2
echo "Состояние службы: $(systemctl is-active mongod)"
