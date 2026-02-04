import fs from 'fs/promises'
import path from 'path'
import { ChatSession, SessionDetail, SessionMessage } from './session-types'

const SESSIONS_DIR = path.join(process.cwd(), '.sessions')

/**
 * Session Storage Manager
 * 会话存储管理器 - 使用文件系统存储
 */
export class SessionStorage {
  /**
   * 确保会话目录存在
   */
  private static async ensureDir() {
    try {
      await fs.access(SESSIONS_DIR)
    } catch {
      await fs.mkdir(SESSIONS_DIR, { recursive: true })
    }
  }

  /**
   * 生成会话 ID
   */
  private static generateId(): string {
    return `session_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`
  }

  /**
   * 获取会话文件路径
   */
  private static getSessionPath(sessionId: string): string {
    return path.join(SESSIONS_DIR, `${sessionId}.json`)
  }

  /**
   * 创建新会话
   */
  static async createSession(
    title: string,
    template: string,
    model: string
  ): Promise<ChatSession> {
    await this.ensureDir()

    const session: SessionDetail = {
      id: this.generateId(),
      title: title || '新对话',
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
      messageCount: 0,
      template,
      model,
      messages: []
    }

    await fs.writeFile(
      this.getSessionPath(session.id),
      JSON.stringify(session, null, 2)
    )

    return session
  }

  /**
   * 获取会话详情
   */
  static async getSession(sessionId: string): Promise<SessionDetail | null> {
    try {
      const data = await fs.readFile(this.getSessionPath(sessionId), 'utf-8')
      return JSON.parse(data)
    } catch {
      return null
    }
  }

  /**
   * 获取所有会话列表
   */
  static async listSessions(page = 1, pageSize = 20): Promise<{
    sessions: ChatSession[]
    total: number
  }> {
    await this.ensureDir()

    try {
      const files = await fs.readdir(SESSIONS_DIR)
      const sessionFiles = files.filter(f => f.endsWith('.json'))

      const sessions: ChatSession[] = []
      for (const file of sessionFiles) {
        try {
          const data = await fs.readFile(path.join(SESSIONS_DIR, file), 'utf-8')
          const session: SessionDetail = JSON.parse(data)
          sessions.push({
            id: session.id,
            title: session.title,
            createdAt: session.createdAt,
            updatedAt: session.updatedAt,
            messageCount: session.messageCount,
            template: session.template,
            model: session.model,
            preview: session.messages[0]?.content.substring(0, 100)
          })
        } catch (error) {
          console.error(`Error reading session file ${file}:`, error)
        }
      }

      // 按更新时间排序
      sessions.sort((a, b) =>
        new Date(b.updatedAt).getTime() - new Date(a.updatedAt).getTime()
      )

      const start = (page - 1) * pageSize
      const end = start + pageSize

      return {
        sessions: sessions.slice(start, end),
        total: sessions.length
      }
    } catch {
      return { sessions: [], total: 0 }
    }
  }

  /**
   * 更新会话
   */
  static async updateSession(
    sessionId: string,
    updates: Partial<ChatSession>
  ): Promise<SessionDetail | null> {
    const session = await this.getSession(sessionId)
    if (!session) return null

    const updated = {
      ...session,
      ...updates,
      updatedAt: new Date().toISOString()
    }

    await fs.writeFile(
      this.getSessionPath(sessionId),
      JSON.stringify(updated, null, 2)
    )

    return updated
  }

  /**
   * 添加消息到会话
   */
  static async addMessage(
    sessionId: string,
    message: SessionMessage
  ): Promise<SessionDetail | null> {
    const session = await this.getSession(sessionId)
    if (!session) return null

    session.messages.push(message)
    session.messageCount = session.messages.length
    session.updatedAt = new Date().toISOString()

    // 如果是第一条消息，自动生成标题
    if (session.messages.length === 1 && session.title === '新对话') {
      session.title = message.content.substring(0, 50) + (message.content.length > 50 ? '...' : '')
    }

    await fs.writeFile(
      this.getSessionPath(sessionId),
      JSON.stringify(session, null, 2)
    )

    return session
  }

  /**
   * 删除会话
   */
  static async deleteSession(sessionId: string): Promise<boolean> {
    try {
      await fs.unlink(this.getSessionPath(sessionId))
      return true
    } catch {
      return false
    }
  }
}
