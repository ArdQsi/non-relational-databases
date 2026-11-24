#!/bin/sh
# Запускается ОДНОРАЗОВЫМ КОНТЕЙНЕРОМ certs-init (alpine/openssl).
# Создаёт собственный CA и сертификаты узлов, admin и Dashboards в каталоге /certs (= ./certs на хосте).
set -eu

cd /certs
DAYS=365
SUBJ="/C=RU/O=Lab2/OU=Lab"

if [ -s root-ca.pem ] && [ -s dashboards-key.pem ]; then
  echo "Сертификаты уже существуют, пропускаю (удалите каталог certs, чтобы перегенерировать)"
  exit 0
fi

echo ">>> Root CA"
openssl genrsa -out root-ca-key.pem 4096
openssl req -new -x509 -sha256 -days "$DAYS" -key root-ca-key.pem \
  -subj "$SUBJ/CN=Lab2 Root CA" -out root-ca.pem

# gen_cert <имя> <строки alt_names> [CN]
gen_cert() {
  name=$1; alt=$2; cn=${3:-$1}
  echo ">>> Сертификат: $name (CN=$cn)"
  openssl genrsa -out "$name-key-tmp.pem" 2048
  # OpenSearch требует ключ в формате PKCS#8 без пароля
  openssl pkcs8 -topk8 -nocrypt -in "$name-key-tmp.pem" -out "$name-key.pem"
  rm -f "$name-key-tmp.pem"
  openssl req -new -key "$name-key.pem" -subj "$SUBJ/CN=$cn" -out "$name.csr"
  cat > "$name.ext" <<EOF
basicConstraints = CA:FALSE
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth, clientAuth
subjectAltName = @alt_names
[alt_names]
$alt
EOF
  openssl x509 -req -sha256 -days "$DAYS" -in "$name.csr" \
    -CA root-ca.pem -CAkey root-ca-key.pem -CAcreateserial \
    -extfile "$name.ext" -out "$name.pem"
  rm -f "$name.csr" "$name.ext"
}

# SAN: имя сервиса compose (проверка hostname), localhost, registered ID 1.2.3.4.5.5 (признак узла кластера)
for n in os-cm1 os-hot1 os-warm1; do
  gen_cert "$n" "DNS.1 = $n
DNS.2 = localhost
IP.1 = 127.0.0.1
RID.1 = 1.2.3.4.5.5"
done

gen_cert admin "DNS.1 = admin" admin

gen_cert dashboards "DNS.1 = dashboards
DNS.2 = localhost
IP.1 = 127.0.0.1"

rm -f root-ca.srl
# Ключи должны читаться пользователем opensearch (uid 1000) внутри других контейнеров
chmod 644 ./*.pem
echo "Готово"
