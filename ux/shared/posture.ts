import type { EvidenceCheck, PostureCategory, PostureKind } from './types'

export const POSTURE_LABELS: Record<PostureKind, string> = {
  terraform: 'Terraform',
  rhel: 'RHEL',
  ansible: 'Ansible',
  vault: 'Vault',
}

export function category(
  kind: PostureKind,
  status: string,
  evidence: EvidenceCheck[],
): PostureCategory {
  const tone = evidence.some(item => item.status === 'fail')
    ? 'critical'
    : evidence.some(item => item.status === 'warn')
      ? 'warning'
      : evidence.length > 0 && evidence.every(item => item.status === 'pass')
        ? 'positive'
        : 'neutral'

  return { kind, label: POSTURE_LABELS[kind], status, tone, evidence }
}

export function aggregateStatus(
  evidence: EvidenceCheck[],
  labels: { pass: string, warn: string, fail: string, unknown: string },
): string {
  if (evidence.length === 0 || evidence.some(item => item.status === 'unknown')) return labels.unknown
  if (evidence.some(item => item.status === 'fail')) return labels.fail
  if (evidence.some(item => item.status === 'warn')) return labels.warn
  return labels.pass
}
