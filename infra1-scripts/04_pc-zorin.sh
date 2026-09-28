#!/usr/bin/env bash
# =============================================================================
# 04_pc-zorin.sh — Configuration du poste client Zorin OS
#   - réseau en DHCP (fourni par dnsmasq sur le pare-feu)
#   - mises à jour + outils de diagnostic
# Usage : sudo ./04_pc-zorin.sh
# =============================================================================
set -euo pipefail

HOSTNAME_PC="pc-zorin"

log() { echo -e "\e[1;32m[+]\e[0m $*"; }
die() { echo -e "\e[1;31m[x]\e[0m $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Lancer avec sudo"

# --- 1. Nom d'hôte -----------------------------------------------------------
log "Nom d'hôte : $HOSTNAME_PC"
hostnamectl set-hostname "$HOSTNAME_PC"
sed -i "s/^127\.0\.1\.1.*/127.0.1.1\t${HOSTNAME_PC}/" /etc/hosts

# --- 2. Réseau en DHCP -------------------------------------------------------
IFACE="$(nmcli -t -f DEVICE,TYPE device | awk -F: '$2=="ethernet"{print $1; exit}')"
[[ -n $IFACE ]] || die "Aucune interface ethernet trouvée"
CON="$(nmcli -g GENERAL.CONNECTION device show "$IFACE" || true)"
if [[ -z $CON || $CON == "--" ]]; then
  nmcli con add type ethernet ifname "$IFACE" con-name lan >/dev/null
  CON="lan"
fi
log "DHCP sur $IFACE (connexion : $CON)"
nmcli con mod "$CON" ipv4.method auto ipv4.addresses "" ipv4.gateway "" ipv4.dns "" connection.autoconnect yes
nmcli con up "$CON" >/dev/null
sleep 3

# --- 3. Mises à jour et outils ----------------------------------------------
log "Mises à jour et outils réseau"
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get upgrade -y -q
apt-get install -y -q openssh-client curl dnsutils traceroute nmap

# --- 4. Résumé ---------------------------------------------------------------
echo
log "Poste client prêt"
ip -br addr show "$IFACE"
ip route | grep default
echo "Lancer ensuite : ./05_tests.sh"
