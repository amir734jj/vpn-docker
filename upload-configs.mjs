import { existsSync, statSync, readdirSync } from 'fs';
import { execSync } from 'child_process';
import { join } from 'path';

const { FTP_HOST, FTP_USER, FTP_PASS, FTP_PATH, CLIENT_NAME, WG_PEERS, MAX_WAIT } = process.env;

if (!FTP_HOST) { console.error('ERROR: FTP_HOST is required'); process.exit(1); }
if (!FTP_USER) { console.error('ERROR: FTP_USER is required'); process.exit(1); }
if (!FTP_PASS) { console.error('ERROR: FTP_PASS is required'); process.exit(1); }

const ftpBase = `ftp://${FTP_HOST}${FTP_PATH || '/vpn'}`;
const clientName = CLIENT_NAME || 'coolify';
const wgPeersRaw = WG_PEERS || 'coolify';
const maxWait = parseInt(MAX_WAIT || '120', 10);

// Parse WG_PEERS: if numeric, peers are peer1..peerN; if names, peers are peer_name
function parsePeers(raw) {
  const n = parseInt(raw, 10);
  if (!isNaN(n) && n > 0) {
    return Array.from({ length: n }, (_, i) => `peer${i + 1}`);
  }
  return raw.split(',').map(s => `peer_${s.trim()}`);
}

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

async function waitForFile(path, label) {
  console.log(`==> Waiting for ${label}: ${path}`);
  for (let i = 0; i < maxWait; i++) {
    if (existsSync(path) && statSync(path).size > 0) {
      console.log(`==> Found ${label}`);
      return;
    }
    await sleep(1000);
  }
  console.error(`ERROR: ${label} not found after ${maxWait}s`);
  process.exit(1);
}

function upload(localPath, remotePath) {
  try {
    execSync(
      `curl -s --ftp-create-dirs -T "${localPath}" "${ftpBase}/${remotePath}" --user "${FTP_USER}:${FTP_PASS}" --connect-timeout 10 --max-time 30 2>&1`,
      { stdio: 'pipe' }
    );
    console.log(`Uploaded ${remotePath}`);
  } catch (err) {
    const output = (err.stderr?.toString() || '') + (err.stdout?.toString() || '');
    console.warn(`WARNING: failed to upload ${remotePath} (exit ${err.status})\n${output}`);
  }
}

function uploadDir(localDir, remoteDir) {
  if (!existsSync(localDir)) return;
  for (const file of readdirSync(localDir)) {
    const localPath = join(localDir, file);
    if (!statSync(localPath).isFile()) continue;
    upload(localPath, `${remoteDir}/${file}`);
  }
}

const ovpnFile = `/openvpn/clients/${clientName}.ovpn`;
await waitForFile(ovpnFile, `OpenVPN config (${clientName})`);

const peers = parsePeers(wgPeersRaw);
for (const peer of peers) {
  await waitForFile(`/wireguard/${peer}/${peer}.conf`, `WireGuard ${peer}`);
}

console.log(`==> Uploading OpenVPN config to ${ftpBase}/openvpn/`);
upload(ovpnFile, `openvpn/${clientName}.ovpn`);

for (const peer of peers) {
  const wgDir = `/wireguard/${peer}`;
  console.log(`==> Uploading WireGuard ${peer} to ${ftpBase}/wireguard/`);
  upload(`${wgDir}/${peer}.conf`, `wireguard/${peer}.conf`);
  const qrPath = `${wgDir}/${peer}.png`;
  if (existsSync(qrPath)) {
    upload(qrPath, `wireguard/${peer}.png`);
  }
}

console.log('==> All VPN configs uploaded to FTP');
