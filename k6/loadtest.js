import http from 'k6/http';
import { check } from 'k6';
import { randomIntBetween, randomItem } from 'https://jslib.k6.io/k6-utils/1.2.0/index.js';

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8000';

// Bounded label cardinality for /hello/{name} — keeps Prometheus happy
// while still producing variation in route labels / span attributes.
const NAMES = ['alice', 'bob', 'carol', 'dave', 'eve', 'frank', 'grace', 'heidi'];

export const options = {
  // Three overlapping arrival-rate scenarios drive RPS independently of VU count,
  // which keeps the request rate predictable and lets latency/availability move
  // on their own merits when the service degrades.
  scenarios: {
    // 36-minute baseline cycle: solid traffic from t=0 so the opening incident
    // has a meaningful denominator, then diurnal shape across the recovery.
    baseline: {
      executor: 'ramping-arrival-rate',
      startRate: 30,
      timeUnit: '1s',
      preAllocatedVUs: 20,
      maxVUs: 100,
      stages: [
        { target: 30, duration: '2m' },   // 0–2m    flat through incident window
        { target: 45, duration: '6m' },   // 2–8m    peak 1
        { target: 25, duration: '6m' },   // 8–14m   dip
        { target: 40, duration: '6m' },   // 14–20m  peak 2
        { target: 20, duration: '10m' },  // 20–30m  wind down
        { target: 10, duration: '6m' },   // 30–36m  tail
      ],
      exec: 'baseline',
    },

    // 5-minute incident at the start of the cycle with varying error rates,
    // then silent for 31m so the SLO budget recovers.
    error_burst: {
      executor: 'ramping-arrival-rate',
      startRate: 0,
      timeUnit: '1s',
      preAllocatedVUs: 5,
      maxVUs: 30,
      stages: [
        { target: 5,  duration: '30s' },  // 00:00  mild bump (warning level)
        { target: 15, duration: '60s' },  // 00:30  escalation to heavy errors
        { target: 15, duration: '60s' },  // 01:30  sustained peak
        { target: 8,  duration: '60s' },  // 02:30  partial recovery
        { target: 3,  duration: '60s' },  // 03:30  cooling
        { target: 0,  duration: '30s' },  // 04:30  clear
        { target: 0,  duration: '31m' },  // 05:00  recovery window — SLO drains alerts
      ],
      exec: 'errorBurst',
    },

    // Latency spike lags errors by 30s — overlaps the worst of the brownout.
    latency_spike: {
      executor: 'ramping-arrival-rate',
      startRate: 0,
      timeUnit: '1s',
      preAllocatedVUs: 5,
      maxVUs: 30,
      stages: [
        { target: 0, duration: '30s' },   // 00:00  lag behind error burst
        { target: 3, duration: '30s' },   // 00:30  early latency creep
        { target: 8, duration: '60s' },   // 01:00  worsening
        { target: 8, duration: '60s' },   // 02:00  peak
        { target: 4, duration: '60s' },   // 03:00  easing
        { target: 0, duration: '30s' },   // 04:00  clearing
        { target: 0, duration: '31m' },   // 04:30  silent — recovery
      ],
      exec: 'latencySpike',
    },
  },

  // SLO-style thresholds, sliced by the tags below. /fail is excluded on purpose
  // — its 5xx are synthetic and shouldn't burn the user-facing error budget.
  thresholds: {
    'http_req_failed{slo:availability}': ['rate<0.01'],
    'http_req_duration{sli:fast}':   ['p(95)<200',  'p(99)<500'],
    'http_req_duration{sli:medium}': ['p(95)<2500', 'p(99)<4000'],
  },
};

function get(path, tags) {
  return http.get(`${BASE_URL}${path}`, { tags, timeout: '10s' });
}

function hitHello() {
  const res = get('/hello', { endpoint: 'hello', sli: 'fast', slo: 'availability' });
  check(res, { 'hello 2xx': (r) => r.status === 200 });
}

function hitHelloName() {
  const name = randomItem(NAMES);
  const res = get(`/hello/${name}`, { endpoint: 'hello_name', sli: 'fast', slo: 'availability', name });
  check(res, { 'hello_name 2xx': (r) => r.status === 200 });
}

function hitWait(ms) {
  const res = get(`/wait?time_ms=${ms}`, { endpoint: 'wait', sli: 'medium', slo: 'availability' });
  check(res, { 'wait 2xx': (r) => r.status === 200 });
}

function hitSyncWait(ms) {
  const res = get(`/sync-wait?time_ms=${ms}`, { endpoint: 'sync_wait', sli: 'slow', slo: 'availability' });
  check(res, { 'sync_wait 2xx': (r) => r.status === 200 });
}

// /fail is intentional traffic — tagged so it doesn't pollute the user-facing SLO.
function hitFail(status, leak = false) {
  const qs = `status_code=${status}${leak ? '&with_mem_leak=1' : ''}`;
  get(`/fail?${qs}`, { endpoint: 'fail', sli: 'error_injection', expected_status: String(status) });
}

function pickWeighted(weights) {
  const total = weights.reduce((a, [, w]) => a + w, 0);
  let r = Math.random() * total;
  for (const [val, w] of weights) {
    if ((r -= w) <= 0) return val;
  }
  return weights[weights.length - 1][0];
}

export function baseline() {
  // No /fail calls here — the 31m baseline window must stay clean so the
  // SLO error budget fully recovers between incident windows.
  const choice = pickWeighted([
    ['hello',      62],
    ['hello_name', 22],
    ['wait_short', 12],
    ['wait_long',   2],
    ['sync_wait',   2],
  ]);
  switch (choice) {
    case 'hello':      return hitHello();
    case 'hello_name': return hitHelloName();
    case 'wait_short': return hitWait(randomIntBetween(50, 300));
    case 'wait_long':  return hitWait(randomIntBetween(800, 2000));
    case 'sync_wait':  return hitSyncWait(randomIntBetween(100, 800));
  }
}

export function errorBurst() {
  const status = randomItem([500, 500, 500, 502, 503, 504, 429]);
  hitFail(status, Math.random() < 0.1);
}

export function latencySpike() {
  if (Math.random() < 0.6) {
    hitWait(randomIntBetween(2500, 5000));
  } else {
    hitSyncWait(randomIntBetween(1000, 2500));
  }
}
