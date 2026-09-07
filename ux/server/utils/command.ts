import { execFile } from 'node:child_process'

const MAX_OUTPUT_BYTES = 1_000_000

export interface CommandResult {
  stdout: string
  stderr: string
}

export class CommandError extends Error {
  constructor(
    message: string,
    public readonly code: string | number | null,
    public readonly stderr = '',
  ) {
    super(message)
    this.name = 'CommandError'
  }
}

export function runCommand(
  executable: string,
  args: readonly string[],
  options: { cwd?: string, timeoutMs?: number, env?: NodeJS.ProcessEnv } = {},
): Promise<CommandResult> {
  return new Promise((resolve, reject) => {
    execFile(executable, [...args], {
      cwd: options.cwd,
      timeout: options.timeoutMs ?? 12_000,
      maxBuffer: MAX_OUTPUT_BYTES,
      encoding: 'utf8',
      env: options.env,
    }, (error, stdout, stderr) => {
      if (error) {
        reject(new CommandError(
          stderr.trim() || error.message,
          typeof error.code === 'string' || typeof error.code === 'number' ? error.code : null,
          stderr,
        ))
        return
      }
      resolve({ stdout, stderr })
    })
  })
}

export function publicError(error: unknown, fallback: string): string {
  if (!(error instanceof Error)) return fallback
  const message = error.message.toLowerCase()
  if (message.includes('enoent') || message.includes('not found')) return 'Required local command is not installed.'
  if (message.includes('socket') || message.includes('daemon') || message.includes('denied')) {
    return 'Multipass is unavailable. Check that the daemon is running and this process can access its socket.'
  }
  if (message.includes('timed out')) return 'The local infrastructure command timed out.'
  return fallback
}
