type HeaderEvent = Parameters<typeof getHeader>[0]

export function assertLocalOrigin(event: HeaderEvent): void {
  const origin = getHeader(event, 'origin')
  const host = getHeader(event, 'host')
  if (!origin || !host) throw createError({ statusCode: 403, statusMessage: 'A local Origin header is required.' })
  let parsed: URL
  try {
    parsed = new URL(origin)
  } catch {
    throw createError({ statusCode: 403, statusMessage: 'Invalid Origin header.' })
  }
  const hostname = parsed.hostname.replace(/^\[|\]$/g, '')
  if (!['127.0.0.1', 'localhost', '::1'].includes(hostname) || parsed.host !== host) {
    throw createError({ statusCode: 403, statusMessage: 'Mutating requests must originate from this local application.' })
  }
}
