const active = new Set<string>()

export async function exclusive<T>(key: string, operation: () => Promise<T>): Promise<T> {
  if (active.has(key)) throw createError({ statusCode: 409, statusMessage: 'An operation is already running for this target.' })
  active.add(key)
  try {
    return await operation()
  } finally {
    active.delete(key)
  }
}
