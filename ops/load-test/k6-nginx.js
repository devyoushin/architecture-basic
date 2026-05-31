import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  stages: [
    { duration: '2m', target: 100 },
    { duration: '5m', target: 500 },
    { duration: '2m', target: 0 },
  ],
  thresholds: {
    http_req_failed: ['rate<0.01'],
    http_req_duration: ['p(95)<500'],
  },
};

const target = __ENV.TARGET_URL || 'https://example.com/';

export default function () {
  const res = http.get(target, {
    headers: {
      'User-Agent': 'k6-architecture-basic',
    },
  });

  check(res, {
    'status is 2xx or 3xx': (r) => r.status >= 200 && r.status < 400,
  });

  sleep(1);
}
