import http from 'k6/http';
import { check } from 'k6';

function toInt(value, fallback) {
  const parsed = Number.parseInt(value || '', 10);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function parseCsv(raw) {
  return (raw || '')
    .split(',')
    .map((item) => item.trim())
    .filter(Boolean);
}

function parseMix(raw) {
  const entries = parseCsv(raw)
    .map((item) => {
      const parts = item.split('=');
      return {
        name: (parts[0] || '').trim(),
        percent: toInt(parts[1], 0),
      };
    })
    .filter((entry) => entry.name && entry.percent > 0);

  if (!entries.length) {
    return [{ name: 'catalog', percent: 100 }];
  }

  return entries;
}

function allocate(total, entries) {
  const weights = entries.map((entry) => ({
    name: entry.name,
    percent: entry.percent,
    exact: (total * entry.percent) / 100,
  }));
  const result = {};
  let assigned = 0;

  for (const entry of weights) {
    const base = Math.floor(entry.exact);
    result[entry.name] = base;
    assigned += base;
  }

  let remaining = total - assigned;
  weights
    .sort((a, b) => (b.exact - Math.floor(b.exact)) - (a.exact - Math.floor(a.exact)))
    .forEach((entry) => {
      if (remaining > 0) {
        result[entry.name] += 1;
        remaining -= 1;
      }
    });

  return result;
}

function parseStages(raw) {
  return parseCsv(raw).map((item) => {
    const parts = item.split(':');
    return {
      target: toInt(parts[0], 0),
      duration: parts[1] || '1m',
    };
  });
}

function loadDataset() {
  const path = __ENV.STRESS_DATASET_FILE || '';

  if (!path) {
    return [];
  }

  try {
    return open(path)
      .split('\n')
      .map((line) => line.trim())
      .filter(Boolean);
  } catch (_error) {
    return [];
  }
}

function buildScenarios(entries) {
  const executor = __ENV.STRESS_EXECUTOR || 'constant-arrival-rate';
  const timeUnit = __ENV.STRESS_TIME_UNIT || '1m';
  const baseRate = toInt(__ENV.STRESS_RATE, 60);
  const preAllocatedVUs = toInt(__ENV.STRESS_PRE_ALLOCATED_VUS, 10);
  const maxVUs = toInt(__ENV.STRESS_MAX_VUS, preAllocatedVUs);
  const duration = __ENV.STRESS_DURATION || '1m';
  const stages = parseStages(__ENV.STRESS_STAGES);
  const rateMix = allocate(baseRate, entries);
  const preVuMix = allocate(preAllocatedVUs, entries);
  const maxVuMix = allocate(maxVUs, entries);
  const scenarios = {};

  for (const entry of entries) {
    const name = entry.name;
    const scenario = {
      executor,
      exec: name,
      tags: {
        profile: __ENV.STRESS_PROFILE_NAME || 'default',
        type: __ENV.STRESS_TYPE || 'run',
        flow: name,
      },
      timeUnit,
      preAllocatedVUs: Math.max(1, preVuMix[name] || 1),
      maxVUs: Math.max(1, maxVuMix[name] || 1),
    };

    if (executor === 'ramping-arrival-rate') {
      scenario.startRate = rateMix[name] || 0;
      scenario.stages = stages.map((stage) => ({
        target: allocate(stage.target, entries)[name] || 0,
        duration: stage.duration,
      }));
    } else {
      scenario.rate = Math.max(1, rateMix[name] || 1);
      scenario.duration = duration;
    }

    scenarios[name] = scenario;
  }

  return scenarios;
}

const baseUrl = (__ENV.STRESS_BASE_URL || '').replace(/\/+$/, '');
if (!baseUrl) {
  throw new Error('STRESS_BASE_URL is required');
}

const mixEntries = parseMix(__ENV.STRESS_SCENARIOS || 'catalog=100');
const dataset = loadDataset();
const urlOrder = __ENV.STRESS_URL_ORDER || 'random';
const urlRevisitRate = Math.max(1, toInt(__ENV.STRESS_URL_REVISIT_RATE, 1));
let catalogRevisitCurrent = null;
let catalogRevisitRemaining = 0;
let searchRevisitCurrent = null;
let searchRevisitRemaining = 0;
const searchPath = __ENV.STRESS_SEARCH_PATH || '/catalogsearch/result/?q=';
const searchTerms = parseCsv(__ENV.STRESS_SEARCH_TERMS || 'shirt,shoe');
const customerSectionLoadLegacy = (__ENV.STRESS_CUSTOMER_SECTION_LOAD || '0') !== '0';
const customerSectionLoadMode = (__ENV.STRESS_CUSTOMER_SECTION_LOAD_MODE || (customerSectionLoadLegacy ? 'always' : 'never')).trim().toLowerCase();
const customerSectionLoadRatio = Number.parseFloat(__ENV.STRESS_CUSTOMER_SECTION_LOAD_RATIO || '1');
const customerSectionLoadPath = __ENV.STRESS_CUSTOMER_SECTION_LOAD_PATH || '/customer/section/load';

export const options = {
  discardResponseBodies: true,
  scenarios: buildScenarios(mixEntries),
  thresholds: {
    http_req_failed: ['rate<0.05'],
    'http_req_duration{flow:catalog}': ['p(95)<2000'],
    'http_req_duration{flow:search}': ['p(95)<2500'],
  },
};

function pickCatalogUrl() {
  if (catalogRevisitCurrent !== null && catalogRevisitRemaining > 0) {
    catalogRevisitRemaining -= 1;
    return catalogRevisitCurrent;
  }

  if (!dataset.length) {
    catalogRevisitCurrent = `${baseUrl}/`;
  } else if (urlOrder === 'sequential') {
    catalogRevisitCurrent = dataset[__ITER % dataset.length];
  } else {
    catalogRevisitCurrent = dataset[Math.floor(Math.random() * dataset.length)];
  }

  catalogRevisitRemaining = Math.max(0, urlRevisitRate - 1);
  return catalogRevisitCurrent;
}

function pickSearchUrl() {
  if (searchRevisitCurrent !== null && searchRevisitRemaining > 0) {
    searchRevisitRemaining -= 1;
    return searchRevisitCurrent;
  }

  const term = searchTerms.length
    ? searchTerms[Math.floor(Math.random() * searchTerms.length)]
    : 'shirt';
  const separator = searchPath.includes('?') ? '' : '?q=';
  searchRevisitCurrent = `${baseUrl}${searchPath}${separator}${encodeURIComponent(term)}`;
  searchRevisitRemaining = Math.max(0, urlRevisitRate - 1);
  return searchRevisitCurrent;
}

function buildCustomerSectionLoadUrl() {
  if (/^https?:\/\//.test(customerSectionLoadPath)) {
    return customerSectionLoadPath;
  }

  return `${baseUrl}${customerSectionLoadPath.startsWith('/') ? '' : '/'}${customerSectionLoadPath}`;
}

function shouldRunCustomerSectionLoad() {
  if (customerSectionLoadMode === 'never') {
    return false;
  }

  if (customerSectionLoadMode === 'always') {
    return true;
  }

  if (customerSectionLoadMode === 'sampled') {
    if (!Number.isFinite(customerSectionLoadRatio) || customerSectionLoadRatio <= 0) {
      return false;
    }

    if (customerSectionLoadRatio >= 1) {
      return true;
    }

    return Math.random() < customerSectionLoadRatio;
  }

  return false;
}

function doRequest(url, flow, step) {
  const response = http.get(url, {
    tags: {
      profile: __ENV.STRESS_PROFILE_NAME || 'default',
      type: __ENV.STRESS_TYPE || 'run',
      flow,
      step,
    },
  });

  check(response, {
    'status < 400': (res) => res.status < 400,
  });
}

export function catalog() {
  doRequest(pickCatalogUrl(), 'catalog', 'page');

  if (shouldRunCustomerSectionLoad()) {
    doRequest(buildCustomerSectionLoadUrl(), 'catalog-section-load', 'section-load');
  }
}

export function search() {
  doRequest(pickSearchUrl(), 'search', 'page');
}
