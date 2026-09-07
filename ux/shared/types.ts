export type EvidenceStatus = 'pass' | 'warn' | 'fail' | 'unknown'
export type EvidenceScope = 'node' | 'cluster'
export type EvidenceSource = 'multipass' | 'terraform' | 'rhel' | 'ansible' | 'vault'
export type PostureKind = 'terraform' | 'rhel' | 'ansible' | 'vault'

export interface EvidenceCheck {
  id: string
  label: string
  status: EvidenceStatus
  scope: EvidenceScope
  source: EvidenceSource
  detail: string
  observedAt: string
}

export interface PostureCategory {
  kind: PostureKind
  label: string
  status: string
  tone: 'positive' | 'warning' | 'critical' | 'neutral'
  evidence: EvidenceCheck[]
}

export interface InstanceResources {
  cpus: number | null
  memoryBytes: number | null
  diskBytes: number | null
}

export interface InstanceSummary {
  name: string
  state: string
  ipv4: string[]
  release: string | null
  imageHash: string | null
  resources: InstanceResources
  snapshotCount: number | null
  deleted: boolean
  posture: Record<PostureKind, PostureCategory>
}

export interface EnvironmentSummary {
  total: number
  running: number
  stopped: number
  deleted: number
  cpus: number
  memoryBytes: number
}

export interface InstancesResponse {
  available: boolean
  message: string | null
  observedAt: string
  summary: EnvironmentSummary
  instances: InstanceSummary[]
  cluster: EvidenceCheck[]
}

export interface InstanceDetailResponse {
  available: boolean
  message: string | null
  observedAt: string
  instance: InstanceSummary | null
  cluster: EvidenceCheck[]
}

export type InstanceAction = 'start' | 'stop' | 'restart' | 'suspend' | 'delete' | 'recover'

export interface ActionRequest {
  confirm?: boolean
  acknowledgeTerraformDrift?: boolean
}

export interface ActionResponse {
  ok: boolean
  action: InstanceAction | 'purge'
  message: string
  instance?: InstanceSummary | null
}
