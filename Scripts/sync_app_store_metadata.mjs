import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const API_BASE_URL = 'https://api.appstoreconnect.apple.com/v1';
const DEFAULT_BUNDLE_ID = 'com.alixkyle.trako';
const DEFAULT_PLATFORM = 'MAC_OS';
const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const DEFAULT_COPY_FILE = path.join(SCRIPT_DIR, '../AppStore/app-store-metadata-copy.json');

const LIMITS = {
  subtitle: 30,
  keywords: 100,
  promotionalText: 170,
  description: 4000,
  whatsNew: 4000,
};

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
const platform = process.env.APP_STORE_PLATFORM || DEFAULT_PLATFORM;
const targetVersionString = process.env.APP_STORE_VERSION_STRING || '';
const dryRun = process.env.DRY_RUN === 'true';
const copyFile = process.env.COPY_FILE || DEFAULT_COPY_FILE;
const updateReviewNotes = process.env.UPDATE_REVIEW_NOTES === 'true';
const updateAppInfo = process.env.UPDATE_APP_INFO !== 'false';

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

function normalize(value) {
  return typeof value === 'string' ? value.trim() : '';
}

function assertMaxLength(label, value, max) {
  if (value.length > max) {
    throw new Error(`${label} is ${value.length} characters; Apple allows ${max}.`);
  }
}

function planFieldUpdates(currentValue, nextValue) {
  const current = normalize(currentValue);
  const next = normalize(nextValue);
  if (!next || current === next) {
    return null;
  }
  return next;
}

function loadCopy() {
  const raw = fs.readFileSync(copyFile, 'utf8');
  return JSON.parse(raw);
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

async function getAppInfoLocalizations(appId) {
  const appInfosPayload = await appStoreRequest(`/apps/${appId}/appInfos?limit=200`);
  const records = [];

  for (const appInfo of appInfosPayload.data || []) {
    const params = new URLSearchParams({
      'fields[appInfoLocalizations]': 'locale,subtitle',
      limit: '200',
    });
    const payload = await appStoreRequest(`/appInfos/${appInfo.id}/appInfoLocalizations?${params}`);
    for (const localization of payload.data || []) {
      records.push({ localization });
    }
  }

  return records;
}

async function getVersionLocalizations(versionId) {
  const params = new URLSearchParams({
    'fields[appStoreVersionLocalizations]':
      'description,keywords,locale,marketingUrl,promotionalText,supportUrl,whatsNew',
    limit: '200',
  });
  const payload = await appStoreRequest(`/appStoreVersions/${versionId}/appStoreVersionLocalizations?${params}`);
  return payload.data || [];
}

async function getReviewDetail(versionId) {
  try {
    const params = new URLSearchParams({
      'fields[appStoreReviewDetails]': 'notes',
    });
    const payload = await appStoreRequest(`/appStoreVersions/${versionId}/appStoreReviewDetail?${params}`);
    return payload.data || null;
  } catch (error) {
    if (String(error.message).includes('404')) {
      return null;
    }
    throw error;
  }
}

async function patchResource(path, id, type, attributes) {
  return appStoreRequest(path, {
    method: 'PATCH',
    body: JSON.stringify({
      data: { id, type, attributes },
    }),
  });
}

async function patchVersionLocalization(localizationId, attributes) {
  try {
    await patchResource(
      `/appStoreVersionLocalizations/${localizationId}`,
      localizationId,
      'appStoreVersionLocalizations',
      attributes
    );
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    const blockedWhatsNew =
      attributes.whatsNew &&
      message.includes('409') &&
      message.toLowerCase().includes('whatsnew');
    if (!blockedWhatsNew) {
      throw error;
    }

    const { whatsNew: _skipped, ...remaining } = attributes;
    if (Object.keys(remaining).length === 0) {
      console.log('- warning: whatsNew cannot be edited for this version state; no other fields to apply.');
      return;
    }

    console.log('- warning: whatsNew cannot be edited for this version state; applying other fields only.');
    await patchResource(
      `/appStoreVersionLocalizations/${localizationId}`,
      localizationId,
      'appStoreVersionLocalizations',
      remaining
    );
  }
}

const copy = loadCopy();
const app = await getApp();
const versions = await getVersions(app.id);
const version = selectVersion(versions);

if (!version) {
  throw new Error(`No ${platform} App Store version found${targetVersionString ? ` for ${targetVersionString}` : ''}`);
}

const [appInfoLocalizationRecords, versionLocalizations, reviewDetail] = await Promise.all([
  getAppInfoLocalizations(app.id),
  getVersionLocalizations(version.id),
  getReviewDetail(version.id),
]);

const plannedUpdates = [];

if (updateAppInfo) {
  for (const { localization } of appInfoLocalizationRecords) {
    const locale = localization.attributes?.locale;
    const localeCopy = copy.locales?.[locale];
    const subtitle = localeCopy?.appInfo?.subtitle;
    if (!subtitle) {
      continue;
    }

    assertMaxLength(`Subtitle (${locale})`, subtitle, LIMITS.subtitle);
    const nextSubtitle = planFieldUpdates(localization.attributes?.subtitle, subtitle);
    if (nextSubtitle) {
      plannedUpdates.push({
        kind: 'appInfoLocalization',
        locale,
        field: 'subtitle',
        id: localization.id,
        attributes: { subtitle: nextSubtitle },
      });
    }
  }
}

for (const localization of versionLocalizations) {
  const locale = localization.attributes?.locale;
  const localeCopy = copy.locales?.[locale];
  if (!localeCopy?.version) {
    continue;
  }

  const attrs = localization.attributes || {};
  const versionCopy = {
    ...copy.defaultUrls,
    ...localeCopy.version,
  };

  const fields = [
    ['description', versionCopy.description, LIMITS.description],
    ['keywords', versionCopy.keywords, LIMITS.keywords],
    ['promotionalText', versionCopy.promotionalText, LIMITS.promotionalText],
    ['whatsNew', versionCopy.whatsNew, LIMITS.whatsNew],
    ['supportUrl', versionCopy.supportUrl, null],
    ['marketingUrl', versionCopy.marketingUrl, null],
  ];

  const attributes = {};
  const changedFields = [];
  for (const [field, nextValue, max] of fields) {
    if (nextValue == null || nextValue === '') {
      continue;
    }
    if (max) {
      assertMaxLength(`${field} (${locale})`, nextValue, max);
    }
    const planned = planFieldUpdates(attrs[field], nextValue);
    if (planned) {
      attributes[field] = planned;
      changedFields.push(field);
    }
  }

  if (Object.keys(attributes).length > 0) {
    plannedUpdates.push({
      kind: 'appStoreVersionLocalization',
      locale,
      field: changedFields.join(', '),
      id: localization.id,
      attributes,
    });
  }
}

if (updateReviewNotes && copy.reviewNotes && reviewDetail) {
  const nextNotes = planFieldUpdates(reviewDetail.attributes?.notes, copy.reviewNotes);
  if (nextNotes) {
    plannedUpdates.push({
      kind: 'appStoreReviewDetail',
      locale: 'n/a',
      field: 'notes',
      id: reviewDetail.id,
      attributes: { notes: nextNotes },
    });
  }
}

console.log('# Trako App Store Metadata Sync');
console.log(`App: ${app.attributes?.name || app.id}`);
console.log(`Bundle ID: ${bundleId}`);
console.log(`Version: ${version.attributes?.versionString || version.id} (${version.attributes?.appStoreState || 'unknown'})`);
console.log(`Copy file: ${copyFile}`);
console.log(`Dry run: ${dryRun ? 'yes' : 'no'}`);
console.log('');

if (plannedUpdates.length === 0) {
  console.log('No update needed. App Store Connect already matches the copy file.');
  process.exit(0);
}

for (const update of plannedUpdates) {
  const status = dryRun ? 'would update' : 'updating';
  console.log(`- ${update.kind} ${update.locale} ${update.field}: ${status}`);

  if (!dryRun) {
    if (update.kind === 'appInfoLocalization') {
      await patchResource(
        `/appInfoLocalizations/${update.id}`,
        update.id,
        'appInfoLocalizations',
        update.attributes
      );
    } else if (update.kind === 'appStoreVersionLocalization') {
      await patchVersionLocalization(update.id, update.attributes);
    } else if (update.kind === 'appStoreReviewDetail') {
      await patchResource(
        `/appStoreReviewDetails/${update.id}`,
        update.id,
        'appStoreReviewDetails',
        update.attributes
      );
    }
  }
}

console.log('');
console.log(dryRun ? 'Dry run complete.' : `Applied ${plannedUpdates.length} update(s).`);
