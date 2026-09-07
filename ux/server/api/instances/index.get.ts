export default defineEventHandler(async (event) => {
  const deep = getQuery(event).deep !== 'false'
  return getControlPlane({ deep })
})
