export function assertInstanceConfirmation(confirm: unknown): void {
  if (confirm !== true) throw new Error('Explicit confirmation is required.')
}

export function assertDeleteConfirmation(confirm: unknown, managed: boolean, acknowledgeDrift: unknown): void {
  assertInstanceConfirmation(confirm)
  if (managed && acknowledgeDrift !== true) throw new Error('Terraform drift acknowledgement is required.')
}

export function assertPurgeConfirmation(phrase: unknown): void {
  if (phrase !== 'PURGE DELETED INSTANCES') throw new Error('The exact purge confirmation phrase is required.')
}
