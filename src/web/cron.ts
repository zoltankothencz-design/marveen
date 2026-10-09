import { CronExpressionParser } from 'cron-parser'

export function computeNextRun(cronExpression: string): number {
  const expr = CronExpressionParser.parse(cronExpression)
  return Math.floor(expr.next().getTime() / 1000)
}

// Accept 5-field (standard) and 6-field (with seconds) cron expressions;
// cron-parser supports both. Anything else -- oversized strings, random
// punctuation, empty fields -- gets rejected at the API boundary instead
// of reaching the parser deep inside the scheduler loop.
export const CRON_SHAPE_RX = /^(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)(?:\s+(\S+))?$/

export function isValidCronShape(cron: unknown): cron is string {
  if (typeof cron !== 'string') return false
  const trimmed = cron.trim()
  if (!trimmed || trimmed.length > 100) return false
  if (!CRON_SHAPE_RX.test(trimmed)) return false
  try {
    const expr = CronExpressionParser.parse(trimmed)
    expr.next()
    return true
  } catch {
    return false
  }
}

// `nowMs` lets a caller pin the reference time for a whole scheduler tick.
// Firing a task blocks for several seconds, so re-reading the clock per task
// made later tasks in the same minute fall outside the catch-up window and
// get skipped silently (2026-10-08/09: the 11:00 job scans never fired).
export function cronMatchesNow(cron: string, catchUpMs: number = 60000, nowMs: number = Date.now()): boolean {
  try {
    const expr = CronExpressionParser.parse(cron, { currentDate: new Date(nowMs) })
    const prev = expr.prev()
    const prevTime = prev.getTime()
    return (nowMs - prevTime) < catchUpMs
  } catch {
    return false
  }
}
