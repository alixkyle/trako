import crypto from 'node:crypto';

const API_BASE_URL = 'https://api.appstoreconnect.apple.com/v1';
const DEFAULT_BUNDLE_ID = 'com.alixkyle.trako';
const DEFAULT_SUPPORT_URL = 'https://alixkyle.github.io/trako/support.html';
const DEFAULT_PLATFORM = 'MAC_OS';

const requiredEnv = [
  'APP_STORE_CONNECT_API_KEY_ID',
  'APP_STORE_CONNECT_API_ISSUER_ID',
  'APP_STORE_CONNECT_API_KEY_BASE64',
];

const missingEnv = requiredEnv.filter((name) => !process.env[name]);
if (missingEnv.length > 0) {
  throw new Error(`Missing App Store Connect credentials: ${missingEnv.join(', ')}`);
}

const keyId = process.env.APP_STORE_CONNECT_API_KEY_ID;
const issuerId = process.env.APP_STORE_CONNECT_API_ISSUER_ID;
const privateKey = Buffer.from(process.env.APP_STORE_CONNECT_API_KEY_BASE64, 'base64').toString('utf8');
const bundleId = process.env.APP_BUNDLE_ID || DEFAULT_BUNDLE_ID;
const supportUrl = process.env.SUPPORT_URL || DEFAULT_SUPPORT_URL;
const platform = process.env.APP_STORE_PLATFORM || DEFAULT_PLATFORM;
const targetVersionString = process.env.APP_STORE_VERSION_STRING || '';
const dryRun = process.env.DRY_RUN === 'true';

function base64Url(input) {
  return Buffer.from(input)
    .toString('base64')
    .replace(/=/g, '')
    .replace(/\+/g, '-')
    .replace(/\//g, '_');
}

function derToJose(signature, keySize = 32) {
  let offset = 0;
  if (signature[offset++] !== 0x30) {
    throw new Error('Invalid ECDSA signature sequence');
  }

  const sequenceLength = signature[offset++];
  if (sequenceLength + offset !== signature.length) {
    throw new Error('Invalid ECDSA signature length');
  }

  if (signature[offset++] !== 0x02) {
    throw new Error('Invalid ECDSA signature R marker');
  }
  const rLength = signature[offset++];
  let r = signature.subarray(offset, offset + rLength);
  offset += rLength;

  if (signature[offset++] !== 0x02) {
    throw new Error('Invalid ECDSA signature S marker');
  }
  const sLength = signature[offset++];
  let s = signature.subarray(offset, offset + sLength);
  offset += sLength;

  if (r.length > keySize) r = r.subarray(r.length - keySize);
  if (s.length > keySize) s = s.subarray(s.length - keySize);

  const jose = Buffer.alloc(keySize * 2);
  r.copy(jose, keySize - r.length);
  s.copy(jose, keySize * 2 - s.length);
  return base64Url(jose);
}

function createJwt() {
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: 'ES256', kid: keyId, typ: 'JWT' };
  const payload = { iss: issuerId, iat: now, exp: now + 20 * 60, aud: 'appstoreconnect-v1' };
  const signingInput = `${base64Url(JSON.stringify(header))}.${base64Url(JSON.stringify(payload))}`;
  const signature = crypto.sign('sha256', Buffer.from(signingInput), privateKey);
  return `${signingInput}.${derToJose(signature)}`;
}

const jwt = createJwt();

async function appStoreRequest(path, options = {}) {
  const response = await fetch(`${API_BASE_URL}${path}`, {
    ...options,
    headers: {
      Authorization: `Bearer ${jwt}`,
      Accept: 'application/json',
      ...(options.body ? { 'Content-Type': 'application/json' } : {}),
      ...options.headers,
    },
  });

  const body = await response.text();
  if (!response.ok) {
    throw new Error(`App Store Connect API ${response.status} ${response.statusText}: ${body}`);
  }

  return body ? JSON.parse(body) : {};
}

async function getApp() {
  const params = new URLSearchParams({
    'filter[bundleId]': bundleId,
    'fields[apps]': 'name,bundleId',
  });
  const payload = await appStoreRequest(`/apps?${params}`);
  const app = payload.data?.[0];
  if (!app) {
    throw new Error(`No App Store Connect app found for bundle ID ${bundleId}`);
  }
  return app;
}

async function getVersions(appId) {
  const params = new URLSearchParams({
    'filter[platform]': platform,
    'fields[appStoreVersions]': 'platform,versionString,appStoreState',
    limit: '200',
  });
  const payload = await appStoreRequest(`/apps/${appId}/appStoreVersions?${params}`);
  return payload.data || [];
}

function selectVersion(versions) {
  if (targetVersionString) {
    return versions.find((version) => version.attributes?.versionString === targetVersionString);
  }

  const preferredStates = new Set([
    'PREPARE_FOR_SUBMISSION',
    'DEVELOPER_REJECTED',
    'REJECTED',
    'METADATA_REJECTED',
    'WAITING_FOR_REVIEW',
    'IN_REVIEW',
  ]);
  return versions.find((version) => preferredStates.has(version.attributes?.appStoreState)) || versions[0];
}

async function getVersionLocalizations(versionId) {
  const params = new URLSearchParams({
    'fields[appStoreVersionLocalizations]': 'locale,supportUrl',
    limit: '200',
  });
  const payload = await appStoreRequest(`/appStoreVersions/${versionId}/appStoreVersionLocalizations?${params}`);
  return payload.data || [];
}

const app = await getApp();
const versions = await getVersions(app.id);
const version = selectVersion(versions);

if (!version) {
  throw new Error(`No ${platform} App Store version found${targetVersionString ? ` for ${targetVersionString}` : ''}`);
}

const localizations = await getVersionLocalizations(version.id);

if (localizations.length === 0) {
  throw new Error('No version localizations found to update.');
}

console.log(`App: ${app.attributes?.name || app.id}`);
console.log(`Bundle ID: ${bundleId}`);
console.log(`Version: ${version.attributes?.versionString || version.id} (${version.attributes?.appStoreState || 'unknown'})`);
console.log(`Support URL: ${supportUrl}`);
console.log(`Dry run: ${dryRun ? 'yes' : 'no'}`);
console.log('');

let updated = 0;
for (const localization of localizations) {
  const locale = localization.attributes?.locale || localization.id;
  const current = (localization.attributes?.supportUrl || '').trim();
  if (current === supportUrl) {
    console.log(`- ${locale}: already set`);
    continue;
  }

  console.log(`- ${locale}: ${current || '(empty)'} -> ${supportUrl}`);
  if (!dryRun) {
    await appStoreRequest(`/appStoreVersionLocalizations/${localization.id}`, {
      method: 'PATCH',
      body: JSON.stringify({
        data: {
          id: localization.id,
          type: 'appStoreVersionLocalizations',
          attributes: { supportUrl },
        },
      }),
    });
    updated += 1;
  }
}

console.log('');
console.log(dryRun ? 'Dry run complete.' : `Updated ${updated} localization(s).`);
