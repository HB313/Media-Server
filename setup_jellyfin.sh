#!/usr/bin/env bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Ce script doit être exécuté en tant que root." >&2
  exit 1
fi

if ! id -u jellyfinuser &>/dev/null; then
  groupadd -g 1001 jellyfinuser
  useradd -u 1001 -g jellyfinuser -M -s /sbin/nologin jellyfinuser
  echo "✔ Utilisateur Linux jellyfinuser (UID=1001) créé."
fi

setenforce 0 || true

read -rp "IP de la VM NAS (ex. 192.168.56.128) : " VM2_IP

read -rp "Utilisateur Samba à utiliser pour le montage (ex. jellyfinuser) : " SMB_USER
read -srp "Mot de passe ${SMB_USER} : " SMB_PASS
echo

read -rp "PUID (UID local pour le montage, ex. 1001)   : " PUID
read -rp "PGID (GID local pour le montage, ex. 1001)   : " PGID
echo

echo "### Paramètres sélectionnés :"
echo "  • VM NAS        : ${VM2_IP}"
echo "  • Samba user    : ${SMB_USER}"
echo "  • PUID / PGID   : ${PUID} / ${PGID}"
echo

if ! id -u "${SMB_USER}" &>/dev/null; then
  echo "### Création du groupe ${SMB_USER} (GID=${PGID}) et de l’utilisateur ${SMB_USER} (UID=${PUID})"
  groupadd -g "${PGID}" "${SMB_USER}"
  useradd  -u "${PUID}" -g "${SMB_USER}" -M -s /sbin/nologin "${SMB_USER}"
  echo "✔ Utilisateur système ${SMB_USER} créé."
else
  echo "ℹ️ L’utilisateur système ${SMB_USER} existe déjà, on ne le recrée pas."
fi

echo
echo "### Mise à jour du système et RPM Fusion"
dnf update -y
dnf install -y dnf-plugins-core cifs-utils samba-client
dnf config-manager --set-enabled crb
dnf install -y --nogpgcheck \
  https://mirrors.rpmfusion.org/free/el/rpmfusion-free-release-9.noarch.rpm \
  https://mirrors.rpmfusion.org/nonfree/el/rpmfusion-nonfree-release-9.noarch.rpm
dnf update -y

echo "### Installation Jellyfin & dépendances"
dnf install -y cifs-utils ffmpeg jellyfin

FFMPEG_PATH=$(which ffmpeg)
if [ -n "$FFMPEG_PATH" ] && [ -f /etc/jellyfin/system.xml ]; then
  sed -i 's|<FFmpegPath>.*</FFmpegPath>|<FFmpegPath>'"$FFMPEG_PATH"'</FFmpegPath>|' \
    /etc/jellyfin/system.xml
fi

echo "### Montage du partage NAS"
mkdir -p /mnt/media

cat > /etc/cifs-credentials <<EOF
username=${SMB_USER}
password=${SMB_PASS}
EOF
chmod 600 /etc/cifs-credentials

grep -q "^//${VM2_IP}/Media" /etc/fstab || cat >> /etc/fstab <<EOF
//${VM2_IP}/Media /mnt/media cifs credentials=/etc/cifs-credentials,uid=${PUID},gid=${PGID},iocharset=utf8,vers=3.0 0 0
EOF

systemctl daemon-reload
if mountpoint -q /mnt/media; then
  umount -l /mnt/media || true
fi
mount /mnt/media

echo "### Vérification du montage"
if ! mountpoint -q /mnt/media; then
  echo "Erreur : impossible de monter //${VM2_IP}/Media" >&2
  exit 1
fi

echo "### Activation de Jellyfin"
systemctl enable --now jellyfin

echo "### Configuration du pare‐feu"
for p in 8096/tcp 8920/tcp; do
  firewall-cmd --permanent --add-port=${p}
done
firewall-cmd --reload

IP_HOST=$(hostname -I | awk '{print $2}')
echo "✅ Jellyfin prêt → http://${IP_HOST}:8096"
