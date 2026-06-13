#!/bin/bash
set -e

# ============================================================
# Auto-initializing OpenVPN entrypoint for Coolify
# On first run: generates server config, PKI, and client cert
# On subsequent runs: just starts OpenVPN
# Everything is non-interactive (no prompts)
#
# Based on: https://github.com/kylemanna/docker-openvpn
# Base image sets:
#   OPENVPN=/etc/openvpn
#   EASYRSA=/usr/share/easy-rsa
#   EASYRSA_PKI=$OPENVPN/pki
# Scripts: ovpn_genconfig, ovpn_initpki, ovpn_getclient, ovpn_run
# ============================================================

# Non-interactive mode for all easyrsa calls (no prompts)
export EASYRSA_BATCH=1

MARKER="${OPENVPN}/.initialized"
VPN_SERVER_URL="${VPN_SERVER_URL:?VPN_SERVER_URL environment variable is required}"
CLIENT_NAME="${CLIENT_NAME:-coolify}"
VPN_PROTO="${VPN_PROTO:-udp}"
VPN_PORT="${VPN_PORT:-53211}"
VPN_DNS="${VPN_DNS:-1.1.1.1}"

if [ ! -f "$MARKER" ] || [ ! -f "${OPENVPN}/clients/${CLIENT_NAME}.ovpn" ]; then
    if [ -f "$MARKER" ]; then
        echo "==> Client config for ${CLIENT_NAME} not found, reinitializing..."
        rm -f "$MARKER"
    fi
    echo "==> First run detected. Initializing OpenVPN..."

    # Step 1: Generate server configuration
    # ovpn_genconfig sets server listen port from URL, so we use 1194 (default)
    # The external port (VPN_PORT) is only for the client remote line
    # -N enables NAT (iptables MASQUERADE) so clients can reach the internet
    echo "==> Generating server config for ${VPN_PROTO}://${VPN_SERVER_URL}:1194"
    ovpn_genconfig -u "${VPN_PROTO}://${VPN_SERVER_URL}:1194" -N -n "${VPN_DNS}"

    # Step 2: Initialize PKI (CA, DH params, ta.key, server cert, CRL)
    # Sources ovpn_env.sh internally, uses OVPN_CN for server cert
    # 'nopass' = no CA passphrase (required for unattended operation)
    echo "==> Initializing PKI (nopass)..."
    ovpn_initpki nopass

    # Step 3: Generate client certificate
    echo "==> Generating client certificate: ${CLIENT_NAME}"
    easyrsa build-client-full "${CLIENT_NAME}" nopass

    # Step 4: Export combined client config (.ovpn)
    # ovpn_getclient sources ovpn_env.sh for server details
    echo "==> Exporting client config to ${OPENVPN}/clients/${CLIENT_NAME}.ovpn"
    mkdir -p "${OPENVPN}/clients"
    ovpn_getclient "${CLIENT_NAME}" > "${OPENVPN}/clients/${CLIENT_NAME}.ovpn"

    # Patch the client config to use the external port (server listens on 1194
    # internally, but Docker maps VPN_PORT:1194)
    if [ "${VPN_PORT}" != "1194" ]; then
        sed -i "s/remote ${VPN_SERVER_URL} 1194/remote ${VPN_SERVER_URL} ${VPN_PORT}/" \
            "${OPENVPN}/clients/${CLIENT_NAME}.ovpn"
        echo "==> Patched client config: remote port set to ${VPN_PORT}"
    fi

    # Mark as initialized so subsequent starts skip setup
    touch "$MARKER"

    echo "==> Initialization complete!"
    echo "==> Client config: ${OPENVPN}/clients/${CLIENT_NAME}.ovpn"
    echo "==> Retrieve with: docker cp <container>:${OPENVPN}/clients/${CLIENT_NAME}.ovpn ."
else
    echo "==> Already initialized, skipping setup."
fi

# Start OpenVPN server
# ovpn_run: sources ovpn_env.sh, sets up iptables/NAT, exec's openvpn
exec ovpn_run
