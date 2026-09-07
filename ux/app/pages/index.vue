<script setup lang="ts">
import type { InstancesResponse, PostureCategory } from '../../shared/types'

const config = useRuntimeConfig()
const { data, status, error, refresh: refreshInventory } = await useFetch<InstancesResponse>('/api/instances?deep=false', { server: false })
const posturePending = ref(false)
const selectedEvidence = ref<PostureCategory | null>(null)
const purgeOpen = ref(false)
const purgePending = ref(false)
const filter = ref<'instances' | 'trash'>('instances')
const { selectedAction, selectedInstance, pending, toast, requestAction, closeAction, confirmAction } = useOperations(refreshPlane)

const visibleInstances = computed(() => data.value?.instances.filter(instance => filter.value === 'trash' ? instance.deleted : !instance.deleted) || [])
const observed = computed(() => data.value?.observedAt ? new Date(data.value.observedAt).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' }) : '—')

let timer: ReturnType<typeof setInterval> | undefined
onMounted(() => {
  void refreshPlane()
  timer = setInterval(() => refreshPlane(), Number(config.public.refreshSeconds) * 1000)
})
onBeforeUnmount(() => clearInterval(timer))

async function refreshPlane() {
  if (posturePending.value) return
  posturePending.value = true
  try {
    data.value = await $fetch<InstancesResponse>('/api/instances')
  } catch {
    toast.value = { type: 'error', message: 'Instances are visible, but posture checks could not be refreshed.' }
  } finally {
    posturePending.value = false
  }
}

async function retryInventory() {
  await refreshInventory()
  if (data.value?.available) await refreshPlane()
}

async function purge(confirmation: string) {
  purgePending.value = true
  try {
    const result = await $fetch<{ message: string }>('/api/purge', { method: 'POST', body: { confirmation } })
    toast.value = { type: 'success', message: result.message }
    purgeOpen.value = false
    await refreshPlane()
  } catch (err) {
    const response = err as { data?: { statusMessage?: string } }
    toast.value = { type: 'error', message: response.data?.statusMessage || 'Purge failed.' }
  } finally {
    purgePending.value = false
  }
}
</script>

<template>
  <div>
    <div class="page-heading">
      <div>
        <p class="eyebrow">Local infrastructure</p>
        <h1>Instances</h1>
        <p>Lifecycle and security posture across your Multipass environment.</p>
      </div>
      <div class="heading-actions">
        <span class="last-seen"><i :class="{ live: data?.available }" /> Observed {{ observed }}</span>
        <button class="button" type="button" :disabled="status === 'pending' || posturePending" @click="refreshPlane()">
          <svg viewBox="0 0 20 20" :class="{ spinning: status === 'pending' || posturePending }"><path d="M16.5 10a6.5 6.5 0 1 1-1.9-4.6M16.5 3.5v5h-5"/></svg>
          {{ posturePending ? 'Checking…' : 'Refresh' }}
        </button>
      </div>
    </div>

    <section v-if="data?.available" class="summary-strip" aria-label="Environment summary">
      <div><span>Instances</span><strong>{{ data.summary.total }}</strong></div>
      <div><span><i class="metric-dot green" /> Running</span><strong>{{ data.summary.running }}</strong></div>
      <div><span><i class="metric-dot gray" /> Stopped</span><strong>{{ data.summary.stopped }}</strong></div>
      <div><span>Compute</span><strong>{{ data.summary.cpus }} <small>CPU</small></strong></div>
      <div><span>Memory</span><strong>{{ (data.summary.memoryBytes / 1024 ** 3).toFixed(0) }} <small>GB</small></strong></div>
    </section>

    <section v-if="!data?.available && status !== 'pending'" class="unavailable-panel">
      <span class="unavailable-icon"><svg viewBox="0 0 24 24"><path d="M12 8v5M12 17h.01M10.3 3.8 2.5 17.2A2 2 0 0 0 4.2 20h15.6a2 2 0 0 0 1.7-2.8L13.7 3.8a2 2 0 0 0-3.4 0Z"/></svg></span>
      <div><h2>Multipass unavailable</h2><p>{{ data?.message || error?.message || 'The local service could not be reached.' }}</p></div>
      <button class="button" type="button" @click="retryInventory()">Try again</button>
    </section>

    <section v-if="status === 'pending' && !data" class="loading-grid" aria-label="Loading instances">
      <div v-for="i in 3" :key="i" class="skeleton-card"><span /><span /><span /><span /></div>
    </section>

    <template v-if="data?.available">
      <div class="list-toolbar">
        <div class="segmented-control">
          <button type="button" :class="{ active: filter === 'instances' }" @click="filter = 'instances'">Instances <span>{{ data.summary.total - data.summary.deleted }}</span></button>
          <button type="button" :class="{ active: filter === 'trash' }" @click="filter = 'trash'">Trash <span>{{ data.summary.deleted }}</span></button>
        </div>
        <button v-if="filter === 'trash' && data.summary.deleted" class="button danger-text" type="button" @click="purgeOpen = true">Purge trash</button>
      </div>

      <div v-if="visibleInstances.length" class="instance-grid">
        <InstanceCard v-for="instance in visibleInstances" :key="instance.name" :instance="instance" :busy="pending" @evidence="selectedEvidence = $event" @action="requestAction" />
      </div>
      <div v-else class="empty-panel">
        <span class="machine-glyph large" aria-hidden="true"><span /><span /><span /></span>
        <h2>{{ filter === 'trash' ? 'Trash is empty' : 'No instances found' }}</h2>
        <p>{{ filter === 'trash' ? 'Deleted instances remain recoverable here until they are purged.' : 'Create instances with the existing Terraform workflow, then refresh.' }}</p>
      </div>
    </template>

    <EvidencePanel :category="selectedEvidence" @close="selectedEvidence = null" />
    <ActionDialog :action="selectedAction" :instance="selectedInstance" :pending="pending" @close="closeAction" @confirm="confirmAction" />
    <PurgeDialog :open="purgeOpen" :pending="purgePending" @close="purgeOpen = false" @confirm="purge" />
    <Transition name="toast"><div v-if="toast" class="toast" :class="toast.type">{{ toast.message }}</div></Transition>
  </div>
</template>
