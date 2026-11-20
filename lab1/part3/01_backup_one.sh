#!/bin/bash
# Пункт 1. Резервная копия одной учебной базы.
# Использование от root: ./01_backup_one.sh [база]     (по умолчанию shop)
# Результат: /var/backups/mongodb/<база>_<дата_время>.archive.gz
if [ "$(id -u)" -ne 0 ]; then echo "Запустите от root (su -)"; exit 1; fi

A="mongodb://admin:Admin_123@127.0.0.1:27017/?authSource=admin"
DB="${1:-shop}"
DIR=/var/backups/mongodb
mkdir -p "$DIR"

# Имя файла содержит дату и время; если такой файл уже есть - ждём секунду, чтобы не перезаписать
FILE="$DIR/${DB}_$(date +%Y%m%d_%H%M%S).archive.gz"
while [ -e "$FILE" ]; do
  sleep 1
  FILE="$DIR/${DB}_$(date +%Y%m%d_%H%M%S).archive.gz"
done

echo "Копирование базы $DB ..."
if mongodump --uri="$A" --db="$DB" --archive="$FILE" --gzip --quiet; then
  echo "Копия создана: $FILE ($(du -h "$FILE" | cut -f1))"
else
  rm -f "$FILE"
  echo "ОШИБКА: не удалось создать копию базы $DB"; exit 1
fi
