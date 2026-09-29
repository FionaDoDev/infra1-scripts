# infra1 — scripts d'automatisation

Mise en œuvre du schéma : Internet → pare-feu → Fedora 44 Server, Debian, Zorin OS.

| Script | Où le lancer | Rôle |
|---|---|---|
| `00_creer_vms_vmware.ps1` | Windows (PowerShell) | Crée les 4 VM VMware Workstation et le LAN Segment `LAN` |
| `00_creer_vms_virtualbox.sh` | Hôte avec VirtualBox | Variante VirtualBox |
| `01_pare-feu.sh` | VM `fw` (root) | Routage, NAT, filtrage nftables, DHCP/DNS dnsmasq |
| `02_srv-fedora.sh` | VM `srv-fedora` (root) | IP fixe .10, mises à jour, Cockpit, firewalld |
| `03_srv-debian.sh` | VM `srv-debian` (root) | IP fixe .20, mises à jour, SSH |
| `04_pc-zorin.sh` | VM `pc-zorin` (sudo) | DHCP, mises à jour, outils réseau |
| `05_tests.sh` | VM `pc-zorin` | Recette du réseau de base avec bilan OK/KO |
| `06_nginx-https.sh` | VM `srv-debian` (root) | Rôle serveur web nginx interne en HTTPS (AC de laboratoire) |
| `07_docker.sh` | VM `srv-fedora` (root) | Rôle 15 conteneurs Docker derrière un reverse proxy |
| `08_fw-publication.sh` | VM `fw` (root) | Publication de 80/443 vers srv-fedora (DNAT) |
| `09_poste-admin.sh` | VM `pc-zorin` (sudo) | Rôle poste d'administration : outils, AC, clé et config SSH |
| `10_tests-roles.sh` | VM `pc-zorin` | Recette des 3 rôles |

## Ordre
1. VMware fermé, dans PowerShell :
   `powershell -ExecutionPolicy Bypass -File .\00_creer_vms_vmware.ps1`
   (les ISO sont cherchées dans Téléchargements ; sinon `-DossierIso "D:\ISO"`).
2. Installer Debian sur `fw` puis lancer `01_pare-feu.sh`. **Toujours en premier** :
   c'est lui qui fournit le DHCP et l'accès Internet aux autres VM.
3. Installer Fedora et Debian serveur (le réseau passe en DHCP pendant l'installation),
   puis lancer `02` et `03` **en console** (l'IP change pendant le script).
4. Installer Zorin OS, lancer `04` puis `05`.
5. Déployer les rôles avant l'audit : `06` (srv-debian), `07` (srv-fedora), `08` (fw), `09` (pc-zorin), puis `10`.
   Les rôles sont déployés en configuration standard : leur durcissement relève de la remédiation après audit.

## Récupérer les scripts dans les VM
Le plus simple : pousser ce dossier sur GitHub puis, dans chaque VM :
```bash
git clone https://github.com/<compte>/infra1-scripts.git && cd infra1-scripts
chmod +x *.sh
```
(ou `curl -O` sur l'URL « raw » d'un script si git n'est pas installé).

## Plan d'adressage
LAN 192.168.10.0/24, passerelle et DNS 192.168.10.254, Fedora .10, Debian .20,
DHCP .100 à .150, domaine local `lab.local`.

## Sécurité du dépôt
Aucun mot de passe, clé, jeton ni donnée personnelle n'est présent dans ce dépôt.
Les adresses utilisées sont des adresses privées de laboratoire (RFC 1918).

## Limites connues (configuration de base, pas un durcissement complet)
- SSH : l'authentification par mot de passe reste autorisée sur les serveurs.
- Pas d'auditd ni de journalisation centralisée.
- Cockpit (Fedora) accessible depuis tout le LAN.
- Docker en configuration par défaut (pas de userns, pas de limites de ressources, images non épinglées par empreinte).
- nginx sans en-têtes de sécurité ni limitation de débit ; AC de laboratoire stockée sur srv-debian.
Ces points font partie des grilles d'audit et sont traités dans la phase de remédiation.
