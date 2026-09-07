import type { ActionResponse, InstanceAction, InstanceSummary } from '../../shared/types'

export function useOperations(refresh: () => Promise<void>) {
  const selectedAction = ref<string | null>(null)
  const selectedInstance = ref<InstanceSummary | null>(null)
  const pending = ref(false)
  const toast = ref<{ type: 'success' | 'error', message: string } | null>(null)

  function requestAction(action: string, instance: InstanceSummary) {
    selectedAction.value = action
    selectedInstance.value = instance
  }

  function closeAction() {
    if (pending.value) return
    selectedAction.value = null
    selectedInstance.value = null
  }

  async function confirmAction(acknowledgeTerraformDrift: boolean) {
    if (!selectedAction.value || !selectedInstance.value) return
    pending.value = true
    try {
      const action = selectedAction.value as InstanceAction
      const name = encodeURIComponent(selectedInstance.value.name)
      const result = action === 'delete'
        ? await $fetch<ActionResponse>(`/api/instances/${name}`, { method: 'DELETE', body: { confirm: true, acknowledgeTerraformDrift } })
        : await $fetch<ActionResponse>(`/api/instances/${name}/${action}`, { method: 'POST', body: { confirm: true } })
      toast.value = { type: 'success', message: result.message }
      selectedAction.value = null
      selectedInstance.value = null
      await refresh()
    } catch (error) {
      const response = error as { data?: { statusMessage?: string } }
      toast.value = { type: 'error', message: response.data?.statusMessage || 'The operation failed.' }
    } finally {
      pending.value = false
      window.setTimeout(() => { toast.value = null }, 5000)
    }
  }

  return { selectedAction, selectedInstance, pending, toast, requestAction, closeAction, confirmAction }
}
