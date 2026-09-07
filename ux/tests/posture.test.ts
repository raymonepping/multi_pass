import { describe, expect, it } from 'vitest'
import { aggregateStatus, category } from '../shared/posture'
import type { EvidenceCheck } from '../shared/types'

const check = (status: EvidenceCheck['status']): EvidenceCheck => ({ id: status, label: status, status, scope: 'node', source: 'rhel', detail: status, observedAt: '2026-09-05T00:00:00.000Z' })
const labels = { pass: 'healthy', warn: 'attention', fail: 'failed', unknown: 'unknown' }

describe('posture aggregation', () => {
  it('never treats unknown evidence as passing', () => expect(aggregateStatus([check('pass'), check('unknown')], labels)).toBe('unknown'))
  it('prioritizes failure over warning', () => expect(aggregateStatus([check('warn'), check('fail')], labels)).toBe('failed'))
  it('derives visual tone outside Vue components', () => expect(category('rhel', 'Healthy', [check('pass')]).tone).toBe('positive'))
})
