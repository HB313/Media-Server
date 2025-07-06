#!/bin/bash
# Append a new [Peer] section to an existing wg server configuration
# Awaits the client public key as first argument

if [[ -z $1 ]]; then
    echo "\$1 is not defined. The first argument must be the public key of the client. Exiting."
    exit 1
fi

if [[ -z $2 ]]; then
    echo "\$2 is not defined. The second argument must be the chosen IP address of the client in the format xxx.xxx.xxx.xxx (without netmask). Exiting."
    exit 2
fi

# Get global variables
# shellcheck source=wg_vars
source wg_vars

if [[ ! -d "${WIREGUARD_CONF_DIR}" ]]; then
    echo "No configuration directory found for Wireguard. Path should exist at ${WIREGUARD_CONF_DIR}."
    exit 3
fi

if [[ ! -f "${CONF}" ]]; then
echo "No configuration file found for interface ${WIREGUARD_INTERFACE}. Config file must be in ${WIREGUARD_CONF_DIR}."
    exit 4
fi

CLIENT_PUBLIC_KEY="${1}"
CLIENT_VPN_IP="${2}"
ALLOWED_IPS="${CLIENT_VPN_IP}/32"

if grep "${CLIENT_PUBLIC_KEY}" "${CONF}" &> /dev/null; then
    echo "A [Peer] section already exists with this public key. Exiting."
    exit 101
fi

if [[ ! "${CLIENT_VPN_IP}" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    echo "The IP address given as second argument (${CLIENT_VPN_IP}) is not a valid IPv4 address. Exiting."
    exit 102
fi

if grep -F "${CLIENT_VPN_IP}" "${CONF}" &> /dev/null; then
    echo "A [Peer] section already exists with this IP address. Exiting."
    exit 103
fi

# echo '' >> "${CONF}"
# echo '[Peer]' >> "${CONF}"
# echo "PublicKey = ${CLIENT_PUBLIC_KEY}" >> "${CONF}"
# echo "AllowedIPs = ${ALLOWED_IPS}" >> "${CONF}"

{
  echo ''
  echo '[Peer]'
  echo "PublicKey = ${CLIENT_PUBLIC_KEY}"
  echo "AllowedIPs = ${ALLOWED_IPS}/32"
} >> "${CONF}"

echo "Data added to files"
