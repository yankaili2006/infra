'use client'

import { useEffect, useState } from 'react'
import { useRouter } from 'next/navigation'
import { formatDistanceToNow, isToday, isYesterday, isThisWeek, isThisMonth } from 'date-fns'
import { zhCN } from 'date-fns/locale'
import { MessageSquare, Trash2, Edit2, Plus, Search, X, Download, ChevronDown, ChevronRight } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { ScrollArea } from '@/components/ui/scroll-area'
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from '@/components/ui/alert-dialog'
import { Input } from '@/components/ui/input'
import { ChatSession } from '@/lib/session-types'

interface SessionListProps {
  currentSessionId?: string
  onSessionSelect?: (sessionId: string) => void
  onNewSession?: () => void
}

export function SessionList({
  currentSessionId,
  onSessionSelect,
  onNewSession
}: SessionListProps) {
  const router = useRouter()
  const [sessions, setSessions] = useState<ChatSession[]>([])
  const [loading, setLoading] = useState(true)
  const [deleteDialogOpen, setDeleteDialogOpen] = useState(false)
  const [renameDialogOpen, setRenameDialogOpen] = useState(false)
  const [exportDialogOpen, setExportDialogOpen] = useState(false)
  const [selectedSession, setSelectedSession] = useState<ChatSession | null>(null)
  const [newTitle, setNewTitle] = useState('')
  const [searchQuery, setSearchQuery] = useState('')
  const [collapsedGroups, setCollapsedGroups] = useState<Set<string>>(new Set())
  const [groupMode, setGroupMode] = useState<'date' | 'template' | 'model'>('date')

  // 加载会话列表
  const loadSessions = async () => {
    try {
      const response = await fetch('/api/sessions')
      const data = await response.json()
      if (data.success) {
        setSessions(data.data.sessions)
      }
    } catch (error) {
      console.error('Failed to load sessions:', error)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    loadSessions()
  }, [])

  // 过滤会话
  const filteredSessions = sessions.filter((session) => {
    if (!searchQuery.trim()) return true
    const query = searchQuery.toLowerCase()
    return (
      session.title.toLowerCase().includes(query) ||
      (session.preview && session.preview.toLowerCase().includes(query))
    )
  })

  // 按日期分组会话
  const groupSessionsByDate = (sessions: ChatSession[]) => {
    const groups: { [key: string]: ChatSession[] } = {
      '今天': [],
      '昨天': [],
      '本周': [],
      '本月': [],
      '更早': []
    }

    sessions.forEach((session) => {
      const date = new Date(session.updatedAt)
      if (isToday(date)) {
        groups['今天'].push(session)
      } else if (isYesterday(date)) {
        groups['昨天'].push(session)
      } else if (isThisWeek(date, { weekStartsOn: 1 })) {
        groups['本周'].push(session)
      } else if (isThisMonth(date)) {
        groups['本月'].push(session)
      } else {
        groups['更早'].push(session)
      }
    })

    // 过滤掉空分组
    return Object.entries(groups).filter(([_, sessions]) => sessions.length > 0)
  }

  // 按模板分组会话
  const groupSessionsByTemplate = (sessions: ChatSession[]) => {
    const groups: { [key: string]: ChatSession[] } = {}

    sessions.forEach((session) => {
      const template = session.template || 'auto'
      if (!groups[template]) {
        groups[template] = []
      }
      groups[template].push(session)
    })

    return Object.entries(groups).filter(([_, sessions]) => sessions.length > 0)
  }

  // 按模型分组会话
  const groupSessionsByModel = (sessions: ChatSession[]) => {
    const groups: { [key: string]: ChatSession[] } = {}

    sessions.forEach((session) => {
      const model = session.model || 'unknown'
      if (!groups[model]) {
        groups[model] = []
      }
      groups[model].push(session)
    })

    return Object.entries(groups).filter(([_, sessions]) => sessions.length > 0)
  }

  // 根据分组模式获取分组会话
  const groupedSessions =
    groupMode === 'date' ? groupSessionsByDate(filteredSessions) :
    groupMode === 'template' ? groupSessionsByTemplate(filteredSessions) :
    groupSessionsByModel(filteredSessions)

  // 切换分组折叠状态
  const toggleGroup = (groupName: string) => {
    setCollapsedGroups((prev) => {
      const newSet = new Set(prev)
      if (newSet.has(groupName)) {
        newSet.delete(groupName)
      } else {
        newSet.add(groupName)
      }
      return newSet
    })
  }

  // 选择会话
  const handleSelectSession = (session: ChatSession) => {
    if (onSessionSelect) {
      onSessionSelect(session.id)
    } else {
      router.push(`/?session=${session.id}`)
    }
  }

  // 删除会话
  const handleDeleteSession = async () => {
    if (!selectedSession) return

    try {
      const response = await fetch(`/api/sessions/${selectedSession.id}`, {
        method: 'DELETE'
      })
      const data = await response.json()

      if (data.success) {
        setSessions(sessions.filter(s => s.id !== selectedSession.id))
        setDeleteDialogOpen(false)
        setSelectedSession(null)

        // 如果删除的是当前会话，跳转到首页
        if (currentSessionId === selectedSession.id) {
          router.push('/')
        }
      }
    } catch (error) {
      console.error('Failed to delete session:', error)
    }
  }

  // 重命名会话
  const handleRenameSession = async () => {
    if (!selectedSession || !newTitle.trim()) return

    try {
      const response = await fetch(`/api/sessions/${selectedSession.id}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ title: newTitle.trim() })
      })
      const data = await response.json()

      if (data.success) {
        setSessions(sessions.map(s =>
          s.id === selectedSession.id ? { ...s, title: newTitle.trim() } : s
        ))
        setRenameDialogOpen(false)
        setSelectedSession(null)
        setNewTitle('')
      }
    } catch (error) {
      console.error('Failed to rename session:', error)
    }
  }

  // 打开删除对话框
  const openDeleteDialog = (session: ChatSession, e: React.MouseEvent) => {
    e.stopPropagation()
    setSelectedSession(session)
    setDeleteDialogOpen(true)
  }

  // 打开重命名对话框
  const openRenameDialog = (session: ChatSession, e: React.MouseEvent) => {
    e.stopPropagation()
    setSelectedSession(session)
    setNewTitle(session.title)
    setRenameDialogOpen(true)
  }

  // 打开导出对话框
  const openExportDialog = (session: ChatSession, e: React.MouseEvent) => {
    e.stopPropagation()
    setSelectedSession(session)
    setExportDialogOpen(true)
  }

  // 导出为 Markdown
  const exportAsMarkdown = async () => {
    if (!selectedSession) return

    try {
      const response = await fetch(`/api/sessions/${selectedSession.id}`)
      const data = await response.json()

      if (data.success) {
        const session = data.data
        let markdown = `# ${session.title}\n\n`
        markdown += `**创建时间**: ${new Date(session.createdAt).toLocaleString('zh-CN')}\n`
        markdown += `**更新时间**: ${new Date(session.updatedAt).toLocaleString('zh-CN')}\n`
        markdown += `**消息数量**: ${session.messageCount}\n`
        markdown += `**模板**: ${session.template}\n`
        markdown += `**模型**: ${session.model}\n\n`
        markdown += `---\n\n`

        session.messages.forEach((msg: any, index: number) => {
          markdown += `## ${msg.role === 'user' ? '用户' : '助手'} (${new Date(msg.timestamp).toLocaleString('zh-CN')})\n\n`
          markdown += `${msg.content}\n\n`
          if (msg.code) {
            markdown += `\`\`\`\n${msg.code}\n\`\`\`\n\n`
          }
        })

        const blob = new Blob([markdown], { type: 'text/markdown' })
        const url = URL.createObjectURL(blob)
        const a = document.createElement('a')
        a.href = url
        a.download = `${session.title.replace(/[^a-zA-Z0-9\u4e00-\u9fa5]/g, '_')}.md`
        document.body.appendChild(a)
        a.click()
        document.body.removeChild(a)
        URL.revokeObjectURL(url)

        setExportDialogOpen(false)
        setSelectedSession(null)
      }
    } catch (error) {
      console.error('Failed to export as Markdown:', error)
    }
  }

  // 导出为 JSON
  const exportAsJSON = async () => {
    if (!selectedSession) return

    try {
      const response = await fetch(`/api/sessions/${selectedSession.id}`)
      const data = await response.json()

      if (data.success) {
        const session = data.data
        const json = JSON.stringify(session, null, 2)

        const blob = new Blob([json], { type: 'application/json' })
        const url = URL.createObjectURL(blob)
        const a = document.createElement('a')
        a.href = url
        a.download = `${session.title.replace(/[^a-zA-Z0-9\u4e00-\u9fa5]/g, '_')}.json`
        document.body.appendChild(a)
        a.click()
        document.body.removeChild(a)
        URL.revokeObjectURL(url)

        setExportDialogOpen(false)
        setSelectedSession(null)
      }
    } catch (error) {
      console.error('Failed to export as JSON:', error)
    }
  }

  if (loading) {
    return (
      <div className="flex items-center justify-center h-full">
        <div className="text-sm text-muted-foreground">加载中...</div>
      </div>
    )
  }

  return (
    <div className="flex flex-col h-full">
      {/* 新建对话按钮 */}
      <div className="p-4 border-b">
        <Button
          onClick={onNewSession || (() => router.push('/'))}
          className="w-full"
          variant="default"
        >
          <Plus className="h-4 w-4 mr-2" />
          新建对话
        </Button>
      </div>

      {/* 搜索框 */}
      <div className="p-4 border-b">
        <div className="relative">
          <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
          <Input
            type="text"
            placeholder="搜索会话..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="pl-9 pr-9"
          />
          {searchQuery && (
            <Button
              variant="ghost"
              size="icon"
              className="absolute right-1 top-1/2 h-7 w-7 -translate-y-1/2"
              onClick={() => setSearchQuery('')}
            >
              <X className="h-4 w-4" />
            </Button>
          )}
        </div>
      </div>

      {/* 分组模式选择器 */}
      <div className="px-4 py-2 border-b">
        <div className="flex gap-1 p-1 bg-muted rounded-lg">
          <Button
            variant={groupMode === 'date' ? 'default' : 'ghost'}
            size="sm"
            className="flex-1 text-xs"
            onClick={() => setGroupMode('date')}
          >
            按时间
          </Button>
          <Button
            variant={groupMode === 'template' ? 'default' : 'ghost'}
            size="sm"
            className="flex-1 text-xs"
            onClick={() => setGroupMode('template')}
          >
            按模板
          </Button>
          <Button
            variant={groupMode === 'model' ? 'default' : 'ghost'}
            size="sm"
            className="flex-1 text-xs"
            onClick={() => setGroupMode('model')}
          >
            按模型
          </Button>
        </div>
      </div>

      {/* 会话列表 */}
      <ScrollArea className="flex-1">
        <div className="p-2 space-y-3">
          {sessions.length === 0 ? (
            <div className="text-center py-8 text-sm text-muted-foreground">
              暂无会话记录
            </div>
          ) : filteredSessions.length === 0 ? (
            <div className="text-center py-8 text-sm text-muted-foreground">
              未找到匹配的会话
            </div>
          ) : (
            groupedSessions.map(([groupName, groupSessions]) => (
              <div key={groupName} className="space-y-1">
                {/* 分组标题 */}
                <div
                  className="flex items-center gap-2 px-2 py-1 cursor-pointer hover:bg-accent/50 rounded-md transition-colors"
                  onClick={() => toggleGroup(groupName)}
                >
                  {collapsedGroups.has(groupName) ? (
                    <ChevronRight className="h-4 w-4 text-muted-foreground" />
                  ) : (
                    <ChevronDown className="h-4 w-4 text-muted-foreground" />
                  )}
                  <span className="text-xs font-semibold text-muted-foreground uppercase">
                    {groupName} ({groupSessions.length})
                  </span>
                </div>

                {/* 分组会话列表 */}
                {!collapsedGroups.has(groupName) && groupSessions.map((session) => (
              <div
                key={session.id}
                className={`
                  group relative p-3 rounded-lg cursor-pointer
                  transition-colors hover:bg-accent
                  ${currentSessionId === session.id ? 'bg-accent' : ''}
                `}
                onClick={() => handleSelectSession(session)}
              >
                <div className="flex items-start gap-3">
                  <MessageSquare className="h-4 w-4 mt-1 flex-shrink-0 text-muted-foreground" />
                  <div className="flex-1 min-w-0">
                    <div className="font-medium text-sm truncate">
                      {session.title}
                    </div>
                    {session.preview && (
                      <div className="text-xs text-muted-foreground truncate mt-1">
                        {session.preview}
                      </div>
                    )}
                    <div className="flex items-center gap-2 mt-2 text-xs text-muted-foreground">
                      <span>
                        {formatDistanceToNow(new Date(session.updatedAt), {
                          addSuffix: true,
                          locale: zhCN
                        })}
                      </span>
                      <span>·</span>
                      <span>{session.messageCount} 条消息</span>
                    </div>
                  </div>
                </div>

                {/* 操作按钮 */}
                <div className="absolute top-2 right-2 opacity-0 group-hover:opacity-100 transition-opacity flex gap-1">
                  <Button
                    variant="ghost"
                    size="icon"
                    className="h-7 w-7"
                    onClick={(e) => openExportDialog(session, e)}
                  >
                    <Download className="h-3 w-3" />
                  </Button>
                  <Button
                    variant="ghost"
                    size="icon"
                    className="h-7 w-7"
                    onClick={(e) => openRenameDialog(session, e)}
                  >
                    <Edit2 className="h-3 w-3" />
                  </Button>
                  <Button
                    variant="ghost"
                    size="icon"
                    className="h-7 w-7 text-destructive hover:text-destructive"
                    onClick={(e) => openDeleteDialog(session, e)}
                  >
                    <Trash2 className="h-3 w-3" />
                  </Button>
                </div>
              </div>
                ))}
              </div>
            ))
          )}
        </div>
      </ScrollArea>

      {/* 删除确认对话框 */}
      <AlertDialog open={deleteDialogOpen} onOpenChange={setDeleteDialogOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>确认删除</AlertDialogTitle>
            <AlertDialogDescription>
              确定要删除会话 &ldquo;{selectedSession?.title}&rdquo; 吗？此操作无法撤销。
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>取消</AlertDialogCancel>
            <AlertDialogAction onClick={handleDeleteSession}>
              删除
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

      {/* 重命名对话框 */}
      <AlertDialog open={renameDialogOpen} onOpenChange={setRenameDialogOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>重命名会话</AlertDialogTitle>
            <AlertDialogDescription>
              <Input
                value={newTitle}
                onChange={(e) => setNewTitle(e.target.value)}
                placeholder="输入新的会话标题"
                className="mt-2"
                onKeyDown={(e) => {
                  if (e.key === 'Enter') {
                    handleRenameSession()
                  }
                }}
              />
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>取消</AlertDialogCancel>
            <AlertDialogAction onClick={handleRenameSession}>
              确定
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

      {/* 导出对话框 */}
      <AlertDialog open={exportDialogOpen} onOpenChange={setExportDialogOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>导出会话</AlertDialogTitle>
            <AlertDialogDescription>
              选择导出格式：
            </AlertDialogDescription>
          </AlertDialogHeader>
          <div className="flex flex-col gap-2 py-4">
            <Button
              variant="outline"
              className="w-full justify-start"
              onClick={exportAsMarkdown}
            >
              <Download className="h-4 w-4 mr-2" />
              导出为 Markdown (.md)
            </Button>
            <Button
              variant="outline"
              className="w-full justify-start"
              onClick={exportAsJSON}
            >
              <Download className="h-4 w-4 mr-2" />
              导出为 JSON (.json)
            </Button>
          </div>
          <AlertDialogFooter>
            <AlertDialogCancel>取消</AlertDialogCancel>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  )
}
