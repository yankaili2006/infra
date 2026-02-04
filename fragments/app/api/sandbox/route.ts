import { FragmentSchema } from '@/lib/schema'
import { ExecutionResultInterpreter, ExecutionResultWeb } from '@/lib/types'
import { E2BDirectClient } from '@/lib/e2b-direct-api'

const sandboxTimeout = 10 * 60 * 1000 // 10 minute in ms

export const maxDuration = 60

export async function DELETE(req: Request) {
  try {
    const { searchParams } = new URL(req.url)
    const sbxId = searchParams.get('sbxId')

    if (!sbxId) {
      return new Response(
        JSON.stringify({ error: 'Sandbox ID is required' }),
        { status: 400, headers: { 'Content-Type': 'application/json' } }
      )
    }

    console.log(`Deleting sandbox ${sbxId}`)

    const client = new E2BDirectClient(
      process.env.E2B_API_KEY!,
      process.env.E2B_API_URL || 'http://localhost:3000'
    )

    await client.deleteSandbox(sbxId)
    console.log(`Sandbox ${sbxId} deleted successfully`)

    return new Response(
      JSON.stringify({ success: true, sbxId }),
      { status: 200, headers: { 'Content-Type': 'application/json' } }
    )
  } catch (error) {
    console.error('Error deleting sandbox:', error)
    return new Response(
      JSON.stringify({
        error: error instanceof Error ? error.message : 'Failed to delete sandbox',
      }),
      { status: 500, headers: { 'Content-Type': 'application/json' } }
    )
  }
}

export async function POST(req: Request) {
  try {
    const {
      fragment,
      userID,
      teamID,
      accessToken,
    }: {
      fragment: FragmentSchema
      userID: string | undefined
      teamID: string | undefined
      accessToken: string | undefined
    } = await req.json()
    console.log('fragment', fragment)
    console.log('userID', userID)
    console.log('E2B_API_KEY:', process.env.E2B_API_KEY ? 'Set' : 'NOT SET')
    console.log('E2B_API_URL:', process.env.E2B_API_URL)

    // Use custom E2B client for local infrastructure
    const client = new E2BDirectClient(
      process.env.E2B_API_KEY!,
      process.env.E2B_API_URL || 'http://localhost:3000'
    )

    // Map templates to actual E2B template IDs
    // Note: Use actual template names that exist in the database
    const templateMap: Record<string, string> = {
      // 'code-interpreter-v1': 'base',  // FIXED: Use actual code-interpreter-v1 template with Python3
      'nextjs-developer-dev': 'nextjs-developer-opt',  // FIXED: Map to actual registered template (envd works correctly)
      'vue-developer-dev': 'base',  // TODO: Create vue-developer template
      'streamlit-developer-dev': 'base',  // TODO: Create streamlit-developer template
      'gradio-developer-dev': 'base',  // TODO: Create gradio-developer template
    }
    const actualTemplate = templateMap[fragment.template] || fragment.template
    console.log(`Using template: ${actualTemplate} (requested: ${fragment.template})`)

    const sbx = await client.createSandbox({
      templateID: actualTemplate,
      timeout: sandboxTimeout / 1000,
      apiKey: process.env.E2B_API_KEY!,
      metadata: {
        template: fragment.template,
        userID: userID ?? '',
        teamID: teamID ?? '',
      },
    })

  // Copy code to fs (for templates that need files)
  // For code-interpreter-v1, code is executed directly, no file writing needed
  if (fragment.template !== 'code-interpreter-v1') {
    if (fragment.code && Array.isArray(fragment.code)) {
      for (const file of fragment.code) {
        await client.writeFile(sbx.sandboxID, file.file_path, file.file_content)
        console.log(`Copied file to ${file.file_path} in ${sbx.sandboxID}`)
      }
    } else if (fragment.file_path && fragment.code) {
      await client.writeFile(sbx.sandboxID, fragment.file_path, fragment.code)
      console.log(`Copied file to ${fragment.file_path} in ${sbx.sandboxID}`)
    }
  }

  // Install packages (skip for code-interpreter-v1 as packages need to be installed differently)
  if (fragment.has_additional_dependencies && fragment.template !== 'code-interpreter-v1') {
    console.log(`Installing dependencies: ${fragment.install_dependencies_command}`)
    await client.executeCommand(sbx.sandboxID, fragment.install_dependencies_command)
    console.log(
      `Installed dependencies: ${fragment.additional_dependencies.join(', ')} in sandbox ${sbx.sandboxID}`,
    )
  }

  // For web templates, create project structure and start the development server
  const webTemplates = ['nextjs-developer-dev', 'vue-developer-dev', 'streamlit-developer-dev', 'gradio-developer-dev']
  const isWebTemplate = webTemplates.includes(fragment.template)

  // Determine the correct port for the development server
  let webPort = 80 // Default fallback
  if (isWebTemplate) {
    if (fragment.template === 'nextjs-developer-dev') {
      webPort = 3000
    } else if (fragment.template === 'vue-developer-dev') {
      webPort = 3000
    } else if (fragment.template === 'streamlit-developer-dev') {
      webPort = 8501
    } else if (fragment.template === 'gradio-developer-dev') {
      webPort = 7860
    }
  }

  if (isWebTemplate) {
    console.log(`Setting up ${fragment.template} project`)

    // Create package.json for Next.js/Vue templates
    if (fragment.template === 'nextjs-developer-dev') {
      const packageJson = {
        name: "nextjs-app",
        version: "0.1.0",
        scripts: {
          dev: "next dev -p 3000 -H 0.0.0.0",
          build: "next build",
          start: "next start"
        },
        dependencies: {
          next: "14.2.5",
          react: "^18",
          "react-dom": "^18",
          typescript: "^5",
          "@types/node": "^20",
          "@types/react": "^18",
          "@types/react-dom": "^18"
        }
      }
      await client.writeFile(sbx.sandboxID, '/root/package.json', JSON.stringify(packageJson, null, 2))
      console.log('Created package.json')

      // Fix file permissions to ensure npm can read it
      await client.executeCommand(sbx.sandboxID, 'chmod 644 /root/package.json')
      console.log('Fixed package.json permissions')

      // Create next.config.js
      const nextConfig = `/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
}
module.exports = nextConfig`
      await client.writeFile(sbx.sandboxID, '/root/next.config.js', nextConfig)
      console.log('Created next.config.js')

      // Create tsconfig.json
      const tsConfig = {
        compilerOptions: {
          target: "es5",
          lib: ["dom", "dom.iterable", "esnext"],
          allowJs: true,
          skipLibCheck: true,
          strict: false,
          forceConsistentCasingInFileNames: true,
          noEmit: true,
          incremental: true,
          esModuleInterop: true,
          module: "esnext",
          moduleResolution: "node",
          resolveJsonModule: true,
          isolatedModules: true,
          jsx: "preserve"
        },
        include: ["next-env.d.ts", "**/*.ts", "**/*.tsx"],
        exclude: ["node_modules"]
      }
      await client.writeFile(sbx.sandboxID, '/root/tsconfig.json', JSON.stringify(tsConfig, null, 2))
      console.log('Created tsconfig.json')
    }

    // Note: Node.js installation is currently disabled due to network isolation in sandboxes
    // Sandboxes have no external network connectivity, making dynamic installation impossible
    // TODO: Create a proper Node.js pre-installed template when infrastructure supports it
    // For now, Next.js templates will fail without Node.js pre-installed in the base template

    // Setup dev server and wait for it to be ready
    console.log(`Setting up dev server for ${sbx.sandboxID}...`)

    // Install dependencies with faster mirror and caching
    console.log(`Installing dependencies for ${sbx.sandboxID}...`)

    // Check if cache exists and use it directly
    const cacheDir = '/root/.npm-cache/nextjs-modules'
    const cacheCheckResult = await client.executeCommand(sbx.sandboxID, `test -d ${cacheDir} && echo "exists" || echo "not_exists"`)

    if (cacheCheckResult.stdout.trim() === 'exists') {
      console.log(`Found npm cache, using it directly via symlink...`)
      // Use symlink and skip npm install - much faster!
      await client.executeCommand(sbx.sandboxID, `ln -sf ${cacheDir} /root/node_modules`)
      console.log(`✓ Dependencies ready (from cache)`)
    } else {
      console.log(`No cache found, installing dependencies...`)
      // First time: install dependencies
      await client.executeCommand(sbx.sandboxID, 'cd /root && npm install --legacy-peer-deps --silent --no-audit --no-fund --prefer-offline --registry=https://registry.npmmirror.com', { timeout: 90000 })
      console.log(`Dependencies installed for ${sbx.sandboxID}`)

      // Save to cache for future use (in background)
      console.log(`Saving node_modules to cache for future use...`)
      client.executeCommand(sbx.sandboxID, `mkdir -p $(dirname ${cacheDir}) && cp -r /root/node_modules ${cacheDir}`).catch(err => {
        console.warn(`Failed to save cache: ${err.message}`)
      })
    }

    // Determine the start command
    let startCommand = 'cd /root && npm run dev'
    if (fragment.template === 'streamlit-developer-dev') {
      startCommand = 'cd /root && streamlit run app.py --server.port 8501 --server.address 0.0.0.0'
    } else if (fragment.template === 'gradio-developer-dev') {
      startCommand = 'cd /root && python app.py'
    }

    // Start the server in the background with better logging
    // Use tee to capture logs while also allowing real-time monitoring
    await client.executeCommand(sbx.sandboxID, `nohup bash -c '${startCommand} 2>&1 | tee /tmp/server.log' > /dev/null &`)
    console.log(`Development server started for ${sbx.sandboxID}`)

    // Wait for the server to be ready by checking if it responds
    console.log(`Waiting for dev server to be ready on port ${webPort}...`)
    const maxRetries = 20 // Reduced from 30 to 20 seconds
    const checkInterval = 500 // Check every 500ms instead of 1000ms
    let serverReady = false

    for (let i = 0; i < maxRetries; i++) {
      try {
        // Check if the server is responding
        const checkResult = await client.executeCommand(
          sbx.sandboxID,
          `curl -s -o /dev/null -w "%{http_code}" http://localhost:${webPort} || echo "000"`,
          { timeout: 2000 }
        )
        const statusCode = checkResult.stdout.trim()

        // Accept any valid HTTP response (200-599)
        // Even 404 from the app itself means server is running
        const code = parseInt(statusCode, 10)
        if (!isNaN(code) && code >= 200 && code < 600) {
          console.log(`Dev server ready! Status code: ${statusCode} (after ${(i * checkInterval) / 1000}s)`)
          serverReady = true
          break
        }
      } catch (error) {
        // Ignore errors during health check
      }

      // Wait before next check
      await new Promise(resolve => setTimeout(resolve, checkInterval))
    }

    if (!serverReady) {
      console.warn(`Dev server did not respond after ${(maxRetries * checkInterval) / 1000} seconds, returning URL anyway`)
    }
  }

  // Execute code or return a URL to the running sandbox
  if (fragment.template === 'code-interpreter-v1') {
    const result = await client.runCode(sbx.sandboxID, fragment.code || '')

    return new Response(
      JSON.stringify({
        sbxId: sbx.sandboxID,
        template: fragment.template,
        stdout: result.stdout ? [result.stdout] : [],
        stderr: result.stderr ? [result.stderr] : [],
        runtimeError: result.error ? { name: 'RuntimeError', value: result.error, traceback: result.stderr || '' } : undefined,
        cellResults: result.results || [],
      } as ExecutionResultInterpreter),
    )
  }

  // For web templates, use the correct port (fragment.port can override if explicitly provided)
  const finalPort = isWebTemplate ? (fragment.port || webPort) : (fragment.port || 80)

  return new Response(
    JSON.stringify({
      sbxId: sbx.sandboxID,
      template: fragment.template,
      url: await client.getSandboxUrl(sbx.sandboxID, finalPort),
    } as ExecutionResultWeb),
  )
  } catch (error) {
    console.error('Error creating sandbox:', error)
    return new Response(
      JSON.stringify({
        error: error instanceof Error ? error.message : 'Failed to create sandbox',
        details: error
      }),
      {
        status: 500,
        headers: { 'Content-Type': 'application/json' }
      }
    )
  }
}
