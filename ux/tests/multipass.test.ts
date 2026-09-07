import { describe, expect, it } from 'vitest'
import { assertValidName, bytes, instanceActionArguments, normalizeInfo, normalizeList } from '../server/utils/multipass'

describe('Multipass normalization', () => {
  it('normalizes list and resource values without trusting extra fields', () => {
    const instances = normalizeList({ list: [{ name: 'vault-1', state: 'Running', ipv4: ['10.0.0.2'], release: 'RHEL 9.8', cpu_count: '2', memory: { total: '4GiB' }, disk: { total: 21474836480 }, secret: 'ignore' }] })
    expect(instances).toEqual([{ name: 'vault-1', state: 'Running', ipv4: ['10.0.0.2'], release: 'RHEL 9.8', imageHash: null, resources: { cpus: 2, memoryBytes: 4294967296, diskBytes: 21474836480 }, snapshotCount: null, deleted: false }])
  })

  it('normalizes named info records and byte units', () => {
    const info = normalizeInfo({ info: { 'lab-1': { state: 'Stopped', memory: '512 MiB', disks: { sda1: { total: '20GiB' } }, snapshot_count: '2' } } }, 'lab-1')
    expect(info?.name).toBe('lab-1')
    expect(info?.resources.diskBytes).toBe(21474836480)
    expect(info?.snapshotCount).toBe(2)
    expect(bytes('1.5 GB')).toBe(1610612736)
  })
})

describe('safe action construction', () => {
  it('uses a fixed two-element argument array', () => expect(instanceActionArguments('vault-1', 'restart')).toEqual(['restart', 'vault-1']))
  it.each(['../../etc/passwd', 'vault-1;whoami', '-danger', 'UPPER'])('rejects unsafe name %s', (name) => expect(() => assertValidName(name)).toThrow())
})
