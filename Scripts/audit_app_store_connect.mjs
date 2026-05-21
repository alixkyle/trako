import crypto from 'node:crypto';
import fs from 'node:fs';

const API_BASE_URL = 'https://api.appstoreconnect.apple.com/v1';
const DEFAULT_BUNDLE_ID = 'com.alixkyle.trako';
const DEFAULT_TERMS_URL = '';
const DEFAULT_PRIVACY_URL = '';

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
const platform = process.env.APP_STORE_PLATFORM || 'MAC_OS';
const targetVersionString = process.env.APP_STORE_VERSION_STRING || '';
const termsUrl = process.env.TERMS_URL || DEFAULT_TERMS_URL;
const privacyUrl = process.env.PRIVACY_URL || DEFAULT_PRIVACY_URL;
const warnings = [];

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

  if (r.length > keySize) r = r.subarray(r.length - keySize);
  if (s.length > keySize) s = s.subarray(s.length - keySize);

  const jose = Buffer.alloc(keySize * 2);
  r.copy(jose, keySize - r.length);
  s.copy(jose, keySize * 2 - s.length);
  return base64Url(jose);
}

function createJwt() {
  const now = Math.floor(Date.now() / 1000);
  const header = {
    alg: 'ES256',
    kid: keyId,
    typ: 'JWT',
  };
  const payload = {
    iss: issuerId,
    iat: now,
    exp: now + 20 * 60,
    aud: 'appstoreconnect-v1',
  };

  const signingInput = `${base64Url(JSON.stringify(header))}.${base64Url(JSON.stringify(payload))}`;
  const signature = crypto.sign('sha256', Buffer.from(signingInput), privateKey);
  return `${signingInput}.${derToJose(signature)}`;
}

const jwt = createJwt();

async function appStoreRequest(path) {
  const response = await fetch(`${API_BASE_URL}${path}`, {
    headers: {
      Authorization: `Bearer ${jwt}`,
      Accept: 'application/json',
    },
  });

  const body = await response.text();
  if (!response.ok) {
    throw new Error(`App Store Connect API ${response.status} ${response.statusText}: ${body}`);
  }

  return body ? JSON.parse(body) : {};
}

async function optionalRequest(label, path, fallback) {
  try {
    return await appStoreRequest(path);
  } catch (error) {
    warnings.push(`${label}: ${String(error.message).slice(0, 260)}`);
    return fallback;
  }
}

function includesUrl(value, url) {
  return typeof value === 'string' && value.toLowerCase().includes(url.toLowerCase());
}

function hasText(value) {
  return typeof value === 'string' && value.trim().length > 0;
}

function status(value) {
  return value ? 'OK' : 'MISSING';
}

function truncate(value, length = 140) {
  if (!hasText(value)) return '';
  return value.length > length ? `${value.slice(0, length - 1)}...` : value;
}

function safeText(value) {
  return hasText(value) ? value.replaceAll('|', '\\|').replaceAll('\n', ' ') : 'Not set';
}

function lengthOf(value) {
  return typeof value === 'string' ? value.length : 0;
}

function firstUrl(value) {
  const match = typeof value === 'string' ? value.match(/https?:\/\/\S+/i) : null;
  return match?.[0]?.replace(/[),.;]+$/, '') || '';
}

async function getApp() {
  const params = new URLSearchParams({
    'filter[bundleId]': bundleId,
    'fields[apps]':
      'name,bundleId,primaryLocale,sku,subscriptionStatusUrl,subscriptionStatusUrlVersion,subscriptionStatusUrlForSandbox,subscriptionStatusUrlVersionForSandbox,contentRightsDeclaration',
  });
  const payload = await appStoreRequest(`/apps?${params}`);
  const app = payload.data?.[0];
  if (!app) {
    throw new Error(`No App Store Connect app found for bundle ID ${bundleId}`);
  }
  return app;
}

async function getAppInfos(appId) {
  const payload = await optionalRequest('App infos', `/apps/${appId}/appInfos?limit=200`, { data: [] });
  return payload.data || [];
}

async function getAppInfoLocalizations(appInfos) {
  const localizations = [];
  for (const appInfo of appInfos) {
    const params = new URLSearchParams({
      'fields[appInfoLocalizations]': 'locale,name,subtitle,privacyPolicyUrl,privacyChoicesUrl,privacyPolicyText',
      limit: '200',
    });
    const payload = await optionalRequest(
      `App info localizations for ${appInfo.id}`,
      `/appInfos/${appInfo.id}/appInfoLocalizations?${params}`,
      { data: [] }
    );
    localizations.push(...(payload.data || []));
  }
  return localizations;
}

async function getVersions(appId) {
  const params = new URLSearchParams({
    'filter[platform]': platform,
    'fields[appStoreVersions]':
      'platform,versionString,appStoreState,appVersionState,copyright,reviewType,releaseType,earliestReleaseDate,usesIdfa,downloadable,createdDate',
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
    'fields[appStoreVersionLocalizations]':
      'description,keywords,locale,marketingUrl,promotionalText,supportUrl,whatsNew',
    limit: '200',
  });
  const payload = await optionalRequest(
    `Version localizations for ${versionId}`,
    `/appStoreVersions/${versionId}/appStoreVersionLocalizations?${params}`,
    { data: [] }
  );
  return payload.data || [];
}

async function getReviewDetail(versionId) {
  const params = new URLSearchParams({
    'fields[appStoreReviewDetails]':
      'contactFirstName,contactLastName,contactPhone,contactEmail,demoAccountName,demoAccountRequired,notes',
  });
  const payload = await optionalRequest(
    `Review detail for ${versionId}`,
    `/appStoreVersions/${versionId}/appStoreReviewDetail?${params}`,
    { data: null }
  );
  return payload.data || null;
}

async function getEndUserLicenseAgreement(appId) {
  const params = new URLSearchParams({
    'fields[endUserLicenseAgreements]': 'agreementText',
  });
  const payload = await optionalRequest(
    'End user license agreement',
    `/apps/${appId}/endUserLicenseAgreement?${params}`,
    { data: null }
  );
  return payload.data || null;
}

async function getSubscriptionGroups(appId) {
  const params = new URLSearchParams({
    'fields[subscriptionGroups]': 'referenceName',
    limit: '200',
  });
  const payload = await optionalRequest('Subscription groups', `/apps/${appId}/subscriptionGroups?${params}`, {
    data: [],
  });
  return payload.data || [];
}

async function getSubscriptionGroupLocalizations(groupId) {
  const params = new URLSearchParams({
    'fields[subscriptionGroupLocalizations]': 'locale,name,customAppName',
    limit: '200',
  });
  const payload = await optionalRequest(
    `Subscription group localizations for ${groupId}`,
    `/subscriptionGroups/${groupId}/subscriptionGroupLocalizations?${params}`,
    { data: [] }
  );
  return payload.data || [];
}

async function getSubscriptions(groupId) {
  const params = new URLSearchParams({
    'fields[subscriptions]': 'name,productId,familySharable,state,subscriptionPeriod,reviewNote,groupLevel',
    limit: '200',
  });
  const payload = await optionalRequest(
    `Subscriptions for ${groupId}`,
    `/subscriptionGroups/${groupId}/subscriptions?${params}`,
    { data: [] }
  );
  return payload.data || [];
}

async function getSubscriptionLocalizations(subscriptionId) {
  const params = new URLSearchParams({
    'fields[subscriptionLocalizations]': 'name,locale,description,state',
    limit: '200',
  });
  const payload = await optionalRequest(
    `Subscription localizations for ${subscriptionId}`,
    `/subscriptions/${subscriptionId}/subscriptionLocalizations?${params}`,
    { data: [] }
  );
  return payload.data || [];
}

async function getSubscriptionPrices(subscriptionId) {
  const params = new URLSearchParams({
    'fields[subscriptionPrices]': 'startDate,preserved',
    limit: '50',
  });
  const payload = await optionalRequest(
    `Subscription prices for ${subscriptionId}`,
    `/subscriptions/${subscriptionId}/prices?${params}`,
    { data: [] }
  );
  return payload.data || [];
}

function analyze({
  app,
  appInfoLocalizations,
  versions,
  selectedVersion,
  versionLocalizations,
  reviewDetail,
  eula,
  subscriptionGroups,
  subscriptionDetails,
}) {
  const findings = [];
  const improvements = [];
  const attrs = app.attributes || {};

  const anyTermsInDescription = versionLocalizations.some((localization) =>
    includesUrl(localization.attributes?.description, termsUrl)
  );
  const hasCustomEula = hasText(eula?.attributes?.agreementText);
  const anyPrivacy = appInfoLocalizations.some((localization) =>
    includesUrl(localization.attributes?.privacyPolicyUrl, privacyUrl)
  );

  findings.push(`${status(anyTermsInDescription || hasCustomEula)} Terms/EULA metadata is discoverable.`);
  findings.push(`${status(anyPrivacy)} Privacy Policy metadata is discoverable.`);

  if (!anyTermsInDescription && !hasCustomEula) {
    improvements.push('Add the Terms URL to the App Store description or configure a custom EULA.');
  }

  if (!anyPrivacy) {
    improvements.push('Set the Privacy Policy URL in App Store Connect app info metadata.');
  }

  for (const localization of versionLocalizations) {
    const locale = localization.attributes?.locale || localization.id;
    const description = localization.attributes?.description || '';
    const supportUrl = localization.attributes?.supportUrl;
    const marketingUrl = localization.attributes?.marketingUrl;
    const whatsNew = localization.attributes?.whatsNew;

    if (!hasText(supportUrl)) {
      improvements.push(`Set a support URL for App Store version locale ${locale}.`);
    }
    if (!hasText(marketingUrl)) {
      improvements.push(`Set a marketing URL for App Store version locale ${locale}.`);
    }
    if (lengthOf(description) < 400) {
      improvements.push(`Consider making the ${locale} App Store description fuller; it is ${lengthOf(description)} chars.`);
    }
    if (selectedVersion?.attributes?.appStoreState !== 'READY_FOR_SALE' && !hasText(whatsNew)) {
      improvements.push(`Add "What's New" text for ${locale} before resubmitting this version.`);
    }
  }

  if (!hasText(attrs.subscriptionStatusUrl)) {
    improvements.push('Consider configuring a production subscription status URL if server-side subscription events matter.');
  }
  if (!hasText(attrs.subscriptionStatusUrlForSandbox)) {
    improvements.push('Consider configuring a sandbox subscription status URL for subscription event testing.');
  }
  if (hasText(attrs.subscriptionStatusUrl) && attrs.subscriptionStatusUrlVersion !== 'V2') {
    improvements.push(
      `Production App Store Server Notifications should use Version 2 in App Store Connect (currently ${safeText(attrs.subscriptionStatusUrlVersion) || 'not set'}). The Firebase function name ending in V2 is not the same setting.`
    );
  }
  if (hasText(attrs.subscriptionStatusUrlForSandbox) && attrs.subscriptionStatusUrlVersionForSandbox !== 'V2') {
    improvements.push(
      `Sandbox App Store Server Notifications should use Version 2 in App Store Connect (currently ${safeText(attrs.subscriptionStatusUrlVersionForSandbox) || 'not set'}).`
    );
  }

  const reviewAttrs = reviewDetail?.attributes || {};
  if (reviewDetail) {
    if (!hasText(reviewAttrs.contactEmail) || !hasText(reviewAttrs.contactPhone)) {
      improvements.push('Review contact details look incomplete; App Review may need a reliable email and phone number.');
    }
    if (reviewAttrs.demoAccountRequired && !hasText(reviewAttrs.demoAccountName)) {
      improvements.push('Demo account is marked required, but the demo account name is missing.');
    }
    if (!hasText(reviewAttrs.notes)) {
      improvements.push('Add concise App Review notes explaining Oona Plus/subscriptions and where legal links appear.');
    }
  } else {
    improvements.push('No App Review detail resource was readable for the selected version.');
  }

  if (subscriptionGroups.length === 0) {
    improvements.push('No subscription groups were readable; confirm Oona Plus subscriptions are configured as expected.');
  }

  for (const detail of subscriptionDetails) {
    const subAttrs = detail.subscription.attributes || {};
    if (!hasText(subAttrs.reviewNote)) {
      improvements.push(`Add a review note for subscription ${subAttrs.productId || detail.subscription.id}.`);
    }
    if (detail.localizations.length === 0) {
      improvements.push(`Add subscription localization metadata for ${subAttrs.productId || detail.subscription.id}.`);
    }
    if (detail.prices.length === 0) {
      improvements.push(`No subscription prices were readable for ${subAttrs.productId || detail.subscription.id}; verify pricing is active.`);
    }
  }

  const rejectedVersions = versions.filter((version) =>
    ['REJECTED', 'METADATA_REJECTED', 'DEVELOPER_REJECTED'].includes(version.attributes?.appStoreState)
  );
  if (rejectedVersions.length > 0) {
    findings.push(
      `${rejectedVersions.length} version(s) are in rejected/developer-rejected metadata states: ${rejectedVersions
        .map((version) => version.attributes?.versionString)
        .join(', ')}.`
    );
  }

  return {
    findings,
    improvements: [...new Set(improvements)],
  };
}

function renderReport(data) {
  const {
    app,
    appInfos,
    appInfoLocalizations,
    versions,
    selectedVersion,
    versionLocalizations,
    reviewDetail,
    eula,
    subscriptionGroups,
    subscriptionGroupLocalizations,
    subscriptionDetails,
    findings,
    improvements,
  } = data;

  const appAttrs = app.attributes || {};
  const selectedAttrs = selectedVersion?.attributes || {};
  const reviewAttrs = reviewDetail?.attributes || {};

  const lines = [
    '# App Store Connect Audit',
    '',
    `App: ${appAttrs.name || app.id}`,
    `Bundle ID: ${appAttrs.bundleId || bundleId}`,
    `Primary locale: ${appAttrs.primaryLocale || 'unknown'}`,
    `Platform checked: ${platform}`,
    `Selected version: ${selectedAttrs.versionString || selectedVersion?.id || 'none'}`,
    `Selected version state: ${selectedAttrs.appStoreState || 'unknown'}`,
    '',
    '## Highest Signal',
    '',
    ...(findings.length > 0 ? findings.map((finding) => `- ${finding}`) : ['- No major findings.']),
    '',
    '## Improvements To Consider',
    '',
    ...(improvements.length > 0 ? improvements.map((improvement) => `- ${improvement}`) : ['- Nothing obvious from the readable metadata.']),
    '',
    '## App Info',
    '',
    `- SKU: ${safeText(appAttrs.sku)}`,
    `- Content rights declaration: ${safeText(appAttrs.contentRightsDeclaration)}`,
    `- Production subscription status URL set: ${status(hasText(appAttrs.subscriptionStatusUrl))}`,
    `- Production subscription status URL: ${safeText(appAttrs.subscriptionStatusUrl)}`,
    `- Production notification version: ${safeText(appAttrs.subscriptionStatusUrlVersion) || 'not set'}`,
    `- Sandbox subscription status URL set: ${status(hasText(appAttrs.subscriptionStatusUrlForSandbox))}`,
    `- Sandbox subscription status URL: ${safeText(appAttrs.subscriptionStatusUrlForSandbox)}`,
    `- Sandbox notification version: ${safeText(appAttrs.subscriptionStatusUrlVersionForSandbox) || 'not set'}`,
    `- App info records readable: ${appInfos.length}`,
    '',
    '## App Info Localizations',
    '',
    '| Locale | Name | Subtitle | Privacy URL | Privacy Choices URL |',
    '| --- | --- | --- | --- | --- |',
    ...(appInfoLocalizations.length > 0
      ? appInfoLocalizations.map((localization) => {
          const attrs = localization.attributes || {};
          return `| ${safeText(attrs.locale)} | ${safeText(attrs.name)} | ${safeText(attrs.subtitle)} | ${safeText(attrs.privacyPolicyUrl)} | ${safeText(attrs.privacyChoicesUrl)} |`;
        })
      : ['| None readable | Not set | Not set | Not set | Not set |']),
    '',
    '## Versions',
    '',
    '| Version | State | Review Type | Release Type | Uses IDFA | Created |',
    '| --- | --- | --- | --- | --- | --- |',
    ...(versions.length > 0
      ? versions.map((version) => {
          const attrs = version.attributes || {};
          return `| ${safeText(attrs.versionString)} | ${safeText(attrs.appStoreState)} | ${safeText(attrs.reviewType)} | ${safeText(attrs.releaseType)} | ${safeText(String(attrs.usesIdfa ?? 'unknown'))} | ${safeText(attrs.createdDate)} |`;
        })
      : ['| None readable | Not set | Not set | Not set | Not set | Not set |']),
    '',
    '## Selected Version Localizations',
    '',
    '| Locale | Description | Terms URL | Support URL | Marketing URL | What\'s New |',
    '| --- | --- | --- | --- | --- | --- |',
    ...(versionLocalizations.length > 0
      ? versionLocalizations.map((localization) => {
          const attrs = localization.attributes || {};
          return `| ${safeText(attrs.locale)} | ${lengthOf(attrs.description)} chars: ${safeText(truncate(attrs.description, 80))} | ${status(includesUrl(attrs.description, termsUrl))} | ${safeText(attrs.supportUrl)} | ${safeText(attrs.marketingUrl)} | ${safeText(truncate(attrs.whatsNew, 80))} |`;
        })
      : ['| None readable | Not set | MISSING | Not set | Not set | Not set |']),
    '',
    '## Legal',
    '',
    `- Expected Terms URL: ${termsUrl}`,
    `- Expected Privacy URL: ${privacyUrl}`,
    `- Custom EULA configured: ${status(hasText(eula?.attributes?.agreementText))}`,
    `- First URL in custom EULA: ${safeText(firstUrl(eula?.attributes?.agreementText))}`,
    '',
    '## Review Detail',
    '',
    `- Review detail readable: ${status(Boolean(reviewDetail))}`,
    `- Contact name set: ${status(hasText(reviewAttrs.contactFirstName) || hasText(reviewAttrs.contactLastName))}`,
    `- Contact email set: ${status(hasText(reviewAttrs.contactEmail))}`,
    `- Contact phone set: ${status(hasText(reviewAttrs.contactPhone))}`,
    `- Demo account required: ${safeText(String(reviewAttrs.demoAccountRequired ?? 'unknown'))}`,
    `- Demo account name set: ${status(hasText(reviewAttrs.demoAccountName))}`,
    `- Notes set: ${status(hasText(reviewAttrs.notes))}`,
    '',
    '## Subscription Groups',
    '',
    '| Group | Reference Name | Localizations | Subscriptions |',
    '| --- | --- | --- | --- |',
    ...(subscriptionGroups.length > 0
      ? subscriptionGroups.map((group) => {
          const groupLocalizations = subscriptionGroupLocalizations.filter((item) => item.groupId === group.id);
          const groupSubscriptions = subscriptionDetails.filter((item) => item.groupId === group.id);
          return `| ${group.id} | ${safeText(group.attributes?.referenceName)} | ${groupLocalizations.length} | ${groupSubscriptions.length} |`;
        })
      : ['| None readable | Not set | 0 | 0 |']),
    '',
    '## Subscriptions',
    '',
    '| Product ID | Name | State | Period | Group Level | Family Shareable | Localizations | Prices Readable | Review Note |',
    '| --- | --- | --- | --- | --- | --- | --- | --- | --- |',
    ...(subscriptionDetails.length > 0
      ? subscriptionDetails.map((detail) => {
          const attrs = detail.subscription.attributes || {};
          return `| ${safeText(attrs.productId)} | ${safeText(attrs.name)} | ${safeText(attrs.state)} | ${safeText(attrs.subscriptionPeriod)} | ${safeText(String(attrs.groupLevel ?? 'unknown'))} | ${safeText(String(attrs.familySharable ?? 'unknown'))} | ${detail.localizations.length} | ${detail.prices.length} | ${status(hasText(attrs.reviewNote))} |`;
        })
      : ['| None readable | Not set | Not set | Not set | Not set | Not set | 0 | 0 | MISSING |']),
    '',
    '## Subscription Localizations',
    '',
    '| Product ID | Locale | Display Name | Description | State |',
    '| --- | --- | --- | --- | --- |',
    ...(subscriptionDetails.flatMap((detail) => {
      const productId = detail.subscription.attributes?.productId || detail.subscription.id;
      return detail.localizations.map((localization) => {
        const attrs = localization.attributes || {};
        return `| ${safeText(productId)} | ${safeText(attrs.locale)} | ${safeText(attrs.name)} | ${safeText(attrs.description)} | ${safeText(attrs.state)} |`;
      });
    }).length > 0
      ? subscriptionDetails.flatMap((detail) => {
          const productId = detail.subscription.attributes?.productId || detail.subscription.id;
          return detail.localizations.map((localization) => {
            const attrs = localization.attributes || {};
            return `| ${safeText(productId)} | ${safeText(attrs.locale)} | ${safeText(attrs.name)} | ${safeText(attrs.description)} | ${safeText(attrs.state)} |`;
          });
        })
      : ['| None readable | Not set | Not set | Not set | Not set |']),
    '',
    '## API Warnings',
    '',
    ...(warnings.length > 0 ? warnings.map((warning) => `- ${warning}`) : ['- None']),
    '',
  ];

  return lines.join('\n');
}

const app = await getApp();
const [appInfos, versions, eula, subscriptionGroups] = await Promise.all([
  getAppInfos(app.id),
  getVersions(app.id),
  getEndUserLicenseAgreement(app.id),
  getSubscriptionGroups(app.id),
]);

const selectedVersion = selectVersion(versions);
if (!selectedVersion) {
  throw new Error(`No ${platform} App Store versions found for ${bundleId}`);
}

const [appInfoLocalizations, versionLocalizations, reviewDetail] = await Promise.all([
  getAppInfoLocalizations(appInfos),
  getVersionLocalizations(selectedVersion.id),
  getReviewDetail(selectedVersion.id),
]);

const subscriptionGroupLocalizations = [];
const subscriptionDetails = [];

for (const group of subscriptionGroups) {
  const [groupLocalizations, subscriptions] = await Promise.all([
    getSubscriptionGroupLocalizations(group.id),
    getSubscriptions(group.id),
  ]);
  subscriptionGroupLocalizations.push(...groupLocalizations.map((localization) => ({ ...localization, groupId: group.id })));

  for (const subscription of subscriptions) {
    const [localizations, prices] = await Promise.all([
      getSubscriptionLocalizations(subscription.id),
      getSubscriptionPrices(subscription.id),
    ]);
    subscriptionDetails.push({
      groupId: group.id,
      subscription,
      localizations,
      prices,
    });
  }
}

const analysis = analyze({
  app,
  appInfoLocalizations,
  versions,
  selectedVersion,
  versionLocalizations,
  reviewDetail,
  eula,
  subscriptionGroups,
  subscriptionDetails,
});

const report = renderReport({
  app,
  appInfos,
  appInfoLocalizations,
  versions,
  selectedVersion,
  versionLocalizations,
  reviewDetail,
  eula,
  subscriptionGroups,
  subscriptionGroupLocalizations,
  subscriptionDetails,
  ...analysis,
});

console.log(report);

if (process.env.GITHUB_STEP_SUMMARY) {
  fs.appendFileSync(process.env.GITHUB_STEP_SUMMARY, report);
}
