#!/usr/bin/env bash
set -euo pipefail

if [ "${EUID:-$(id -u)}" -ne 0 ]; then
  echo "Este script debe ejecutarse como root (usa sudo)." >&2
  exit 1
fi

DOMAIN="${DOMAIN:-empresa.local}"
CA_DIR="/etc/ssl/empresa-ca"
WEB_ROOT="${WEB_ROOT:-/var/www/empresa.local/html}"
FORCE_CERT="${1:-}"

install -d -o root -g root -m 700 "$CA_DIR"
install -d -o root -g root -m 755 /etc/ssl/certs /usr/local/share/ca-certificates
install -d -o root -g ssl-cert -m 710 /etc/ssl/private

# 1. Crear CA raiz interna si aun no existe (idempotente)
if [ ! -f "$CA_DIR/ca.key" ] || [ ! -f "$CA_DIR/ca.crt" ]; then
  echo "[cert] Generando CA raiz interna ($CA_DIR)..."
  openssl genrsa -out "$CA_DIR/ca.key" 4096
  chmod 600 "$CA_DIR/ca.key"

  cat > "$CA_DIR/ca.cnf" <<'EOF'
[req]
distinguished_name = dn
x509_extensions = v3_ca
prompt = no

[dn]
C = MX
O = Empresa
OU = Infraestructura TI
CN = Empresa Local Root CA

[v3_ca]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical, CA:TRUE
keyUsage = critical, digitalSignature, cRLSign, keyCertSign
EOF

  openssl req -x509 -new -nodes -key "$CA_DIR/ca.key" -sha256 -days 3650 \
    -out "$CA_DIR/ca.crt" -config "$CA_DIR/ca.cnf"
  chmod 644 "$CA_DIR/ca.crt"
else
  echo "[cert] CA raiz existente conservada: $CA_DIR/ca.crt"
fi

# Registrar la CA en el almacen del sistema
cp "$CA_DIR/ca.crt" /usr/local/share/ca-certificates/empresa-ca.crt
chmod 644 /usr/local/share/ca-certificates/empresa-ca.crt
update-ca-certificates >/dev/null

# 2. Crear o renovar certificado de servidor firmado por la CA
CERT_PATH="/etc/ssl/certs/${DOMAIN}.crt"
KEY_PATH="/etc/ssl/private/${DOMAIN}.key"

if [ ! -f "$CERT_PATH" ] || [ ! -f "$KEY_PATH" ] || [ "$FORCE_CERT" = "--force" ]; then
  echo "[cert] Generando certificado de servidor para $DOMAIN..."
  openssl genrsa -out "$KEY_PATH" 2048
  chown root:ssl-cert "$KEY_PATH"
  chmod 640 "$KEY_PATH"

  cat > "$CA_DIR/server-csr.cnf" <<EOF
[req]
distinguished_name = dn
prompt = no

[dn]
C = MX
O = Empresa
OU = Servicios Web
CN = ${DOMAIN}
EOF

  cat > "$CA_DIR/server-ext.cnf" <<EOF
basicConstraints = critical, CA:FALSE
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = ${DOMAIN}
DNS.2 = www.${DOMAIN}
EOF

  openssl req -new -key "$KEY_PATH" \
    -out "$CA_DIR/${DOMAIN}.csr" -config "$CA_DIR/server-csr.cnf"

  openssl x509 -req -in "$CA_DIR/${DOMAIN}.csr" \
    -CA "$CA_DIR/ca.crt" -CAkey "$CA_DIR/ca.key" -CAcreateserial \
    -out "$CERT_PATH" -days 825 -sha256 \
    -extfile "$CA_DIR/server-ext.cnf"

  chmod 644 "$CERT_PATH"
else
  echo "[cert] Certificado de servidor existente conservado: $CERT_PATH"
fi

# Publicar el certificado publico de la CA para nuevos clientes
if [ -d "$WEB_ROOT" ]; then
  cp "$CA_DIR/ca.crt" "$WEB_ROOT/empresa-ca.crt"
  chown www-data:www-data "$WEB_ROOT/empresa-ca.crt"
  chmod 644 "$WEB_ROOT/empresa-ca.crt"
fi

openssl verify "$CERT_PATH"
