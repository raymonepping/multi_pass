import { describe, expect, it } from 'vitest'
import { terraformOwnership } from '../server/utils/repository'

describe('Terraform ownership truth rules', () => {
  it('returns unknown when state outputs are unreadable', () => expect(terraformOwnership('scratch', { readable: false, nodeNames: [] })).toBe('unknown'))
  it('returns unmanaged only when readable state excludes the VM', () => expect(terraformOwnership('scratch', { readable: true, nodeNames: ['vault-1'] })).toBe('unmanaged'))
  it('proves management by state membership', () => expect(terraformOwnership('vault-1', { readable: true, nodeNames: ['vault-1'] })).toBe('managed'))
})
