import { NextResponse } from 'next/server'
import { SessionStorage } from '@/lib/session-storage'

export const dynamic = 'force-dynamic'

/**
 * GET /api/sessions/[id]
 * 获取会话详情
 */
export async function GET(
  request: Request,
  { params }: { params: { id: string } }
) {
  try {
    const session = await SessionStorage.getSession(params.id)

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
    console.error('Error fetching session:', error)
    return NextResponse.json(
      { success: false, error: 'Failed to fetch session' },
      { status: 500 }
    )
  }
}

/**
 * PATCH /api/sessions/[id]
 * 更新会话
 */
export async function PATCH(
  request: Request,
  { params }: { params: { id: string } }
) {
  try {
    const body = await request.json()
    const session = await SessionStorage.updateSession(params.id, body)

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
    console.error('Error updating session:', error)
    return NextResponse.json(
      { success: false, error: 'Failed to update session' },
      { status: 500 }
    )
  }
}

/**
 * DELETE /api/sessions/[id]
 * 删除会话
 */
export async function DELETE(
  request: Request,
  { params }: { params: { id: string } }
) {
  try {
    const success = await SessionStorage.deleteSession(params.id)

    if (!success) {
      return NextResponse.json(
        { success: false, error: 'Session not found' },
        { status: 404 }
      )
    }

    return NextResponse.json({
      success: true,
      message: 'Session deleted successfully'
    })
  } catch (error) {
    console.error('Error deleting session:', error)
    return NextResponse.json(
      { success: false, error: 'Failed to delete session' },
      { status: 500 }
    )
  }
}
