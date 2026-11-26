// Нагрузочный тест: постоянная нагрузка (constant-arrival-rate).
//   MODE=cache|nocache  — через кэш (/products/{id}) или напрямую в БД (/products/nocache/{id})
//   RATE=100            — запросов в секунду
//   DURATION=2m         — длительность
//
// Профиль запросов: 80% чтений — "горячие" 20% товаров (закон Парето),
// 95% чтение / 5% запись, ~1% запросов к несуществующим id.
import http from 'k6/http';
import { check } from 'k6';

const BASE = __ENV.BASE_URL || 'http://localhost:8000';
const MODE = __ENV.MODE || 'cache';
const RATE = parseInt(__ENV.RATE || '100');
const DURATION = __ENV.DURATION || '2m';
const N = 10000;
const HOT = N * 0.2;

export const options = {
  scenarios: {
    load: {
      executor: 'constant-arrival-rate',
      rate: RATE, timeUnit: '1s', duration: DURATION,
      preAllocatedVUs: 100, maxVUs: 1000,
    },
  },
  thresholds: {
    http_req_failed:   ['rate<0.02'],
    http_req_duration: ['p(95)<100'],
  },
};

function pickId() {
  const r = Math.random();
  if (r < 0.01) return N + 1 + Math.floor(Math.random() * 1000);  // не существует
  if (r < 0.80) return 1 + Math.floor(Math.random() * HOT);       // hot set
  return 1 + Math.floor(Math.random() * N);                       // cold
}

const params = { timeout: '10s', tags: { name: 'GET /products/{id}' } };

export default function () {
  const id = pickId();
  if (Math.random() < 0.05) {
    const res = http.put(`${BASE}/products/${id}`,
      JSON.stringify({ price: Math.round(Math.random() * 100000) / 100 }),
      { headers: { 'Content-Type': 'application/json' }, timeout: '10s' });
    check(res, { 'put ok/404': (r) => r.status === 200 || r.status === 404 });
  } else {
    const url = MODE === 'nocache' ? `${BASE}/products/nocache/${id}` : `${BASE}/products/${id}`;
    const res = http.get(url, params);
    check(res, { 'get ok/404': (r) => r.status === 200 || r.status === 404 });
  }
}
