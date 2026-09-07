import { resolve } from 'node:path'
import type { EvidenceCheck, InstanceSummary, InstancesResponse, PostureCategory } from '../../shared/types'
import { aggregateStatus, category } from '../../shared/posture'
import type { MultipassInstance } from './multipass'
import { instanceInfo, listInstances } from './multipass'
import { loadTerraformEvidence, terraformOwnership, type TerraformEvidence } from './repository'
import { clusterChecks, nodeChecks } from './checks'
import { publicError } from './command'

function evidence(
  id: string,
  label: string,
  status: EvidenceCheck['status'],
  source: EvidenceCheck['source'],
  detail: string,
  observedAt: string,
): EvidenceCheck {
  return { id, label, status, source, detail, scope: 'node', observedAt }
}

function terraformPosture(instance: MultipassInstance, state: TerraformEvidence, now: string): PostureCategory {
  const ownership = terraformOwnership(instance.name, state)
  if (ownership === 'unknown') return category('terraform', 'Unknown', [evidence('terraform-state', 'Infrastructure state', 'unknown', 'terraform', 'Terraform outputs are unavailable.', now)])
  if (ownership === 'unmanaged') return category('terraform', 'Unmanaged', [evidence('terraform-state', 'Infrastructure state', 'warn', 'terraform', 'Not present in the successfully read deployment state.', now)])
  const expectedIp = state.nodeIps[instance.name]
  const ipMatches = !expectedIp || instance.ipv4.includes(expectedIp)
  const checks = [
    evidence('terraform-state', 'State presence', 'pass', 'terraform', `multipass_instance.vault["${instance.name}"]`, now),
    evidence('terraform-ip', 'Address agreement', ipMatches ? 'pass' : 'fail', 'terraform', expectedIp ? `Terraform ${expectedIp}; Multipass ${instance.ipv4[0] || 'none'}` : 'No address output', now),
  ]
  return category('terraform', ipMatches ? 'Managed' : 'Drift detected', checks)
}

function unavailableCategory(kind: 'rhel' | 'vault', reason: string, now: string): PostureCategory {
  const label = kind === 'rhel' ? 'Guest checks' : 'Vault health'
  return category(kind, 'Unknown', [evidence(`${kind}-unavailable`, label, 'unknown', kind, reason, now)])
}

function ansiblePosture(instance: MultipassInstance, state: TerraformEvidence, managed: boolean, now: string): PostureCategory {
  if (!managed) return category('ansible', 'Never run', [evidence('ansible-scope', 'Convergence scope', 'unknown', 'ansible', 'Not a Terraform-managed lab node.', now)])
  if (!state.appliedDigest || !state.currentDigest || !state.convergedNodes.includes(instance.name)) {
    return category('ansible', 'Unknown', [evidence('ansible-state', 'Applied automation', 'unknown', 'ansible', 'Applied orchestration evidence is unavailable.', now)])
  }
  const matches = state.appliedDigest === state.currentDigest
  return category('ansible', matches ? 'Converged' : 'Outdated', [
    evidence('ansible-node', 'Applied node set', 'pass', 'ansible', 'Present in terraform/ansible deployment_nodes.', state.ansibleObservedAt || now),
    evidence('ansible-digest', 'Automation digest', matches ? 'pass' : 'warn', 'ansible', matches ? `Matches ${state.currentDigest.slice(0, 12)}…` : 'The current automation differs from the last applied digest.', state.ansibleObservedAt || now),
  ])
}

async function buildInstance(instance: MultipassInstance, state: TerraformEvidence, cluster: EvidenceCheck[], now: string, deep: boolean): Promise<InstanceSummary> {
  const terraform = terraformPosture(instance, state, now)
  const managed = state.readable && state.nodeNames.includes(instance.name)
  const running = instance.state.toLowerCase() === 'running'
  const mayCheck = deep && managed && running
  const checks = mayCheck ? await nodeChecks(instance.name, instance.ipv4[0]) : { rhel: [], vault: [] }
  const rhelEvidence = checks.rhel
  const vaultEvidence = checks.vault

  const rhel = mayCheck
    ? category('rhel', aggregateStatus(rhelEvidence, { pass: 'Healthy', warn: 'Attention required', fail: 'Unreachable', unknown: 'Unknown' }), rhelEvidence)
    : unavailableCategory('rhel', !deep ? 'Posture checks are loading.' : managed ? 'The instance is not running.' : 'Checks run only for Terraform-managed lab nodes.', now)
  const ansible = ansiblePosture(instance, state, managed, now)
  const combinedVault = mayCheck ? [...vaultEvidence, ...cluster] : []
  const vault = mayCheck
    ? category('vault', aggregateStatus(combinedVault, { pass: 'Secured', warn: 'Attention required', fail: 'Not ready', unknown: 'Unknown' }), combinedVault)
    : unavailableCategory('vault', !deep ? 'Posture checks are loading.' : managed ? 'The instance is not running.' : 'Checks run only for Terraform-managed lab nodes.', now)

  return { ...instance, posture: { terraform, rhel, ansible, vault } }
}

export function repositoryRoot(): string {
  const configured = useRuntimeConfig().repositoryRoot
  return resolve(process.cwd(), typeof configured === 'string' ? configured : '..')
}

export async function getControlPlane(options: { deep?: boolean } = {}): Promise<InstancesResponse> {
  const now = new Date().toISOString()
  const deep = options.deep !== false
  try {
    const listed = await listInstances()
    const instances = await Promise.all(listed.map(async (instance) => {
      try {
        return await instanceInfo(instance.name) || instance
      } catch {
        return instance
      }
    }))
    const state = await loadTerraformEvidence(repositoryRoot())
    const allManagedRunning = state.readable
      && state.nodeNames.length > 0
      && state.nodeNames.every(name => instances.some(instance => instance.name === name && instance.state.toLowerCase() === 'running'))
    const cluster = deep
      ? await clusterChecks(repositoryRoot(), allManagedRunning)
      : []
    const enriched = await Promise.all(instances.map(instance => buildInstance(instance, state, cluster, now, deep)))
    return {
      available: true,
      message: null,
      observedAt: now,
      summary: {
        total: enriched.length,
        running: enriched.filter(item => item.state.toLowerCase() === 'running').length,
        stopped: enriched.filter(item => item.state.toLowerCase() === 'stopped').length,
        deleted: enriched.filter(item => item.deleted).length,
        cpus: enriched.reduce((sum, item) => sum + (item.resources.cpus || 0), 0),
        memoryBytes: enriched.reduce((sum, item) => sum + (item.resources.memoryBytes || 0), 0),
      },
      instances: enriched,
      cluster,
    }
  } catch (error) {
    return {
      available: false,
      message: publicError(error, 'Multipass data could not be read.'),
      observedAt: now,
      summary: { total: 0, running: 0, stopped: 0, deleted: 0, cpus: 0, memoryBytes: 0 },
      instances: [],
      cluster: [],
    }
  }
}
