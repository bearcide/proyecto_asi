#!/usr/bin/env bash
set -euo pipefail

if [ "${EUID:-$(id -u)}" -ne 0 ]; then
  echo "Ejecuta este script como root en la VM cliente: sudo bash $0 [IP_SERVIDOR]" >&2
  exit 1
fi

SERVER_IP="${1:-${SERVER_IP:-192.168.40.130}}"
DOMAIN="${DOMAIN:-empresa.local}"
CA_DEST="/usr/local/share/ca-certificates/empresa-ca.crt"

# 1. Resolucion local en /etc/hosts (idempotente)
if grep -qE "[[:space:]]${DOMAIN}([[:space:]]|$)" /etc/hosts; then
  sed -i -E "s|^[^#]*[[:space:]]${DOMAIN}([[:space:]].*)?$|${SERVER_IP} ${DOMAIN} www.${DOMAIN}|" /etc/hosts
else
  printf '\n%s %s www.%s\n' "$SERVER_IP" "$DOMAIN" "$DOMAIN" >> /etc/hosts
fi

# 2. Descargar e instalar certificado raiz de la CA interna
curl -fsSLk "https://${DOMAIN}/empresa-ca.crt" -o "$CA_DEST"
chmod 644 "$CA_DEST"
update-ca-certificates --fresh >/dev/null

# 3. Politica de Firefox para confiar en la CA interna
mkdir -p /etc/firefox/policies
cat > /etc/firefox/policies/policies.json <<EOF
{
  "policies": {
    "Certificates": {
      "ImportEnterpriseRoots": true,
      "Install": [
        "${CA_DEST}"
      ]
    }
  }
}
EOF
chmod 644 /etc/firefox/policies/policies.json

echo "=== Verificacion desde el cliente ==="
getent hosts "$DOMAIN"
curl -sI "http://${DOMAIN}/" | head -n 5
curl -sI "https://${DOMAIN}/" | head -n 6
echo "Reinicia Firefox si estaba abierto para aplicar policies.json."
