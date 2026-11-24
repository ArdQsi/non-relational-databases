#!/bin/bash
# Запускается ОДНОРАЗОВЫМ КОНТЕЙНЕРОМ security-init на образе OpenSearch.
# Считает bcrypt-хэши (hash.sh из плагина security) и создаёт internal_users.yml
# для встроенных пользователей admin и kibanaserver.
set -eu

OUT=/out/internal_users.yml
HASH_SH=/usr/share/opensearch/plugins/opensearch-security/tools/hash.sh

if grep -q '^admin:' "$OUT" 2>/dev/null; then
  echo "internal_users.yml уже существует, пропускаю"
  exit 0
fi

# hash.sh печатает bcrypt-хэш
hash_pw() {
  raw=$("$HASH_SH" -p "$1" 2>&1) || { echo "hash.sh завершился с ошибкой:" >&2; echo "$raw" >&2; exit 1; }
  h=$(printf '%s\n' "$raw" | grep -E '^\$2[aby]\$' | tail -n 1 || true)
  if [ -z "$h" ]; then
    echo "В выводе hash.sh не найден bcrypt-хэш. Полный вывод:" >&2
    echo "$raw" >&2
    exit 1
  fi
  printf '%s' "$h"
}

ADMIN_HASH=$(hash_pw "$ADMIN_PASSWORD")
KIBANA_HASH=$(hash_pw "$KIBANASERVER_PASSWORD")

cat > "$OUT" <<EOF
---
# Сгенерировано контейнером security-init
_meta:
  type: "internalusers"
  config_version: 2

admin:
  hash: "${ADMIN_HASH}"
  reserved: true
  backend_roles:
    - "admin"
  description: "Администратор кластера"

kibanaserver:
  hash: "${KIBANA_HASH}"
  reserved: true
  description: "Служебный пользователь OpenSearch Dashboards"
EOF
chmod 644 "$OUT"
echo "Создан $OUT"
