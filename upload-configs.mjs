import { existsSync, statSync, readdirSync } from 'fs';
import { execSync } from 'child_process';
import { join } from 'path';

const { FTP_HOST, FTP_USER, FTP_PASS, FTP_PATH, CLIENT_NAME, WG_PEERS, MAX_WAIT } = process.env;

if (!FTP_HOST) { console.error('ERROR: FTP_HOST is required'); process.exit(1); }
if (!FTP_USER) { console.error('ERROR: FTP_USER is required'); process.exit(1); }
if (!FTP_PASS) { console.error('ERROR: FTP_PASS is required'); process.exit(1); }

const ftpBase = `ftp://${FTP_HOST}${FTP_PATH || '/vpn'}/`;
const clientName = CLIENT_NAME || 'my-client';
const wgPeers = parseInt(WG_PEERS || '1', 10);
const maxWait = parseInt(MAX_WAIT || '120', 10);

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
      `curl -s --ftp-create-dirs -T "${localPath}" "${ftpBase}${remotePath}" --user "${FTP_USER}:${FTP_PASS}" --connect-timeout 10 --max-time 30 2>&1`,
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

for (let p = 1; p <= wgPeers; p++) {
  await waitForFile(`/wireguard/peer${p}/peer${p}.conf`, `WireGuard peer${p}`);
}

console.log(`==> Uploading OpenVPN configs to ${ftpBase}openvpn/`);
upload(ovpnFile, `openvpn/${clientName}.ovpn`);

for (let p = 1; p <= wgPeers; p++) {
  const wgDir = `/wireguard/peer${p}`;
  console.log(`==> Uploading WireGuard peer${p} to ${ftpBase}wireguard/`);
  uploadDir(wgDir, 'wireguard');
}

console.log('==> All VPN configs uploaded to FTP');
