#!/usr/bin/env bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Ce script doit être exécuté en tant que root." >&2
  exit 1
fi

setenforce 0 || true

read -rp "IP de la VM NAS (ex. 192.168.56.151) : " VM2_IP
read -rp "Utilisateur Samba (pour le partage) : " SMB_USER
read -srp "Mot de passe pour ${SMB_USER} : " SMB_PASS
echo

read -rp "PUID (UID local pour le montage, ex. 1004) : " PUID
read -rp "PGID (GID local pour le montage, ex. 1004) : " PGID
echo

echo "### Paramètres sélectionnés :"
echo "  • VM NAS     : ${VM2_IP}"
echo "  • SMB user   : ${SMB_USER}"
echo "  • UID / GID  : ${PUID} / ${PGID}"
echo

echo "### Installation des dépendances"
dnf update -y
dnf install -y dnf-plugins-core cifs-utils samba-client

echo "### Ajout du dépôt Docker CE"
dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo

dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

echo "### Activation de Docker"
systemctl enable --now docker

echo "### Montage du partage NAS"
mkdir -p /mnt/media
cat > /etc/cifs-credentials <<EOF
username=${SMB_USER}
password=${SMB_PASS}
EOF
chmod 600 /etc/cifs-credentials

grep -q "^//${VM2_IP}/Media" /etc/fstab || cat >> /etc/fstab <<EOF
//${VM2_IP}/Media /mnt/media cifs credentials=/etc/cifs-credentials,uid=${PUID},gid=${PGID},dir_mode=0777,file_mode=0777,vers=3.0 0 0
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

echo "### Préparation de la DL-stack"
mkdir -p /srv/dl-stack/config/{qbittorrent,sonarr,radarr,prowlarr,jellyseerr}

echo "### Pull des images et démarrage de la stack"
cd /srv/dl-stack
if [ ! -f docker-compose.yml ]; then
  echo "Erreur : docker-compose.yml introuvable dans /srv/dl-stack" >&2
  exit 1
fi

docker-compose pull || docker compose pull
docker-compose up -d    || docker compose up -d

echo "### Ouverture des ports"
for p in 8080/tcp 6881/tcp 6881/udp 8989/tcp 7878/tcp 9696/tcp 5055/tcp; do
  firewall-cmd --permanent --add-port=${p}
done
firewall-cmd --reload

IP_HOST=$(hostname -I | awk '{print $2}')
echo "✅ DL-stack déployée et accessible :"
echo "   • qBittorrent → http://${IP_HOST}:8080"
echo "   • Sonarr      → http://${IP_HOST}:8989"
echo "   • Radarr      → http://${IP_HOST}:7878"
echo "   • Prowlarr    → http://${IP_HOST}:9696"
echo "   • Jellyseerr  → http://${IP_HOST}:5055"
