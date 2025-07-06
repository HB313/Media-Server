#!/usr/bin/env bash
set -euo pipefail

### ─────────────────────────────────────────────────────────────
### Vérification des privilèges root
### ─────────────────────────────────────────────────────────────
if [ "$(id -u)" -ne 0 ]; then
  echo "Ce script doit être exécuté en tant que root." >&2
  exit 1
fi

echo "### Mise à jour du système et installation des dépendances"
dnf update -y
dnf install -y dnf-plugins-core cifs-utils samba-client firewalld

### ─────────────────────────────────────────────────────────────
### Installation de Docker
### ─────────────────────────────────────────────────────────────
echo "### Ajout du dépôt Docker CE"
dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo
dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

echo "### Activation de Docker"
systemctl enable --now docker

### ─────────────────────────────────────────────────────────────
### (Optionnel) Mettre SELinux en permissif temporairement
### ─────────────────────────────────────────────────────────────
setenforce 0 || true

### ─────────────────────────────────────────────────────────────
### Variables de configuration
### ─────────────────────────────────────────────────────────────
NAS_IP="10.3.1.10"
SMB_USER="downloaderuser"
SMB_PASS="downloaderuser"
DL_BASE="/srv/dl-stack"
CREDENTIALS_FILE="/etc/cifs-credentials"

### ─────────────────────────────────────────────────────────────
### Montage du partage Samba
### ─────────────────────────────────────────────────────────────
echo "### Montage du partage NAS"
mkdir -p /mnt/media
cat > "${CREDENTIALS_FILE}" <<EOF
username=${SMB_USER}
password=${SMB_PASS}
EOF
chmod 600 "${CREDENTIALS_FILE}"

if ! grep -q "^//${NAS_IP}/Media" /etc/fstab; then
  echo "//${NAS_IP}/Media /mnt/media cifs credentials=${CREDENTIALS_FILE},uid=1000,gid=1000,dir_mode=0777,file_mode=0777,vers=3.0 0 0" >> /etc/fstab
fi

mount -a

if mountpoint -q /mnt/media; then
  echo "✅ Montage réussi"
else
  echo "❌ Erreur de montage" >&2
  exit 1
fi

### ─────────────────────────────────────────────────────────────
### Préparation de la structure Docker
### ─────────────────────────────────────────────────────────────
echo "### Préparation de la DL-stack"
mkdir -p "${DL_BASE}"/config/{qbittorrent,sonarr,radarr,prowlarr,jellyseerr}
cd "${DL_BASE}"

echo "### Génération de docker-compose.yml"
cat > docker-compose.yml <<'EOF'
version: '3.8'

services:
  qbittorrent:
    image: linuxserver/qbittorrent:latest
    container_name: qbittorrent
    restart: unless-stopped
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Europe/Paris
      - WEBUI_PORT=8080
      - WEBUI_USERNAME=admin
      - WEBUI_PASSWORD=adminadmin
    volumes:
      - ./config/qbittorrent:/config
      - /mnt/media/Torrents:/Torrents
    ports:
      - "8080:8080"
      - "6881:6881"
      - "6881:6881/udp"

  sonarr:
    image: linuxserver/sonarr:latest
    container_name: sonarr
    restart: unless-stopped
    depends_on:
      - qbittorrent
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Europe/Paris
    volumes:
      - ./config/sonarr:/config
      - /mnt/media/Torrents:/Torrents
      - /mnt/media/Series:/Series
    ports:
      - "8989:8989"

  radarr:
    image: linuxserver/radarr:latest
    container_name: radarr
    restart: unless-stopped
    depends_on:
      - qbittorrent
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Europe/Paris
    volumes:
      - ./config/radarr:/config
      - /mnt/media/Torrents:/Torrents
      - /mnt/media/Movies:/Movies
    ports:
      - "7878:7878"

  prowlarr:
    image: linuxserver/prowlarr:latest
    container_name: prowlarr
    restart: unless-stopped
    depends_on:
      - sonarr
      - radarr
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Europe/Paris
    volumes:
      - ./config/prowlarr:/config
    ports:
      - "9696:9696"

  jellyseerr:
    image: fallenbagel/jellyseerr:latest
    container_name: jellyseerr
    restart: unless-stopped
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Europe/Paris
    volumes:
      - ./config/jellyseerr:/config
    ports:
      - "5055:5055"

networks:
  default:
    driver: bridge
EOF

### ─────────────────────────────────────────────────────────────
### Lancement de la stack
### ─────────────────────────────────────────────────────────────
echo "### Lancement des conteneurs Docker"
docker compose up -d

### ─────────────────────────────────────────────────────────────
### Configuration du pare-feu
### ─────────────────────────────────────────────────────────────
echo "### Ouverture des ports dans firewalld"
for port in 8080 6881 8989 7878 9696 5055; do
  firewall-cmd --permanent --add-port=${port}/tcp
done
firewall-cmd --permanent --add-port=6881/udp
firewall-cmd --reload

### ─────────────────────────────────────────────────────────────
### Affichage des URLs de services
### ─────────────────────────────────────────────────────────────
IP_ADDR=$(ip -4 addr show "$(ip route get 8.8.8.8 | awk '{print $5}')" \
           | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n1)

echo "✅ DL-stack déployée :"
echo "   • qBittorrent → http://${IP_ADDR}:8080"
echo "   • Sonarr      → http://${IP_ADDR}:8989"
echo "   • Radarr      → http://${IP_ADDR}:7878"
echo "   • Prowlarr    → http://${IP_ADDR}:9696"
echo "   • Jellyseerr  → http://${IP_ADDR}:5055"
