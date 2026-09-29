#!/usr/bin/env bash
# =============================================================================
# 07_docker.sh — Rôle « 15 conteneurs Docker exposés sur Internet » (srv-fedora)
#   - installe Docker (dépôt officiel, repli sur moby-engine de Fedora)
#   - déploie 15 conteneurs avec Docker Compose :
#       1 reverse proxy nginx (seul à publier 80/443)
#       10 applications de test (whoami), 1 site statique, 1 serveur httpd
#       2 services internes (redis, postgres) sur un réseau sans sortie
# Configuration Docker PAR DÉFAUT volontairement : pas de userns, pas de limites
# de ressources, tags non épinglés… Ce sont des points de la grille d'audit,
# corrigés pendant la remédiation. Aucun secret n'est écrit dans le dépôt :
# le mot de passe de la base est généré localement dans un fichier .env.
# À lancer en root sur srv-fedora. Puis lancer 08_fw-publication.sh sur fw.
# =============================================================================
set -euo pipefail

DIR="/opt/infra1-docker"; IP="192.168.10.10"; CN="services.infra1.lab"
APPS=$(printf 'app%02d ' $(seq 1 10))

log()  { echo -e "\e[1;32m[+]\e[0m $*"; }
warn() { echo -e "\e[1;33m[!]\e[0m $*"; }
die()  { echo -e "\e[1;31m[x]\e[0m $*" >&2; exit 1; }
[[ $EUID -eq 0 ]] || die "Lancer en root (sudo -i puis ./$0)"

# --- 1. Docker ---------------------------------------------------------------
if ! command -v docker >/dev/null 2>&1; then
  log "Installation de Docker"
  dnf -y remove podman-docker >/dev/null 2>&1 || true
  dnf -y install dnf-plugins-core openssl >/dev/null
  REPO=/etc/yum.repos.d/docker-ce.repo
  if { [[ -f $REPO ]] || dnf config-manager addrepo --from-repofile=https://download.docker.com/linux/fedora/docker-ce.repo; } \
     && dnf -y install docker-ce docker-ce-cli containerd.io docker-compose-plugin; then
    log "Docker CE installé depuis le dépôt officiel"
  else
    warn "Dépôt Docker indisponible pour cette version de Fedora : repli sur moby-engine"
    rm -f "$REPO"
    dnf -y install moby-engine docker-compose
  fi
fi
if docker compose version >/dev/null 2>&1; then DC="docker compose"; else DC="docker-compose"; fi

# --- 2. Pare-feu local (avant le démarrage de Docker) ------------------------
log "Ouverture de http et https dans firewalld"
firewall-cmd -q --permanent --add-service=http --add-service=https
firewall-cmd -q --reload
systemctl enable docker >/dev/null
systemctl restart docker

# --- 3. Fichiers du projet ---------------------------------------------------
log "Préparation de $DIR"
mkdir -p "$DIR/proxy/certs" "$DIR/static"
cd "$DIR"

if [[ ! -f .env ]]; then
  echo "DB_PASSWORD=$(openssl rand -hex 16)" > .env      # généré ici, jamais publié
  chmod 600 .env
fi

if [[ ! -f proxy/certs/proxy.crt ]]; then
  openssl req -x509 -newkey rsa:3072 -noenc -sha256 -days 397 -subj "/CN=${CN}" \
    -addext "subjectAltName=DNS:${CN},IP:${IP}" \
    -keyout proxy/certs/proxy.key -out proxy/certs/proxy.crt 2>/dev/null
  chmod 600 proxy/certs/proxy.key
fi

echo '<!doctype html><html lang="fr"><head><meta charset="utf-8"><title>Statique</title></head><body><h1>Site statique infra1</h1></body></html>' > static/index.html

# Configuration du reverse proxy
{
  cat <<'CONF'
server {
    listen 80;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    ssl_certificate     /etc/nginx/certs/proxy.crt;
    ssl_certificate_key /etc/nginx/certs/proxy.key;

    location = / {
        default_type text/plain;
        return 200 "infra1 : 15 conteneurs derriere un reverse proxy\n";
    }
CONF
  for a in $APPS static httpd; do
    printf '    location /%s/ { proxy_pass http://%s:80/; proxy_set_header Host $host; }\n' "$a" "$a"
  done
  echo "}"
} > proxy/nginx.conf

# Fichier compose : 15 services
{
  echo "services:"
  echo "  proxy:"
  echo "    image: nginx:1.27-alpine"
  echo "    ports: [\"80:80\", \"443:443\"]"
  echo "    volumes:"
  echo "      - ./proxy/nginx.conf:/etc/nginx/conf.d/default.conf:ro,z"
  echo "      - ./proxy/certs:/etc/nginx/certs:ro,z"
  echo "    networks: [frontend]"
  echo "    depends_on: [$(echo $APPS static httpd | sed 's/ /, /g')]"
  echo "    restart: unless-stopped"
  for a in $APPS; do
    echo "  $a:"
    echo "    image: traefik/whoami:v1.10"
    if [[ $a == app01 ]]; then echo "    networks: [frontend, backend]"; else echo "    networks: [frontend]"; fi
    echo "    restart: unless-stopped"
  done
  cat <<'YAML'
  static:
    image: nginx:1.27-alpine
    volumes:
      - ./static:/usr/share/nginx/html:ro,z
    networks: [frontend]
    restart: unless-stopped
  httpd:
    image: httpd:2.4-alpine
    networks: [frontend]
    restart: unless-stopped
  redis:
    image: redis:7-alpine
    networks: [backend]
    restart: unless-stopped
  db:
    image: postgres:16-alpine
    environment:
      POSTGRES_PASSWORD: ${DB_PASSWORD}
    volumes:
      - dbdata:/var/lib/postgresql/data
    networks: [backend]
    restart: unless-stopped

networks:
  frontend: {}
  backend:
    internal: true

volumes:
  dbdata: {}
YAML
} > compose.yaml

# --- 4. Démarrage ------------------------------------------------------------
log "Téléchargement des images et démarrage (quelques minutes)"
$DC -f compose.yaml pull -q
$DC -f compose.yaml up -d

# --- 5. Résumé ---------------------------------------------------------------
sleep 5
echo
log "Conteneurs en cours d'exécution : $(docker ps -q | wc -l) (15 attendus)"
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Ports}}'
curl -sk -o /dev/null -w "Proxy HTTPS -> code %{http_code} (200 attendu)\n" https://127.0.0.1/app01/
echo "Étape suivante : lancer 08_fw-publication.sh sur fw pour exposer 80/443 côté Internet."
