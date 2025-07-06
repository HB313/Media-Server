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
### Mise à jour du système
### ─────────────────────────────────────────────────────────────
echo "### Mise à jour du système"
dnf update -y

echo "### Installation de Samba, ACL et Firewalld"
dnf install -y samba samba-client samba-common acl firewalld

### ─────────────────────────────────────────────────────────────
### Variables de configuration
### ─────────────────────────────────────────────────────────────
SHARE_DIR="/srv/media"
JUSER="jellyfinuser"
DUSER="downloaderuser"
AUSER="abc"
JUSER_PASS="jellyfinuser"
DUSER_PASS="downloaderuser"
AUSER_PASS="abc"

### ─────────────────────────────────────────────────────────────
### Préparation du répertoire de partage
### ─────────────────────────────────────────────────────────────
echo "### Préparation du dossier de partage"
mkdir -p "${SHARE_DIR}"/{Movies,Series,Torrents}
chown root:root "${SHARE_DIR}"
chmod 2775 "${SHARE_DIR}"

### ─────────────────────────────────────────────────────────────
### Création des utilisateurs système sans shell
### ─────────────────────────────────────────────────────────────
for u in "${JUSER}" "${DUSER}" "${AUSER}"; do
  useradd -M -s /sbin/nologin "$u" || echo "Utilisateur $u déjà existant"
done

### ─────────────────────────────────────────────────────────────
### Configuration des comptes Samba
### ─────────────────────────────────────────────────────────────
echo "### Configuration des comptes Samba"
(echo "${JUSER_PASS}"; echo "${JUSER_PASS}") | smbpasswd -s -a "${JUSER}"
(echo "${DUSER_PASS}"; echo "${DUSER_PASS}") | smbpasswd -s -a "${DUSER}"
(echo "${AUSER_PASS}"; echo "${AUSER_PASS}") | smbpasswd -s -a "${AUSER}"

### ─────────────────────────────────────────────────────────────
### Configuration de Samba
### ─────────────────────────────────────────────────────────────
echo "### Sauvegarde et écriture de smb.conf"
cp /etc/samba/smb.conf /etc/samba/smb.conf.bak

cat > /etc/samba/smb.conf <<EOF
[global]
   interfaces = lo wg0 10.3.1.12/24
   bind interfaces only = yes
   workgroup = WORKGROUP
   server string = NAS via VPN
   security = user
   map to guest = never
   log file = /var/log/samba/log.%m

[Media]
   path = ${SHARE_DIR}
   valid users = ${JUSER},${DUSER},${AUSER}
   read only = no
   write list = ${DUSER},${AUSER}
   browsable = yes
   guest ok = no
   create mask = 0664
   directory mask = 2775
EOF

### ─────────────────────────────────────────────────────────────
### Sécurisation SELinux et ACL
### ─────────────────────────────────────────────────────────────
echo "### Sécurisation SELinux et ACL"
if command -v semanage &>/dev/null; then
  semanage fcontext -a -t samba_share_t "${SHARE_DIR}(/.*)?"
  restorecon -Rv "${SHARE_DIR}"
else
  chcon -t samba_share_t -R "${SHARE_DIR}"
fi

setfacl -R -m u:${JUSER}:rx "${SHARE_DIR}"

### ─────────────────────────────────────────────────────────────
### Configuration du pare-feu
### ─────────────────────────────────────────────────────────────
echo "### Activation de firewalld et ouverture de Samba"
systemctl enable --now firewalld
firewall-cmd --permanent --add-service=samba
firewall-cmd --reload

### ─────────────────────────────────────────────────────────────
### Démarrage du service Samba
### ─────────────────────────────────────────────────────────────
echo "### Démarrage des services Samba"
systemctl enable --now smb nmb

### ─────────────────────────────────────────────────────────────
### Affichage de l’adresse réseau
### ─────────────────────────────────────────────────────────────
IP_ADDR=$(ip -4 addr show "$(ip route get 8.8.8.8 | awk '{print $5}')" \
           | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n1)

echo "✅ Partage Samba accessible à : //${IP_ADDR}/Media"
