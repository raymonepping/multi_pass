interface CacheEntry<T> { value: T, expiresAt: number }
const cache = new Map<string, CacheEntry<unknown>>()

export async function cached<T>(key: string, ttlMs: number, load: () => Promise<T>): Promise<T> {
  const existing = cache.get(key) as CacheEntry<T> | undefined
  if (existing && existing.expiresAt > Date.now()) return existing.value
  const value = await load()
  cache.set(key, { value, expiresAt: Date.now() + ttlMs })
  return value
}

export function invalidate(prefix = ''): void {
  for (const key of cache.keys()) {
    if (key.startsWith(prefix)) cache.delete(key)
  }
}
