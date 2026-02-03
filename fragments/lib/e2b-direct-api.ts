/**
 * Direct E2B API Client for Local Infrastructure
 *
 * This client connects to the local E2B API for sandbox management
 * and uses HTTP to call envd gRPC-Web endpoints for code execution.
 *
 * Based on the E2B JS SDK source code in:
 * /home/primihub/pcloud/external/e2b-sdk/packages/js-sdk/src/
 *
 * Key endpoints:
 * - E2B API: POST /sandboxes (create sandbox)
 * - envd Process RPC: POST /api.v2.ProcessService/Start (execute command)
 * - envd Process RPC: POST /api.v2.ProcessService/Connect (connect to process)
 * - envd Filesystem RPC: POST /api.v2.FilesystemService/Write (write file)
 */

import { spawn } from 'child_process'

export interface SandboxCreateOptions {
  templateID: string
  timeout?: number
  metadata?: Record<string, string>
  apiKey: string
  apiUrl?: string
}

export interface SandboxInfo {
  sandboxID: string
  clientID: string
  templateID: string
  alias?: string
  domain: string | null
  envdVersion: string
  state?: string
  envdURL?: string
}

export interface CodeExecutionResult {
  stdout: string
  stderr: string
  error?: string
  results?: any[]
  exitCode?: number
}

/**
 * Sleep utility
 */
function sleep(ms: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms))
}

/**
 * Connect-RPC envelope format: 5-byte header + JSON data
 * Header: flags (1 byte, big endian) + data_len (4 bytes, big endian)
 */
function encodeEnvelope(data: string): Uint8Array {
  const encoder = new TextEncoder()
  const dataBytes = encoder.encode(data)
  const flags = 0 // No compression, not end stream

  // Create 5-byte header: flags (1 byte) + length (4 bytes)
  const header = new Uint8Array(5)
  new DataView(header.buffer).setUint8(0, flags)
  new DataView(header.buffer).setUint32(1, dataBytes.length, false) // big endian

  // Combine header + data
  const envelope = new Uint8Array(header.length + dataBytes.length)
  envelope.set(header)
  envelope.set(dataBytes, header.length)

  return envelope
}


export class E2BDirectClient {
  private apiUrl: string
  private apiKey: string
  private sandboxEnvdUrls: Map<string, string> = new Map()
  private sandboxPortForwards: Map<string, number> = new Map()

  constructor(apiKey: string, apiUrl: string = 'http://localhost:3000') {
    this.apiUrl = apiUrl
    this.apiKey = apiKey
  }

  /**
   * Create a new sandbox via E2B API
   */
  async createSandbox(options: SandboxCreateOptions): Promise<SandboxInfo> {
    const response = await fetch(`${this.apiUrl}/sandboxes`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-API-Key': this.apiKey,
      },
      body: JSON.stringify({
        templateID: options.templateID,
        timeout: options.timeout || 300,
        metadata: options.metadata || {},
      }),
    })

    if (!response.ok) {
      const error = await response.text()
      throw new Error(`Failed to create sandbox: ${response.status} ${error}`)
    }

    const data = await response.json() as SandboxInfo & { envdURL?: string }
    console.log(`Created sandbox: ${data.sandboxID}, envdURL: ${data.envdURL}`)

    // Store envdURL for later use
    if (data.envdURL) {
      this.sandboxEnvdUrls.set(data.sandboxID, data.envdURL)
    }

    return data
  }

  /**
   * Get envd URL for a sandbox (from API response or stored value)
   */
  private async getEnvdUrl(sandboxID: string): Promise<string> {
    // Check if we have it stored
    let envdUrl = this.sandboxEnvdUrls.get(sandboxID)

    if (!envdUrl) {
      // Fetch sandbox info to get envdURL
      const response = await fetch(`${this.apiUrl}/sandboxes/${sandboxID}`, {
        headers: {
          'X-API-Key': this.apiKey,
        },
      })

      if (response.ok) {
        const data = await response.json() as SandboxInfo & { envdURL?: string }
        if (data.envdURL) {
          envdUrl = data.envdURL
          this.sandboxEnvdUrls.set(sandboxID, envdUrl)
        }
      }
    }

    if (!envdUrl) {
      throw new Error(`Cannot find envdURL for sandbox ${sandboxID}`)
    }

    return envdUrl
  }

  /**
   * Execute a command in the sandbox via envd Process RPC
   */
  async executeCommand(
    sandboxID: string,
    command: string,
    opts: { cwd?: string; envs?: Record<string, string>; timeout?: number } = {}
  ): Promise<{ stdout: string; stderr: string; exitCode: number }> {
    const envdUrl = await this.getEnvdUrl(sandboxID)
    console.log(`Executing command in sandbox ${sandboxID}: ${command}`)

    // Call process.Process/Start via Connect-RPC endpoint
    const request = {
      process: {
        cmd: '/bin/bash',
        args: ['-l', '-c', command],
        cwd: opts.cwd || '/root',
        envs: opts.envs || {},
      },
      stdin: false,
    }

    const envelope = encodeEnvelope(JSON.stringify(request))
    const url = `${envdUrl}/process.Process/Start`

    // Add timeout to prevent hanging on long-running commands
    const controller = new AbortController()
    const timeoutMs = opts.timeout || 300000 // Default 5 minutes, configurable
    const timeoutId = setTimeout(() => controller.abort(), timeoutMs)

    try {
      const response = await fetch(url, {
        method: 'POST',
        headers: {
          'Connect-Protocol-Version': '1',
          'Content-Type': 'application/connect+json',
          'Connect-Content-Encoding': 'identity',
        },
        body: envelope,
        signal: controller.signal,
      })
      clearTimeout(timeoutId)

      if (!response.ok) {
        const text = await response.text()
        throw new Error(`Failed to start process: ${response.status} ${text}`)
      }

      // Parse streaming response to collect output
      const { stdout, stderr, exitCode } = await this.parseProcessStream(response.body)

      return { stdout, stderr, exitCode }
    } catch (error: any) {
      clearTimeout(timeoutId)
      if (error.name === 'AbortError') {
        throw new Error(`Command execution timed out after ${timeoutMs}ms: ${command}`)
      }
      throw error
    }
  }

  /**
   * Parse the streaming response from a process execution
   */
  private async parseProcessStream(body: ReadableStream<Uint8Array> | null): Promise<{ stdout: string; stderr: string; exitCode: number }> {
    if (!body) {
      return { stdout: '', stderr: '', exitCode: -1 }
    }

    const decoder = new TextDecoder()
    const encoder = new TextEncoder()
    let stdout = ''
    let stderr = ''
    let exitCode = 0
    let buffer = new Uint8Array(0)

    const reader = body.getReader()

    try {
      while (true) {
        const { done, value } = await reader.read()
        if (done) break

        // Append new data to buffer
        const newBuffer = new Uint8Array(buffer.length + value.length)
        newBuffer.set(buffer)
        newBuffer.set(value, buffer.length)
        buffer = newBuffer

        // Parse envelopes from buffer
        while (buffer.length >= 5) {
          // Read header: flags (1 byte) + length (4 bytes)
          const flags = buffer[0]
          const dataLen = new DataView(buffer.buffer).getUint32(1, false) // big endian

          // Check if we have the complete message
          if (buffer.length < 5 + dataLen) {
            break // Incomplete message, wait for more data
          }

          // Extract message data
          const messageData = buffer.slice(5, 5 + dataLen)

          // Advance buffer
          buffer = buffer.slice(5 + dataLen)

          // Skip end stream messages (flags & 0x02)
          if (flags & 0x02) {
            continue
          }

          try {
            const jsonData = JSON.parse(decoder.decode(messageData))

            // Process different event types
            if (jsonData.event?.start) {
              // Process started, get PID if needed
            } else if (jsonData.event?.data?.stdout) {
              // Regular stdout data
              stdout += this.decodeBase64(jsonData.event.data.stdout)
            } else if (jsonData.event?.stdout?.data) {
              // Stdout data (alternative format)
              stdout += this.decodeBase64(jsonData.event.stdout.data)
            } else if (jsonData.event?.data?.stderr) {
              stderr += this.decodeBase64(jsonData.event.data.stderr)
            } else if (jsonData.event?.stderr?.data) {
              stderr += this.decodeBase64(jsonData.event.stderr.data)
            } else if (jsonData.event?.end) {
              // Process ended, get exit code
              const status = jsonData.event.end.status || 'exit status 0'
              if (status.includes('exit status')) {
                exitCode = parseInt(status.split('exit status ')[1]) || 0
              }
            }
          } catch (e) {
            // Skip non-JSON or malformed messages
          }
        }
      }
    } finally {
      reader.releaseLock()
    }

    return { stdout, stderr, exitCode }
  }

  /**
   * Decode base64 string to text
   */
  private decodeBase64(encoded: string): string {
    try {
      return Buffer.from(encoded, 'base64').toString('utf-8')
    } catch {
      return encoded
    }
  }

  /**
   * Write a file to the sandbox via envd Filesystem RPC
   */
  async writeFile(sandboxID: string, path: string, content: string): Promise<void> {
    console.log(`Writing file to sandbox ${sandboxID}: ${path}`)

    // Use shell command to write file since filesystem API is not available
    // Create directory if it doesn't exist
    const dir = path.substring(0, path.lastIndexOf('/'))
    if (dir) {
      await this.executeCommand(sandboxID, `mkdir -p '${dir}'`)
    }

    // Write file using heredoc to handle special characters
    const writeCommand = `cat > '${path}' << 'EOF_WRITE_FILE'
${content}
EOF_WRITE_FILE`

    await this.executeCommand(sandboxID, writeCommand)
    console.log(`File written successfully: ${path}`)
  }

  /**
   * Run Python code in the sandbox (for code-interpreter template)
   */
  async runCode(sandboxID: string, code: string): Promise<CodeExecutionResult> {
    console.log(`Running Python code in sandbox ${sandboxID}, code length: ${code.length}`)

    // Escape the code for bash
    const escapedCode = code
      .replace(/\\/g, '\\\\')
      .replace(/"/g, '\\"')
      .replace(/\$/g, '\\$')

    const command = `python3 -c "${escapedCode}"`

    const result = await this.executeCommand(sandboxID, command)
    console.log(
      `Python code execution: exitCode=${result.exitCode}, stdout_len=${result.stdout?.length || 0}, stderr_len=${result.stderr?.length || 0}`
    )

    return {
      stdout: result.stdout || '',
      stderr: result.stderr || '',
      error: result.exitCode !== 0 ? result.stderr || 'Command failed' : undefined,
      exitCode: result.exitCode,
    }
  }

  /**
   * Get sandbox information
   */
  async getSandbox(sandboxID: string): Promise<SandboxInfo> {
    const response = await fetch(`${this.apiUrl}/sandboxes/${sandboxID}`, {
      headers: {
        'X-API-Key': this.apiKey,
      },
    })

    if (!response.ok) {
      const error = await response.text()
      throw new Error(`Failed to get sandbox: ${response.status} ${error}`)
    }

    const data = await response.json()
    return data
  }

  /**
   * Get sandbox host URL for web applications
   * For local E2B, extract IP from envdURL and use the specified port
   * If TAILSCALE_IP is set, setup port forwarding and return Tailscale-accessible URL
   */
  async getSandboxUrl(sandboxID: string, port: number = 80): Promise<string> {
    const envdUrl = await this.getEnvdUrl(sandboxID)

    // Extract IP address from envdURL (e.g., "http://10.11.0.100:49983" -> "10.11.0.100")
    const match = envdUrl.match(/http:\/\/([^:]+)/)
    if (!match || !match[1]) {
      return `http://localhost:${port}`
    }

    const sandboxIP = match[1]

    // Check if we should use Tailscale IP for external access
    const tailscaleIP = process.env.TAILSCALE_IP || '100.64.0.23'
    const useTailscale = process.env.USE_TAILSCALE_FORWARDING !== 'false'

    if (useTailscale && tailscaleIP) {
      // Generate external port based on sandbox ID hash
      const externalPort = this.getExternalPort(sandboxID, port)

      // Setup port forwarding using socat
      await this.setupPortForwarding(sandboxID, sandboxIP, port, externalPort, tailscaleIP)

      return `http://${tailscaleIP}:${externalPort}`
    }

    // Fallback to direct sandbox IP
    return `http://${sandboxIP}:${port}`
  }

  /**
   * Generate a unique external port for a sandbox
   */
  private getExternalPort(sandboxID: string, basePort: number): number {
    // Use sandbox ID hash to generate a consistent port number
    // Port range: 30000-39999
    const hash = sandboxID.split('').reduce((acc, char) => acc + char.charCodeAt(0), 0)
    return 30000 + (hash % 10000)
  }

  /**
   * Setup port forwarding using socat with dual-layer architecture
   * Layer 1: Tailscale IP -> Namespace IP (sandboxIP)
   * Layer 2: Namespace IP -> VM internal IP (169.254.0.21)
   */
  private async setupPortForwarding(
    sandboxID: string,
    sandboxIP: string,
    sandboxPort: number,
    externalPort: number,
    tailscaleIP: string
  ): Promise<void> {
    const { spawn, exec } = await import('child_process')
    const { promisify } = await import('util')
    const execAsync = promisify(exec)

    // Extract slot index from sandboxIP (e.g., 10.11.1.58 -> slot 314)
    const ipParts = sandboxIP.split('.')
    const slotIdx = parseInt(ipParts[2]) * 256 + parseInt(ipParts[3])
    const namespaceID = `ns-${slotIdx}`

    // Calculate vpeerIP from slot index
    // vpeerIP = 10.12.0.0 + (slotIdx * 2 + 1)
    const vpeerOffset = slotIdx * 2 + 1
    const vpeerIP = `10.12.${Math.floor(vpeerOffset / 256)}.${vpeerOffset % 256}`

    console.log(`Setting up dual-layer port forwarding for sandbox ${sandboxID}:`)
    console.log(`  Namespace: ${namespaceID}`)
    console.log(`  VpeerIP: ${vpeerIP}`)
    console.log(`  Layer 1: ${tailscaleIP}:${externalPort} -> ${vpeerIP}:${sandboxPort}`)
    console.log(`  Layer 2: ${vpeerIP}:${sandboxPort} -> 169.254.0.21:${sandboxPort}`)

    // Kill existing socat processes for this port
    spawn('pkill', ['-f', `socat.*${externalPort}`])
    try {
      await execAsync(`echo "Primihub@2022." | sudo -S pkill -f "socat.*${vpeerIP}:${sandboxPort}"`)
    } catch (e) {
      // Ignore errors - process might not exist
    }

    // Wait for processes to die
    await new Promise(resolve => setTimeout(resolve, 500))

    // Layer 2: Setup forwarding inside network namespace (vpeerIP:port -> 169.254.0.21:port)
    const layer2Cmd = `echo "Primihub@2022." | sudo -S ip netns exec ${namespaceID} socat TCP4-LISTEN:${sandboxPort},bind=${vpeerIP},reuseaddr,fork TCP4:169.254.0.21:${sandboxPort}`

    try {
      const layer2 = spawn('bash', ['-c', layer2Cmd], {
        detached: true,
        stdio: 'ignore'
      })
      layer2.unref()
      console.log(`  ✓ Layer 2 forwarding started in namespace ${namespaceID}`)
    } catch (error) {
      console.error(`  ✗ Failed to setup Layer 2 forwarding:`, error)
      throw error
    }

    // Wait for Layer 2 to be ready
    await new Promise(resolve => setTimeout(resolve, 500))

    // Layer 1: Setup forwarding on host (tailscaleIP:externalPort -> vpeerIP:sandboxPort)
    const socat = spawn('socat', [
      `TCP-LISTEN:${externalPort},bind=${tailscaleIP},fork,reuseaddr`,
      `TCP:${vpeerIP}:${sandboxPort}`
    ], {
      detached: true,
      stdio: 'ignore'
    })

    socat.unref()

    // Store the port forwarding mapping
    this.sandboxPortForwards.set(sandboxID, externalPort)

    console.log(`  ✓ Layer 1 forwarding started`)
    console.log(`✓ Dual-layer port forwarding established for ${tailscaleIP}:${externalPort}`)
  }

  /**
   * Cleanup port forwarding for a sandbox
   * Uses process inspection to find and kill socat processes
   */
  private async cleanupPortForwarding(sandboxID: string): Promise<void> {
    const { spawn, exec } = await import('child_process')
    const { promisify } = await import('util')
    const execAsync = promisify(exec)

    try {
      // Find socat processes that match this sandbox's IP pattern
      // First, get the sandbox info to find its IP
      const envdUrl = this.sandboxEnvdUrls.get(sandboxID)
      if (!envdUrl) {
        console.log(`No envdURL found for sandbox ${sandboxID}, attempting to fetch`)
        try {
          const response = await fetch(`${this.apiUrl}/sandboxes/${sandboxID}`, {
            headers: { 'X-API-Key': this.apiKey },
          })
          if (response.ok) {
            const data = await response.json() as { envdURL?: string }
            if (data.envdURL) {
              const match = data.envdURL.match(/http:\/\/([^:]+)/)
              if (match && match[1]) {
                const sandboxIP = match[1]
                // Kill all socat processes forwarding to this sandbox IP
                const killCmd = `pkill -f 'socat.*100.64.0.23.*${sandboxIP}'`
                await execAsync(killCmd).catch(() => {
                  // Ignore errors if no processes found
                })
                console.log(`Cleaned up port forwarding for sandbox ${sandboxID} (IP: ${sandboxIP})`)
              }
            }
          }
        } catch (err) {
          console.log(`Could not fetch sandbox info for cleanup: ${err}`)
        }
        return
      }

      // Extract IP from envdURL
      const match = envdUrl.match(/http:\/\/([^:]+)/)
      if (match && match[1]) {
        const sandboxIP = match[1]
        // Kill all socat processes forwarding to this sandbox IP
        const killCmd = `pkill -f 'socat.*100.64.0.23.*${sandboxIP}'`
        await execAsync(killCmd).catch(() => {
          // Ignore errors if no processes found
        })
        console.log(`Cleaned up port forwarding for sandbox ${sandboxID} (IP: ${sandboxIP})`)
      }

      // Remove from tracking map
      this.sandboxPortForwards.delete(sandboxID)
    } catch (error) {
      console.error(`Error cleaning up port forwarding for ${sandboxID}:`, error)
    }
  }

  /**
   * Delete/stop a sandbox
   */
  async deleteSandbox(sandboxID: string): Promise<void> {
    // Clean up port forwarding first
    await this.cleanupPortForwarding(sandboxID)

    const response = await fetch(`${this.apiUrl}/sandboxes/${sandboxID}`, {
      method: 'DELETE',
      headers: {
        'X-API-Key': this.apiKey,
      },
    })

    if (!response.ok) {
      const error = await response.text()
      throw new Error(`Failed to delete sandbox: ${response.status} ${error}`)
    }

    // Clean up stored envd URL
    this.sandboxEnvdUrls.delete(sandboxID)
  }
}
