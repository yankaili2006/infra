import { exec } from 'child_process'
import { promisify } from 'util'

const execAsync = promisify(exec)

/**
 * Check if a service is reachable via HTTP
 */
export async function checkHttpService(url: string, timeout = 3000): Promise<boolean> {
  try {
    const controller = new AbortController()
    const timeoutId = setTimeout(() => controller.abort(), timeout)

    const response = await fetch(url, {
      method: 'HEAD',
      signal: controller.signal,
    })

    clearTimeout(timeoutId)
    return response.ok
  } catch (error) {
    return false
  }
}

/**
 * Get disk usage information
 */
export async function getDiskUsage(): Promise<{
  total: string
  used: string
  available: string
  usage: string
} | null> {
  try {
    const { stdout } = await execAsync("df -h / | tail -1 | awk '{print $2,$3,$4,$5}'")
    const [total, used, available, usage] = stdout.trim().split(' ')

    return { total, used, available, usage }
  } catch (error) {
    console.error('Error getting disk usage:', error)
    return null
  }
}

/**
 * Get Docker container information
 */
export async function getDockerInfo(): Promise<{
  containers: number
  running: number
  images: number
} | null> {
  try {
    const { stdout: containersOut } = await execAsync('docker ps -a --format "{{.ID}}" | wc -l')
    const { stdout: runningOut } = await execAsync('docker ps --format "{{.ID}}" | wc -l')
    const { stdout: imagesOut } = await execAsync('docker images --format "{{.ID}}" | wc -l')

    return {
      containers: parseInt(containersOut.trim()),
      running: parseInt(runningOut.trim()),
      images: parseInt(imagesOut.trim())
    }
  } catch (error) {
    console.error('Error getting Docker info:', error)
    return null
  }
}

/**
 * Check if a Docker container is running
 */
export async function checkDockerContainer(containerName: string): Promise<boolean> {
  try {
    const { stdout } = await execAsync(`docker ps --filter "name=${containerName}" --format "{{.Names}}"`)
    return stdout.trim().length > 0
  } catch (error) {
    return false
  }
}
