import type { ActionRequest, ActionResponse } from '../../../shared/types'

export default defineEventHandler(async (event): Promise<ActionResponse> => {
  assertLocalOrigin(event)
  const name = getRouterParam(event, 'name') || ''
  assertValidName(name)
  const body = await readBody<ActionRequest>(event)
  const before = await getControlPlane()
  const instance = before.instances.find(item => item.name === name)
  if (!before.available || !instance) throw createError({ statusCode: 404, statusMessage: 'Instance not found in the latest Multipass list.' })
  try {
    assertDeleteConfirmation(body?.confirm, instance.posture.terraform.status === 'Managed', body?.acknowledgeTerraformDrift)
  } catch (error) {
    throw createError({ statusCode: 409, statusMessage: error instanceof Error ? error.message : 'Delete confirmation is required.' })
  }
  await exclusive(name, async () => runInstanceAction(name, 'delete'))
  invalidate()
  return { ok: true, action: 'delete', message: 'Instance moved to Multipass trash and remains recoverable.' }
})
