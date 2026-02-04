import { NextResponse } from 'next/server'
import { SessionStorage } from '@/lib/session-storage'

export const dynamic = 'force-dynamic'

/**
 * GET /api/sessions
 * 获取会话列表
 */
export async function GET(request: Request) {
  try {
    const { searchParams } = new URL(request.url)
    const page = parseInt(searchParams.get('page') || '1')
    const pageSize = parseInt(searchParams.get('pageSize') || '20')

    const result = await SessionStorage.listSessions(page, pageSize)

    return NextResponse.json({
      success: true,
      data: {
        sessions: result.sessions,
        total: result.total,
        page,
        pageSize
      }
    })
  } catch (error) {
    console.error('Error fetching sessions:', error)
    return NextResponse.json(
      { success: false, error: 'Failed to fetch sessions' },
      { status: 500 }
    )
  }
}

/**
 * POST /api/sessions
 * 创建新会话
 */
export async function POST(request: Request) {
  try {
    const body = await request.json()
    const { title, template, model } = body

    if (!template || !model) {
      return NextResponse.json(
        { success: false, error: 'Template and model are required' },
        { status: 400 }
      )
    }

    const session = await SessionStorage.createSession(
      title || '新对话',
      template,
      model
    )

    return NextResponse.json({
      success: true,
      data: session
    })
  } catch (error) {
    console.error('Error creating session:', error)
    return NextResponse.json(
      { success: false, error: 'Failed to create session' },
      { status: 500 }
    )
  }
}
