#!/bin/bash
# Пункт 4. Проверка доступности сервера и сообщение о результате.
# Запуск: ./04_check.sh   (код возврата 0 - доступен, 1 - недоступен)
ok=1

echo "Проверка MongoDB на 127.0.0.1:27017"

if systemctl is-active --quiet mongod; then
  echo "  [OK]   служба mongod запущена"
else
  echo "  [FAIL] служба mongod не запущена"; ok=0
fi

if systemctl is-enabled --quiet mongod; then
  echo "  [OK]   автозапуск включён"
else
  echo "  [WARN] автозапуск выключен"
fi

if timeout 3 bash -c "</dev/tcp/127.0.0.1/27017" 2>/dev/null; then
  echo "  [OK]   порт 27017 открыт"
else
  echo "  [FAIL] порт 27017 закрыт"; ok=0
fi

if [ "$(mongosh --quiet --eval 'db.adminCommand({ping:1}).ok' 2>/dev/null)" = "1" ]; then
  echo "  [OK]   сервер отвечает на ping"
else
  echo "  [FAIL] сервер не отвечает на ping"; ok=0
fi

if [ $ok -eq 1 ]; then
  echo "РЕЗУЛЬТАТ: MongoDB ДОСТУПНА"; exit 0
else
  echo "РЕЗУЛЬТАТ: MongoDB НЕДОСТУПНА"; exit 1
fi
