import type { InstanceResources } from '../../shared/types'
import { runCommand } from './command'

export const INSTANCE_NAME_PATTERN = /^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/
export const INSTANCE_ACTIONS = ['start', 'stop', 'restart', 'suspend', 'delete', 'recover'] as const

export interface MultipassInstance {
  name: string
  state: string
  ipv4: string[]
  release: string | null
  imageHash: string | null
  resources: InstanceResources
  snapshotCount: number | null
  deleted: boolean
}

type UnknownRecord = Record<string, unknown>

function record(value: unknown): UnknownRecord {
  return value && typeof value === 'object' && !Array.isArray(value) ? value as UnknownRecord : {}
}

function strings(value: unknown): string[] {
  if (Array.isArray(value)) return value.filter((item): item is string => typeof item === 'string')
  return typeof value === 'string' && value ? [value] : []
}

function number(value: unknown): number | null {
  if (typeof value === 'number' && Number.isFinite(value)) return value
  if (typeof value === 'string' && /^\d+$/.test(value)) return Number(value)
  return null
}

function diskBytes(item: UnknownRecord): number | null {
  const direct = bytes(item.disk)
  if (direct !== null) return direct
  const disks = record(item.disks)
  const totals = Object.values(disks).map(value => bytes(record(value).total)).filter((value): value is number => value !== null)
  return totals.length ? totals.reduce((sum, value) => sum + value, 0) : null
}

export function bytes(value: unknown): number | null {
  if (typeof value === 'number' && Number.isFinite(value)) return value
  const source = record(value)
  if ('total' in source) return bytes(source.total)
  if (typeof value !== 'string') return null
  const match = value.trim().match(/^([0-9.]+)\s*([kmgt]?i?b?)?$/i)
  if (!match) return null
  const amount = Number(match[1])
  const unit = (match[2] || '').toLowerCase()
  const power = unit.startsWith('t') ? 4 : unit.startsWith('g') ? 3 : unit.startsWith('m') ? 2 : unit.startsWith('k') ? 1 : 0
  return Math.round(amount * 1024 ** power)
}

function normalize(raw: unknown, fallbackName?: string): MultipassInstance {
  const item = record(raw)
  const name = typeof item.name === 'string' ? item.name : fallbackName || ''
  const state = typeof item.state === 'string' ? item.state : 'Unknown'
  return {
    name,
    state,
    ipv4: strings(item.ipv4),
    release: typeof item.release === 'string' ? item.release : null,
    imageHash: typeof item.image_hash === 'string' ? item.image_hash : null,
    resources: {
      cpus: number(item.cpu_count) ?? number(item.cpus),
      memoryBytes: bytes(item.memory),
      diskBytes: diskBytes(item),
    },
    snapshotCount: number(item.snapshot_count),
    deleted: state.toLowerCase() === 'deleted',
  }
}

export function normalizeList(payload: unknown): MultipassInstance[] {
  const root = record(payload)
  const list = Array.isArray(root.list) ? root.list : []
  return list.map(item => normalize(item)).filter(item => INSTANCE_NAME_PATTERN.test(item.name))
}

export function normalizeInfo(payload: unknown, name: string): MultipassInstance | null {
  const info = record(record(payload).info)
  return info[name] ? normalize(info[name], name) : null
}

export async function listInstances(): Promise<MultipassInstance[]> {
  const { stdout } = await runCommand('multipass', ['list', '--format', 'json'])
  return normalizeList(JSON.parse(stdout))
}

export async function instanceInfo(name: string): Promise<MultipassInstance | null> {
  assertValidName(name)
  const { stdout } = await runCommand('multipass', ['info', name, '--format', 'json'])
  return normalizeInfo(JSON.parse(stdout), name)
}

export async function runInstanceAction(name: string, action: typeof INSTANCE_ACTIONS[number]): Promise<void> {
  assertValidName(name)
  await runCommand('multipass', instanceActionArguments(name, action), { timeoutMs: 120_000 })
}

export function instanceActionArguments(name: string, action: typeof INSTANCE_ACTIONS[number]): string[] {
  assertValidName(name)
  if (!INSTANCE_ACTIONS.includes(action)) throw new Error('Invalid instance action.')
  return [action, name]
}

export async function purgeInstances(): Promise<void> {
  await runCommand('multipass', ['purge'], { timeoutMs: 120_000 })
}

export function assertValidName(name: string): void {
  if (!INSTANCE_NAME_PATTERN.test(name)) throw new Error('Invalid instance name.')
}
