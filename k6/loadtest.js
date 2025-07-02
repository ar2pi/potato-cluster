import http from 'k6/http';
import exec from 'k6/execution';
import { sleep, check } from 'k6';
import { randomIntBetween } from 'https://jslib.k6.io/k6-utils/1.2.0/index.js';

export const options = {
  stages: [
    { duration: '5m', target: 4 },
    { duration: '5m', target: 6 },
    { duration: '5m', target: 10 },
    { duration: '5m', target: 16 },
    { duration: '5m', target: 26 },
    { duration: '5m', target: 8 },
  ],
};

function fetch(url) {
  console.log(`Fetching ${url}...`);
  let res = http.get(url, { timeout: '5s' });
  check(res, { 'status is 200': (res) => res.status === 200 });
}

export default function () {
  let randomInt = randomIntBetween(1, 2);
  let randomTimeMs = randomIntBetween(1, 2500);

  const now = new Date();
  const currentMinute = now.getMinutes();

  // fail every 2d minute
  if (currentMinute % 2 === 0) {
    // 50% /fail if vu > 4, else /wait
    if (randomInt === 1) {
      if (exec.instance.vusActive > 4) {
        for (let i = 0; i < exec.instance.vusActive - 4; i++) {
          fetch('http://localhost:8000/fail?with_mem_leak=1');
        }
      } else {
        if (randomTimeMs > 2000) {
          fetch(`http://localhost:8000/sync-wait?time_ms=${randomTimeMs + 1000}`);
        } else {
          fetch(`http://localhost:8000/wait?time_ms=${randomTimeMs + 1000}`);
        }
      }
    }
    // 50% /wait
    if (randomInt === 2) {
      fetch(`http://localhost:8000/wait?time_ms=${randomTimeMs + 2500}`);
    }
  } else {
    // 50% /hello
    if (randomInt === 1) {
      fetch('http://localhost:8000/hello');
    }
    // 50% /wait
    if (randomInt === 2) {
      fetch(`http://localhost:8000/wait?time_ms=${Math.round(randomTimeMs / 100) * 100}`);
    }
  }

  sleep(randomIntBetween(1, 5) / 10);
}
