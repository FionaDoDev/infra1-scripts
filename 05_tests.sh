#!/usr/bin/env bash
# =============================================================================
# 05_tests.sh — Recette de l'infrastructure infra1
# À lancer depuis le poste Zorin (pas besoin de root).
# Affiche un bilan OK/KO — pratique pour les captures du rendu.
# =============================================================================

FW="192.168.10.254"
FEDORA="192.168.10.10"
DEBIAN="192.168.10.20"
PASS=0
FAIL=0

check() {
  local desc=$1; shift
  if "$@" >/dev/null 2>&1; then
    echo -e "  \e[32m[OK]\e[0m $desc"; PASS=$((PASS + 1))
  else
    echo -e "  \e[31m[KO]\e[0m $desc"; FAIL=$((FAIL + 1))
  fi
}
port_ouvert() { timeout 3 bash -c "</dev/tcp/$1/$2"; }

echo "== Configuration du poste =="
check "Adresse obtenue par DHCP (192.168.10.100-150)" \
  bash -c "ip -4 -o addr | grep -Eq '192\.168\.10\.(1[0-4][0-9]|150)/'"
check "Passerelle par défaut = pare-feu ($FW)" \
  bash -c "ip route | grep -q 'default via $FW'"

echo "== Connectivité LAN =="
check "Ping pare-feu ($FW)"        ping -c2 -W2 "$FW"
check "Ping Fedora ($FEDORA)"      ping -c2 -W2 "$FEDORA"
check "Ping Debian ($DEBIAN)"      ping -c2 -W2 "$DEBIAN"

echo "== DNS local (dnsmasq) =="
check "Résolution srv-fedora.lab.local" bash -c "getent hosts srv-fedora.lab.local | grep -q $FEDORA"
check "Résolution srv-debian.lab.local" bash -c "getent hosts srv-debian.lab.local | grep -q $DEBIAN"

echo "== Services =="
check "SSH Fedora (22)"            port_ouvert "$FEDORA" 22
check "Cockpit Fedora (9090)"      port_ouvert "$FEDORA" 9090
check "SSH Debian (22)"            port_ouvert "$DEBIAN" 22
check "SSH pare-feu (22)"          port_ouvert "$FW" 22

echo "== Sortie Internet via le pare-feu (NAT) =="
check "Route vers Internet via $FW" bash -c "ip route get 1.1.1.1 | grep -q 'via $FW'"
check "Ping Internet (1.1.1.1)"    ping -c2 -W3 1.1.1.1
check "Résolution DNS externe"     getent hosts debian.org
check "Accès HTTPS (fedoraproject.org)" curl -sfI --max-time 8 https://fedoraproject.org

echo "== Filtrage =="
check "Port non autorisé fermé sur le pare-feu (80)" bash -c "! timeout 3 bash -c '</dev/tcp/$FW/80'"

echo
echo "Bilan : $PASS OK / $FAIL KO"
[[ $FAIL -eq 0 ]]
