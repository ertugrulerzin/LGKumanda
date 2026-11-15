#!/usr/bin/env node
// Credentials remain in the existing account directory; never print the token.
// Usage: node scripts/asc.mjs GET '/v1/apps?...'
// Mutations accept a JSON body file as the fourth argument.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';
const team = 'PBY9P5GVFB';
const account = process.env.ASC_ACCOUNT_DIR || path.join(os.homedir(), '.apple', team);
const read = name => fs.readFileSync(path.join(account, name), 'utf8').trim();
const method = (process.argv[2] || 'GET').toUpperCase();
const route = process.argv[3];
if (!route?.startsWith('/v1/') || !['GET','POST','PATCH'].includes(method)) {
  console.error('Usage: node scripts/asc.mjs GET|POST|PATCH /v1/route [body.json]');
  process.exit(2);
}
try {
  const keyId = read('key-id');
  const now = Math.floor(Date.now() / 1000);
  const b64 = value => Buffer.from(JSON.stringify(value)).toString('base64url');
  const head = b64({alg:'ES256', kid:keyId, typ:'JWT'});
  const payload = b64({iss:read('issuer'), iat:now, exp:now+600, aud:'appstoreconnect-v1'});
  const signature = crypto.sign('sha256', Buffer.from(`${head}.${payload}`), {
    key: read(`AuthKey_${keyId}.p8`), dsaEncoding:'ieee-p1363'
  }).toString('base64url');
  const body = process.argv[4] ? JSON.stringify(JSON.parse(fs.readFileSync(process.argv[4], 'utf8'))) : undefined;
  // IPv4 curl avoids intermittent Node TLS connection failures on this network.
  // The token travels through stdin, never command arguments or shell text.
  const config = `header = "Authorization: Bearer ${head}.${payload}.${signature}"\n`
    + (body ? `header = "Content-Type: application/json"\ndata-binary = ${JSON.stringify(body)}\n` : '');
  const args = ['--config', '-', '--ipv4', '--globoff', '--silent', '--show-error',
    '--connect-timeout', '10', '--max-time', '30', '--request', method,
    '--url', `https://api.appstoreconnect.apple.com${route}`, '--write-out', '\n%{http_code}'];
  // Retry only reads; a failed mutation may already have reached Apple.
  if (method === 'GET') args.push('--retry', '2', '--retry-delay', '1');
  const response = spawnSync('curl', args, {input:config, encoding:'utf8', maxBuffer:8*1024*1024});
  if (response.status !== 0) throw new Error(response.stderr || 'App Store Connect request failed');
  const split = response.stdout.lastIndexOf('\n');
  const status = Number(response.stdout.slice(split + 1));
  const text = response.stdout.slice(0, split);
  if (status < 200 || status >= 300) { console.error(`HTTP ${status}\n${text}`); process.exit(1); }
  console.log(text || '{}');
} catch (error) {
  console.error(error.message);
  process.exit(1);
}
