#!/bin/bash
# Ran by client to generate its own config

if [[ -z $1 ]]; then
  echo "\$1 is not defined. The first argument must be the public key of the server. Exiting."
  exit 1
fi

SERVER_PUBLIC_KEY="${1}"

# keep on generating the client config file
# shellcheck source=wg_vars
source wg_vars

#!/usr/bin/env bash
 
declare -r OLDDIR="$(pwd)"

packages() {
    sudo dnf update -y && sudo dnf upgrade -y
    sudo dnf install wireguard-tools -y
}

wg-gen() {
    cd /etc/wireguard || return
    wg genkey \
        | tee "${CLIENT_PRIVATE_KEY_FILE}" \
        | wg pubkey \
        > "${CLIENT_PUBLIC_KEY_FILE}"
    cd "${OLDDIR}" || return
}

wg-conf() {
    cp template_client.conf "${CONF}" 

    echo "Enter valid IP : "
    read -r CLIENT_VPN_IP

    if [[ ! "${CLIENT_VPN_IP}" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        echo "The IP address given as second argument (${CLIENT_VPN_IP}) is not a valid IPv4 address. Exiting."
        exit 102
    fi

    CLEAN_KEY=$(echo -n "${SERVER_PUBLIC_KEY}" | tr -d '\n\r ')
    CLEAN_KEY=$(echo -n "${CLIENT_PRIVATE_KEY}" | tr -d '\n\r ')

    sed -i "s/<CLIENT_VPN_IP>/${CLIENT_VPN_IP}/" "${CONF}"
    sed -i "s|<CLIENT_PRIVATE_KEY>|${CLIENT_PRIVATE_KEY}|g" "${CONF}"
    sed -i "s/<SERVER_IP>/${SERVER_IP}/" "${CONF}"
    sed -i "s/<SERVER_PORT>/${SERVER_PORT}/" "${CONF}" 
    sed -i "s|<SERVER_PUBLIC_KEY>|${SERVER_PUBLIC_KEY}|g" "${CONF}"
    sed -i "s/<ALLOWED_IPS>/${ALLOWED_IPS}/" "${CONF}"
}


wg-start() {
    wg-quick up "${WIREGUARD_INTERFACE}"
}

# Code
echo "beginning installation"
packages
wg-gen

declare -r CLIENT_PRIVATE_KEY="$(cat "${CLIENT_PRIVATE_KEY_FILE}")"

wg-conf
wg-start

echo "CLIENT_PUBLIC_KEY=$(cat "${CLIENT_PUBLIC_KEY_FILE}")"
