import { NextResponse } from 'next/server'
import {
  checkHttpService,
  getDiskUsage,
  getDockerInfo,
  checkDockerContainer
} from '@/lib/system-checks'

export const dynamic = 'force-dynamic'

interface ServiceStatus {
  name: string
  status: 'running' | 'stopped' | 'error' | 'unknown'
  url?: string
  description?: string
}

interface SystemStatus {
  timestamp: string
  services: {
    core: ServiceStatus[]
    mcp: ServiceStatus[]
    skills: ServiceStatus[]
    infrastructure: ServiceStatus[]
  }
  resources: {
    disk: {
      total: string
      used: string
      available: string
      usage: string
    }
    docker: {
      containers: number
      running: number
      images: number
    }
  }
}

export async function GET() {
  try {
    // Check service status in parallel
    const [
      fragmentsStatus,
      nocodbStatus,
      diskUsage,
      dockerInfo
    ] = await Promise.all([
      checkHttpService('http://localhost:3001'),
      checkHttpService('http://localhost:8080'),
      getDiskUsage(),
      getDockerInfo()
    ])

    const status: SystemStatus = {
      timestamp: new Date().toISOString(),
      services: {
        core: [
          {
            name: 'Fragments UI',
            status: fragmentsStatus ? 'running' : 'stopped',
            url: 'http://localhost:3001',
            description: 'AI代码执行界面'
          },
          {
            name: 'E2B Orchestrator',
            status: 'unknown',
            description: '代码执行编排器'
          },
          {
            name: 'NocoDB',
            status: nocodbStatus ? 'running' : 'stopped',
            url: 'http://localhost:8080',
            description: '数据管理平台'
          }
        ],
        mcp: [
          {
            name: 'MCP Proxy',
            status: 'unknown',
            description: 'MCP服务代理'
          }
        ],
        skills: [
          {
            name: 'Infrastructure Skill',
            status: 'unknown',
            description: '基础设施监控'
          },
          {
            name: 'Server Skill',
            status: 'unknown',
            description: '服务器管理'
          }
        ],
        infrastructure: [
          {
            name: 'Proxmox',
            status: 'unknown',
            description: '虚拟化平台'
          },
          {
            name: 'Docker',
            status: dockerInfo ? 'running' : 'stopped',
            description: '容器平台'
          }
        ]
      },
      resources: {
        disk: diskUsage || {
          total: '98G',
          used: '43G',
          available: '51G',
          usage: '46%'
        },
        docker: dockerInfo || {
          containers: 0,
          running: 0,
          images: 0
        }
      }
    }

    return NextResponse.json(status)
  } catch (error) {
    console.error('Error fetching system status:', error)
    return NextResponse.json(
      { error: 'Failed to fetch system status' },
      { status: 500 }
    )
  }
}
