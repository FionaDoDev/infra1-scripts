<#
.SYNOPSIS
  Crée automatiquement les 4 VM du schéma infra1 dans VMware Workstation (Windows).

.DESCRIPTION
  - trouve VMware Workstation et les ISO (par défaut dans le dossier Téléchargements)
  - crée (ou réutilise) le LAN Segment "LAN" dans les préférences de VMware
  - crée pour chaque VM : dossier, disque virtuel, fichier .vmx (RAM, CPU, cartes réseau, ISO)
  - ouvre les VM dans VMware Workstation (elles apparaissent dans la bibliothèque)

  VM            ISO             RAM    Disque  Carte 1            Carte 2
  fw            Debian          1 Go   10 Go   NAT                LAN Segment "LAN"
  srv-fedora    Fedora Server   2 Go   20 Go   LAN Segment "LAN"  -
  srv-debian    Debian          1 Go   15 Go   LAN Segment "LAN"  -
  pc-zorin      Zorin OS        4 Go   25 Go   LAN Segment "LAN"  -

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\00_creer_vms_vmware.ps1

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\00_creer_vms_vmware.ps1 -DossierIso "D:\ISO"
#>
param(
    [string]$DossierIso = "$env:USERPROFILE\Downloads",
    [string]$IsoDebian  = "",
    [string]$IsoFedora  = "",
    [string]$IsoZorin   = "",
    [string]$DossierVM  = "$env:USERPROFILE\Documents\Virtual Machines",
    [string]$NomSegment = "LAN"
)

$ErrorActionPreference = 'Stop'
$Utf8SansBom = New-Object System.Text.UTF8Encoding($false)

function Info($m)        { Write-Host "[+] $m" -ForegroundColor Green }
function Avertir($m)     { Write-Host "[=] $m" -ForegroundColor Yellow }
function Stop-Erreur($m) { Write-Host "[x] $m" -ForegroundColor Red; exit 1 }

# -----------------------------------------------------------------------------
# 1. Localiser VMware Workstation
# -----------------------------------------------------------------------------
$candidats = @()
$reg = Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\VMware, Inc.\VMware Workstation' -ErrorAction SilentlyContinue
if ($reg -and $reg.InstallPath) { $candidats += $reg.InstallPath }
$candidats += "${env:ProgramFiles(x86)}\VMware\VMware Workstation"
$candidats += "$env:ProgramFiles\VMware\VMware Workstation"

$VMwareDir = $candidats | Where-Object { $_ -and (Test-Path (Join-Path $_ 'vmware-vdiskmanager.exe')) } | Select-Object -First 1
if (-not $VMwareDir) { Stop-Erreur "VMware Workstation introuvable (vmware-vdiskmanager.exe absent)." }
$vdisk     = Join-Path $VMwareDir 'vmware-vdiskmanager.exe'
$vmwareExe = Join-Path $VMwareDir 'vmware.exe'
Info "VMware Workstation : $VMwareDir"

# VMware réécrit ses préférences en se fermant : il doit être fermé pendant le script
if (Get-Process -Name vmware -ErrorAction SilentlyContinue) {
    Stop-Erreur "Fermez VMware Workstation puis relancez le script."
}

# -----------------------------------------------------------------------------
# 2. Trouver les ISO
# -----------------------------------------------------------------------------
function Trouver-Iso($explicite, $motif, $nom) {
    if ($explicite) {
        if (Test-Path -LiteralPath $explicite) { return (Resolve-Path -LiteralPath $explicite).Path }
        Stop-Erreur "ISO $nom introuvable : $explicite"
    }
    $f = Get-ChildItem -Path $DossierIso -Filter $motif -File -ErrorAction SilentlyContinue |
         Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $f) { Stop-Erreur "Aucune ISO $nom ($motif) dans $DossierIso. Utilisez -DossierIso ou -Iso$nom." }
    return $f.FullName
}

$IsoDebian = Trouver-Iso $IsoDebian 'debian-*.iso'       'Debian'
$IsoFedora = Trouver-Iso $IsoFedora 'Fedora-Server*.iso' 'Fedora'
$IsoZorin  = Trouver-Iso $IsoZorin  'Zorin-OS*.iso'      'Zorin'
Info "ISO Debian : $IsoDebian"
Info "ISO Fedora : $IsoFedora"
Info "ISO Zorin  : $IsoZorin"

# -----------------------------------------------------------------------------
# 3. LAN Segment "LAN" (déclaré dans %APPDATA%\VMware\preferences.ini)
# -----------------------------------------------------------------------------
$prefs  = Join-Path $env:APPDATA 'VMware\preferences.ini'
$lignes = @()
if (Test-Path -LiteralPath $prefs) { $lignes = @(Get-Content -LiteralPath $prefs -Encoding UTF8) }

$pvnId = $null
foreach ($l in $lignes) {
    if ($l -match '^pref\.namedPVNs(\d+)\.name\s*=\s*"(.*)"' -and $Matches[2] -eq $NomSegment) {
        $idx = $Matches[1]
        $ligneId = $lignes | Where-Object { $_ -match "^pref\.namedPVNs$idx\.pvnID\s*=" } | Select-Object -First 1
        if ($ligneId -match '"(.+)"') { $pvnId = $Matches[1] }
        break
    }
}

if ($pvnId) {
    Avertir "LAN Segment '$NomSegment' déjà existant, réutilisé"
} else {
    # Identifiant au format VMware : "52 xx xx xx xx xx xx xx-xx xx xx xx xx xx xx xx"
    $octets = New-Object byte[] 16
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($octets)
    $octets[0] = 0x52
    $hex   = $octets | ForEach-Object { $_.ToString('x2') }
    $pvnId = ($hex[0..7] -join ' ') + '-' + ($hex[8..15] -join ' ')

    $count = 0
    $ligneCount = $lignes | Where-Object { $_ -match '^pref\.namedPVNs\.count\s*=' } | Select-Object -First 1
    if ($ligneCount -match '"(\d+)"') { $count = [int]$Matches[1] }

    $lignes = @($lignes | Where-Object { $_ -notmatch '^pref\.namedPVNs\.count\s*=' })
    if ($lignes.Count -eq 0) { $lignes = @('.encoding = "UTF-8"') }
    $lignes += "pref.namedPVNs.count = `"$($count + 1)`""
    $lignes += "pref.namedPVNs$count.name = `"$NomSegment`""
    $lignes += "pref.namedPVNs$count.pvnID = `"$pvnId`""

    New-Item -ItemType Directory -Force -Path (Split-Path $prefs) | Out-Null
    if (Test-Path -LiteralPath $prefs) { Copy-Item -LiteralPath $prefs "$prefs.bak" -Force }
    [IO.File]::WriteAllLines($prefs, [string[]]$lignes, $Utf8SansBom)
    Info "LAN Segment '$NomSegment' créé"
}

# -----------------------------------------------------------------------------
# 4. Création des VM
# -----------------------------------------------------------------------------
$vms = @(
    @{ Nom = 'fw';         Iso = $IsoDebian; GuestOS = 'debian12-64'; Cpu = 1; RamMo = 1024; DisqueGo = 10; Wan = $true;  Bureau = $false },
    @{ Nom = 'srv-fedora'; Iso = $IsoFedora; GuestOS = 'fedora-64';   Cpu = 2; RamMo = 2048; DisqueGo = 20; Wan = $false; Bureau = $false },
    @{ Nom = 'srv-debian'; Iso = $IsoDebian; GuestOS = 'debian12-64'; Cpu = 1; RamMo = 1024; DisqueGo = 15; Wan = $false; Bureau = $false },
    @{ Nom = 'pc-zorin';   Iso = $IsoZorin;  GuestOS = 'ubuntu-64';   Cpu = 2; RamMo = 4096; DisqueGo = 25; Wan = $false; Bureau = $true  }
)

function Nouvelle-VM($vm) {
    $dir  = Join-Path $DossierVM $vm.Nom
    $vmx  = Join-Path $dir "$($vm.Nom).vmx"
    $vmdk = Join-Path $dir "$($vm.Nom).vmdk"

    if (Test-Path -LiteralPath $vmx) { Avertir "$($vm.Nom) existe déjà, ignorée"; return $vmx }

    Info "Création de $($vm.Nom) ($($vm.RamMo) Mo, $($vm.DisqueGo) Go)"
    New-Item -ItemType Directory -Force -Path $dir | Out-Null

    # Disque virtuel extensible (n'occupe que l'espace réellement utilisé)
    & $vdisk -c -s "$($vm.DisqueGo)GB" -a ide -t 0 $vmdk | Out-Null
    if ($LASTEXITCODE -ne 0) { Stop-Erreur "Échec de création du disque de $($vm.Nom)" }

    $l = @(
        '.encoding = "UTF-8"'
        'config.version = "8"'
        'virtualHW.version = "19"'
        "displayName = `"$($vm.Nom)`""
        "guestOS = `"$($vm.GuestOS)`""
        "numvcpus = `"$($vm.Cpu)`""
        "memsize = `"$($vm.RamMo)`""
        'pciBridge0.present = "TRUE"'
        'pciBridge4.present = "TRUE"'
        'pciBridge4.virtualDev = "pcieRootPort"'
        'pciBridge4.functions = "8"'
        'pciBridge5.present = "TRUE"'
        'pciBridge5.virtualDev = "pcieRootPort"'
        'pciBridge5.functions = "8"'
        'pciBridge6.present = "TRUE"'
        'pciBridge6.virtualDev = "pcieRootPort"'
        'pciBridge6.functions = "8"'
        'pciBridge7.present = "TRUE"'
        'pciBridge7.virtualDev = "pcieRootPort"'
        'pciBridge7.functions = "8"'
        'vmci0.present = "TRUE"'
        'hpet0.present = "TRUE"'
        'usb.present = "TRUE"'
        'ehci.present = "TRUE"'
        'sound.present = "FALSE"'
        'floppy0.present = "FALSE"'
        'tools.syncTime = "TRUE"'
        'sata0.present = "TRUE"'
        'sata0:0.present = "TRUE"'
        "sata0:0.fileName = `"$($vm.Nom).vmdk`""
        'sata0:1.present = "TRUE"'
        'sata0:1.deviceType = "cdrom-image"'
        "sata0:1.fileName = `"$($vm.Iso)`""
        'sata0:1.startConnected = "TRUE"'
    )

    # Cartes réseau : fw = NAT + LAN, les autres = LAN uniquement
    $cartes = @(if ($vm.Wan) { 'nat', 'pvn' } else { 'pvn' })
    for ($i = 0; $i -lt $cartes.Count; $i++) {
        $l += "ethernet$i.present = `"TRUE`""
        $l += "ethernet$i.virtualDev = `"e1000`""
        $l += "ethernet$i.addressType = `"generated`""
        $l += "ethernet$i.connectionType = `"$($cartes[$i])`""
        if ($cartes[$i] -eq 'pvn') { $l += "ethernet$i.pvnID = `"$pvnId`"" }
    }

    if ($vm.Bureau) { $l += 'mks.enable3d = "TRUE"' }   # accélération graphique pour Zorin

    [IO.File]::WriteAllLines($vmx, [string[]]$l, $Utf8SansBom)
    return $vmx
}

$fichiersVmx = @()
foreach ($vm in $vms) { $fichiersVmx += Nouvelle-VM $vm }

# -----------------------------------------------------------------------------
# 5. Ouverture dans VMware Workstation (ajout à la bibliothèque)
# -----------------------------------------------------------------------------
Info "Ouverture des VM dans VMware Workstation"
$premier = $true
foreach ($vmx in $fichiersVmx) {
    Start-Process -FilePath $vmwareExe -ArgumentList "`"$vmx`""
    if ($premier) { Start-Sleep -Seconds 6; $premier = $false } else { Start-Sleep -Seconds 2 }
}

Write-Host ""
Info "Terminé. VM créées dans : $DossierVM"
Write-Host "    Ordre d'installation : 1) fw   2) srv-fedora et srv-debian   3) pc-zorin"
Write-Host "    Démarrez fw en premier : il fournit Internet et le DHCP aux autres VM."
