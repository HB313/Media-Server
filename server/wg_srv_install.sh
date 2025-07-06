#!/usr/bin/env bash

if [[ $(id -u) -ne 0 ]]; then
  echo "This script must be run as root. Exiting."
  exit 1
fi

declare -r OLDDIR="$(pwd)"

# Global configuration
# shellcheck source=wg_vars
source wg_vars

#Launching packages and updating the machine
packages() {
    dnf update -y
    dnf install wireguard-tools -y
}

wg-gen() {
    cd /etc/wireguard || return
    wg genkey \
        | tee "${SERVER_PRIVATE_KEY_FILE}" \
        | wg pubkey \
        > "${SERVER_PUBLIC_KEY_FILE}"
    cd "${OLDDIR}" || return
}

wg-conf() {
    cp template_serv.conf "${CONF}"

    CLEAN_KEY=$(echo -n "${SERVER_PRIVATE_KEY}" | tr -d '\n\r ')

    echo -n "Enter valid IP address : "
    read -r SERVER_VPN_IP
    sed -i "s/<SERVER_VPN_IP>/${SERVER_VPN_IP}/" "${CONF}"
    sed -i "s/<SERVER_PORT>/${SERVER_PORT}/" "${CONF}"
    sed -i "s|<SERVER_PRIVATE_KEY>|${SERVER_PRIVATE_KEY}|g" "${CONF}"
}

firewall() {
    firewall-cmd --permanent --add-port="${SERVER_PORT}/udp" --zone=public
    firewall-cmd --reload
}

wg-start() {
    wg-quick up "${WIREGUARD_INTERFACE}"
}

# Code
echo "beginning installation"
packages
wg-gen

declare -r SERVER_PRIVATE_KEY="$(cat "${SERVER_PRIVATE_KEY_FILE}")"

wg-conf
firewall
wg-start

echo "public key to provide to client: $(cat ${SERVER_PUBLIC_KEY_FILE})"

