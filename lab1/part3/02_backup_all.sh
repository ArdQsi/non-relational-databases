#!/bin/bash
# Пункт 2. Резервная копия всех учебных баз (shop, school, library).
# Использование от root: ./02_backup_all.sh
# Результат: каталог /var/backups/mongodb/all_<дата_время>/ с файлом на каждую базу
if [ "$(id -u)" -ne 0 ]; then echo "Запустите от root (su -)"; exit 1; fi

A="mongodb://admin:Admin_123@127.0.0.1:27017/?authSource=admin"
DIR=/var/backups/mongodb/all_$(date +%Y%m%d_%H%M%S)

# mkdir без -p завершится ошибкой, если каталог уже есть, поэтому старая копия не пострадает
while ! mkdir -p /var/backups/mongodb || ! mkdir "$DIR" 2>/dev/null; do
  sleep 1
  DIR=/var/backups/mongodb/all_$(date +%Y%m%d_%H%M%S)
done

for DB in shop school library; do
  echo "Копирование базы $DB ..."
  if ! mongodump --uri="$A" --db="$DB" --archive="$DIR/$DB.archive.gz" --gzip --quiet; then
    echo "ОШИБКА: не удалось скопировать $DB"; rm -rf "$DIR"; exit 1
  fi
done

echo "Копия всех баз создана: $DIR"
ls -lh "$DIR"
