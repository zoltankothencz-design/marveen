import { existsSync, mkdirSync, readFileSync } from 'node:fs'
import { join } from 'node:path'
import { randomBytes, timingSafeEqual } from 'node:crypto'
import { PROJECT_ROOT } from '../config.js'
import { atomicWriteFileSync } from './atomic-write.js'

// A single bearer token gates every /api/* route. It is loaded from
// DASHBOARD_TOKEN if set, otherwise persisted at store/.dashboard-token
// (mode 0600) and auto-generated on first run. Static assets (/, /index.html,
// /style.css, /app.js, /avatars/*) and the auth-status endpoint stay public
// so the UI can bootstrap itself.
const DASHBOARD_TOKEN_PATH = join(PROJECT_ROOT, 'store', '.dashboard-token')

export function loadOrCreateDashboardToken(): string {
  const fromEnv = process.env.DASHBOARD_TOKEN?.trim()
  if (fromEnv) return fromEnv
  try {
    if (existsSync(DASHBOARD_TOKEN_PATH)) {
      const cached = readFileSync(DASHBOARD_TOKEN_PATH, 'utf-8').trim()
      if (cached) return cached
    }
  } catch { /* fall through and regenerate */ }
  const fresh = randomBytes(32).toString('hex')
  mkdirSync(join(PROJECT_ROOT, 'store'), { recursive: true })
  atomicWriteFileSync(DASHBOARD_TOKEN_PATH, fresh, { mode: 0o600 })
  return fresh
}

function tokenEquals(provided: string, expected: string): boolean {
  const a = Buffer.from(provided)
  const b = Buffer.from(expected)
  if (a.length !== b.length) return false
  return timingSafeEqual(a, b)
}

export function checkBearerToken(header: string | undefined, expected: string): boolean {
  if (!header) return false
  const m = /^Bearer\s+(.+)$/.exec(header)
  if (!m) return false
  return tokenEquals(m[1].trim(), expected)
}

// Session cookie fallback. The UI keeps the token in localStorage, but Safari
// (incl. home-screen shortcuts) wipes script-writable storage after ~7 days
// without a visit. A server-set HttpOnly cookie is not subject to that cap, so
// once the user opens the bootstrap URL (?token=...) the browser stays
// authenticated. SameSite=Strict + the Origin check in web.ts keep CSRF out.
export const DASHBOARD_COOKIE_NAME = 'marveen_dash'
const DASHBOARD_COOKIE_MAX_AGE = 365 * 24 * 60 * 60

export function readCookie(header: string | undefined, name: string): string | undefined {
  if (!header) return undefined
  for (const part of header.split(';')) {
    const eq = part.indexOf('=')
    if (eq === -1) continue
    if (part.slice(0, eq).trim() === name) return decodeURIComponent(part.slice(eq + 1).trim())
  }
  return undefined
}

export function checkCookieToken(header: string | undefined, expected: string): boolean {
  const value = readCookie(header, DASHBOARD_COOKIE_NAME)
  return !!value && tokenEquals(value, expected)
}

export function checkRequestAuth(
  headers: { authorization?: string; cookie?: string },
  expected: string,
): boolean {
  return checkBearerToken(headers.authorization, expected) || checkCookieToken(headers.cookie, expected)
}

// Returns true when `candidate` is the valid token (used to validate ?token=
// before persisting it as a cookie).
export function isValidToken(candidate: string | null, expected: string): boolean {
  return !!candidate && tokenEquals(candidate.trim(), expected)
}

export function buildAuthCookie(token: string): string {
  return `${DASHBOARD_COOKIE_NAME}=${encodeURIComponent(token)}; Max-Age=${DASHBOARD_COOKIE_MAX_AGE}; Path=/; HttpOnly; SameSite=Strict`
}
