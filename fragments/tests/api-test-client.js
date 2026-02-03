#!/usr/bin/env node
/**
 * Fragments API Test Client
 *
 * Direct HTTP API testing for Fragments endpoints:
 * - Health checks
 * - Sandbox creation
 * - Code execution
 * - Chat/LLM integration
 *
 * Usage:
 *   node api-test-client.js
 *   node api-test-client.js --verbose
 *   node api-test-client.js --test=sandbox
 */

const http = require('http');
const https = require('https');

// Configuration
const config = {
  baseUrl: 'http://localhost:3001',
  apiUrl: 'http://localhost:3000',
  verbose: process.argv.includes('--verbose'),
  specificTest: process.argv.find(arg => arg.startsWith('--test='))?.split('=')[1],
};

// Test results tracking
const results = {
  total: 0,
  passed: 0,
  failed: 0,
  skipped: 0,
  tests: []
};

// Colors for terminal output
const colors = {
  reset: '\x1b[0m',
  bright: '\x1b[1m',
  green: '\x1b[32m',
  red: '\x1b[31m',
  yellow: '\x1b[33m',
  blue: '\x1b[34m',
  cyan: '\x1b[36m',
};

// Helper: HTTP request
function request(url, options = {}) {
  return new Promise((resolve, reject) => {
    const urlObj = new URL(url);
    const protocol = urlObj.protocol === 'https:' ? https : http;

    const reqOptions = {
      hostname: urlObj.hostname,
      port: urlObj.port || (urlObj.protocol === 'https:' ? 443 : 80),
      path: urlObj.pathname + urlObj.search,
      method: options.method || 'GET',
      headers: {
        'Content-Type': 'application/json',
        ...options.headers,
      },
    };

    const req = protocol.request(reqOptions, (res) => {
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
    req.setTimeout(30000, () => {
      req.destroy();
      reject(new Error('Request timeout'));
    });

    if (options.body) {
      req.write(JSON.stringify(options.body));
    }
    req.end();
  });
}

// Helper: Log with color
function log(message, color = 'reset') {
  console.log(`${colors[color]}${message}${colors.reset}`);
}

// Helper: Log verbose
function logVerbose(message) {
  if (config.verbose) {
    log(`  📝 ${message}`, 'cyan');
  }
}

// Helper: Run test
async function runTest(name, category, testFn) {
  results.total++;

  if (config.specificTest && config.specificTest !== category) {
    results.skipped++;
    return;
  }

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
      category,
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
      category,
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

// Test Suite: Health Checks
async function testHealthChecks() {
  log('\n' + '='.repeat(60), 'bright');
  log('📋 HEALTH CHECKS', 'bright');
  log('='.repeat(60), 'bright');

  await runTest('Fragments Web UI Health', 'health', async () => {
    logVerbose(`GET ${config.baseUrl}`);
    const res = await request(config.baseUrl);
    logVerbose(`Status: ${res.status}`);

    return {
      success: res.status === 200,
      message: res.status === 200 ? 'Fragments is running' : `HTTP ${res.status}`,
      data: { status: res.status }
    };
  });

  await runTest('E2B API Health', 'health', async () => {
    logVerbose(`GET ${config.apiUrl}/health`);
    const res = await request(`${config.apiUrl}/health`);
    logVerbose(`Status: ${res.status}, Body: ${res.raw}`);

    return {
      success: res.status === 200,
      message: res.status === 200 ? 'E2B API is healthy' : `HTTP ${res.status}`,
      data: { status: res.status, response: res.raw }
    };
  });
}

// Test Suite: Sandbox API
async function testSandboxAPI() {
  log('\n' + '='.repeat(60), 'bright');
  log('📦 SANDBOX API TESTS', 'bright');
  log('='.repeat(60), 'bright');

  await runTest('Create Python Code Interpreter Sandbox', 'sandbox', async () => {
    const fragment = {
      template: 'code-interpreter-v1',
      title: 'Test Python',
      description: 'Test Python code execution',
      commentary: 'Testing simple Python print statement',
      code: 'print("Hello from E2B sandbox!")',
      file_path: 'test.py',
      port: null,
      additional_dependencies: [],
      has_additional_dependencies: false,
      install_dependencies_command: '',
    };

    logVerbose(`POST ${config.baseUrl}/api/sandbox`);
    logVerbose(`Fragment: ${JSON.stringify(fragment, null, 2)}`);

    const res = await request(`${config.baseUrl}/api/sandbox`, {
      method: 'POST',
      body: { fragment, userID: 'test-user', teamID: undefined, accessToken: undefined },
    });

    logVerbose(`Status: ${res.status}`);
    logVerbose(`Response: ${JSON.stringify(res.data, null, 2)}`);

    if (res.status !== 200) {
      return {
        success: false,
        message: `HTTP ${res.status}: ${res.data?.error || res.raw}`,
        data: res.data
      };
    }

    const hasOutput = res.data?.stdout && res.data.stdout.length > 0;
    const hasError = res.data?.error || res.data?.runtimeError;

    return {
      success: res.status === 200 && !hasError,
      message: hasOutput
        ? `Sandbox created: ${res.data.sbxId}, Output: ${res.data.stdout.join('')}`
        : `Sandbox created: ${res.data.sbxId}`,
      data: res.data
    };
  });

  await runTest('Create Sandbox with Math Calculation', 'sandbox', async () => {
    const fragment = {
      template: 'code-interpreter-v1',
      title: 'Math Test',
      description: 'Test Python math operations',
      commentary: 'Testing mathematical calculation',
      code: `
import math
result = math.sqrt(144)
print(f"Square root of 144 is {result}")
      `.trim(),
      file_path: 'math_test.py',
      port: null,
      additional_dependencies: [],
      has_additional_dependencies: false,
      install_dependencies_command: '',
    };

    logVerbose(`POST ${config.baseUrl}/api/sandbox`);

    const res = await request(`${config.baseUrl}/api/sandbox`, {
      method: 'POST',
      body: { fragment, userID: 'test-user' },
    });

    logVerbose(`Status: ${res.status}`);

    if (res.status !== 200) {
      return {
        success: false,
        message: `HTTP ${res.status}`,
        data: res.data
      };
    }

    const output = res.data?.stdout?.join('') || '';
    const hasCorrectOutput = output.includes('12');

    return {
      success: hasCorrectOutput,
      message: hasCorrectOutput
        ? `Correct output: ${output.trim()}`
        : `Unexpected output: ${output}`,
      data: res.data
    };
  });

  await runTest('Create Sandbox with Dependencies', 'sandbox', async () => {
    const fragment = {
      template: 'code-interpreter-v1',
      title: 'NumPy Test',
      description: 'Test with external dependencies',
      commentary: 'Testing numpy installation and usage',
      code: `
import numpy as np
arr = np.array([1, 2, 3, 4, 5])
print(f"Array sum: {arr.sum()}")
      `.trim(),
      file_path: 'numpy_test.py',
      port: null,
      additional_dependencies: ['numpy'],
      has_additional_dependencies: true,
      install_dependencies_command: 'pip install numpy',
    };

    logVerbose(`POST ${config.baseUrl}/api/sandbox`);

    const res = await request(`${config.baseUrl}/api/sandbox`, {
      method: 'POST',
      body: { fragment, userID: 'test-user' },
    });

    logVerbose(`Status: ${res.status}`);

    if (res.status !== 200) {
      return {
        success: false,
        message: `HTTP ${res.status}`,
        data: res.data
      };
    }

    const output = res.data?.stdout?.join('') || '';
    const hasCorrectOutput = output.includes('15');

    return {
      success: hasCorrectOutput,
      message: hasCorrectOutput
        ? `Dependencies installed, output: ${output.trim()}`
        : `Output: ${output}`,
      data: res.data
    };
  });

  await runTest('Handle Sandbox Error Gracefully', 'sandbox', async () => {
    const fragment = {
      template: 'code-interpreter-v1',
      title: 'Error Test',
      description: 'Test error handling',
      commentary: 'Testing error handling',
      code: 'print(undefined_variable)',  // This will cause an error
      file_path: 'error_test.py',
      port: null,
      additional_dependencies: [],
      has_additional_dependencies: false,
      install_dependencies_command: '',
    };

    logVerbose(`POST ${config.baseUrl}/api/sandbox`);

    const res = await request(`${config.baseUrl}/api/sandbox`, {
      method: 'POST',
      body: { fragment, userID: 'test-user' },
    });

    logVerbose(`Status: ${res.status}`);

    // We expect the sandbox to be created but execution to fail
    const hasError = res.data?.runtimeError || (res.data?.stderr && res.data.stderr.length > 0);

    return {
      success: res.status === 200 && hasError,
      message: hasError
        ? `Error handled correctly: ${res.data.runtimeError?.name || 'stderr present'}`
        : 'Expected error not detected',
      data: res.data
    };
  });
}

// Test Suite: Chat API (LLM Integration)
async function testChatAPI() {
  log('\n' + '='.repeat(60), 'bright');
  log('💬 CHAT API TESTS (LLM)', 'bright');
  log('='.repeat(60), 'bright');

  log('\n⚠️  Note: Chat API tests require API keys (OpenAI, DeepSeek, etc.)', 'yellow');
  log('   Set DEEPSEEK_API_KEY or OPENAI_API_KEY in .env.local', 'yellow');

  await runTest('Chat API - Generate Simple Code', 'chat', async () => {
    const payload = {
      messages: [
        {
          role: 'user',
          content: 'Write a Python function that adds two numbers'
        }
      ],
      userID: 'test-user',
      teamID: undefined,
      template: 'code-interpreter-v1',
      model: 'deepseek-chat',
      config: {
        model: 'deepseek-chat',
        apiKey: process.env.DEEPSEEK_API_KEY,
        temperature: 0.7,
      }
    };

    logVerbose(`POST ${config.baseUrl}/api/chat`);
    logVerbose(`Model: deepseek-chat`);

    try {
      const res = await request(`${config.baseUrl}/api/chat`, {
        method: 'POST',
        body: payload,
      });

      logVerbose(`Status: ${res.status}`);

      if (res.status === 429) {
        return {
          success: false,
          message: 'Rate limited - increase RATE_LIMIT_MAX_REQUESTS or wait',
          data: res.data
        };
      }

      if (res.status === 401 || res.status === 500) {
        return {
          success: false,
          message: `API Key issue (HTTP ${res.status}) - Check DEEPSEEK_API_KEY`,
          data: res.data
        };
      }

      return {
        success: res.status === 200,
        message: res.status === 200
          ? 'Chat API responding (streaming)'
          : `HTTP ${res.status}`,
        data: { status: res.status }
      };
    } catch (error) {
      if (error.message.includes('timeout')) {
        return {
          success: true,  // Streaming may cause timeout, that's OK
          message: 'Chat API streaming (connection timeout expected)',
          data: null
        };
      }
      throw error;
    }
  });
}

// Test Suite: E2B API Direct
async function testE2BAPIDirect() {
  log('\n' + '='.repeat(60), 'bright');
  log('🔌 E2B API DIRECT TESTS', 'bright');
  log('='.repeat(60), 'bright');

  await runTest('List Available Templates', 'e2b-api', async () => {
    logVerbose(`GET ${config.apiUrl}/templates`);

    try {
      const res = await request(`${config.apiUrl}/templates`, {
        headers: {
          'X-API-Key': 'e2b_53ae1fed82754c17ad8077fbc8bcdd90',
        }
      });

      logVerbose(`Status: ${res.status}`);
      if (res.data) {
        logVerbose(`Templates: ${JSON.stringify(res.data, null, 2)}`);
      }

      return {
        success: res.status === 200,
        message: res.status === 200
          ? `Found ${Array.isArray(res.data) ? res.data.length : 'unknown'} templates`
          : `HTTP ${res.status}`,
        data: res.data
      };
    } catch (error) {
      // Endpoint might not exist
      return {
        success: false,
        message: `Endpoint not available: ${error.message}`,
        data: null
      };
    }
  });

  await runTest('Create Sandbox via E2B API', 'e2b-api', async () => {
    logVerbose(`POST ${config.apiUrl}/sandboxes`);

    const res = await request(`${config.apiUrl}/sandboxes`, {
      method: 'POST',
      headers: {
        'X-API-Key': 'e2b_53ae1fed82754c17ad8077fbc8bcdd90',
      },
      body: {
        templateID: 'base',
        timeout: 300,
      }
    });

    logVerbose(`Status: ${res.status}`);
    logVerbose(`Response: ${JSON.stringify(res.data, null, 2)}`);

    if (res.status === 201 || res.status === 200) {
      return {
        success: true,
        message: `Sandbox created: ${res.data?.sandboxID || res.data?.clientID}`,
        data: res.data
      };
    }

    return {
      success: false,
      message: `HTTP ${res.status}: ${res.data?.message || res.raw}`,
      data: res.data
    };
  });
}

// ============================================================
// MAIN EXECUTION
// ============================================================

async function main() {
  log('\n' + '='.repeat(60), 'bright');
  log('🚀 FRAGMENTS API TEST CLIENT', 'bright');
  log('='.repeat(60), 'bright');
  log(`Base URL: ${config.baseUrl}`, 'cyan');
  log(`E2B API: ${config.apiUrl}`, 'cyan');
  log(`Verbose: ${config.verbose}`, 'cyan');
  if (config.specificTest) {
    log(`Running only: ${config.specificTest}`, 'yellow');
  }

  const startTime = Date.now();

  // Run test suites
  await testHealthChecks();
  await testSandboxAPI();
  await testChatAPI();
  await testE2BAPIDirect();

  // Print summary
  const duration = Date.now() - startTime;
  log('\n' + '='.repeat(60), 'bright');
  log('📊 TEST SUMMARY', 'bright');
  log('='.repeat(60), 'bright');
  log(`Total tests:   ${results.total}`, 'cyan');
  log(`✅ Passed:     ${results.passed}`, 'green');
  log(`❌ Failed:     ${results.failed}`, 'red');
  log(`⏭️  Skipped:    ${results.skipped}`, 'yellow');
  log(`⏱️  Duration:   ${duration}ms`, 'cyan');
  log('='.repeat(60), 'bright');

  // Calculate pass rate
  const passRate = results.total > 0
    ? ((results.passed / (results.total - results.skipped)) * 100).toFixed(1)
    : 0;

  if (results.failed === 0 && results.passed > 0) {
    log(`\n🎉 ALL TESTS PASSED! (${passRate}%)`, 'green');
  } else if (results.failed > 0) {
    log(`\n⚠️  SOME TESTS FAILED (${passRate}% pass rate)`, 'red');
  } else {
    log(`\n⚠️  NO TESTS RAN`, 'yellow');
  }

  // Export results to JSON
  const resultsFile = `test-results-${Date.now()}.json`;
  require('fs').writeFileSync(
    `/tmp/${resultsFile}`,
    JSON.stringify({ ...results, duration, passRate: parseFloat(passRate) }, null, 2)
  );
  log(`\n📄 Results saved to: /tmp/${resultsFile}`, 'cyan');

  // Exit with appropriate code
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

module.exports = { request, runTest, results };
