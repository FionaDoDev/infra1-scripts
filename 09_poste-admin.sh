#!/usr/bin/env bash
# =============================================================================
# 09_poste-admin.sh — Rôle « poste de l'administrateur principal » (pc-zorin)
#   - installe les outils d'administration
#   - fait confiance à l'AC de laboratoire (certificat publié par srv-debian)
#   - crée une clé SSH dédiée et un fichier ~/.ssh/config vers fw et les serveurs
# Le durcissement du poste (ufw, compte d'admin séparé, MFA, USBGuard, auditd…)
# relève de la remédiation après audit.
# Usage : sudo ./09_poste-admin.sh   (compte distant différent : sudo SRV_USER=nom ./09_poste-admin.sh)
# À lancer après 06_nginx-https.sh.
# =============================================================================
set -euo pipefail

CA_URL="https://192.168.10.20/lab-ca.crt"
CA_DEST="/usr/local/share/ca-certificates/infra1-lab-ca.crt"

log()  { echo -e "\e[1;32m[+]\e[0m $*"; }
warn() { echo -e "\e[1;33m[!]\e[0m $*"; }
die()  { echo -e "\e[1;31m[x]\e[0m $*" >&2; exit 1; }
[[ $EUID -eq 0 ]] || die "Lancer avec sudo depuis ton compte"
ADMIN_USER="${SUDO_USER:-}"
[[ -n $ADMIN_USER && $ADMIN_USER != root ]] || die "Lancer avec sudo depuis ton compte (pas depuis root)"
USER_HOME=$(getent passwd "$ADMIN_USER" | cut -d: -f6)
SRV_USER="${SRV_USER:-$ADMIN_USER}"

# --- 1. Outils ---------------------------------------------------------------
log "Installation des outils d'administration"
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get install -y -q openssh-client curl git nmap ca-certificates openssl
apt-get install -y -q keepassxc ansible || warn "keepassxc ou ansible indisponible : installation facultative ignorée"

# --- 2. Confiance dans l'AC de laboratoire -----------------------------------
log "Récupération du certificat de l'AC depuis srv-debian"
curl -fsSk "$CA_URL" -o /tmp/lab-ca.crt || die "Impossible de joindre $CA_URL : lancer d'abord 06_nginx-https.sh"
echo "Empreinte reçue (doit être identique à celle affichée par 06 sur srv-debian) :"
openssl x509 -in /tmp/lab-ca.crt -noout -fingerprint -sha256
read -r -p "Les empreintes sont-elles identiques ? (o/N) " ok
[[ ${ok,,} == o* ]] || die "Empreinte non confirmée : certificat non installé"
install -m 644 /tmp/lab-ca.crt "$CA_DEST"
update-ca-certificates >/dev/null
rm -f /tmp/lab-ca.crt

# --- 3. Clé SSH dédiée -------------------------------------------------------
KEY="$USER_HOME/.ssh/id_ed25519_infra1"
sudo -u "$ADMIN_USER" mkdir -p "$USER_HOME/.ssh"; chmod 700 "$USER_HOME/.ssh"
if [[ ! -f $KEY ]]; then
  log "Création de la clé SSH (choisis une phrase de passe)"
  sudo -u "$ADMIN_USER" ssh-keygen -t ed25519 -f "$KEY" -C "admin@pc-zorin"
fi

# --- 4. Fichier ~/.ssh/config ------------------------------------------------
CFG="$USER_HOME/.ssh/config"
if ! grep -q '# >>> infra1' "$CFG" 2>/dev/null; then
  log "Ajout des hôtes fw, srv-fedora et srv-debian dans ~/.ssh/config"
  cat >> "$CFG" <<CONF
# >>> infra1
Host fw
    HostName 192.168.10.254
Host srv-fedora
    HostName 192.168.10.10
Host srv-debian
    HostName 192.168.10.20
Host fw srv-fedora srv-debian
    User ${SRV_USER}
    IdentityFile ~/.ssh/id_ed25519_infra1
    IdentitiesOnly yes
# <<< infra1
CONF
  chown "$ADMIN_USER:$ADMIN_USER" "$CFG"; chmod 600 "$CFG"
fi

# --- 5. Résumé ---------------------------------------------------------------
echo
log "Poste d'administration préparé"
curl -s -o /dev/null -w "Intranet https://srv-debian.lab.local -> code %{http_code} (200 attendu, sans -k)\n" https://srv-debian.lab.local/
echo "Étape suivante, depuis ton compte (sans sudo), copier la clé sur chaque machine :"
echo "  ssh-copy-id -i ~/.ssh/id_ed25519_infra1.pub fw"
echo "  ssh-copy-id -i ~/.ssh/id_ed25519_infra1.pub srv-fedora"
echo "  ssh-copy-id -i ~/.ssh/id_ed25519_infra1.pub srv-debian"
echo "Puis lancer ./10_tests-roles.sh"
