import { Button, ButtonProps } from './button'
import { Check, Copy } from 'lucide-react'
import { useState, forwardRef } from 'react'

export const CopyButton = forwardRef<
  HTMLButtonElement,
  {
    variant?: ButtonProps['variant']
    content: string
    onCopy?: () => void
    className?: string
  }
>(({ variant = 'ghost', content, onCopy, className, ...props }, ref) => {
  const [copied, setCopied] = useState(false)

  function copy(content: string) {
    setCopied(true)

    // Check if clipboard API is available
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(content).catch(err => {
        console.error('Failed to copy:', err)
        fallbackCopy(content)
      })
    } else {
      fallbackCopy(content)
    }

    setTimeout(() => setCopied(false), 1000)
    onCopy?.()
  }

  function fallbackCopy(content: string) {
    // Fallback for browsers without clipboard API
    const textArea = document.createElement('textarea')
    textArea.value = content
    textArea.style.position = 'fixed'
    textArea.style.left = '-999999px'
    document.body.appendChild(textArea)
    textArea.select()
    try {
      document.execCommand('copy')
    } catch (err) {
      console.error('Fallback copy failed:', err)
    }
    document.body.removeChild(textArea)
  }

  return (
    <Button
      {...props}
      ref={ref}
      variant={variant}
      size="icon"
      className={className}
      onClick={() => copy(content)}
    >
      {copied ? <Check className="h-4 w-4" /> : <Copy className="h-4 w-4" />}
    </Button>
  )
})

CopyButton.displayName = 'CopyButton'
