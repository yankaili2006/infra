/**
 * Test Fragments API - Create and Preview
 * Tests the complete flow: generate code -> execute in sandbox -> get preview URL
 */

const FRAGMENTS_URL = 'http://localhost:3001'

// Test 1: Generate a simple Python code fragment
async function testGenerateFragment() {
  console.log('\n=== Test 1: Generate Fragment ===')

  const response = await fetch(`${FRAGMENTS_URL}/api/chat`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      messages: [
        {
          role: 'user',
          content: 'Create a simple Python script that prints "Hello from Fragments!" and calculates 2+2'
        }
      ],
      template: 'code-interpreter-v1',
      model: 'claude-3-5-sonnet-20241022',
      config: {
        model: 'claude-3-5-sonnet-20241022',
        temperature: 0.7
      }
    })
  })

  if (!response.ok) {
    throw new Error(`Generate failed: ${response.status} ${await response.text()}`)
  }

  // Parse streaming response
  const text = await response.text()
  console.log('Raw response:', text.substring(0, 500))

  // Extract JSON from streaming format
  const lines = text.split('\n').filter(line => line.trim())
  let fragment = null

  for (const line of lines) {
    try {
      const parsed = JSON.parse(line)
      if (parsed.code) {
        fragment = parsed
      }
    } catch (e) {
      // Skip non-JSON lines
    }
  }

  if (!fragment) {
    throw new Error('No fragment generated')
  }

  console.log('✓ Fragment generated:')
  console.log('  Template:', fragment.template)
  console.log('  Code length:', fragment.code?.length || 0)
  console.log('  Code preview:', fragment.code?.substring(0, 100))

  return fragment
}

// Test 2: Execute fragment in sandbox
async function testExecuteFragment(fragment) {
  console.log('\n=== Test 2: Execute Fragment ===')

  const response = await fetch(`${FRAGMENTS_URL}/api/sandbox`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      fragment: fragment,
      userID: 'test-user',
      teamID: 'test-team'
    })
  })

  if (!response.ok) {
    const error = await response.text()
    throw new Error(`Execute failed: ${response.status} ${error}`)
  }

  const result = await response.json()
  console.log('✓ Execution result:')
  console.log('  Sandbox ID:', result.sbxId)
  console.log('  Template:', result.template)

  if (result.stdout) {
    console.log('  Stdout:', result.stdout)
  }
  if (result.stderr) {
    console.log('  Stderr:', result.stderr)
  }
  if (result.url) {
    console.log('  Preview URL:', result.url)
  }

  return result
}

// Test 3: Generate and execute a web app
async function testWebApp() {
  console.log('\n=== Test 3: Generate Web App ===')

  const response = await fetch(`${FRAGMENTS_URL}/api/chat`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      messages: [
        {
          role: 'user',
          content: 'Create a simple Next.js page that displays "Hello World" with a blue background'
        }
      ],
      template: 'nextjs-developer-dev',
      model: 'claude-3-5-sonnet-20241022',
      config: {
        model: 'claude-3-5-sonnet-20241022',
        temperature: 0.7
      }
    })
  })

  if (!response.ok) {
    throw new Error(`Generate web app failed: ${response.status}`)
  }

  const text = await response.text()
  const lines = text.split('\n').filter(line => line.trim())
  let fragment = null

  for (const line of lines) {
    try {
      const parsed = JSON.parse(line)
      if (parsed.code) {
        fragment = parsed
      }
    } catch (e) {
      // Skip non-JSON lines
    }
  }

  if (!fragment) {
    throw new Error('No web app fragment generated')
  }

  console.log('✓ Web app fragment generated')
  console.log('  Template:', fragment.template)

  // Execute in sandbox
  console.log('\n=== Executing Web App ===')
  const execResponse = await fetch(`${FRAGMENTS_URL}/api/sandbox`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      fragment: fragment,
      userID: 'test-user',
      teamID: 'test-team'
    })
  })

  if (!execResponse.ok) {
    const error = await execResponse.text()
    throw new Error(`Web app execution failed: ${execResponse.status} ${error}`)
  }

  const result = await execResponse.json()
  console.log('✓ Web app deployed:')
  console.log('  Sandbox ID:', result.sbxId)
  console.log('  Preview URL:', result.url)
  console.log('\n  🌐 Open this URL in browser to see the preview!')

  return result
}

// Run all tests
async function runTests() {
  console.log('🧪 Testing Fragments API\n')
  console.log('Target:', FRAGMENTS_URL)

  try {
    // Test 1: Simple Python code
    const fragment = await testGenerateFragment()
    const result = await testExecuteFragment(fragment)

    // Test 2: Web app with preview
    const webResult = await testWebApp()

    console.log('\n✅ All tests passed!')
    console.log('\n📊 Summary:')
    console.log('  - Code generation: ✓')
    console.log('  - Code execution: ✓')
    console.log('  - Web app preview: ✓')
    console.log(`  - Preview URL: ${webResult.url}`)

  } catch (error) {
    console.error('\n❌ Test failed:', error.message)
    process.exit(1)
  }
}

runTests()
