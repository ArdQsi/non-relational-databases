#!/bin/bash
# Пункт 1. Подготовка хоста и установка MongoDB 8.0 на Debian 12.
# Запуск от root: ./01_install.sh
set -e

if [ "$(id -u)" -ne 0 ]; then
  echo "Запустите скрипт от root (su -)"; exit 1
fi

echo "Обновление списка пакетов и установка зависимостей"
apt-get update
apt-get install -y gnupg curl ca-certificates chrony

echo "Подключение официального репозитория MongoDB 8.0"
curl -fsSL https://www.mongodb.org/static/pgp/server-8.0.asc | gpg --dearmor --yes -o /usr/share/keyrings/mongodb-server-8.0.gpg
echo "deb [signed-by=/usr/share/keyrings/mongodb-server-8.0.gpg] https://repo.mongodb.org/apt/debian bookworm/mongodb-org/8.0 main" > /etc/apt/sources.list.d/mongodb-org-8.0.list
apt-get update

echo "Установка MongoDB"
apt-get install -y mongodb-org

echo "Первый запуск"
systemctl daemon-reload
systemctl start mongod
sleep 3

echo "Результат"
mongod --version | head -1
mongosh --version
systemctl is-active mongod
echo "MongoDB установлена"
