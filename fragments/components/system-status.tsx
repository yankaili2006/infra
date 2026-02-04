'use client'

import { useEffect, useState } from 'react'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { RefreshCw, CheckCircle2, XCircle, AlertCircle, HelpCircle } from 'lucide-react'

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

const StatusIcon = ({ status }: { status: string }) => {
  switch (status) {
    case 'running':
      return <CheckCircle2 className="h-4 w-4 text-green-500" />
    case 'stopped':
      return <XCircle className="h-4 w-4 text-red-500" />
    case 'error':
      return <AlertCircle className="h-4 w-4 text-yellow-500" />
    default:
      return <HelpCircle className="h-4 w-4 text-gray-400" />
  }
}

const StatusBadge = ({ status }: { status: string }) => {
  const variants: Record<string, 'default' | 'secondary' | 'destructive' | 'outline'> = {
    running: 'default',
    stopped: 'destructive',
    error: 'secondary',
    unknown: 'outline'
  }

  return (
    <Badge variant={variants[status] || 'outline'}>
      {status}
    </Badge>
  )
}

export function SystemStatus() {
  const [status, setStatus] = useState<SystemStatus | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const fetchStatus = async () => {
    try {
      setLoading(true)
      setError(null)
      const response = await fetch('/api/system/status')
      if (!response.ok) {
        throw new Error('Failed to fetch system status')
      }
      const data = await response.json()
      setStatus(data)
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Unknown error')
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    fetchStatus()
    // Auto-refresh every 30 seconds
    const interval = setInterval(fetchStatus, 30000)
    return () => clearInterval(interval)
  }, [])

  if (loading && !status) {
    return (
      <div className="flex items-center justify-center p-8">
        <RefreshCw className="h-6 w-6 animate-spin" />
      </div>
    )
  }

  if (error) {
    return (
      <Card>
        <CardHeader>
          <CardTitle className="text-red-500">Error</CardTitle>
        </CardHeader>
        <CardContent>
          <p>{error}</p>
          <Button onClick={fetchStatus} className="mt-4">
            Retry
          </Button>
        </CardContent>
      </Card>
    )
  }

  if (!status) return null

  const ServiceList = ({ services, title }: { services: ServiceStatus[], title: string }) => (
    <Card>
      <CardHeader>
        <CardTitle className="text-lg">{title}</CardTitle>
      </CardHeader>
      <CardContent>
        <div className="space-y-3">
          {services.map((service) => (
            <div key={service.name} className="flex items-center justify-between p-2 rounded-lg hover:bg-accent">
              <div className="flex items-center gap-3">
                <StatusIcon status={service.status} />
                <div>
                  <div className="font-medium">{service.name}</div>
                  {service.description && (
                    <div className="text-sm text-muted-foreground">{service.description}</div>
                  )}
                </div>
              </div>
              <div className="flex items-center gap-2">
                <StatusBadge status={service.status} />
                {service.url && (
                  <Button
                    variant="ghost"
                    size="sm"
                    onClick={() => window.open(service.url, '_blank')}
                  >
                    Open
                  </Button>
                )}
              </div>
            </div>
          ))}
        </div>
      </CardContent>
    </Card>
  )

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-2xl font-bold">系统状态</h2>
          <p className="text-sm text-muted-foreground">
            最后更新: {new Date(status.timestamp).toLocaleString('zh-CN')}
          </p>
        </div>
        <Button onClick={fetchStatus} variant="outline" size="sm" disabled={loading}>
          <RefreshCw className={`h-4 w-4 mr-2 ${loading ? 'animate-spin' : ''}`} />
          刷新
        </Button>
      </div>

      {/* Resources Overview */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        <Card>
          <CardHeader>
            <CardTitle className="text-lg">磁盘使用</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="space-y-2">
              <div className="flex justify-between">
                <span className="text-sm text-muted-foreground">总容量</span>
                <span className="font-medium">{status.resources.disk.total}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-sm text-muted-foreground">已使用</span>
                <span className="font-medium">{status.resources.disk.used}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-sm text-muted-foreground">可用</span>
                <span className="font-medium">{status.resources.disk.available}</span>
              </div>
              <div className="mt-4">
                <div className="flex justify-between mb-2">
                  <span className="text-sm font-medium">使用率</span>
                  <span className="text-sm font-medium">{status.resources.disk.usage}</span>
                </div>
                <div className="w-full bg-secondary rounded-full h-2">
                  <div
                    className="bg-primary h-2 rounded-full transition-all"
                    style={{ width: status.resources.disk.usage }}
                  />
                </div>
              </div>
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="text-lg">Docker 容器</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="space-y-2">
              <div className="flex justify-between">
                <span className="text-sm text-muted-foreground">总容器数</span>
                <span className="font-medium">{status.resources.docker.containers}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-sm text-muted-foreground">运行中</span>
                <span className="font-medium text-green-500">{status.resources.docker.running}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-sm text-muted-foreground">镜像数</span>
                <span className="font-medium">{status.resources.docker.images}</span>
              </div>
            </div>
          </CardContent>
        </Card>
      </div>

      {/* Services */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <ServiceList services={status.services.core} title="核心服务" />
        <ServiceList services={status.services.mcp} title="MCP 服务" />
        <ServiceList services={status.services.skills} title="Skills 技能" />
        <ServiceList services={status.services.infrastructure} title="基础设施" />
      </div>
    </div>
  )
}
