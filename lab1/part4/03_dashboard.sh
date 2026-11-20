#!/bin/bash
# Пункт 3. Установка дашборда в Grafana (файл dashboard.json лежит рядом со скриптом).
# Запуск от root: ./03_dashboard.sh
set -e
if [ "$(id -u)" -ne 0 ]; then echo "Запустите от root (su -)"; exit 1; fi
cd "$(dirname "$0")"

mkdir -p /etc/grafana/provisioning/dashboards /var/lib/grafana/dashboards
cat > /etc/grafana/provisioning/dashboards/lab1.yml <<'Y'
apiVersion: 1
providers:
  - name: lab1
    type: file
    options:
      path: /var/lib/grafana/dashboards
Y
cp dashboard.json /var/lib/grafana/dashboards/mongodb.json
chown -R grafana:grafana /var/lib/grafana/dashboards

systemctl restart grafana-server
sleep 8

if curl -s -u admin:admin "http://127.0.0.1:3000/api/search?query=MongoDB" | grep -q 'mongo-lab1'; then
  echo "Дашборд установлен."
else
  echo "Дашборд скопирован. Если пароль admin уже менялся, проверьте его в браузере."
fi
echo "Откройте: http://$(hostname -I | awk '{print $1}'):3000  ->  Dashboards  ->  «MongoDB - лабораторная 1»"
