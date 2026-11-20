#!/bin/bash
# Пункт 4. Восстановление данных после удаления коллекции shop.orders.
# Использование от root: ./04_restore.sh
if [ "$(id -u)" -ne 0 ]; then echo "Запустите от root (su -)"; exit 1; fi

A="mongodb://admin:Admin_123@127.0.0.1:27017/?authSource=admin"
cd "$(dirname "$0")"
count() { mongosh --quiet "$A" --eval 'db.getSiblingDB("shop").orders.countDocuments()'; }

echo "1. Свежая копия базы shop"
./01_backup_one.sh shop || exit 1
BEFORE=$(count)
echo "Документов в shop.orders: $BEFORE"

echo; echo "2. Удаляем коллекцию shop.orders"
mongosh --quiet "$A" --eval 'db.getSiblingDB("shop").orders.drop()' > /dev/null
echo "Документов в shop.orders: $(count)"

echo; echo "3. Восстановление из последней копии"
FILE=$(ls -1 /var/backups/mongodb/shop_*.archive.gz | sort | tail -1)
echo "Файл: $FILE"
mongorestore --uri="$A" --archive="$FILE" --gzip --nsInclude="shop.orders" --quiet

AFTER=$(count)
echo; echo "4. Результат"
echo "Было: $BEFORE, стало: $AFTER"
if [ "$BEFORE" = "$AFTER" ]; then
  echo "РЕЗУЛЬТАТ: данные восстановлены"
else
  echo "РЕЗУЛЬТАТ: ОШИБКА, количество документов не совпало"; exit 1
fi
