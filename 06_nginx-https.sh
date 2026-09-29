#!/usr/bin/env bash
# =============================================================================
# 06_nginx-https.sh — Rôle « serveur web nginx interne en HTTPS » (srv-debian)
#   - installe nginx
#   - crée une autorité de certification (AC) de laboratoire et un certificat
#     serveur signé par elle (SAN : nom court, nom lab.local, adresse IP)
#   - publie un site intranet en HTTPS, HTTP redirigé vers HTTPS
# Déploie le rôle dans une configuration standard : le durcissement (en-têtes,
# limitation de débit, pare-feu local…) relève de la remédiation après audit.
# À lancer en root sur srv-debian.
# =============================================================================
set -euo pipefail

FQDN="srv-debian.lab.local"; SHORT="srv-debian"; IP="192.168.10.20"
CA_DIR="/root/lab-ca"; CERT_DIR="/etc/ssl/lab"; KEY="/etc/ssl/private/${SHORT}.key"
WEB_ROOT="/var/www/intranet"

log() { echo -e "\e[1;32m[+]\e[0m $*"; }
die() { echo -e "\e[1;31m[x]\e[0m $*" >&2; exit 1; }
[[ $EUID -eq 0 ]] || die "Lancer en root (su - puis ./$0)"

log "Installation de nginx"
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get install -y -q nginx openssl curl

# --- AC de laboratoire (créée une seule fois) -------------------------------
mkdir -p "$CA_DIR" "$CERT_DIR"; chmod 700 "$CA_DIR"
if [[ ! -f "$CA_DIR/ca.crt" ]]; then
  log "Création de l'AC de laboratoire"
  openssl req -x509 -new -newkey rsa:3072 -noenc -sha256 -days 1825 \
    -subj "/CN=infra1 Lab CA" -keyout "$CA_DIR/ca.key" -out "$CA_DIR/ca.crt" 2>/dev/null
  chmod 600 "$CA_DIR/ca.key"
fi

# --- Certificat serveur ------------------------------------------------------
log "Création du certificat de $FQDN"
cat > /tmp/ext.cnf <<CONF
basicConstraints=CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:${FQDN},DNS:${SHORT},IP:${IP}
CONF
openssl req -new -newkey rsa:3072 -noenc -subj "/CN=${FQDN}" -keyout "$KEY" -out /tmp/srv.csr 2>/dev/null
openssl x509 -req -in /tmp/srv.csr -CA "$CA_DIR/ca.crt" -CAkey "$CA_DIR/ca.key" -CAcreateserial \
  -days 397 -sha256 -extfile /tmp/ext.cnf -out "$CERT_DIR/${SHORT}.crt" 2>/dev/null
chmod 600 "$KEY"; rm -f /tmp/srv.csr /tmp/ext.cnf

# --- Contenu du site ---------------------------------------------------------
mkdir -p "$WEB_ROOT"
cat > "$WEB_ROOT/index.html" <<'HTML'
<!doctype html>
<html lang="fr"><head><meta charset="utf-8"><title>Intranet infra1</title></head>
<body><h1>Intranet infra1</h1><p>Serveur nginx interne en HTTPS (srv-debian).</p></body></html>
HTML
cp "$CA_DIR/ca.crt" "$WEB_ROOT/lab-ca.crt"     # certificat PUBLIC de l'AC, pour les clients

# --- Site nginx --------------------------------------------------------------
log "Configuration du site nginx"
cat > /etc/nginx/sites-available/intranet <<'CONF'
server {
    listen 80;
    listen [::]:80;
    server_name srv-debian.lab.local srv-debian 192.168.10.20;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;
    server_name srv-debian.lab.local srv-debian 192.168.10.20;

    ssl_certificate     /etc/ssl/lab/srv-debian.crt;
    ssl_certificate_key /etc/ssl/private/srv-debian.key;

    root  /var/www/intranet;
    index index.html;

    access_log /var/log/nginx/intranet_access.log;
    error_log  /var/log/nginx/intranet_error.log;

    location / {
        try_files $uri $uri/ =404;
    }
}
CONF
ln -sf /etc/nginx/sites-available/intranet /etc/nginx/sites-enabled/intranet
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl enable nginx >/dev/null
systemctl reload nginx || systemctl restart nginx

# --- Résumé ------------------------------------------------------------------
echo
log "Serveur web HTTPS opérationnel"
curl -s -o /dev/null -w "HTTP  -> code %{http_code} (301 attendu)\n" http://127.0.0.1/
curl -s --cacert "$CA_DIR/ca.crt" --resolve "${FQDN}:443:127.0.0.1" -o /dev/null \
  -w "HTTPS -> code %{http_code} (200 attendu)\n" "https://${FQDN}/"
echo "Empreinte SHA-256 de l'AC (à comparer sur pc-zorin avec le script 09) :"
openssl x509 -in "$CA_DIR/ca.crt" -noout -fingerprint -sha256
