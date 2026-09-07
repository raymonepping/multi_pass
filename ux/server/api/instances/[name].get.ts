export default defineEventHandler(async (event) => {
  const name = getRouterParam(event, 'name') || ''
  assertValidName(name)
  const plane = await getControlPlane()
  if (!plane.available) return { available: false, message: plane.message, observedAt: plane.observedAt, instance: null, cluster: [] }
  const instance = plane.instances.find(item => item.name === name)
  if (!instance) throw createError({ statusCode: 404, statusMessage: 'Instance not found.' })
  return { available: true, message: null, observedAt: plane.observedAt, instance, cluster: plane.cluster }
})
