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
| `05_tests.sh` | VM `pc-zorin` | Recette complète avec bilan OK/KO |

## Ordre
1. VMware fermé, dans PowerShell :
   `powershell -ExecutionPolicy Bypass -File .\00_creer_vms_vmware.ps1`
   (les ISO sont cherchées dans Téléchargements ; sinon `-DossierIso "D:\ISO"`).
2. Installer Debian sur `fw` puis lancer `01_pare-feu.sh`. **Toujours en premier** :
   c'est lui qui fournit le DHCP et l'accès Internet aux autres VM.
3. Installer Fedora et Debian serveur (le réseau passe en DHCP pendant l'installation),
   puis lancer `02` et `03` **en console** (l'IP change pendant le script).
4. Installer Zorin OS, lancer `04` puis `05`.

## Récupérer les scripts dans les VM
Le plus simple : pousser ce dossier sur GitHub puis, dans chaque VM :
```bash
git clone https://github.com/<compte>/<depot>.git && cd <depot>
chmod +x *.sh
```
(ou `curl -O` sur l'URL « raw » d'un script si git n'est pas installé).

## Plan d'adressage
LAN 192.168.10.0/24, passerelle et DNS 192.168.10.254, Fedora .10, Debian .20,
DHCP .100 à .150, domaine local `lab.local`.
