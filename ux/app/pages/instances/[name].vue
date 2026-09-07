<script setup lang="ts">
import type { InstanceDetailResponse, PostureCategory } from '../../../shared/types'

const route = useRoute()
const name = computed(() => String(route.params.name))
const { data, status, error, refresh } = await useFetch<InstanceDetailResponse>(() => `/api/instances/${encodeURIComponent(name.value)}`, { server: false })
const selectedEvidence = ref<PostureCategory | null>(null)
const { selectedAction, selectedInstance, pending, toast, requestAction, closeAction, confirmAction } = useOperations(refresh)

const formatBytes = (bytes: number | null | undefined) => bytes == null ? 'Unavailable' : `${(bytes / 1024 ** 3).toFixed(bytes >= 10 * 1024 ** 3 ? 0 : 1)} GB`
const running = computed(() => data.value?.instance?.state.toLowerCase() === 'running')
</script>

<template>
  <div>
    <NuxtLink to="/" class="back-link"><svg viewBox="0 0 16 16"><path d="m10 3-5 5 5 5"/></svg> All instances</NuxtLink>

    <div v-if="status === 'pending' && !data" class="detail-loading"><span /><span /><span /></div>
    <section v-else-if="error || !data?.instance" class="unavailable-panel">
      <div><h2>Instance unavailable</h2><p>{{ data?.message || error?.message || 'This instance could not be found.' }}</p></div>
      <NuxtLink to="/" class="button">Return to instances</NuxtLink>
    </section>

    <template v-else>
      <header class="detail-header">
        <div class="detail-identity">
          <span class="machine-glyph large"><span /><span /><span /></span>
          <div>
            <div class="flex items-center gap-3"><h1>{{ data.instance.name }}</h1><span class="state-chip" :class="{ running }"><i />{{ data.instance.state }}</span></div>
            <p>{{ data.instance.release || 'Operating system unavailable' }} <span>·</span> {{ data.instance.ipv4[0] || 'No IPv4 address' }}</p>
          </div>
        </div>
        <div class="detail-actions">
          <button v-if="running" class="button" :disabled="pending" @click="requestAction('restart', data.instance)">Restart</button>
          <button v-if="running" class="button" :disabled="pending" @click="requestAction('stop', data.instance)">Stop</button>
          <button v-else-if="data.instance.deleted" class="button primary" :disabled="pending" @click="requestAction('recover', data.instance)">Recover</button>
          <button v-else class="button primary" :disabled="pending" @click="requestAction('start', data.instance)">Start</button>
          <button class="icon-button bordered" title="Move to trash" :disabled="pending || data.instance.deleted" @click="requestAction('delete', data.instance)"><svg viewBox="0 0 20 20"><path d="M4 6h12M8 6V4h4v2M6 6l1 10h6l1-10"/></svg></button>
        </div>
      </header>

      <section class="lifecycle-panel">
        <div class="section-title"><div><p class="eyebrow">Lifecycle posture</p><h2>Terraform to Vault</h2></div><span>Each stage is backed by observed evidence</span></div>
        <div class="lifecycle-grid">
          <template v-for="(item, key, index) in data.instance.posture" :key="key">
            <StatusPill :category="item" @select="selectedEvidence = $event" />
            <span v-if="index < 3" class="flow-arrow">→</span>
          </template>
        </div>
      </section>

      <div class="detail-columns">
        <section class="detail-panel">
          <div class="panel-heading"><div><p class="eyebrow">Overview</p><h2>Instance resources</h2></div><span class="source-label">Multipass</span></div>
          <dl class="data-list">
            <div><dt>State</dt><dd>{{ data.instance.state }}</dd></div>
            <div><dt>IPv4 addresses</dt><dd>{{ data.instance.ipv4.join(', ') || 'Unavailable' }}</dd></div>
            <div><dt>CPU</dt><dd>{{ data.instance.resources.cpus ?? 'Unavailable' }}</dd></div>
            <div><dt>Memory</dt><dd>{{ formatBytes(data.instance.resources.memoryBytes) }}</dd></div>
            <div><dt>Disk</dt><dd>{{ formatBytes(data.instance.resources.diskBytes) }}</dd></div>
            <div><dt>Snapshots</dt><dd>{{ data.instance.snapshotCount ?? 'Unavailable' }}</dd></div>
            <div><dt>Image hash</dt><dd class="mono">{{ data.instance.imageHash ? `${data.instance.imageHash.slice(0, 16)}…` : 'Unavailable' }}</dd></div>
          </dl>
        </section>

        <section class="detail-panel">
          <div class="panel-heading"><div><p class="eyebrow">Ownership</p><h2>Terraform evidence</h2></div><span class="source-label purple">terraform/infra</span></div>
          <div class="compact-evidence">
            <article v-for="item in data.instance.posture.terraform.evidence" :key="item.id">
              <span :class="`is-${item.status}`">{{ item.status === 'pass' ? '✓' : item.status === 'fail' ? '×' : '?' }}</span>
              <div><strong>{{ item.label }}</strong><p>{{ item.detail }}</p></div>
            </article>
          </div>
        </section>
      </div>

      <section class="detail-panel mt-5">
        <div class="panel-heading"><div><p class="eyebrow">Security posture</p><h2>Vault cluster evidence</h2></div><span class="source-label gold">Cluster scope</span></div>
        <div class="cluster-evidence">
          <article v-for="item in data.cluster" :key="item.id">
            <span class="evidence-state" :class="`is-${item.status}`">{{ item.status === 'pass' ? '✓' : item.status === 'fail' ? '×' : '?' }}</span>
            <div><strong>{{ item.label }}</strong><p>{{ item.detail }}</p></div>
          </article>
        </div>
      </section>
    </template>

    <EvidencePanel :category="selectedEvidence" @close="selectedEvidence = null" />
    <ActionDialog :action="selectedAction" :instance="selectedInstance" :pending="pending" @close="closeAction" @confirm="confirmAction" />
    <Transition name="toast"><div v-if="toast" class="toast" :class="toast.type">{{ toast.message }}</div></Transition>
  </div>
</template>
