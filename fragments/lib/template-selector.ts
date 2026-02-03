import { CoreMessage } from 'ai'
import templates from './templates'

/**
 * Analyzes user messages to determine the most appropriate template
 * based on task type and user intent
 */
export function selectTemplateFromMessages(messages: CoreMessage[]): string {
  // Get the last user message
  const lastUserMessage = messages
    .filter(m => m.role === 'user')
    .pop()

  if (!lastUserMessage || typeof lastUserMessage.content !== 'string') {
    return 'code-interpreter-v1' // Default fallback
  }

  const content = lastUserMessage.content.toLowerCase()

  // Desktop environment keywords
  const desktopKeywords = [
    'desktop', 'gui', 'vnc', 'browser', 'firefox', 'chrome',
    'visual', 'click', 'mouse', 'window', 'screen', 'display',
    '桌面', '浏览器', '界面', '窗口', '屏幕'
  ]

  // Next.js/React keywords
  const nextjsKeywords = [
    'nextjs', 'next.js', 'react', 'frontend', 'web app', 'website',
    'ui', 'component', 'page', 'routing', 'tailwind',
    '前端', '网页', '页面', '组件'
  ]

  // Python/Data analysis keywords
  const pythonKeywords = [
    'python', 'jupyter', 'pandas', 'numpy', 'matplotlib',
    'data analysis', 'plot', 'chart', 'dataframe', 'csv',
    '数据分析', '绘图', '图表', '数据处理'
  ]

  // Base Linux keywords
  const baseKeywords = [
    'bash', 'shell', 'command', 'script', 'linux', 'file',
    'directory', 'curl', 'wget', 'grep', 'sed', 'awk', 'ls', 'cd', 'mkdir',
    '命令', '脚本', '文件操作', '系统', '列出', '目录', '文件', '查看'
  ]

  // Check for desktop environment
  if (desktopKeywords.some(keyword => content.includes(keyword))) {
    return 'desktop-template-000-0000-0000-000000000001'
  }

  // Check for Next.js/React
  if (nextjsKeywords.some(keyword => content.includes(keyword))) {
    return 'nextjs-developer-dev'
  }

  // Check for Python/Data analysis
  if (pythonKeywords.some(keyword => content.includes(keyword))) {
    return 'code-interpreter-v1'
  }

  // Check for base Linux
  if (baseKeywords.some(keyword => content.includes(keyword))) {
    return 'base'
  }

  // Default: code-interpreter for general coding tasks
  return 'code-interpreter-v1'
}

/**
 * Get template display name for logging
 */
export function getTemplateName(templateId: string): string {
  const template = templates[templateId as keyof typeof templates]
  return template ? template.name : templateId
}
