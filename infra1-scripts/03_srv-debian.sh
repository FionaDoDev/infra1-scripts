#!/usr/bin/env bash
# =============================================================================
# 03_srv-debian.sh — Configuration du serveur Debian
#   - IP fixe, passerelle et DNS = pare-feu
#   - mises à jour, SSH
# À lancer en root, EN CONSOLE (l'IP change en cours de route).
# Interface forçable : IFACE=... ./03_srv-debian.sh
# =============================================================================
set -euo pipefail

HOSTNAME_SRV="srv-debian"
DOMAIN="lab.local"
IP="192.168.10.20"
CIDR="24"
GW="192.168.10.254"
DNS="192.168.10.254"

log() { echo -e "\e[1;32m[+]\e[0m $*"; }
die() { echo -e "\e[1;31m[x]\e[0m $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Lancer en root (su - puis ./$0)"

# --- 1. Interface ------------------------------------------------------------
IFACE="${IFACE:-$(ls /sys/class/net | grep -v '^lo$' | head -1 || true)}"
[[ -n $IFACE ]] || die "Aucune interface trouvée"
log "Interface : $IFACE"

# --- 2. Nom d'hôte -----------------------------------------------------------
log "Nom d'hôte : $HOSTNAME_SRV"
hostnamectl set-hostname "$HOSTNAME_SRV"
sed -i "s/^127\.0\.1\.1.*/127.0.1.1\t${HOSTNAME_SRV}.${DOMAIN} ${HOSTNAME_SRV}/" /etc/hosts

# --- 3. IP fixe --------------------------------------------------------------
log "Passage en IP fixe $IP/$CIDR"
ifdown "$IFACE" 2>/dev/null || true
pkill -f "dhclient.*${IFACE}" 2>/dev/null || true
pkill -f "dhcpcd.*${IFACE}" 2>/dev/null || true
ip addr flush dev "$IFACE"

cp -n /etc/network/interfaces /etc/network/interfaces.bak || true
cat > /etc/network/interfaces <<CONF
source /etc/network/interfaces.d/*

auto lo
iface lo inet loopback

auto ${IFACE}
iface ${IFACE} inet static
    address ${IP}/${CIDR}
    gateway ${GW}
CONF

cat > /etc/resolv.conf <<CONF
search ${DOMAIN}
nameserver ${DNS}
CONF

ifup "$IFACE"
sleep 2
ping -c2 -W2 "$GW" >/dev/null || die "Le pare-feu ($GW) ne répond pas : vérifier le réseau interne"

# --- 4. Mises à jour et outils ----------------------------------------------
log "Mises à jour"
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get full-upgrade -y -q
apt-get install -y -q openssh-server sudo vim curl

systemctl enable --now ssh >/dev/null

# --- 5. Résumé ---------------------------------------------------------------
echo
log "Serveur Debian prêt"
ip -br addr show "$IFACE"
ip route | grep default
echo "SSH : $(systemctl is-active ssh)"
