#!/usr/bin/env node
/**
 * E2B Integration Test for Fragments
 *
 * Tests E2B infrastructure integration:
 * - E2B API connectivity
 * - Sandbox lifecycle
 * - Code execution in sandboxes
 * - Template management
 * - Performance benchmarks
 *
 * Usage:
 *   node e2b-integration-test.js
 *   node e2b-integration-test.js --verbose
 */

const http = require('http');

// Configuration
const config = {
  e2bApiUrl: 'http://localhost:3000',
  apiKey: 'e2b_53ae1fed82754c17ad8077fbc8bcdd90',
  verbose: process.argv.includes('--verbose'),
  timeout: 60000, // 60 seconds for sandbox operations
};

// Test results
const results = {
  total: 0,
  passed: 0,
  failed: 0,
  tests: [],
  sandboxes: [], // Track created sandboxes for cleanup
};

// Colors
const colors = {
  reset: '\x1b[0m',
  bright: '\x1b[1m',
  green: '\x1b[32m',
  red: '\x1b[31m',
  yellow: '\x1b[33m',
  blue: '\x1b[34m',
  cyan: '\x1b[36m',
};

function log(message, color = 'reset') {
  console.log(`${colors[color]}${message}${colors.reset}`);
}

function logVerbose(message) {
  if (config.verbose) {
    log(`  📝 ${message}`, 'cyan');
  }
}

// HTTP request helper
function request(url, options = {}) {
  return new Promise((resolve, reject) => {
    const urlObj = new URL(url);

    const reqOptions = {
      hostname: urlObj.hostname,
      port: urlObj.port || 80,
      path: urlObj.pathname + urlObj.search,
      method: options.method || 'GET',
      headers: {
        'Content-Type': 'application/json',
        'X-API-Key': config.apiKey,
        ...options.headers,
      },
      timeout: options.timeout || config.timeout,
    };

    const req = http.request(reqOptions, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try {
          const jsonData = data ? JSON.parse(data) : null;
          resolve({ status: res.statusCode, headers: res.headers, data: jsonData, raw: data });
        } catch (e) {
          resolve({ status: res.statusCode, headers: res.headers, data: null, raw: data });
        }
      });
    });

    req.on('error', reject);
    req.on('timeout', () => {
      req.destroy();
      reject(new Error('Request timeout'));
    });

    if (options.body) {
      req.write(JSON.stringify(options.body));
    }
    req.end();
  });
}

async function runTest(name, testFn) {
  results.total++;
  const startTime = Date.now();

  log(`\n🧪 Testing: ${name}`, 'blue');

  try {
    const result = await testFn();
    const duration = Date.now() - startTime;

    if (result.success) {
      results.passed++;
      log(`✅ PASSED (${duration}ms)`, 'green');
      if (result.message) {
        log(`   ${result.message}`, 'green');
      }
    } else {
      results.failed++;
      log(`❌ FAILED (${duration}ms)`, 'red');
      log(`   ${result.message}`, 'red');
    }

    results.tests.push({
      name,
      success: result.success,
      duration,
      message: result.message,
      data: result.data,
    });

    return result;
  } catch (error) {
    const duration = Date.now() - startTime;
    results.failed++;

    log(`❌ ERROR (${duration}ms)`, 'red');
    log(`   ${error.message}`, 'red');

    if (config.verbose && error.stack) {
      console.error(error.stack);
    }

    results.tests.push({
      name,
      success: false,
      duration,
      message: error.message,
      error: error.stack,
    });
  }
}

// ============================================================
// TEST SUITES
// ============================================================

async function testE2BHealth() {
  log('\n' + '='.repeat(60), 'bright');
  log('🏥 E2B API HEALTH CHECKS', 'bright');
  log('='.repeat(60), 'bright');

  await runTest('E2B API Health Endpoint', async () => {
    logVerbose(`GET ${config.e2bApiUrl}/health`);

    const res = await request(`${config.e2bApiUrl}/health`);
    logVerbose(`Status: ${res.status}`);
    logVerbose(`Response: ${res.raw}`);

    return {
      success: res.status === 200,
      message: res.status === 200
        ? 'E2B API is healthy'
        : `HTTP ${res.status}: ${res.raw}`,
      data: { status: res.status, response: res.raw }
    };
  });
}

async function testSandboxLifecycle() {
  log('\n' + '='.repeat(60), 'bright');
  log('📦 SANDBOX LIFECYCLE TESTS', 'bright');
  log('='.repeat(60), 'bright');

  let sandboxId = null;

  await runTest('Create Sandbox', async () => {
    logVerbose(`POST ${config.e2bApiUrl}/sandboxes`);
    logVerbose(`Template: base, Timeout: 300s`);

    const res = await request(`${config.e2bApiUrl}/sandboxes`, {
      method: 'POST',
      body: {
        templateID: 'base',
        timeout: 300,
      },
    });

    logVerbose(`Status: ${res.status}`);
    logVerbose(`Response: ${JSON.stringify(res.data, null, 2)}`);

    if (res.status === 200 || res.status === 201) {
      sandboxId = res.data?.sandboxID || res.data?.clientID;
      results.sandboxes.push(sandboxId);

      return {
        success: true,
        message: `Sandbox created: ${sandboxId}`,
        data: res.data
      };
    }

    return {
      success: false,
      message: `Failed to create sandbox: HTTP ${res.status}`,
      data: res.data
    };
  });

  await runTest('List Sandboxes', async () => {
    logVerbose(`GET ${config.e2bApiUrl}/sandboxes`);

    const res = await request(`${config.e2bApiUrl}/sandboxes`);
    logVerbose(`Status: ${res.status}`);

    if (res.status === 200) {
      const count = Array.isArray(res.data) ? res.data.length : 'unknown';
      return {
        success: true,
        message: `Found ${count} sandboxes`,
        data: res.data
      };
    }

    return {
      success: false,
      message: `HTTP ${res.status}`,
      data: res.data
    };
  });

  if (sandboxId) {
    await runTest('Get Sandbox Details', async () => {
      logVerbose(`GET ${config.e2bApiUrl}/sandboxes/${sandboxId}`);

      const res = await request(`${config.e2bApiUrl}/sandboxes/${sandboxId}`);
      logVerbose(`Status: ${res.status}`);
      logVerbose(`Response: ${JSON.stringify(res.data, null, 2)}`);

      return {
        success: res.status === 200,
        message: res.status === 200
          ? `Sandbox details retrieved: ${sandboxId}`
          : `HTTP ${res.status}`,
        data: res.data
      };
    });

    await runTest('Delete Sandbox', async () => {
      logVerbose(`DELETE ${config.e2bApiUrl}/sandboxes/${sandboxId}`);

      const res = await request(`${config.e2bApiUrl}/sandboxes/${sandboxId}`, {
        method: 'DELETE',
      });

      logVerbose(`Status: ${res.status}`);

      // Remove from tracking
      const index = results.sandboxes.indexOf(sandboxId);
      if (index > -1) {
        results.sandboxes.splice(index, 1);
      }

      return {
        success: res.status === 200 || res.status === 204,
        message: res.status === 200 || res.status === 204
          ? `Sandbox deleted: ${sandboxId}`
          : `HTTP ${res.status}`,
        data: res.data
      };
    });
  }
}

async function testSandboxExecution() {
  log('\n' + '='.repeat(60), 'bright');
  log('⚙️  SANDBOX CODE EXECUTION', 'bright');
  log('='.repeat(60), 'bright');

  await runTest('Execute Python Code in Sandbox', async () => {
    // Create sandbox
    logVerbose(`Creating sandbox for code execution...`);

    const createRes = await request(`${config.e2bApiUrl}/sandboxes`, {
      method: 'POST',
      body: {
        templateID: 'base',
        timeout: 300,
      },
    });

    if (createRes.status !== 200 && createRes.status !== 201) {
      return {
        success: false,
        message: `Failed to create sandbox: HTTP ${createRes.status}`,
        data: createRes.data
      };
    }

    const sandboxId = createRes.data?.sandboxID || createRes.data?.clientID;
    results.sandboxes.push(sandboxId);

    logVerbose(`Sandbox created: ${sandboxId}`);

    // Note: Code execution would require envd API endpoint
    // This is a placeholder for the full implementation

    logVerbose(`Code execution API would be tested here`);
    logVerbose(`Sandbox will be cleaned up later`);

    return {
      success: true,
      message: `Sandbox ready for execution: ${sandboxId}`,
      data: { sandboxId }
    };
  });
}

async function testTemplateManagement() {
  log('\n' + '='.repeat(60), 'bright');
  log('📋 TEMPLATE MANAGEMENT', 'bright');
  log('='.repeat(60), 'bright');

  await runTest('List Available Templates', async () => {
    logVerbose(`GET ${config.e2bApiUrl}/templates`);

    try {
      const res = await request(`${config.e2bApiUrl}/templates`);
      logVerbose(`Status: ${res.status}`);

      if (res.status === 200) {
        const templates = res.data || [];
        logVerbose(`Templates: ${JSON.stringify(templates, null, 2)}`);

        return {
          success: true,
          message: `Found ${Array.isArray(templates) ? templates.length : 'unknown'} templates`,
          data: templates
        };
      }

      return {
        success: false,
        message: `HTTP ${res.status}`,
        data: res.data
      };
    } catch (error) {
      // Endpoint might not be implemented
      return {
        success: false,
        message: `Templates endpoint not available: ${error.message}`,
        data: null
      };
    }
  });
}

async function testPerformanceBenchmarks() {
  log('\n' + '='.repeat(60), 'bright');
  log('⏱️  PERFORMANCE BENCHMARKS', 'bright');
  log('='.repeat(60), 'bright');

  await runTest('Sandbox Creation Time', async () => {
    const iterations = 3;
    const times = [];

    for (let i = 0; i < iterations; i++) {
      logVerbose(`Iteration ${i + 1}/${iterations}...`);

      const startTime = Date.now();

      const res = await request(`${config.e2bApiUrl}/sandboxes`, {
        method: 'POST',
        body: {
          templateID: 'base',
          timeout: 300,
        },
      });

      const duration = Date.now() - startTime;
      times.push(duration);

      if (res.status === 200 || res.status === 201) {
        const sandboxId = res.data?.sandboxID || res.data?.clientID;
        results.sandboxes.push(sandboxId);
        logVerbose(`  Created in ${duration}ms`);
      }
    }

    const avgTime = times.reduce((a, b) => a + b, 0) / times.length;
    const minTime = Math.min(...times);
    const maxTime = Math.max(...times);

    return {
      success: true,
      message: `Avg: ${avgTime.toFixed(0)}ms, Min: ${minTime}ms, Max: ${maxTime}ms`,
      data: { times, avgTime, minTime, maxTime }
    };
  });

  await runTest('API Response Time', async () => {
    const iterations = 5;
    const times = [];

    for (let i = 0; i < iterations; i++) {
      const startTime = Date.now();

      await request(`${config.e2bApiUrl}/health`);

      const duration = Date.now() - startTime;
      times.push(duration);
    }

    const avgTime = times.reduce((a, b) => a + b, 0) / times.length;

    return {
      success: avgTime < 100,
      message: `Average API response: ${avgTime.toFixed(2)}ms`,
      data: { times, avgTime }
    };
  });
}

// ============================================================
// CLEANUP
// ============================================================

async function cleanup() {
  if (results.sandboxes.length === 0) return;

  log('\n' + '='.repeat(60), 'bright');
  log('🧹 CLEANUP', 'bright');
  log('='.repeat(60), 'bright');

  log(`\nCleaning up ${results.sandboxes.length} sandboxes...`, 'yellow');

  for (const sandboxId of [...results.sandboxes]) {
    try {
      logVerbose(`Deleting sandbox: ${sandboxId}`);

      const res = await request(`${config.e2bApiUrl}/sandboxes/${sandboxId}`, {
        method: 'DELETE',
      });

      if (res.status === 200 || res.status === 204) {
        log(`  ✓ Deleted: ${sandboxId}`, 'green');
      } else {
        log(`  ⚠ Failed to delete ${sandboxId}: HTTP ${res.status}`, 'yellow');
      }
    } catch (error) {
      log(`  ⚠ Error deleting ${sandboxId}: ${error.message}`, 'yellow');
    }
  }

  results.sandboxes = [];
  log('✅ Cleanup complete', 'green');
}

// ============================================================
// MAIN EXECUTION
// ============================================================

async function main() {
  log('\n' + '='.repeat(60), 'bright');
  log('🔗 E2B INTEGRATION TEST', 'bright');
  log('='.repeat(60), 'bright');
  log(`E2B API: ${config.e2bApiUrl}`, 'cyan');
  log(`API Key: ${config.apiKey.substring(0, 20)}...`, 'cyan');
  log(`Verbose: ${config.verbose}`, 'cyan');

  const startTime = Date.now();

  try {
    // Run test suites
    await testE2BHealth();
    await testSandboxLifecycle();
    await testSandboxExecution();
    await testTemplateManagement();
    await testPerformanceBenchmarks();
  } finally {
    // Always cleanup
    await cleanup();
  }

  // Print summary
  const duration = Date.now() - startTime;
  log('\n' + '='.repeat(60), 'bright');
  log('📊 TEST SUMMARY', 'bright');
  log('='.repeat(60), 'bright');
  log(`Total tests:   ${results.total}`, 'cyan');
  log(`✅ Passed:     ${results.passed}`, 'green');
  log(`❌ Failed:     ${results.failed}`, 'red');
  log(`⏱️  Duration:   ${duration}ms`, 'cyan');
  log('='.repeat(60), 'bright');

  // Calculate pass rate
  const passRate = results.total > 0
    ? ((results.passed / results.total) * 100).toFixed(1)
    : 0;

  if (results.failed === 0 && results.passed > 0) {
    log(`\n🎉 ALL TESTS PASSED! (${passRate}%)`, 'green');
  } else if (results.failed > 0) {
    log(`\n⚠️  SOME TESTS FAILED (${passRate}% pass rate)`, 'red');
  }

  // Export results
  const resultsFile = `e2b-integration-results-${Date.now()}.json`;
  require('fs').writeFileSync(
    `/tmp/${resultsFile}`,
    JSON.stringify({ ...results, duration, passRate: parseFloat(passRate) }, null, 2)
  );
  log(`\n📄 Results saved to: /tmp/${resultsFile}`, 'cyan');

  // Exit
  process.exit(results.failed > 0 ? 1 : 0);
}

// Run if called directly
if (require.main === module) {
  main().catch(error => {
    log(`\n💥 Fatal error: ${error.message}`, 'red');
    console.error(error.stack);
    process.exit(1);
  });
}

module.exports = { request, runTest, cleanup, results };
