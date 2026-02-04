import { handleAPIError, createRateLimitResponse } from '@/lib/api-errors'
import { Duration } from '@/lib/duration'
import { getModelClient, LLMModel, LLMModelConfig } from '@/lib/models'
import { toPrompt } from '@/lib/prompt'
import ratelimit from '@/lib/ratelimit'
import { fragmentSchema as schema } from '@/lib/schema'
import templates, { Templates } from '@/lib/templates'
import { selectTemplateFromMessages, getTemplateName } from '@/lib/template-selector'
import { streamObject, LanguageModel, CoreMessage } from 'ai'

export const maxDuration = 300

const rateLimitMaxRequests = process.env.RATE_LIMIT_MAX_REQUESTS
  ? parseInt(process.env.RATE_LIMIT_MAX_REQUESTS)
  : 10
const ratelimitWindow = process.env.RATE_LIMIT_WINDOW
  ? (process.env.RATE_LIMIT_WINDOW as Duration)
  : '1d'

export async function POST(req: Request) {
  const {
    messages,
    userID,
    teamID,
    template: requestedTemplate,
    model,
    config,
  }: {
    messages: CoreMessage[]
    userID: string | undefined
    teamID: string | undefined
    template?: Templates | string
    model: LLMModel
    config: LLMModelConfig
  } = await req.json()

  const limit = !config.apiKey
    ? await ratelimit(
        req.headers.get('x-forwarded-for'),
        rateLimitMaxRequests,
        ratelimitWindow,
      )
    : false

  if (limit) {
    return createRateLimitResponse(limit)
  }

  // Auto-select template if not provided or if all templates passed (auto mode)
  let templateKey: string
  let templateObj: Templates
  let autoSelected = false

  if (!requestedTemplate || requestedTemplate === '' || typeof requestedTemplate === 'object') {
    templateKey = selectTemplateFromMessages(messages)
    templateObj = (requestedTemplate as Templates) || templates
    autoSelected = true
    console.log('🤖 Auto-selected template:', templateKey, `(${getTemplateName(templateKey)})`)
  } else {
    templateKey = requestedTemplate
    // When a string key is provided, use all templates
    templateObj = templates
    console.log('📌 Using requested template:', templateKey)
  }

  console.log('userID', userID)
  console.log('teamID', teamID)
  console.log('template', JSON.stringify(templateKey, null, 2))
  console.log('template type:', typeof templateKey)
  console.log('auto-selected:', autoSelected)
  console.log('model', model)
  // console.log('config', config)

  const { model: modelNameString, apiKey: modelApiKey, ...modelParams } = config
  const modelClient = getModelClient(model, config)

  try {
    const stream = await streamObject({
      model: modelClient as LanguageModel,
      schema,
      system: toPrompt(templateObj),
      messages,
      maxRetries: 0, // do not retry on errors
      ...modelParams,
    })

    return stream.toTextStreamResponse()
  } catch (error: any) {
    return handleAPIError(error, { hasOwnApiKey: !!config.apiKey })
  }
}
