import { describe, expect, it } from 'vitest'
import { assertDeleteConfirmation, assertPurgeConfirmation } from '../server/utils/confirmation'
import { publicError } from '../server/utils/command'

describe('destructive confirmation', () => {
  it('requires drift acknowledgement for a managed delete', () => expect(() => assertDeleteConfirmation(true, true, false)).toThrow(/drift/i))
  it('allows an explicitly acknowledged managed delete', () => expect(() => assertDeleteConfirmation(true, true, true)).not.toThrow())
  it('requires the exact purge phrase', () => expect(() => assertPurgeConfirmation('purge deleted instances')).toThrow())
})

describe('public error redaction', () => {
  it('does not return arbitrary command output', () => {
    const secret = 'root-token-value'
    expect(publicError(new Error(`failed: ${secret}`), 'Operation failed.')).toBe('Operation failed.')
  })
})
