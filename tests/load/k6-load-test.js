import http from 'k6/http';
import { check, sleep } from 'k6';
import { Counter, Rate, Trend } from 'k6/metrics';

// Custom metrics
export const requests = new Counter('ecotrack_requests_total');
export const failureRate = new Rate('ecotrack_failure_rate');
export const responseTime = new Trend('ecotrack_response_time');

// Test configuration
export const options = {
  stages: [
    // Ramp up
    { duration: '2m', target: 10 },   // Ramp up to 10 users over 2 minutes
    { duration: '5m', target: 10 },   // Stay at 10 users for 5 minutes
    { duration: '2m', target: 20 },   // Ramp up to 20 users over 2 minutes
    { duration: '5m', target: 20 },   // Stay at 20 users for 5 minutes
    { duration: '2m', target: 0 },    // Ramp down to 0 users over 2 minutes
  ],
  thresholds: {
    http_req_duration: ['p(95)<500', 'p(99)<1000'],  // 95% of requests should be below 500ms, 99% below 1s
    http_req_failed: ['rate<0.05'],                   // Error rate should be less than 5%
    ecotrack_failure_rate: ['rate<0.05'],            // Custom failure rate should be less than 5%
  },
};

// Base URL configuration
const BASE_URL = __ENV.BASE_URL || 'http://localhost:3000';
const DEMO_URL = __ENV.DEMO_URL || 'http://demo.ecotrack.local';

// Test data
const testItems = [
  { name: 'Solar Panels', value: 500.0, unit: 'kWh' },
  { name: 'Wind Turbine', value: 750.5, unit: 'kWh' },
  { name: 'Hydro Power', value: 300.2, unit: 'kWh' },
  { name: 'Geothermal', value: 200.8, unit: 'kWh' },
  { name: 'Biomass', value: 150.3, unit: 'kWh' },
];

export function setup() {
  // Setup phase - run once before all VUs
  console.log('🚀 Starting EcoTrack Load Test');
  console.log(`Base URL: ${BASE_URL}`);
  console.log(`Demo URL: ${DEMO_URL}`);
  
  // Test if services are available
  const healthCheck = http.get(`${BASE_URL}/health`);
  check(healthCheck, {
    'setup: health check passed': (r) => r.status === 200,
  });
  
  return { baseUrl: BASE_URL, demoUrl: DEMO_URL };
}

export default function (data) {
  const baseUrl = data.baseUrl;
  const demoUrl = data.demoUrl;
  
  // Test scenario weights
  const scenario = Math.random();
  
  if (scenario < 0.3) {
    // 30% - Test health endpoints
    testHealthEndpoints(baseUrl);
  } else if (scenario < 0.6) {
    // 30% - Test API endpoints
    testApiEndpoints(baseUrl);
  } else if (scenario < 0.8) {
    // 20% - Test demo application
    testDemoApplication(demoUrl);
  } else {
    // 20% - Test CRUD operations
    testCrudOperations(baseUrl);
  }
  
  // Random sleep between 1-5 seconds
  sleep(Math.random() * 4 + 1);
}

function testHealthEndpoints(baseUrl) {
  const endpoints = ['/health', '/ready', '/metrics'];
  
  endpoints.forEach(endpoint => {
    const response = http.get(`${baseUrl}${endpoint}`, {
      tags: { name: `health_${endpoint.replace('/', '')}` },
    });
    
    requests.add(1);
    responseTime.add(response.timings.duration);
    
    const success = check(response, {
      [`${endpoint} status is 200`]: (r) => r.status === 200,
      [`${endpoint} response time < 200ms`]: (r) => r.timings.duration < 200,
    });
    
    if (!success) {
      failureRate.add(1);
    } else {
      failureRate.add(0);
    }
  });
}

function testApiEndpoints(baseUrl) {
  // Test service status
  const statusResponse = http.get(`${baseUrl}/api/v1/status`, {
    tags: { name: 'api_status' },
  });
  
  requests.add(1);
  responseTime.add(statusResponse.timings.duration);
  
  const statusSuccess = check(statusResponse, {
    'status endpoint returns 200': (r) => r.status === 200,
    'status endpoint has service field': (r) => r.json().hasOwnProperty('service'),
    'status endpoint response time < 500ms': (r) => r.timings.duration < 500,
  });
  
  if (!statusSuccess) {
    failureRate.add(1);
  } else {
    failureRate.add(0);
  }
  
  // Test items listing
  const itemsResponse = http.get(`${baseUrl}/api/v1/items`, {
    tags: { name: 'api_items_list' },
  });
  
  requests.add(1);
  responseTime.add(itemsResponse.timings.duration);
  
  const itemsSuccess = check(itemsResponse, {
    'items endpoint returns 200': (r) => r.status === 200,
    'items endpoint returns array': (r) => Array.isArray(r.json().data),
    'items endpoint response time < 500ms': (r) => r.timings.duration < 500,
  });
  
  if (!itemsSuccess) {
    failureRate.add(1);
  } else {
    failureRate.add(0);
  }
}

function testDemoApplication(demoUrl) {
  const response = http.get(demoUrl, {
    tags: { name: 'demo_app' },
  });
  
  requests.add(1);
  responseTime.add(response.timings.duration);
  
  const success = check(response, {
    'demo app returns 200': (r) => r.status === 200,
    'demo app contains EcoTrack': (r) => r.body.includes('EcoTrack'),
    'demo app response time < 1s': (r) => r.timings.duration < 1000,
  });
  
  if (!success) {
    failureRate.add(1);
  } else {
    failureRate.add(0);
  }
}

function testCrudOperations(baseUrl) {
  // Create a new item
  const randomItem = testItems[Math.floor(Math.random() * testItems.length)];
  const createPayload = JSON.stringify({
    ...randomItem,
    value: randomItem.value + Math.random() * 100, // Add some randomness
  });
  
  const createResponse = http.post(`${baseUrl}/api/v1/items`, createPayload, {
    headers: {
      'Content-Type': 'application/json',
    },
    tags: { name: 'api_items_create' },
  });
  
  requests.add(1);
  responseTime.add(createResponse.timings.duration);
  
  const createSuccess = check(createResponse, {
    'create item returns 201': (r) => r.status === 201,
    'create item returns success': (r) => r.json().success === true,
    'create item has data': (r) => r.json().hasOwnProperty('data'),
    'create item response time < 500ms': (r) => r.timings.duration < 500,
  });
  
  if (!createSuccess) {
    failureRate.add(1);
  } else {
    failureRate.add(0);
  }
  
  // Test invalid create request
  const invalidPayload = JSON.stringify({
    name: 'Invalid Item',
    // Missing required fields: value, unit
  });
  
  const invalidResponse = http.post(`${baseUrl}/api/v1/items`, invalidPayload, {
    headers: {
      'Content-Type': 'application/json',
    },
    tags: { name: 'api_items_create_invalid' },
  });
  
  requests.add(1);
  responseTime.add(invalidResponse.timings.duration);
  
  const invalidSuccess = check(invalidResponse, {
    'invalid create returns 400': (r) => r.status === 400,
    'invalid create returns error': (r) => r.json().success === false,
    'invalid create response time < 500ms': (r) => r.timings.duration < 500,
  });
  
  if (!invalidSuccess) {
    failureRate.add(1);
  } else {
    failureRate.add(0);
  }
}

export function teardown(data) {
  // Teardown phase - run once after all VUs finish
  console.log('🏁 EcoTrack Load Test Complete');
  
  // Optional: Clean up any test data
  // This could include API calls to clean up test items created during the test
}

// Handle different test scenarios based on environment variables
export function handleSummary(data) {
  return {
    'load-test-results.json': JSON.stringify(data, null, 2),
    stdout: textSummary(data, { indent: ' ', enableColors: true }),
  };
}

function textSummary(data, options = {}) {
  const indent = options.indent || '';
  const enableColors = options.enableColors || false;
  
  let summary = '\n';
  summary += `${indent}📊 EcoTrack Load Test Results\n`;
  summary += `${indent}===============================\n\n`;
  
  // Test execution info
  summary += `${indent}Test Duration: ${Math.round(data.state.testRunDurationMs / 1000)}s\n`;
  summary += `${indent}VUs: ${data.options.stages ? 'Variable (staged)' : data.options.vus || 'N/A'}\n`;
  summary += `${indent}Iterations: ${data.metrics.iterations.values.count}\n\n`;
  
  // HTTP metrics
  summary += `${indent}🌐 HTTP Metrics:\n`;
  summary += `${indent}  Total Requests: ${data.metrics.http_reqs ? data.metrics.http_reqs.values.count : 'N/A'}\n`;
  summary += `${indent}  Failed Requests: ${data.metrics.http_req_failed ? Math.round(data.metrics.http_req_failed.values.rate * 100) : 'N/A'}%\n`;
  summary += `${indent}  Avg Response Time: ${data.metrics.http_req_duration ? Math.round(data.metrics.http_req_duration.values.avg) : 'N/A'}ms\n`;
  summary += `${indent}  95th Percentile: ${data.metrics.http_req_duration ? Math.round(data.metrics.http_req_duration.values['p(95)']) : 'N/A'}ms\n`;
  summary += `${indent}  99th Percentile: ${data.metrics.http_req_duration ? Math.round(data.metrics.http_req_duration.values['p(99)']) : 'N/A'}ms\n\n`;
  
  // Custom metrics
  if (data.metrics.ecotrack_requests_total) {
    summary += `${indent}🎯 EcoTrack Metrics:\n`;
    summary += `${indent}  Total EcoTrack Requests: ${data.metrics.ecotrack_requests_total.values.count}\n`;
    summary += `${indent}  EcoTrack Failure Rate: ${Math.round(data.metrics.ecotrack_failure_rate.values.rate * 100)}%\n`;
    summary += `${indent}  Avg EcoTrack Response Time: ${Math.round(data.metrics.ecotrack_response_time.values.avg)}ms\n\n`;
  }
  
  // Thresholds
  summary += `${indent}📋 Threshold Results:\n`;
  Object.keys(data.thresholds || {}).forEach(threshold => {
    const result = data.thresholds[threshold];
    const status = result.ok ? '✅' : '❌';
    summary += `${indent}  ${status} ${threshold}\n`;
  });
  
  // Final status
  const allThresholdsPassed = Object.values(data.thresholds || {}).every(t => t.ok);
  summary += `\n${indent}🎉 Overall Result: ${allThresholdsPassed ? 'PASSED' : 'FAILED'}\n`;
  
  return summary;
}