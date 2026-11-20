#!/bin/bash
# Пункт 3. Несколько копий: новая не перезаписывает предыдущие.
# Использование от root: ./03_multiple_copies.sh
if [ "$(id -u)" -ne 0 ]; then echo "Запустите от root (su -)"; exit 1; fi

A="mongodb://admin:Admin_123@127.0.0.1:27017/?authSource=admin"
cd "$(dirname "$0")"

echo "Копия №1 базы shop"
./01_backup_one.sh shop

echo; echo "Меняем данные: добавляем клиента в shop.customers"
mongosh --quiet "$A" --eval 'db.getSiblingDB("shop").customers.insertOne({_id: 9999, name: "Новый клиент"})' > /dev/null

echo; echo "Копия №2 базы shop (уже с новым клиентом)"
./01_backup_one.sh shop

echo; echo "Копия №3: все учебные базы"
./02_backup_all.sh

echo; echo "Все сохранённые копии (старые на месте)"
ls -lhR /var/backups/mongodb

# возвращаем данные в исходное состояние
mongosh --quiet "$A" --eval 'db.getSiblingDB("shop").customers.deleteOne({_id: 9999})' > /dev/null
