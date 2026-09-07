import type { ActionResponse } from '../../shared/types'

export default defineEventHandler(async (event): Promise<ActionResponse> => {
  assertLocalOrigin(event)
  const body = await readBody<{ confirmation?: string }>(event)
  try {
    assertPurgeConfirmation(body?.confirmation)
  } catch (error) {
    throw createError({ statusCode: 400, statusMessage: error instanceof Error ? error.message : 'The exact purge confirmation phrase is required.' })
  }
  await exclusive('__purge__', purgeInstances)
  invalidate()
  return { ok: true, action: 'purge', message: 'Deleted instances were permanently purged.' }
})
