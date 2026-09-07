<script setup lang="ts">
import type { PostureCategory } from '../../shared/types'

defineProps<{ category: PostureCategory | null }>()
defineEmits<{ close: [] }>()

const statusIcon = (status: string) => status === 'pass' ? '✓' : status === 'fail' ? '×' : status === 'warn' ? '!' : '?'
</script>

<template>
  <Teleport to="body">
    <Transition name="drawer">
      <div v-if="category" class="drawer-layer" role="presentation" @click.self="$emit('close')">
        <aside class="evidence-drawer" role="dialog" aria-modal="true" :aria-label="`${category.label} evidence`">
          <div class="drawer-head">
            <div>
              <p class="eyebrow">Posture evidence</p>
              <h2>{{ category.label }} <span>· {{ category.status }}</span></h2>
            </div>
            <button class="icon-button" type="button" aria-label="Close evidence" @click="$emit('close')">
              <svg viewBox="0 0 20 20"><path d="m5 5 10 10M15 5 5 15" /></svg>
            </button>
          </div>
          <p class="drawer-intro">This result is derived from the checks below. Unknown evidence is never treated as passing.</p>
          <div class="evidence-list">
            <article v-for="item in category.evidence" :key="item.id" class="evidence-row">
              <span class="evidence-state" :class="`is-${item.status}`">{{ statusIcon(item.status) }}</span>
              <div class="min-w-0 flex-1">
                <div class="flex items-start justify-between gap-4">
                  <h3>{{ item.label }}</h3>
                  <span class="scope-chip">{{ item.scope }}</span>
                </div>
                <p>{{ item.detail }}</p>
                <span class="evidence-meta">{{ item.source }} · {{ new Date(item.observedAt).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' }) }}</span>
              </div>
            </article>
          </div>
        </aside>
      </div>
    </Transition>
  </Teleport>
</template>
