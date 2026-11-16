#!/usr/bin/env bash
set -euo pipefail

if [ "${EUID:-$(id -u)}" -ne 0 ]; then
  echo "Este script debe ejecutarse como root (usa sudo bash deploy.sh)." >&2
  exit 1
fi

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOMAIN="${DOMAIN:-empresa.local}"
SERVER_IP="${SERVER_IP:-192.168.40.130}"
WEB_ROOT="/var/www/${DOMAIN}/html"
HTPASSWD_FILE="/etc/apache2/empresa.htpasswd"

export DEBIAN_FRONTEND=noninteractive

# 1. Paquetes necesarios
MISSING_PKGS=()
for pkg in apache2 apache2-utils openssl ufw ca-certificates; do
  if ! dpkg -s "$pkg" >/dev/null 2>&1; then
    MISSING_PKGS+=("$pkg")
  fi
done

if [ "${#MISSING_PKGS[@]}" -gt 0 ]; then
  echo "[deploy] Instalando paquetes: ${MISSING_PKGS[*]}..."
  apt-get update
  apt-get install -y "${MISSING_PKGS[@]}"
fi

# 2. Modulos de Apache requeridos
a2enmod ssl headers auth_basic authn_file authz_user >/dev/null

# 3. Entrada local en /etc/hosts si no existe
if ! grep -qE "[[:space:]]${DOMAIN}([[:space:]]|$)" /etc/hosts; then
  printf '\n%s %s www.%s\n' "$SERVER_IP" "$DOMAIN" "$DOMAIN" >> /etc/hosts
fi

# 4. Contenido web
install -d -o www-data -g www-data -m 755 "$WEB_ROOT" "${WEB_ROOT}/privado"
install -o www-data -g www-data -m 644 "${REPO_DIR}/html/index.html" "${WEB_ROOT}/index.html"
install -o www-data -g www-data -m 644 "${REPO_DIR}/html/privado/index.html" "${WEB_ROOT}/privado/index.html"

# 5. Certificados (CA interna + certificado del servidor)
bash "${REPO_DIR}/scripts/generar_cert.sh"

# 6. Credenciales para /privado/ (sin hardcodear secretos en el repositorio)
if [ -n "${BASIC_AUTH_USER:-}" ] && [ -n "${BASIC_AUTH_PASS:-}" ]; then
  if [ -f "$HTPASSWD_FILE" ]; then
    htpasswd -b "$HTPASSWD_FILE" "$BASIC_AUTH_USER" "$BASIC_AUTH_PASS" >/dev/null
  else
    htpasswd -bc "$HTPASSWD_FILE" "$BASIC_AUTH_USER" "$BASIC_AUTH_PASS" >/dev/null
  fi
elif [ ! -f "$HTPASSWD_FILE" ]; then
  if [ -t 0 ]; then
    read -rp "[deploy] Usuario para /privado/: " BASIC_AUTH_USER
    read -rsp "[deploy] Contrasena para ${BASIC_AUTH_USER}: " BASIC_AUTH_PASS
    echo
    htpasswd -bc "$HTPASSWD_FILE" "$BASIC_AUTH_USER" "$BASIC_AUTH_PASS" >/dev/null
  else
    echo "No existe $HTPASSWD_FILE. Define BASIC_AUTH_USER y BASIC_AUTH_PASS o ejecuta de forma interactiva." >&2
    exit 1
  fi
else
  echo "[deploy] Conservando archivo de credenciales existente: $HTPASSWD_FILE"
fi
chown root:www-data "$HTPASSWD_FILE"
chmod 640 "$HTPASSWD_FILE"

# 7. Configuracion de Apache (VirtualHost + endurecimiento)
install -o root -g root -m 644 "${REPO_DIR}/apache/empresa.local.conf" /etc/apache2/sites-available/empresa.local.conf
install -o root -g root -m 644 "${REPO_DIR}/apache/z-empresa-hardening.conf" /etc/apache2/conf-available/z-empresa-hardening.conf

a2enconf z-empresa-hardening >/dev/null
a2ensite empresa.local.conf >/dev/null
a2dissite 000-default.conf >/dev/null || true

apache2ctl configtest
if systemctl is-active --quiet apache2; then
  systemctl reload apache2
else
  systemctl enable --now apache2
fi

# 8. Cortafuegos UFW
bash "${REPO_DIR}/scripts/setup_firewall.sh"

echo "[deploy] Despliegue completado correctamente para https://${DOMAIN}/"
