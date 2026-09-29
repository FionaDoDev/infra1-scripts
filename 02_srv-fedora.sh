#!/usr/bin/env bash
# =============================================================================
# 02_srv-fedora.sh — Configuration du serveur Fedora 44
#   - IP fixe, passerelle et DNS = pare-feu
#   - mises à jour, Cockpit, firewalld (ssh + cockpit)
# À lancer en root, EN CONSOLE (l'IP change en cours de route).
# Interface forçable : IFACE=... ./02_srv-fedora.sh
# =============================================================================
set -euo pipefail

HOSTNAME_SRV="srv-fedora"
DOMAIN="lab.local"
IP_CIDR="192.168.10.10/24"
GW="192.168.10.254"
DNS="192.168.10.254"

log() { echo -e "\e[1;32m[+]\e[0m $*"; }
die() { echo -e "\e[1;31m[x]\e[0m $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Lancer en root (sudo $0)"

# --- 1. Interface et connexion NetworkManager -------------------------------
IFACE="${IFACE:-$(nmcli -t -f DEVICE,TYPE device | awk -F: '$2=="ethernet"{print $1; exit}')}"
[[ -n $IFACE ]] || die "Aucune interface ethernet trouvée"
CON="$(nmcli -g GENERAL.CONNECTION device show "$IFACE" || true)"
if [[ -z $CON || $CON == "--" ]]; then
  log "Aucune connexion sur $IFACE, création de 'lan'"
  nmcli con add type ethernet ifname "$IFACE" con-name lan >/dev/null
  CON="lan"
fi
log "Interface $IFACE (connexion : $CON)"

# --- 2. Nom d'hôte -----------------------------------------------------------
log "Nom d'hôte : $HOSTNAME_SRV"
hostnamectl set-hostname "$HOSTNAME_SRV"

# --- 3. IP fixe --------------------------------------------------------------
log "IP fixe $IP_CIDR, passerelle $GW"
nmcli con mod "$CON" \
  ipv4.method manual \
  ipv4.addresses "$IP_CIDR" \
  ipv4.gateway "$GW" \
  ipv4.dns "$DNS" \
  ipv4.dns-search "$DOMAIN" \
  connection.autoconnect yes
nmcli con up "$CON" >/dev/null
sleep 2

ping -c2 -W2 "$GW" >/dev/null || die "Le pare-feu ($GW) ne répond pas : vérifier le réseau interne"

# --- 4. Mises à jour et outils ----------------------------------------------
log "Mises à jour (peut être long)"
dnf -y -q upgrade
dnf -y -q install cockpit bash-completion vim-enhanced

# --- 5. Services et pare-feu local ------------------------------------------
log "Activation de sshd, Cockpit et firewalld"
systemctl enable --now sshd cockpit.socket firewalld >/dev/null
firewall-cmd -q --permanent --add-service=ssh
firewall-cmd -q --permanent --add-service=cockpit
firewall-cmd -q --reload

# --- 6. Résumé ---------------------------------------------------------------
echo
log "Serveur Fedora prêt"
ip -br addr show "$IFACE"
ip route | grep default
echo "Services ouverts : $(firewall-cmd --list-services)"
echo "Cockpit : https://${IP_CIDR%/*}:9090"
