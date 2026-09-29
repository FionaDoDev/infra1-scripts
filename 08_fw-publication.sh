#!/usr/bin/env bash
# =============================================================================
# 08_fw-publication.sh — Publication des ports 80/443 de srv-fedora sur Internet
#   Ajoute sur fw une traduction d'adresse (DNAT) : ce qui arrive sur l'interface
#   WAN en 80/443 est redirigé vers srv-fedora, et autorise ce flux dans la
#   chaîne forward. Seuls ces deux ports sont publiés.
# À lancer en root sur fw, après 01_pare-feu.sh et 07_docker.sh.
# =============================================================================
set -euo pipefail

TARGET="192.168.10.10"
CONF="/etc/nftables.conf"

log() { echo -e "\e[1;32m[+]\e[0m $*"; }
die() { echo -e "\e[1;31m[x]\e[0m $*" >&2; exit 1; }
[[ $EUID -eq 0 ]] || die "Lancer en root (su - puis ./$0)"

WAN_IF="${WAN_IF:-$(ip route show default | awk '{print $5; exit}')}"
[[ -n $WAN_IF ]] || die "Interface WAN introuvable (WAN_IF=... pour forcer)"
grep -q 'LAN -> Internet' "$CONF" || die "$CONF ne vient pas de 01_pare-feu.sh"

if grep -q 'Publication Docker' "$CONF"; then
  log "Publication déjà présente, rien à faire"
else
  log "Ajout du DNAT $WAN_IF:80,443 -> $TARGET"
  cp "$CONF" "$CONF.avant-publication"
  awk -v wan="$WAN_IF" -v t="$TARGET" '
    /chain postrouting \{/ {
      print "    chain prerouting {"
      print "        type nat hook prerouting priority dstnat; policy accept;"
      print "        iifname \"" wan "\" tcp dport { 80, 443 } dnat to " t " comment \"Publication Docker\""
      print "    }"
      print ""
    }
    { print }
    /comment "LAN -> Internet"/ {
      print "        iifname \"" wan "\" ip daddr " t " tcp dport { 80, 443 } ct status dnat accept comment \"Publication Docker\""
    }' "$CONF.avant-publication" > "$CONF"
fi

nft -c -f "$CONF" || { cp "$CONF.avant-publication" "$CONF"; die "Erreur de syntaxe : configuration restaurée"; }
nft -f "$CONF"

echo
log "Publication active"
nft list ruleset | grep -n 'Publication Docker'
WAN_IP=$(ip -4 -o addr show dev "$WAN_IF" | awk '{print $4}' | cut -d/ -f1)
echo "Test depuis Windows (côté « Internet ») : https://${WAN_IP}/app01/  (certificat auto-signé : avertissement normal)"
