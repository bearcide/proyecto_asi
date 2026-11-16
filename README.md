# Servidor Web Seguro HTTPS (`empresa.local`)

Proyecto de **Administración de Servicios de Internet (ASI)** para desplegar un servidor web Apache con HTTPS mediante CA interna, redirección permanente de HTTP a HTTPS, autenticación básica en una zona privada y endurecimiento con UFW y cabeceras de seguridad.

## Estructura del repositorio

```text
proyecto_asi/
├── README.md
├── .gitignore
├── deploy.sh                        # Orquestador principal de despliegue en el servidor
├── apache/
│   ├── empresa.local.conf           # VirtualHosts :80 (301) y :443 (TLS + Auth Basic)
│   └── z-empresa-hardening.conf     # ServerName global, ServerTokens Prod y ServerSignature Off
├── html/
│   ├── index.html                   # Portal corporativo público
│   └── privado/
│       └── index.html               # Sección privada autenticada
└── scripts/
    ├── generar_cert.sh              # CA raíz interna + certificado firmado para empresa.local
    ├── setup_firewall.sh            # Reglas UFW (22/tcp, 80/tcp, 443/tcp)
    └── setup_client.sh              # Alta rápida de nuevas VMs cliente Linux
```

## Topología de red

| Host | Rol | Sistema | IP |
| --- | --- | --- | --- |
| `host8` | Servidor web Apache | Ubuntu Server 26.04.1 | `192.168.40.130` |
| `mint` | Cliente 1 | Linux Mint 22.3 | `192.168.40.131` |
| Adicionales | Clientes 2 y 3 | Red `192.168.40.0/24` | Por asignar |

## Despliegue en el servidor (`host8`)

Los scripts son idempotentes y no versionan llaves privadas, certificados ni archivos `.htpasswd`.

1. Clonar o actualizar el repositorio y entrar al directorio:
   ```bash
   cd ~/proyecto_asi
   ```
2. Ejecutar el despliegue (indicando usuario y contraseña para `/privado/` en la primera instalación):
   ```bash
   sudo BASIC_AUTH_USER=empleado BASIC_AUTH_PASS='<contraseña>' bash deploy.sh
   ```
   Si `/etc/apache2/empresa.htpasswd` ya existe y no se pasan variables de entorno, `deploy.sh` conserva las credenciales actuales.
3. Para forzar la regeneración del certificado de servidor (manteniendo la misma CA raíz):
   ```bash
   sudo bash scripts/generar_cert.sh --force
   sudo systemctl reload apache2
   ```

## Alta de máquinas cliente Linux

En cada nueva VM cliente en la red `192.168.40.0/24`:

```bash
sudo bash scripts/setup_client.sh 192.168.40.130
```

O sin clonar el repositorio completo en el cliente:

```bash
echo "192.168.40.130 empresa.local www.empresa.local" | sudo tee -a /etc/hosts
curl -fsSLk https://empresa.local/empresa-ca.crt | sudo tee /usr/local/share/ca-certificates/empresa-ca.crt >/dev/null
sudo chmod 644 /usr/local/share/ca-certificates/empresa-ca.crt
sudo update-ca-certificates --fresh
```

Después, en Firefox, configurar `/etc/firefox/policies/policies.json` (como hace `scripts/setup_client.sh`) y reiniciar el navegador para que confíe en `Empresa Local Root CA` sin mostrar advertencias.

## Comprobaciones de verificación

Desde cualquier cliente configurado:

```bash
# Redirección HTTP -> HTTPS
curl -sI http://empresa.local/

# HTTPS verificado contra la CA interna (sin -k)
curl -sI https://empresa.local/

# Acceso a zona privada: 401 sin credenciales, 200 con credenciales válidas
curl -s -o /dev/null -w "%{http_code}\n" https://empresa.local/privado/
curl -s -o /dev/null -w "%{http_code}\n" -u empleado:'<contraseña>' https://empresa.local/privado/
```
