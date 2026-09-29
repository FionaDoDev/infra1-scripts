#!/usr/bin/env bash
# =============================================================================
# 01_pare-feu.sh — Configuration du pare-feu / routeur (Debian)
#   - IP fixe côté LAN, DHCP côté WAN
#   - routage IPv4 + NAT (masquerade) avec nftables
#   - politique "tout refuser" sauf ce qui est explicitement autorisé
#   - DHCP + DNS local pour le LAN avec dnsmasq
# À lancer en root, EN CONSOLE, sur la VM "fw" juste après l'installation.
# Interfaces détectées automatiquement ; forçables : WAN_IF=... LAN_IF=... ./01_pare-feu.sh
# =============================================================================
set -euo pipefail

HOSTNAME_FW="fw"
DOMAIN="lab.local"
LAN_IP="192.168.10.254"
LAN_CIDR="24"
LAN_NET="192.168.10.0/24"
DHCP_START="192.168.10.100"
DHCP_END="192.168.10.150"
IP_FEDORA="192.168.10.10"
IP_DEBIAN="192.168.10.20"

log() { echo -e "\e[1;32m[+]\e[0m $*"; }
die() { echo -e "\e[1;31m[x]\e[0m $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Lancer en root (sudo $0)"

# --- 1. Détection des interfaces --------------------------------------------
WAN_IF="${WAN_IF:-$(ip route show default | awk '{print $5; exit}')}"
[[ -n $WAN_IF ]] || die "Pas de route par défaut : la carte NAT doit être active (WAN_IF=... pour forcer)"
LAN_IF="${LAN_IF:-$(ls /sys/class/net | grep -Ev "^(lo|${WAN_IF})$" | head -1 || true)}"
[[ -n $LAN_IF ]] || die "Aucune seconde interface trouvée pour le LAN"
log "WAN = $WAN_IF | LAN = $LAN_IF"

# --- 2. Paquets (tant que l'accès Internet est sûr) -------------------------
log "Installation des paquets"
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get install -y -q nftables dnsmasq

# --- 3. Nom d'hôte -----------------------------------------------------------
log "Nom d'hôte : $HOSTNAME_FW"
hostnamectl set-hostname "$HOSTNAME_FW"
sed -i "s/^127\.0\.1\.1.*/127.0.1.1\t${HOSTNAME_FW}.${DOMAIN} ${HOSTNAME_FW}/" /etc/hosts

# --- 4. Interfaces réseau ----------------------------------------------------
log "Configuration de /etc/network/interfaces (sauvegarde en .bak)"
cp -n /etc/network/interfaces /etc/network/interfaces.bak || true
cat > /etc/network/interfaces <<CONF
source /etc/network/interfaces.d/*

auto lo
iface lo inet loopback

# WAN : vers Internet (NAT de l'hyperviseur)
auto ${WAN_IF}
iface ${WAN_IF} inet dhcp

# LAN : réseau interne du schéma
auto ${LAN_IF}
iface ${LAN_IF} inet static
    address ${LAN_IP}/${LAN_CIDR}
CONF
ifup "$LAN_IF" 2>/dev/null || ip addr replace "${LAN_IP}/${LAN_CIDR}" dev "$LAN_IF"
ip link set "$LAN_IF" up

# --- 5. Routage --------------------------------------------------------------
log "Activation du routage IPv4"
echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-routage.conf
sysctl -q --system

# --- 6. nftables -------------------------------------------------------------
log "Écriture des règles nftables"
cp -n /etc/nftables.conf /etc/nftables.conf.bak || true
cat > /etc/nftables.conf <<CONF
#!/usr/sbin/nft -f
# Pare-feu infra1 — généré par 01_pare-feu.sh
flush ruleset

table inet filter {
    chain input {
        type filter hook input priority 0; policy drop;
        ct state established,related accept
        ct state invalid drop
        iif lo accept
        iifname "${LAN_IF}" icmp type echo-request accept
        iifname "${LAN_IF}" tcp dport 22 accept comment "SSH admin depuis le LAN"
        iifname "${LAN_IF}" udp dport { 53, 67 } accept comment "DNS + DHCP"
        iifname "${LAN_IF}" tcp dport 53 accept comment "DNS"
        log prefix "FW-INPUT-DROP " limit rate 5/minute
    }

    chain forward {
        type filter hook forward priority 0; policy drop;
        ct state established,related accept
        ct state invalid drop
        iifname "${LAN_IF}" oifname "${WAN_IF}" ip saddr ${LAN_NET} accept comment "LAN -> Internet"
        log prefix "FW-FORWARD-DROP " limit rate 5/minute
    }

    chain output {
        type filter hook output priority 0; policy accept;
    }
}

table ip nat {
    chain postrouting {
        type nat hook postrouting priority srcnat; policy accept;
        oifname "${WAN_IF}" ip saddr ${LAN_NET} masquerade
    }
}
CONF
nft -c -f /etc/nftables.conf || die "Erreur de syntaxe nftables"
systemctl enable --now nftables >/dev/null
nft -f /etc/nftables.conf

# --- 7. dnsmasq (DHCP + DNS du LAN) -----------------------------------------
log "Configuration de dnsmasq"
cat > /etc/dnsmasq.d/lan.conf <<CONF
# DHCP + DNS pour le LAN infra1 — généré par 01_pare-feu.sh
interface=${LAN_IF}
bind-dynamic
domain=${DOMAIN}
local=/${DOMAIN}/
domain-needed
bogus-priv

dhcp-range=${DHCP_START},${DHCP_END},12h
dhcp-option=option:router,${LAN_IP}
dhcp-option=option:dns-server,${LAN_IP}
dhcp-option=option:domain-name,${DOMAIN}
dhcp-authoritative

# Noms des serveurs (IP fixes)
host-record=fw.${DOMAIN},fw,${LAN_IP}
host-record=srv-fedora.${DOMAIN},srv-fedora,${IP_FEDORA}
host-record=srv-debian.${DOMAIN},srv-debian,${IP_DEBIAN}
CONF
dnsmasq --test || die "Erreur de configuration dnsmasq"
systemctl enable dnsmasq >/dev/null
systemctl restart dnsmasq

# --- 8. Résumé ---------------------------------------------------------------
echo
log "Pare-feu opérationnel"
ip -br addr show dev "$WAN_IF"
ip -br addr show dev "$LAN_IF"
echo "Routage : $(sysctl -n net.ipv4.ip_forward)  |  nftables : $(systemctl is-active nftables)  |  dnsmasq : $(systemctl is-active dnsmasq)"
echo "Baux DHCP : cat /var/lib/misc/dnsmasq.leases   |   Règles : nft list ruleset"
