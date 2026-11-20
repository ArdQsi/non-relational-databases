#!/bin/bash
# Пункт 1. Экспортер метрик: percona/mongodb_exporter, подключённый к развёрнутой MongoDB.
# Запуск от root: ./01_install_exporter.sh   (скрипт можно запускать повторно)
if [ "$(id -u)" -ne 0 ]; then echo "Запустите от root (su -)"; exit 1; fi

A="mongodb://admin:Admin_123@127.0.0.1:27017/?authSource=admin"

echo "1. Пользователь mongo_exporter с правами только на мониторинг"
mongosh --quiet "$A" --eval '
  const a = db.getSiblingDB("admin");
  const roles = [{role:"clusterMonitor", db:"admin"}, {role:"read", db:"local"}];
  if (a.getUser("mongo_exporter")) a.updateUser("mongo_exporter", {pwd:"Exporter_123", roles});
  else a.createUser({user:"mongo_exporter", pwd:"Exporter_123", roles});
  print("пользователь mongo_exporter готов")' || { echo "ОШИБКА: не удалось войти в MongoDB администратором"; exit 1; }

echo "2. Проверка входа под mongo_exporter"
mongosh --quiet "mongodb://mongo_exporter:Exporter_123@127.0.0.1:27017/admin?authSource=admin" \
  --eval 'db.adminCommand({serverStatus:1}).ok' | grep -q '^1$' \
  && echo "вход и serverStatus: OK" \
  || { echo "ОШИБКА: mongo_exporter не может читать serverStatus"; exit 1; }

echo "3. Загрузка экспортера 0.47.2"
apt-get install -y curl >/dev/null
ARCH=$(dpkg --print-architecture)
TMP=$(mktemp -d)
if ! curl -fsSL "https://github.com/percona/mongodb_exporter/releases/download/v0.47.2/mongodb_exporter-0.47.2.linux-$ARCH.tar.gz" | tar -xz -C "$TMP"; then
  echo "ОШИБКА: не удалось скачать экспортер (проверьте интернет и версию на github.com/percona/mongodb_exporter/releases)"; exit 1
fi
systemctl stop mongodb_exporter 2>/dev/null
install -m 0755 "$(find "$TMP" -name mongodb_exporter -type f | head -1)" /usr/local/bin/mongodb_exporter
rm -rf "$TMP"
/usr/local/bin/mongodb_exporter --version 2>&1 | head -3

echo "4. Служба systemd"
id mongodb_exporter >/dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin mongodb_exporter
echo 'MONGODB_URI=mongodb://mongo_exporter:Exporter_123@127.0.0.1:27017/admin?authSource=admin' > /etc/default/mongodb_exporter
chown root:mongodb_exporter /etc/default/mongodb_exporter
chmod 640 /etc/default/mongodb_exporter

# Сборщики: diagnosticdata (serverStatus: операции, подключения, память, кэш), dbstats (размеры баз)
cat > /etc/systemd/system/mongodb_exporter.service <<UNIT
[Unit]
Description=MongoDB Exporter
After=mongod.service

[Service]
User=mongodb_exporter
EnvironmentFile=/etc/default/mongodb_exporter
ExecStart=/usr/local/bin/mongodb_exporter --web.listen-address=127.0.0.1:9216 --collector.diagnosticdata --collector.dbstats
Restart=on-failure

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable mongodb_exporter
systemctl restart mongodb_exporter

echo "5. Проверка (ожидание до 30 секунд)"
for i in $(seq 1 15); do
  CODE=$(curl -s -o /tmp/metrics.txt -w '%{http_code}' --max-time 10 http://127.0.0.1:9216/metrics)
  if [ "$CODE" = "200" ] && grep -q '^mongodb_' /tmp/metrics.txt; then
    echo "HTTP 200, метрик mongodb_*: $(grep -c '^mongodb_' /tmp/metrics.txt)"
    grep -E '^mongodb_up ' /tmp/metrics.txt
    echo "Экспортер работает: http://127.0.0.1:9216/metrics (mongodb_up 1 = MongoDB доступна)"
    exit 0
  fi
  sleep 2
done

echo "ОШИБКА: экспортер не отдаёт метрики"
exit 1
