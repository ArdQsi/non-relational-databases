#!/bin/bash
# Установка Prometheus (хранит метрики) и Grafana (рисует графики).
# Запуск от root: ./02_install_prometheus_grafana.sh   (можно запускать повторно)
#
# Если репозиторий Grafana недоступен (ошибка 403 - Grafana блокирует часть IP-адресов),
# положите рядом со скриптом файл grafana_*_amd64.deb, скачанный на другом компьютере и запустите скрипт снова.
if [ "$(id -u)" -ne 0 ]; then echo "Запустите от root (su -)"; exit 1; fi
cd "$(dirname "$0")"

echo "Prometheus"
apt-get update
apt-get install -y prometheus curl gnupg || { echo "ОШИБКА: не удалось установить prometheus"; exit 1; }
cat > /etc/prometheus/prometheus.yml <<'CONF'
global:
  scrape_interval: 5s

scrape_configs:
  - job_name: mongodb
    static_configs:
      - targets: ["127.0.0.1:9216"]
CONF
systemctl enable prometheus
systemctl restart prometheus

echo "Ожидание, пока Prometheus начнёт опрашивать экспортер (до 30 секунд)..."
UP=0
for i in $(seq 1 15); do
  if curl -s http://127.0.0.1:9090/api/v1/targets | grep -q '"health":"up"'; then UP=1; break; fi
  sleep 2
done
if [ $UP -eq 1 ]; then
  echo "Prometheus опрашивает экспортер: OK"
else
  echo "ВНИМАНИЕ: цель mongodb не в состоянии up."
  if curl -s http://127.0.0.1:9216/metrics | grep -q '^mongodb_up'; then
    echo "Экспортер отвечает; подождите минуту и проверьте http://127.0.0.1:9090/targets"
  else
    echo "Экспортер на порту 9216 НЕ отвечает. Сначала добейтесь успеха ./01_install_exporter.sh"
  fi
fi

echo "Grafana"
if dpkg -s grafana >/dev/null 2>&1; then
  echo "Grafana уже установлена"
else
  INSTALLED=0
  echo "Пробуем официальный репозиторий..."
  if curl -fsSL -o /tmp/grafana.key https://apt.grafana.com/gpg.key && gpg --dearmor --yes -o /usr/share/keyrings/grafana.gpg /tmp/grafana.key; then
    echo "deb [signed-by=/usr/share/keyrings/grafana.gpg] https://apt.grafana.com stable main" > /etc/apt/sources.list.d/grafana.list
    if apt-get update && apt-get install -y grafana; then INSTALLED=1; fi
  fi
  if [ $INSTALLED -eq 0 ]; then
    rm -f /etc/apt/sources.list.d/grafana.list /usr/share/keyrings/grafana.gpg
    apt-get update >/dev/null 2>&1
    DEB=$(ls -1 ./grafana*.deb 2>/dev/null | sort | tail -1)
    if [ -n "$DEB" ]; then
      echo "Репозиторий недоступен, устанавливаем из локального файла $DEB"
      apt-get install -y "$DEB" && INSTALLED=1
    fi
  fi
  if [ $INSTALLED -eq 0 ]; then
    echo
    echo "ОШИБКА: Grafana не установлена. Репозиторий apt.grafana.com отдаёт 403"
  fi
fi

mkdir -p /etc/grafana/provisioning/datasources
cat > /etc/grafana/provisioning/datasources/prometheus.yml <<'Y'
apiVersion: 1
datasources:
  - name: Prometheus
    uid: prom
    type: prometheus
    access: proxy
    url: http://127.0.0.1:9090
    isDefault: true
Y
systemctl daemon-reload
systemctl enable grafana-server
systemctl restart grafana-server

echo "Grafana: http://$(hostname -I | awk '{print $1}'):3000  (логин admin, пароль admin)"
