import { describe, it, expect, vi, afterEach } from 'vitest'
import { cronMatchesNow } from '../web/cron.js'

describe('cronMatchesNow with pinned tick time', () => {
  afterEach(() => { vi.useRealTimers() })

  it('still matches when the live clock has moved past the catch-up window', () => {
    const occurrence = new Date(2026, 9, 9, 11, 0, 0).getTime()
    const tickStart = occurrence + 58_600
    // Earlier fires in the same tick blocked for a few seconds.
    vi.useFakeTimers()
    vi.setSystemTime(tickStart + 5_000)
    expect(cronMatchesNow('0 11 * * *', 60_000)).toBe(false)
    expect(cronMatchesNow('0 11 * * *', 60_000, tickStart)).toBe(true)
  })

  it('does not match a tick that started after the window', () => {
    const occurrence = new Date(2026, 9, 9, 11, 0, 0).getTime()
    expect(cronMatchesNow('0 11 * * *', 60_000, occurrence + 61_000)).toBe(false)
  })

  it('matches only the occurrence belonging to the pinned tick', () => {
    const tickStart = new Date(2026, 9, 9, 11, 0, 58).getTime()
    vi.useFakeTimers()
    vi.setSystemTime(tickStart + 5_000)
    expect(cronMatchesNow('1,31 * * * *', 60_000, tickStart)).toBe(false)
    expect(cronMatchesNow('* * * * *', 60_000, tickStart)).toBe(true)
  })
})
