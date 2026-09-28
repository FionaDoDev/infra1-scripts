#!/usr/bin/env bash
# =============================================================================
# 00_creer_vms.sh — Création des 4 VM VirtualBox du schéma infra1
# À lancer sur la MACHINE HÔTE (Linux, macOS, ou Windows via Git Bash avec
# VBoxManage dans le PATH).
# Usage : ./00_creer_vms.sh
# =============================================================================
set -euo pipefail

# --- Chemins des ISO (à adapter) --------------------------------------------
ISO_DIR="${ISO_DIR:-$HOME/ISO}"
ISO_DEBIAN="${ISO_DEBIAN:-$ISO_DIR/debian-netinst-amd64.iso}"
ISO_FEDORA="${ISO_FEDORA:-$ISO_DIR/Fedora-Server-dvd-x86_64-44.iso}"
ISO_ZORIN="${ISO_ZORIN:-$ISO_DIR/Zorin-OS-Core-64-bit.iso}"

BASE="${BASE:-$HOME/VirtualBox VMs}"   # dossier des VM
INTNET="LAN"                           # nom du réseau interne VirtualBox

command -v VBoxManage >/dev/null || { echo "VBoxManage introuvable dans le PATH"; exit 1; }

for iso in "$ISO_DEBIAN" "$ISO_FEDORA" "$ISO_ZORIN"; do
  [[ -f "$iso" ]] || { echo "ISO manquante : $iso (modifier les variables en tête du script)"; exit 1; }
done

# creer_vm NOM OSTYPE CPU RAM_Mo DISQUE_Go VRAM_Mo ISO WAN(oui/non)
creer_vm() {
  local nom=$1 ostype=$2 cpu=$3 ram=$4 disque=$5 vram=$6 iso=$7 wan=$8
  local vdi="$BASE/$nom/$nom.vdi"

  if VBoxManage showvminfo "$nom" >/dev/null 2>&1; then
    echo "[=] $nom existe déjà, ignorée"
    return
  fi

  echo "[+] Création de $nom"
  VBoxManage createvm --name "$nom" --ostype "$ostype" --basefolder "$BASE" --register >/dev/null
  VBoxManage modifyvm "$nom" --cpus "$cpu" --memory "$ram" --vram "$vram" \
    --graphicscontroller vmsvga --boot1 dvd --boot2 disk --boot3 none --boot4 none

  if [[ $wan == "oui" ]]; then
    # Carte 1 = NAT (Internet), carte 2 = réseau interne LAN
    VBoxManage modifyvm "$nom" --nic1 nat --nic2 intnet --intnet2 "$INTNET"
  else
    # Carte unique sur le réseau interne LAN
    VBoxManage modifyvm "$nom" --nic1 intnet --intnet1 "$INTNET"
  fi

  VBoxManage createmedium disk --filename "$vdi" --size $((disque * 1024)) --format VDI >/dev/null
  VBoxManage storagectl "$nom" --name SATA --add sata --controller IntelAhci
  VBoxManage storageattach "$nom" --storagectl SATA --port 0 --device 0 --type hdd --medium "$vdi"
  VBoxManage storageattach "$nom" --storagectl SATA --port 1 --device 0 --type dvddrive --medium "$iso"
}

#         NOM          OSTYPE      CPU  RAM   DISQUE VRAM ISO            WAN
creer_vm  fw           Debian_64   1    1024  10     16   "$ISO_DEBIAN"  oui
creer_vm  srv-fedora   Fedora_64   2    2048  20     16   "$ISO_FEDORA"  non
creer_vm  srv-debian   Debian_64   1    1024  15     16   "$ISO_DEBIAN"  non
creer_vm  pc-zorin     Ubuntu_64   2    4096  25     128  "$ISO_ZORIN"   non

echo
echo "VM prêtes. Ordre d'installation : fw -> srv-fedora / srv-debian -> pc-zorin"
