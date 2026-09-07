import { resolve } from 'node:path'
import { isIP } from 'node:net'
import type { EvidenceCheck } from '../../shared/types'
import { runCommand } from './command'
import { cached } from './cache'

const observedAt = () => new Date().toISOString()
const check = (id: string, label: string, status: EvidenceCheck['status'], source: EvidenceCheck['source'], detail: string, scope: EvidenceCheck['scope'] = 'node'): EvidenceCheck => ({ id, label, status, source, detail, scope, observedAt: observedAt() })

const NODE_PROBE = String.raw`
release="$(cat /etc/redhat-release 2>/dev/null || true)"
architecture="$(uname -m 2>/dev/null || true)"
selinux="$(getenforce 2>/dev/null || true)"
if [ -z "$(swapon --show --noheadings 2>/dev/null)" ]; then swap=disabled; else swap=active; fi
firewall="$(systemctl is-active firewalld 2>/dev/null || true)"
failed_services="$(systemctl --failed --no-legend --plain 2>/dev/null | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')"
vault_service="$(systemctl is-active vault 2>/dev/null || true)"
vault_health="$(curl --silent --show-error --max-time 4 --cacert /opt/vault/tls/ca.crt "$1" 2>/dev/null || true)"
printf 'release=%s\narchitecture=%s\nselinux=%s\nswap=%s\nfirewall=%s\nfailed_services=%s\nvault_service=%s\nvault_health=%s\n' "$release" "$architecture" "$selinux" "$swap" "$firewall" "$failed_services" "$vault_service" "$vault_health"
`.trim()

export interface NodeChecks {
  rhel: EvidenceCheck[]
  vault: EvidenceCheck[]
}

function parseProbe(output: string): Record<string, string> {
  return Object.fromEntries(output.split('\n').map((line) => {
    const separator = line.indexOf('=')
    return separator < 1 ? ['', ''] : [line.slice(0, separator), line.slice(separator + 1)]
  }).filter(([key]) => key))
}

export async function nodeChecks(name: string, address: string | undefined): Promise<NodeChecks> {
  return cached(`node:${name}:${address || 'unknown'}`, 15_000, async () => {
    if (!address || isIP(address) === 0) {
      return {
        rhel: [check('rhel-reachable', 'Guest checks', 'unknown', 'rhel', 'A validated node address is unavailable.')],
        vault: [check('vault-reachable', 'Vault health', 'unknown', 'vault', 'A validated node address is unavailable.')],
      }
    }
    try {
      const url = `https://${address}:8200/v1/sys/health?standbyok=true&perfstandbyok=true`
      const { stdout } = await runCommand('multipass', ['exec', name, '--', 'sudo', '/bin/sh', '-c', NODE_PROBE, 'node-probe', url], { timeoutMs: 10_000 })
      const values = parseProbe(stdout.trim())
      const rhel = [
        check('rhel-release', 'Operating system', /^Red Hat Enterprise Linux(?: Server)? release 9\./.test(values.release || '') ? 'pass' : 'warn', 'rhel', values.release || 'Release unavailable'),
        check('architecture', 'Architecture', ['aarch64', 'arm64'].includes(values.architecture || '') ? 'pass' : 'warn', 'rhel', values.architecture || 'Unknown'),
        check('selinux', 'SELinux', values.selinux === 'Enforcing' ? 'pass' : 'fail', 'rhel', values.selinux || 'Unknown'),
        check('swap', 'Swap', values.swap === 'disabled' ? 'pass' : 'fail', 'rhel', values.swap === 'disabled' ? 'Disabled' : 'Active swap detected'),
        check('firewalld', 'Firewall', values.firewall === 'active' ? 'pass' : 'fail', 'rhel', values.firewall || 'Inactive'),
        check('systemd', 'Failed services', values.failed_services === '0' ? 'pass' : 'warn', 'rhel', values.failed_services === '0' ? 'None' : `${values.failed_services || 'Unknown'} failed`),
      ]

      let health: Record<string, unknown> | null = null
      try {
        health = values.vault_health ? JSON.parse(values.vault_health) as Record<string, unknown> : null
      } catch {
        health = null
      }
      if (!health) {
        return { rhel, vault: [check('vault-reachable', 'Vault health', 'fail', 'vault', 'Verified Vault health is unavailable.')] }
      }
      const initialized = health.initialized === true
      const unsealed = health.sealed === false
      const role = health.standby === true ? 'Standby' : health.performance_standby === true ? 'Performance standby' : 'Active'
      return {
        rhel,
        vault: [
          check('vault-service', 'Vault service', values.vault_service === 'active' ? 'pass' : 'fail', 'vault', values.vault_service || 'Inactive'),
          check('vault-tls', 'TLS health endpoint', 'pass', 'vault', 'Reachable with the configured CA'),
          check('vault-initialized', 'Initialized', initialized ? 'pass' : 'fail', 'vault', initialized ? 'Initialized' : 'Not initialized'),
          check('vault-seal', 'Seal state', unsealed ? 'pass' : 'fail', 'vault', unsealed ? 'Unsealed' : 'Sealed'),
          check('vault-role', 'HA role', 'pass', 'vault', role),
        ],
      }
    } catch {
      return {
        rhel: [check('rhel-reachable', 'Guest checks', 'fail', 'rhel', 'The guest did not answer the fixed read-only probe.')],
        vault: [check('vault-reachable', 'Vault health', 'fail', 'vault', 'The guest did not answer the fixed read-only probe.')],
      }
    }
  })
}

export async function clusterChecks(repositoryRoot: string, shouldRun: boolean): Promise<EvidenceCheck[]> {
  if (!shouldRun) return [check('cluster-validation', 'Cluster validation', 'unknown', 'vault', 'Requires all Terraform-managed nodes to be running.', 'cluster')]
  return cached('cluster-validation', 30_000, async () => {
    try {
      await runCommand(resolve(repositoryRoot, 'scripts/validate.sh'), [], { cwd: repositoryRoot, timeoutMs: 30_000 })
      return [
        check('cluster-validation', 'Cluster contract', 'pass', 'vault', 'One active node, two standbys, three Raft voters, and an active Enterprise license.', 'cluster'),
      ]
    } catch {
      return [check('cluster-validation', 'Cluster contract', 'fail', 'vault', 'The repository validation contract did not pass.', 'cluster')]
    }
  })
}
