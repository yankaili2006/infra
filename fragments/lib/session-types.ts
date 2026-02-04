/**
 * Session History Types
 * 会话历史数据类型定义
 */

export interface ChatSession {
  id: string
  title: string
  createdAt: string
  updatedAt: string
  messageCount: number
  template: string
  model: string
  preview?: string // 第一条消息的预览
}

export interface SessionMessage {
  role: 'user' | 'assistant'
  content: string
  timestamp: string
  code?: string
  result?: any
}

export interface SessionDetail extends ChatSession {
  messages: SessionMessage[]
}

export interface SessionListResponse {
  sessions: ChatSession[]
  total: number
  page: number
  pageSize: number
}

export interface CreateSessionRequest {
  title?: string
  template: string
  model: string
}

export interface UpdateSessionRequest {
  title?: string
}

export interface AddMessageRequest {
  sessionId: string
  message: SessionMessage
}
