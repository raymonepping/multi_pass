import { createHash } from 'node:crypto'
import { readdir, readFile, stat } from 'node:fs/promises'
import { resolve, join, relative } from 'node:path'
import { runCommand } from './command'
import { cached } from './cache'

export interface TerraformEvidence {
  readable: boolean
  nodeNames: string[]
  nodeIps: Record<string, string>
  convergedNodes: string[]
  appliedDigest: string | null
  currentDigest: string | null
  ansibleObservedAt: string | null
}

export function terraformOwnership(name: string, state: Pick<TerraformEvidence, 'readable' | 'nodeNames'>): 'managed' | 'unmanaged' | 'unknown' {
  if (!state.readable) return 'unknown'
  return state.nodeNames.includes(name) ? 'managed' : 'unmanaged'
}

async function terraformOutput<T>(root: string, output: string): Promise<T> {
  const { stdout } = await runCommand('terraform', [`-chdir=${root}`, 'output', '-json', output])
  return JSON.parse(stdout) as T
}

async function walk(root: string, extensions?: Set<string>): Promise<string[]> {
  const found: string[] = []
  for (const entry of await readdir(root, { withFileTypes: true })) {
    const path = join(root, entry.name)
    if (entry.isDirectory()) found.push(...await walk(path, extensions))
    else if (!extensions || extensions.has(entry.name.slice(entry.name.lastIndexOf('.')))) found.push(path)
  }
  return found
}

export async function computeAutomationDigest(repositoryRoot: string): Promise<string> {
  const ansibleRoot = resolve(repositoryRoot, 'ansible')
  const templateRoot = resolve(repositoryRoot, 'templates')
  const files = [
    ...await walk(ansibleRoot, new Set(['.yml', '.j2'])),
    ...await walk(templateRoot),
    resolve(repositoryRoot, 'policies/platform-admin.hcl'),
  ].sort((a, b) => relative(repositoryRoot, a).localeCompare(relative(repositoryRoot, b)))
  const fileDigests: string[] = []
  for (const file of files) fileDigests.push(createHash('sha256').update(await readFile(file)).digest('hex'))
  return createHash('sha256').update(fileDigests.join('')).digest('hex')
}

export async function loadTerraformEvidence(repositoryRoot: string): Promise<TerraformEvidence> {
  return cached('terraform-evidence', 5_000, async () => {
    const infraRoot = resolve(repositoryRoot, 'terraform/infra')
    const ansibleRoot = resolve(repositoryRoot, 'terraform/ansible')
    try {
      const [nodeNames, nodeIps] = await Promise.all([
        terraformOutput<string[]>(infraRoot, 'node_names'),
        terraformOutput<Record<string, string>>(infraRoot, 'node_ipv4'),
      ])
      let convergedNodes: string[] = []
      let appliedDigest: string | null = null
      let currentDigest: string | null = null
      let ansibleObservedAt: string | null = null
      try {
        [convergedNodes, appliedDigest, currentDigest] = await Promise.all([
          terraformOutput<string[]>(ansibleRoot, 'deployment_nodes'),
          terraformOutput<string>(ansibleRoot, 'automation_digest'),
          computeAutomationDigest(repositoryRoot),
        ])
        ansibleObservedAt = (await stat(resolve(ansibleRoot, 'terraform.tfstate'))).mtime.toISOString()
      } catch {
        // Infrastructure ownership remains usable if orchestration state is absent.
      }
      return { readable: true, nodeNames, nodeIps, convergedNodes, appliedDigest, currentDigest, ansibleObservedAt }
    } catch {
      return { readable: false, nodeNames: [], nodeIps: {}, convergedNodes: [], appliedDigest: null, currentDigest: null, ansibleObservedAt: null }
    }
  })
}
