#!/bin/sh
# Проверка ролевой модели. Запуск: docker compose --profile check run --rm rbac-check
set -u

URL=https://os-hot1:9200
CA=/certs/root-ca.pem
DOC='{"@timestamp":"2026-01-01T00:00:00Z","message":"rbac test"}'

# code USER PASSWORD METHOD PATH [BODY]
code() {
  u=$1; p=$2; m=$3; path=$4; body=${5:-}
  if [ -n "$body" ]; then
    curl -s -o /dev/null -w '%{http_code}' --cacert "$CA" -u "$u:$p" -X "$m" "$URL$path" -H 'Content-Type: application/json' -d "$body"
  else
    curl -s -o /dev/null -w '%{http_code}' --cacert "$CA" -u "$u:$p" -X "$m" "$URL$path"
  fi
}

# row ОПИСАНИЕ ОЖИДАЕМЫЙ_КОД ФАКТИЧЕСКИЙ_КОД
row() {
  if [ "$2" = "$3" ]; then res=OK; else res=FAIL; fi
  printf '%-34s ожидается %s, получено %s  [%s]\n' "$1" "$2" "$3" "$res"
}

W=log_writer; R=log_reader; M=monitor_user

row "writer  POST /logs/_doc"        201 "$(code $W "$LOG_WRITER_PASSWORD" POST /logs/_doc "$DOC")"
row "writer  GET  /logs/_search"     403 "$(code $W "$LOG_WRITER_PASSWORD" GET /logs/_search)"
row "writer  POST /other/_doc"       403 "$(code $W "$LOG_WRITER_PASSWORD" POST /other/_doc '{"a":1}')"
sleep 6   # refresh_interval индекса = 5s
row "reader  GET  /logs/_search"     200 "$(code $R "$LOG_READER_PASSWORD" GET /logs/_search)"
row "reader  POST /logs/_doc"        403 "$(code $R "$LOG_READER_PASSWORD" POST /logs/_doc "$DOC")"
row "monitor GET  /_prometheus/metrics" 200 "$(code $M "$MONITOR_PASSWORD" GET /_prometheus/metrics)"
row "monitor GET  /_cluster/health"  200 "$(code $M "$MONITOR_PASSWORD" GET /_cluster/health)"
row "monitor GET  /logs/_search"     403 "$(code $M "$MONITOR_PASSWORD" GET /logs/_search)"
row "без пароля GET /"               401 "$(curl -s -o /dev/null -w '%{http_code}' --cacert "$CA" "$URL/")"
