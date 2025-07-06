#!/usr/bin/env bash
set -euo pipefail

### ─────────────────────────────────────────────────────────────
### Vérification des privilèges root
### ─────────────────────────────────────────────────────────────
if [ "$(id -u)" -ne 0 ]; then
  echo "Ce script doit être exécuté en tant que root." >&2
  exit 1
fi

### ─────────────────────────────────────────────────────────────
### Variables à personnaliser
### ─────────────────────────────────────────────────────────────
NAS_IP="10.3.1.10"
SMB_USER="jellyfinuser"
SMB_PASS="jellyfinuser"
CREDENTIALS_FILE="/etc/samba/credentials/jellyfin"

### ─────────────────────────────────────────────────────────────
### Préparation système
### ─────────────────────────────────────────────────────────────
echo "### Mise à jour et préparation du système"
dnf update -y
dnf config-manager --set-enabled crb

echo "### Ajout des dépôts RPM Fusion"
dnf install -y --nogpgcheck \
  https://mirrors.rpmfusion.org/free/el/rpmfusion-free-release-9.noarch.rpm \
  https://mirrors.rpmfusion.org/nonfree/el/rpmfusion-nonfree-release-9.noarch.rpm

dnf update -y

echo "### Installation des paquets Jellyfin et dépendances"
dnf install -y cifs-utils ffmpeg jellyfin

### ─────────────────────────────────────────────────────────────
### Vérification de la disponibilité du NAS
### ─────────────────────────────────────────────────────────────
echo "### Vérification de la disponibilité du NAS (${NAS_IP})"
if ! ping -c1 "${NAS_IP}" &>/dev/null; then
  echo "Erreur : le NAS ${NAS_IP} ne répond pas." >&2
  exit 1
fi

### ─────────────────────────────────────────────────────────────
### Configuration du montage Samba
### ─────────────────────────────────────────────────────────────
echo "### Montage du partage NAS"
mkdir -p /mnt/media
mkdir -p "$(dirname "${CREDENTIALS_FILE}")"
chmod 700 "$(dirname "${CREDENTIALS_FILE}")"

cat > "${CREDENTIALS_FILE}" <<EOF
username=${SMB_USER}
password=${SMB_PASS}
EOF
chmod 600 "${CREDENTIALS_FILE}"

if ! grep -q "://${NAS_IP}/Media" /etc/fstab; then
  echo "//${NAS_IP}/Media /mnt/media cifs credentials=${CREDENTIALS_FILE},uid=1000,gid=1000,iocharset=utf8,vers=3.0 0 0" >> /etc/fstab
fi

mount -a

if mountpoint -q /mnt/media; then
  echo "✅ Montage du NAS réussi."
else
  echo "❌ Échec du montage du NAS." >&2
  exit 1
fi

### ─────────────────────────────────────────────────────────────
### Activation et démarrage de Jellyfin
### ─────────────────────────────────────────────────────────────
echo "### Activation et démarrage de Jellyfin"
systemctl enable --now jellyfin

### ─────────────────────────────────────────────────────────────
### Configuration du pare-feu
### ─────────────────────────────────────────────────────────────
echo "### Ouverture des ports Jellyfin dans le pare-feu"
firewall-cmd --permanent --add-port=8096/tcp
firewall-cmd --permanent --add-port=8920/tcp
firewall-cmd --reload

### ─────────────────────────────────────────────────────────────
### Affichage de l'URL d'accès à Jellyfin
### ─────────────────────────────────────────────────────────────
IP_ADDR=$(ip -4 addr show "$(ip route get 8.8.8.8 | awk '{print $5}')" \
           | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n1)

echo "✅ Jellyfin est prêt à l'adresse : http://${IP_ADDR}:8096"