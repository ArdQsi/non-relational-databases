#!/bin/sh
# Генератор запросов к nginx (запускается в контейнере).
#   steady        - ровный поток (~10 запросов/с) до остановки контейнера
#   burst [N]     - N запросов с длинными URI, чтобы быстро набрать ~1 МБ логов (rollover по размеру)
set -eu

URL=${NGINX_URL:-http://nginx}
MODE=${1:-steady}

case "$MODE" in
  steady)
    echo "Поток запросов на $URL"
    i=0
    while true; do
      i=$((i + 1))
      curl -s -o /dev/null -A "lab2-traffic/1.0" "$URL/?r=$i"
      curl -s -o /dev/null "$URL/not-found-$i"   # даёт 404
      sleep 0.1
    done
    ;;
  burst)
    N=${2:-5000}
    PAD=$(head -c 300 /dev/zero | tr '\0' 'x')
    echo "Отправляю $N запросов"
    i=0
    while [ "$i" -lt "$N" ]; do
      i=$((i + 1))
      curl -s -o /dev/null "$URL/?i=$i&pad=$PAD"
    done
    echo "Готово"
    ;;
  *)
    echo "Использование: traffic.sh [steady|burst N]" >&2; exit 1 ;;
esac
