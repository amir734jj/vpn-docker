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
CLIENT_NAME="${CLIENT_NAME:-my-client}"
VPN_PROTO="${VPN_PROTO:-udp}"
VPN_PORT="${VPN_PORT:-53211}"
VPN_DNS="${VPN_DNS:-1.1.1.1}"

if [ ! -f "$MARKER" ]; then
    echo "==> First run detected. Initializing OpenVPN..."

    # Step 1: Generate server configuration
    # Creates $OPENVPN/ovpn_env.sh and $OPENVPN/openvpn.conf
    # -u sets proto://hostname:port (parsed for OVPN_CN, OVPN_PROTO, OVPN_PORT)
    # -n sets DNS pushed to clients
    echo "==> Generating server config for ${VPN_PROTO}://${VPN_SERVER_URL}:${VPN_PORT}"
    ovpn_genconfig -u "${VPN_PROTO}://${VPN_SERVER_URL}:${VPN_PORT}" -n "${VPN_DNS}"

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
