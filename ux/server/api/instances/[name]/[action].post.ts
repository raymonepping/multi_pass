import type { ActionRequest, ActionResponse, InstanceAction } from '../../../../shared/types'

export default defineEventHandler(async (event): Promise<ActionResponse> => {
  assertLocalOrigin(event)
  const name = getRouterParam(event, 'name') || ''
  const action = getRouterParam(event, 'action') || ''
  assertValidName(name)
  if (!INSTANCE_ACTIONS.includes(action as InstanceAction) || action === 'delete') {
    throw createError({ statusCode: 404, statusMessage: 'Unsupported instance action.' })
  }
  const body = await readBody<ActionRequest>(event)
  try {
    assertInstanceConfirmation(body?.confirm)
  } catch (error) {
    throw createError({ statusCode: 400, statusMessage: error instanceof Error ? error.message : 'Explicit confirmation is required.' })
  }

  const before = await getControlPlane()
  if (!before.available || !before.instances.some(item => item.name === name)) {
    throw createError({ statusCode: 404, statusMessage: 'Instance not found in the latest Multipass list.' })
  }
  await exclusive(name, async () => runInstanceAction(name, action as InstanceAction))
  invalidate()
  const after = await getControlPlane()
  return { ok: true, action: action as InstanceAction, message: `${action} completed; posture was refreshed.`, instance: after.instances.find(item => item.name === name) || null }
})
