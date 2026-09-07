<script setup lang="ts">
import type { InstanceSummary } from '../../shared/types'

const props = defineProps<{ action: string | null, instance: InstanceSummary | null, pending?: boolean }>()
const emit = defineEmits<{ close: [], confirm: [acknowledgeDrift: boolean] }>()
const acknowledgement = ref(false)
const managedDelete = computed(() => props.action === 'delete' && props.instance?.posture.terraform.status === 'Managed')
const destructive = computed(() => props.action === 'delete')

watch(() => props.action, () => { acknowledgement.value = false })
</script>

<template>
  <Teleport to="body">
    <div v-if="action && instance" class="modal-layer" role="presentation" @click.self="emit('close')">
      <section class="action-dialog" role="dialog" aria-modal="true" :aria-label="`${action} ${instance.name}`">
        <span class="dialog-icon" :class="{ destructive }">
          <svg v-if="destructive" viewBox="0 0 24 24"><path d="M4 7h16M9 7V4h6v3m-8 0 1 13h8l1-13M10 11v5M14 11v5"/></svg>
          <svg v-else viewBox="0 0 24 24"><path d="M20 12a8 8 0 1 1-2.3-5.7M20 4v6h-6"/></svg>
        </span>
        <p class="eyebrow">Confirm operation</p>
        <h2>{{ action.charAt(0).toUpperCase() + action.slice(1) }} {{ instance.name }}?</h2>
        <p v-if="action === 'delete'">The instance will move to Multipass trash and can be recovered until purge.</p>
        <p v-else>The command result and all posture checks will refresh after the operation.</p>

        <div v-if="managedDelete" class="drift-warning">
          <strong>Terraform ownership boundary</strong>
          <p>Deleting this instance directly introduces drift for <code>multipass_instance.vault["{{ instance.name }}"]</code>.</p>
          <label><input v-model="acknowledgement" type="checkbox"> I understand this creates Terraform drift.</label>
        </div>

        <div class="dialog-actions">
          <button class="button" type="button" :disabled="pending" @click="emit('close')">Cancel</button>
          <button class="button" :class="destructive ? 'danger-solid' : 'primary'" type="button" :disabled="pending || (managedDelete && !acknowledgement)" @click="emit('confirm', acknowledgement)">
            <span v-if="pending" class="spinner" />
            {{ pending ? 'Working…' : `Confirm ${action}` }}
          </button>
        </div>
      </section>
    </div>
  </Teleport>
</template>
