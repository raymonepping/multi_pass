<script setup lang="ts">
import type { InstanceSummary, PostureCategory } from '../../shared/types'

const props = defineProps<{ instance: InstanceSummary, busy?: boolean }>()
const emit = defineEmits<{ evidence: [category: PostureCategory], action: [action: string, instance: InstanceSummary] }>()
const menuOpen = ref(false)

const formatBytes = (bytes: number | null) => {
  if (bytes === null) return '—'
  return `${(bytes / 1024 ** 3).toFixed(bytes >= 10 * 1024 ** 3 ? 0 : 1)} GB`
}

const isRunning = computed(() => props.instance.state.toLowerCase() === 'running')
const isStopped = computed(() => props.instance.state.toLowerCase() === 'stopped')
</script>

<template>
  <article class="instance-card" :class="{ 'is-deleted': instance.deleted }">
    <div class="card-head">
      <NuxtLink :to="`/instances/${encodeURIComponent(instance.name)}`" class="instance-name">
        <span class="machine-glyph" aria-hidden="true"><span /><span /><span /></span>
        <span>
          <strong>{{ instance.name }}</strong>
          <small>{{ instance.release || 'Operating system unavailable' }}</small>
        </span>
      </NuxtLink>
      <span class="state-chip" :class="{ running: isRunning, deleted: instance.deleted }"><i />{{ instance.state }}</span>
    </div>

    <div class="address-row">
      <span>{{ instance.ipv4[0] || 'No IPv4 address' }}</span>
      <span v-if="instance.ipv4.length > 1">+{{ instance.ipv4.length - 1 }}</span>
    </div>

    <div class="posture-stack">
      <StatusPill v-for="item in instance.posture" :key="item.kind" :category="item" @select="emit('evidence', $event)" />
    </div>

    <div class="resource-row">
      <span><b>{{ instance.resources.cpus ?? '—' }}</b> CPU</span>
      <span><b>{{ formatBytes(instance.resources.memoryBytes) }}</b> memory</span>
      <span><b>{{ formatBytes(instance.resources.diskBytes) }}</b> disk</span>
    </div>

    <div class="card-actions">
      <button v-if="isStopped" class="button primary" type="button" :disabled="busy" @click="emit('action', 'start', instance)">Start</button>
      <button v-else-if="isRunning" class="button" type="button" :disabled="busy" @click="emit('action', 'restart', instance)">Restart</button>
      <button v-else-if="instance.deleted" class="button primary" type="button" :disabled="busy" @click="emit('action', 'recover', instance)">Recover</button>
      <div class="action-menu-wrap">
        <button class="icon-button" type="button" :disabled="busy" aria-label="More instance actions" @click="menuOpen = !menuOpen">
          <svg viewBox="0 0 20 20"><circle cx="4" cy="10" r="1"/><circle cx="10" cy="10" r="1"/><circle cx="16" cy="10" r="1"/></svg>
        </button>
        <div v-if="menuOpen" class="action-menu" @mouseleave="menuOpen = false">
          <button v-if="isRunning" @click="emit('action', 'stop', instance); menuOpen = false">Stop</button>
          <button v-if="isRunning" @click="emit('action', 'suspend', instance); menuOpen = false">Suspend</button>
          <button v-if="!instance.deleted" class="danger" @click="emit('action', 'delete', instance); menuOpen = false">Move to trash</button>
        </div>
      </div>
    </div>
  </article>
</template>
