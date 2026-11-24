#!/bin/sh
# Запускается ОДНОРАЗОВЫМ КОНТЕЙНЕРОМ setup (curlimages/curl) после старта кластера.
# Настройки ISM -> роли -> пользователи -> ISM-политика -> шаблон -> data stream.
set -eu

URL=https://os-hot1:9200
CA=/certs/root-ca.pem

# api METHOD PATH [аргументы curl]
api() {
  method=$1; path=$2; shift 2
  curl -sS --cacert "$CA" -u "admin:${ADMIN_PASSWORD}" \
    -X "$method" "$URL$path" -H 'Content-Type: application/json' "$@"
  echo
}

echo ">>> Ожидаю кластер из 3 узлов"
i=0
until curl -sSf --cacert "$CA" -u "admin:${ADMIN_PASSWORD}" \
    "$URL/_cluster/health?wait_for_status=yellow&wait_for_nodes=3&timeout=5s" >/dev/null 2>&1; do
  i=$((i + 1))
  if [ "$i" -gt 80 ]; then echo "Кластер не поднялся за отведённое время" >&2; exit 1; fi
  sleep 3
done
api GET "/_cluster/health?pretty"

echo ">>> Настройки ISM: проверка раз в минуту (по умолчанию 5 минут)"
api PUT /_cluster/settings -d '{"persistent":{"plugins.index_state_management.job_interval":1}}'
api PUT /_cluster/settings -d '{"persistent":{"plugins.index_state_management.coordinator.sweep_period":"1m"}}' || true

echo ">>> Роли"
api PUT /_plugins/_security/api/roles/logs_writer     --data-binary @/api/roles/logs_writer.json
api PUT /_plugins/_security/api/roles/logs_reader     --data-binary @/api/roles/logs_reader.json
api PUT /_plugins/_security/api/roles/metrics_monitor --data-binary @/api/roles/metrics_monitor.json

echo ">>> Пользователи"
api PUT /_plugins/_security/api/internalusers/log_writer   -d "{\"password\":\"${LOG_WRITER_PASSWORD}\",\"description\":\"Fluent Bit: запись в logs\"}"
api PUT /_plugins/_security/api/internalusers/log_reader   -d "{\"password\":\"${LOG_READER_PASSWORD}\",\"description\":\"Чтение logs*\"}"
api PUT /_plugins/_security/api/internalusers/monitor_user -d "{\"password\":\"${MONITOR_PASSWORD}\",\"description\":\"Prometheus\"}"

echo ">>> Маппинг пользователей на роли"
api PUT /_plugins/_security/api/rolesmapping/logs_writer     -d '{"users":["log_writer"]}'
api PUT /_plugins/_security/api/rolesmapping/logs_reader     -d '{"users":["log_reader"]}'
api PUT /_plugins/_security/api/rolesmapping/metrics_monitor -d '{"users":["monitor_user"]}'

echo ">>> ISM-политика (создаём ДО data stream, чтобы первый индекс сразу попал под управление)"
# Политику создаём только если её ещё нет: пересоздание сломало бы уже управляемые индексы
code=$(curl -s -o /dev/null -w '%{http_code}' --cacert "$CA" -u "admin:${ADMIN_PASSWORD}" "$URL/_plugins/_ism/policies/nginx-logs-policy")
if [ "$code" = "200" ]; then
  echo "Политика nginx-logs-policy уже существует, пропускаю"
else
  api PUT /_plugins/_ism/policies/nginx-logs-policy --data-binary @/api/ism-policy.json
fi

echo ">>> Шаблон индекса и data stream logs"
api PUT /_index_template/nginx-logs --data-binary @/api/index-template.json
api PUT /_data_stream/logs

echo ">>> Проверка"
api GET "/_cat/nodeattrs?v&h=node,attr,value&s=node"
api GET "/_data_stream/logs?pretty"
echo "Настройка завершена"
