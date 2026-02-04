import { NextResponse } from 'next/server'
import { SessionStorage } from '@/lib/session-storage'

export const dynamic = 'force-dynamic'

/**
 * POST /api/sessions/[id]/messages
 * 添加消息到会话
 */
export async function POST(
  request: Request,
  { params }: { params: { id: string } }
) {
  try {
    const body = await request.json()
    const { message } = body

    if (!message) {
      return NextResponse.json(
        { success: false, error: 'Message is required' },
        { status: 400 }
      )
    }

    const session = await SessionStorage.addMessage(params.id, message)

    if (!session) {
      return NextResponse.json(
        { success: false, error: 'Session not found' },
        { status: 404 }
      )
    }

    return NextResponse.json({
      success: true,
      data: session
    })
  } catch (error) {
    console.error('Error adding message to session:', error)
    return NextResponse.json(
      { success: false, error: 'Failed to add message' },
      { status: 500 }
    )
  }
}
