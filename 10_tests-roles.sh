#!/usr/bin/env bash
# =============================================================================
# 10_tests-roles.sh — Recette des 3 rôles déployés (à lancer depuis pc-zorin)
# Sans root. Complète 05_tests.sh, qui vérifie le réseau de base.
# =============================================================================

WEB="srv-debian.lab.local"; DKR="192.168.10.10"
PASS=0; FAIL=0

check() {
  local desc=$1; shift
  if "$@" >/dev/null 2>&1; then echo -e "  \e[32m[OK]\e[0m $desc"; PASS=$((PASS + 1))
  else echo -e "  \e[31m[KO]\e[0m $desc"; FAIL=$((FAIL + 1)); fi
}
code() { curl -s -o /dev/null -w '%{http_code}' "$@"; }
port_ferme() { ! timeout 3 bash -c "</dev/tcp/$1/$2"; }

echo "== Serveur web nginx HTTPS (srv-debian) =="
check "HTTP redirigé vers HTTPS (301)"           bash -c "[[ \$(curl -s -o /dev/null -w '%{http_code}' http://$WEB/) == 301 ]]"
check "HTTPS répond 200 avec un certificat reconnu" bash -c "[[ \$(curl -s -o /dev/null -w '%{http_code}' https://$WEB/) == 200 ]]"
check "Certificat émis par l'AC de laboratoire"   bash -c "echo | openssl s_client -connect $WEB:443 -servername $WEB 2>/dev/null | openssl x509 -noout -issuer | grep -q 'infra1 Lab CA'"

echo "== Hôte Docker (srv-fedora) =="
check "Page d'accueil du reverse proxy"           bash -c "curl -sk https://$DKR/ | grep -q '15 conteneurs'"
ok=0; for i in $(seq -w 1 10); do curl -sk "https://$DKR/app$i/" | grep -q Hostname && ok=$((ok + 1)); done
check "10 applications whoami joignables ($ok/10)" test "$ok" -eq 10
check "Site statique joignable"                    bash -c "curl -sk https://$DKR/static/ | grep -q 'Site statique'"
check "Serveur httpd joignable"                    bash -c "curl -sk https://$DKR/httpd/ | grep -qi 'works'"
check "PostgreSQL non joignable depuis le LAN (5432)" port_ferme "$DKR" 5432
check "Redis non joignable depuis le LAN (6379)"      port_ferme "$DKR" 6379

echo "== Poste d'administration (pc-zorin) =="
check "AC de laboratoire installée"               test -f /usr/local/share/ca-certificates/infra1-lab-ca.crt
check "Clé SSH dédiée présente"                   test -f "$HOME/.ssh/id_ed25519_infra1"
check "Hôtes infra1 dans ~/.ssh/config"           grep -q '# >>> infra1' "$HOME/.ssh/config"
check "Connexion SSH par clé vers srv-debian"     ssh -o BatchMode=yes -o ConnectTimeout=5 srv-debian true

echo
echo "Bilan : $PASS OK / $FAIL KO"
echo "Exposition Internet : depuis Windows, ouvrir https://<IP WAN de fw>/app01/"
[[ $FAIL -eq 0 ]]
