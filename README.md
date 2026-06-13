# VPN Docker (Coolify)

OpenVPN + WireGuard in Docker, designed for Coolify. Everything is automated and idempotent — first boot generates all certs and configs, subsequent boots just start the servers. Client configs get uploaded to FTP automatically.

## Setup

1. Add this repo as a Docker Compose service in Coolify
2. Set environment variables (see below)
3. Deploy

## Environment Variables

**Required:**

- `VPN_SERVER_URL` — your server's public IP or hostname
- `FTP_HOST` — FTP server for uploading client configs
- `FTP_USER` — FTP username
- `FTP_PASS` — FTP password

**Optional:**

- `CLIENT_NAME` — OpenVPN client name (default: `coolify`)
- `VPN_PROTO` — protocol, `udp` or `tcp` (default: `udp`)
- `VPN_PORT` — external port for client config (default: `53211`)
- `VPN_DNS` — DNS pushed to OpenVPN clients (default: `1.1.1.1`)
- `WG_PEERS` — WireGuard peers: number or comma-separated names (default: `coolify`)
- `WG_DNS` — DNS for WireGuard peers (default: `1.1.1.1`)
- `WG_SUBNET` — WireGuard internal subnet (default: `10.13.13.0`)
- `WG_ALLOWED_IPS` — WireGuard allowed IPs (default: `0.0.0.0/0`)
- `FTP_PATH` — FTP upload path (default: `/vpn`)
- `MAX_WAIT` — seconds to wait for configs before failing (default: `120`)
- `TZ` — timezone (default: `UTC`)

## Ports

- `53211/udp` — OpenVPN
- `53212/udp` — WireGuard

## What happens on deploy

First time: the entrypoint generates the PKI, server config, and client certs. A `.initialized` marker is written to the volume so it doesn't repeat. The upload service waits for the configs to appear, then pushes them to FTP under `/vpn/openvpn/` and `/vpn/wireguard/`.

Every time after: servers start immediately, upload service re-uploads the same configs.

Deleting the volume (`docker volume rm openvpn-data` or `wireguard-data`) will trigger a full re-initialization on next deploy.

## Getting client configs manually

If you don't use FTP, you can grab them from the containers:

```bash
# OpenVPN
docker cp openvpn-server:/etc/openvpn/clients/my-client.ovpn .

# WireGuard
docker cp wireguard-server:/config/peer1/peer1.conf .
```

## Based on

- [kylemanna/docker-openvpn](https://github.com/kylemanna/docker-openvpn)
- [linuxserver/wireguard](https://github.com/linuxserver/docker-wireguard)
