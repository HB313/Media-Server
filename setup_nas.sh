#!/usr/bin/env bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Ce script doit être exécuté en tant que root." >&2
  exit 1
fi

read -rp "Nom du premier utilisateur Samba : " JUSER

read -srp "Mot de passe pour ${JUSER} : " JUSER_PASS
echo

read -rp "Nom du second utilisateur Samba : " DUSER

read -srp "Mot de passe pour ${DUSER} : " DUSER_PASS
echo

read -rp "Interfaces Samba (ex. eth0 enp3s0 192.168.1.0/24) : " INTERFACES

read -rp "UID/GID de base [2002] : " BASE_ID
BASE_ID=${BASE_ID:-2002}

echo
echo "Configuration :"
echo "  • Utilisateurs : ${JUSER}, ${DUSER}"
echo "  • UID/GID de base : ${BASE_ID}"
echo "  • Interfaces : ${INTERFACES}"
echo

SHARE_DIR="/srv/media"
BASE_UID=$((BASE_ID))
BASE_GID=$((BASE_ID))

echo "### Mise à jour et installation des paquets requis"
dnf update -y
dnf install -y samba samba-client samba-common acl firewalld

echo "### Création des comptes système"
groupadd -g $((BASE_GID    )) "${JUSER}"   || true
groupadd -g $((BASE_GID+1  )) "${DUSER}"   || true
useradd  -u $((BASE_UID    )) -g "${JUSER}" -M -s /sbin/nologin "${JUSER}"   || true
useradd  -u $((BASE_UID+1  )) -g "${DUSER}" -M -s /sbin/nologin "${DUSER}"   || true

echo "### Configuration des mots de passe Samba"
(echo "${JUSER_PASS}"; echo "${JUSER_PASS}") | smbpasswd -s -a "${JUSER}"
(echo "${DUSER_PASS}"; echo "${DUSER_PASS}") | smbpasswd -s -a "${DUSER}"

echo "### Préparation du dossier de partage (${SHARE_DIR})"
mkdir -p "${SHARE_DIR}"/{movies,tv,downloadscd}
chown root:root "${SHARE_DIR}"
chmod 2775 "${SHARE_DIR}"

echo "### Désactivation temporaire de SELinux"
setenforce 0 || true

echo "### Application des contexts SELinux et ACL"
if command -v semanage &>/dev/null; then
  semanage fcontext -a -t samba_share_t "${SHARE_DIR}(/.*)?"
  restorecon -Rv "${SHARE_DIR}"
else
  chcon -t samba_share_t -R "${SHARE_DIR}"
fi
setfacl -R -m u:${JUSER}:rx,u:${DUSER}:rwx "${SHARE_DIR}"
setfacl -R -d -m u:${JUSER}:rx,u:${DUSER}:rwx "${SHARE_DIR}"

echo "### Activation de firewalld et ouverture de Samba"
systemctl enable --now firewalld
firewall-cmd --permanent --add-service=samba
firewall-cmd --reload

echo "### Écriture de /etc/samba/smb.conf"
cp /etc/samba/smb.conf /etc/samba/smb.conf.bak
cat > /etc/samba/smb.conf <<EOF
[global]
   workgroup = WORKGROUP
   server string = NAS via VPN
   security = user
   map to guest = never
   log file = /var/log/samba/log.%m

   interfaces = ${INTERFACES}
   bind interfaces only = yes

[Media]
   path = ${SHARE_DIR}
   valid users = ${JUSER},${DUSER}
   read only = no
   write list = ${DUSER}
   browsable = yes
   guest ok = no
   create mask = 0664
   directory mask = 2775
EOF

echo "### Démarrage de Samba"
systemctl enable --now smb nmb


echo "✅ Partage Samba accessible à : //${INTERFACES}/Media"
