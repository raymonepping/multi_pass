<script setup lang="ts">
defineProps<{ open: boolean, pending?: boolean }>()
const emit = defineEmits<{ close: [], confirm: [phrase: string] }>()
const phrase = ref('')
const required = 'PURGE DELETED INSTANCES'
</script>

<template>
  <Teleport to="body">
    <div v-if="open" class="modal-layer" role="presentation" @click.self="emit('close')">
      <section class="action-dialog" role="dialog" aria-modal="true" aria-label="Purge deleted instances">
        <span class="dialog-icon destructive"><svg viewBox="0 0 24 24"><path d="M4 7h16M9 7V4h6v3m-8 0 1 13h8l1-13M10 11v5M14 11v5"/></svg></span>
        <p class="eyebrow">Permanent operation</p>
        <h2>Purge deleted instances?</h2>
        <p>This permanently removes every instance currently in Multipass trash. It cannot be undone.</p>
        <label class="phrase-label">Type <strong>{{ required }}</strong>
          <input v-model="phrase" autocomplete="off" spellcheck="false">
        </label>
        <div class="dialog-actions">
          <button class="button" type="button" :disabled="pending" @click="emit('close')">Cancel</button>
          <button class="button danger-solid" type="button" :disabled="pending || phrase !== required" @click="emit('confirm', phrase)">Purge permanently</button>
        </div>
      </section>
    </div>
  </Teleport>
</template>
