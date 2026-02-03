/**
 * Health Check Utilities
 *
 * Provides reusable health check and resource readiness functions
 * based on lessons learned from production issues.
 *
 * @see /home/primihub/pcloud/docs/DEVELOPMENT_LESSONS_LEARNED.md
 */

export interface HealthCheckOptions {
  /** Maximum number of retry attempts (default: 30) */
  maxRetries?: number
  /** Interval between checks in milliseconds (default: 1000) */
  interval?: number
  /** Total timeout in milliseconds (default: 30000) */
  timeout?: number
  /** Function to call on each retry for progress feedback */
  onRetry?: (attempt: number, maxRetries: number) => void
  /** Function to call when check succeeds */
  onSuccess?: (attempt: number) => void
  /** Function to call when check times out */
  onTimeout?: () => void
}

export interface HealthCheckResult {
  /** Whether the resource is ready */
  ready: boolean
  /** Number of attempts made */
  attempts: number
  /** Time taken in milliseconds */
  duration: number
  /** Error message if failed */
  error?: string
}

/**
 * Wait for a resource to become ready using a health check function
 *
 * @example
 * ```typescript
 * const result = await waitForResource(
 *   async () => {
 *     const response = await fetch('http://localhost:3000/health')
 *     return response.ok
 *   },
 *   { maxRetries: 30, interval: 1000 }
 * )
 * ```
 */
export async function waitForResource(
  checkFn: () => Promise<boolean>,
  options: HealthCheckOptions = {}
): Promise<HealthCheckResult> {
  const {
    maxRetries = 30,
    interval = 1000,
    timeout = 30000,
    onRetry,
    onSuccess,
    onTimeout
  } = options

  const startTime = Date.now()
  let attempts = 0

  for (let i = 0; i < maxRetries; i++) {
    attempts++

    // Check timeout
    const elapsed = Date.now() - startTime
    if (elapsed > timeout) {
      onTimeout?.()
      return {
        ready: false,
        attempts,
        duration: elapsed,
        error: `Timeout after ${timeout}ms`
      }
    }

    try {
      const isReady = await checkFn()
      if (isReady) {
        const duration = Date.now() - startTime
        onSuccess?.(attempts)
        return {
          ready: true,
          attempts,
          duration
        }
      }
    } catch (error) {
      // Continue on error - resource might not be ready yet
    }

    onRetry?.(attempts, maxRetries)

    // Wait before next check
    if (i < maxRetries - 1) {
      await new Promise(resolve => setTimeout(resolve, interval))
    }
  }

  const duration = Date.now() - startTime
  return {
    ready: false,
    attempts,
    duration,
    error: `Resource not ready after ${maxRetries} attempts`
  }
}

/**
 * Check if an HTTP endpoint is responding
 *
 * @example
 * ```typescript
 * const isReady = await checkHttpEndpoint('http://localhost:3000')
 * ```
 */
export async function checkHttpEndpoint(url: string): Promise<boolean> {
  try {
    const response = await fetch(url, {
      method: 'GET',
      signal: AbortSignal.timeout(5000) // 5 second timeout
    })
    // Accept any HTTP response (even 404 means server is running)
    return response.status > 0
  } catch {
    return false
  }
}

/**
 * Check if a TCP port is listening using a command execution function
 *
 * @example
 * ```typescript
 * const isReady = await checkTcpPort(
 *   async (cmd) => await executeCommand(sandboxID, cmd),
 *   'localhost',
 *   3000
 * )
 * ```
 */
export async function checkTcpPort(
  executeFn: (command: string) => Promise<{ stdout: string; stderr: string; exitCode: number }>,
  host: string,
  port: number
): Promise<boolean> {
  try {
    const result = await executeFn(
      `curl -s -o /dev/null -w "%{http_code}" http://${host}:${port} || echo "000"`
    )
    const statusCode = result.stdout.trim()
    // Any non-zero status code means server is responding
    return statusCode !== '000' && statusCode !== ''
  } catch {
    return false
  }
}

/**
 * Wait for an HTTP endpoint to become ready
 *
 * @example
 * ```typescript
 * const result = await waitForHttpEndpoint('http://localhost:3000', {
 *   maxRetries: 30,
 *   onRetry: (attempt, max) => console.log(`Waiting... ${attempt}/${max}`)
 * })
 * ```
 */
export async function waitForHttpEndpoint(
  url: string,
  options: HealthCheckOptions = {}
): Promise<HealthCheckResult> {
  return waitForResource(
    () => checkHttpEndpoint(url),
    options
  )
}

/**
 * Wait for a TCP port to become ready
 *
 * @example
 * ```typescript
 * const result = await waitForTcpPort(
 *   async (cmd) => await client.executeCommand(sandboxID, cmd),
 *   'localhost',
 *   3000,
 *   { maxRetries: 30 }
 * )
 * ```
 */
export async function waitForTcpPort(
  executeFn: (command: string) => Promise<{ stdout: string; stderr: string; exitCode: number }>,
  host: string,
  port: number,
  options: HealthCheckOptions = {}
): Promise<HealthCheckResult> {
  return waitForResource(
    () => checkTcpPort(executeFn, host, port),
    options
  )
}

/**
 * Exponential backoff strategy for retries
 *
 * @example
 * ```typescript
 * for (let i = 0; i < maxRetries; i++) {
 *   const delay = exponentialBackoff(i, 1000, 10000)
 *   await sleep(delay)
 * }
 * ```
 */
export function exponentialBackoff(
  attempt: number,
  baseDelay: number = 1000,
  maxDelay: number = 10000
): number {
  const delay = Math.min(baseDelay * Math.pow(2, attempt), maxDelay)
  // Add jitter to avoid thundering herd
  return delay + Math.random() * 1000
}
