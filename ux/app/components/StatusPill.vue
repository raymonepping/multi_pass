<script setup lang="ts">
import type { PostureCategory } from '../../shared/types'

defineProps<{ category: PostureCategory, compact?: boolean }>()
defineEmits<{ select: [category: PostureCategory] }>()
</script>

<template>
  <button
    type="button"
    class="status-pill"
    :class="[`status-${category.kind}`, `tone-${category.tone}`, { compact }]"
    :aria-label="`${category.label}: ${category.status}. Show evidence.`"
    @click.stop="$emit('select', category)"
  >
    <span class="status-icon" aria-hidden="true">
      <svg v-if="category.tone === 'positive'" viewBox="0 0 16 16"><path d="m4 8 2.5 2.5L12 5" /></svg>
      <svg v-else-if="category.tone === 'critical'" viewBox="0 0 16 16"><path d="M8 4v4.5M8 12h.01" /></svg>
      <svg v-else-if="category.tone === 'warning'" viewBox="0 0 16 16"><path d="M8 4v4.5M8 12h.01" /></svg>
      <svg v-else viewBox="0 0 16 16"><path d="M5.5 5.5a2.6 2.6 0 0 1 5 .9c0 2-2.5 2-2.5 3.5M8 12h.01" /></svg>
    </span>
    <span class="min-w-0 text-left">
      <span class="status-label">{{ category.label }}</span>
      <span class="status-value">{{ category.status }}</span>
    </span>
    <svg class="status-chevron" viewBox="0 0 16 16" aria-hidden="true"><path d="m6 4 4 4-4 4" /></svg>
  </button>
</template>
