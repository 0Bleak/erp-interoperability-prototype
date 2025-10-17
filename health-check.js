const https = require('https');
const http = require('http');

const COLORS = {
  RED: '\x1b[31m',
  GREEN: '\x1b[32m',
  YELLOW: '\x1b[33m',
  BLUE: '\x1b[34m',
  RESET: '\x1b[0m'
};

const services = [
  {
    name: 'WagonLits ERP',
    url: 'http://localhost:3001/api/health',
    expectedStatus: 200
  },
  {
    name: 'DevMateriels ERP',
    url: 'http://localhost:3002/api/health',
    expectedStatus: 200
  },
  {
    name: 'ConstructWagons ERP',
    url: 'http://localhost:3003/api/health',
    expectedStatus: 200
  },
  {
    name: 'Prometheus',
    url: 'http://localhost:9090/-/healthy',
    expectedStatus: 200
  },
  {
    name: 'Grafana',
    url: 'http://localhost:3000/api/health',
    expectedStatus: 200
  },
  {
    name: 'Kafka UI',
    url: 'http://localhost:8080',
    expectedStatus: 200
  }
];

function checkHealth(service) {
  return new Promise((resolve) => {
    const url = new URL(service.url);
    const protocol = url.protocol === 'https:' ? https : http;

    const req = protocol.get(service.url, { timeout: 5000 }, (res) => {
      const success = res.statusCode === service.expectedStatus;
      resolve({
        name: service.name,
        url: service.url,
        status: res.statusCode,
        success: success
      });
    });

    req.on('error', (error) => {
      resolve({
        name: service.name,
        url: service.url,
        status: 'ERROR',
        success: false,
        error: error.message
      });
    });

    req.on('timeout', () => {
      req.destroy();
      resolve({
        name: service.name,
        url: service.url,
        status: 'TIMEOUT',
        success: false,
        error: 'Request timeout'
      });
    });
  });
}

async function runHealthChecks() {
  console.log(`${COLORS.BLUE}========================================${COLORS.RESET}`);
  console.log(`${COLORS.BLUE}   ERP SYSTEM HEALTH CHECK${COLORS.RESET}`);
  console.log(`${COLORS.BLUE}========================================${COLORS.RESET}`);
  console.log('');

  const results = [];

  for (const service of services) {
    const result = await checkHealth(service);
    results.push(result);

    const statusColor = result.success ? COLORS.GREEN : COLORS.RED;
    const statusSymbol = result.success ? '✓' : '✗';
    const statusText = result.success ? 'PASS' : 'FAIL';

    console.log(`${statusColor}${statusSymbol}${COLORS.RESET} ${service.name.padEnd(25)} ${statusColor}${statusText}${COLORS.RESET}`);
    
    if (!result.success) {
      console.log(`  ${COLORS.YELLOW}URL:${COLORS.RESET} ${result.url}`);
      console.log(`  ${COLORS.YELLOW}Status:${COLORS.RESET} ${result.status}`);
      if (result.error) {
        console.log(`  ${COLORS.YELLOW}Error:${COLORS.RESET} ${result.error}`);
      }
    }
  }

  console.log('');
  console.log(`${COLORS.BLUE}========================================${COLORS.RESET}`);

  const passed = results.filter(r => r.success).length;
  const failed = results.filter(r => !r.success).length;
  const total = results.length;

  console.log(`${COLORS.BLUE}Results:${COLORS.RESET} ${COLORS.GREEN}${passed} passed${COLORS.RESET}, ${COLORS.RED}${failed} failed${COLORS.RESET}, ${total} total`);
  console.log(`${COLORS.BLUE}========================================${COLORS.RESET}`);
  console.log('');

  if (failed > 0) {
    console.log(`${COLORS.RED} Health check FAILED${COLORS.RESET}`);
    process.exit(1);
  } else {
    console.log(`${COLORS.GREEN} All services are healthy!${COLORS.RESET}`);
    process.exit(0);
  }
}

runHealthChecks().catch((error) => {
  console.error(`${COLORS.RED}Fatal error:${COLORS.RESET}`, error);
  process.exit(1);
});