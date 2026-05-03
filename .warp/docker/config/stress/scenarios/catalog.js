import http from 'k6/http';
import { check } from 'k6';

function toInt(value, fallback) {
  const parsed = Number.parseInt(value || '', 10);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function toStages(raw) {
  return (raw || '')
    .split(',')
    .map((item) => item.trim())
    .filter(Boolean)
    .map((item) => {
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

function buildScenario() {
  const executor = __ENV.STRESS_EXECUTOR || 'constant-arrival-rate';
  const timeUnit = __ENV.STRESS_TIME_UNIT || '1m';
  const preAllocatedVUs = toInt(__ENV.STRESS_PRE_ALLOCATED_VUS, 10);
  const maxVUs = toInt(__ENV.STRESS_MAX_VUS, preAllocatedVUs);

  if (executor === 'ramping-arrival-rate') {
    return {
      executor,
      startRate: toInt(__ENV.STRESS_RATE, 0),
      timeUnit,
      preAllocatedVUs,
      maxVUs,
      stages: toStages(__ENV.STRESS_STAGES),
    };
  }

  return {
    executor,
    rate: toInt(__ENV.STRESS_RATE, 60),
    timeUnit,
    duration: __ENV.STRESS_DURATION || '1m',
    preAllocatedVUs,
    maxVUs,
  };
}

const baseUrl = (__ENV.STRESS_BASE_URL || '').replace(/\/+$/, '');
if (!baseUrl) {
  throw new Error('STRESS_BASE_URL is required');
}

const dataset = loadDataset();
const urlOrder = __ENV.STRESS_URL_ORDER || 'random';
const urlRevisitRate = Math.max(1, toInt(__ENV.STRESS_URL_REVISIT_RATE, 1));
let urlRevisitCurrent = null;
let urlRevisitRemaining = 0;
const customerSectionLoadLegacy = (__ENV.STRESS_CUSTOMER_SECTION_LOAD || '0') !== '0';
const customerSectionLoadMode = (__ENV.STRESS_CUSTOMER_SECTION_LOAD_MODE || (customerSectionLoadLegacy ? 'always' : 'never')).trim().toLowerCase();
const customerSectionLoadRatio = Number.parseFloat(__ENV.STRESS_CUSTOMER_SECTION_LOAD_RATIO || '1');
const customerSectionLoadPath = __ENV.STRESS_CUSTOMER_SECTION_LOAD_PATH || '/customer/section/load';

export const options = {
  discardResponseBodies: true,
  scenarios: {
    catalog: buildScenario(),
  },
  thresholds: {
    http_req_failed: ['rate<0.05'],
    http_req_duration: ['p(95)<2000'],
  },
};

function pickUrl() {
  if (urlRevisitCurrent !== null && urlRevisitRemaining > 0) {
    urlRevisitRemaining -= 1;
    return urlRevisitCurrent;
  }

  if (!dataset.length) {
    urlRevisitCurrent = `${baseUrl}/`;
  } else if (urlOrder === 'sequential') {
    urlRevisitCurrent = dataset[__ITER % dataset.length];
  } else {
    urlRevisitCurrent = dataset[Math.floor(Math.random() * dataset.length)];
  }

  urlRevisitRemaining = Math.max(0, urlRevisitRate - 1);
  return urlRevisitCurrent;
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

export default function () {
  doRequest(pickUrl(), 'catalog', 'page');

  if (shouldRunCustomerSectionLoad()) {
    doRequest(buildCustomerSectionLoadUrl(), 'catalog-section-load', 'section-load');
  }
}
