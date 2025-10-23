import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  vus: 5,
  duration: '30s',
  thresholds: {
    http_req_failed: ['rate<0.01'],
    http_req_duration: ['p(95)<500'],
  },
};

const baseUrl = __ENV.BASE_URL || 'http://127.0.0.1:80';

export default function () {
  const res = http.get(`${baseUrl}/`);

  check(res, {
    'status is 200': (r) => r.status === 200,
    'response contains varnish marker': (r) => r.body && r.body.includes('hello from varnish backend'),
  });

  sleep(1);
}
