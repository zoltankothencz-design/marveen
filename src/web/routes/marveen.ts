import { existsSync, unlinkSync, copyFileSync, writeFileSync } from 'node:fs'
import { join, extname } from 'node:path'
import { PROJECT_ROOT, OWNER_NAME, BOT_NAME } from '../../config.js'
import { readMarveenTelegramConfig, sendMarveenAvatarChange } from '../telegram.js'
import { hardRestartMarveenChannels } from '../channel-monitor.js'
import { readFileOr } from '../agent-config.js'
import { parseMultipart } from '../multipart.js'
import { readBody, json, serveFile } from '../http-helpers.js'
import type { RouteContext } from './types.js'

export async function tryHandleMarveen(ctx: RouteContext, webDir: string): Promise<boolean> {
  const { req, res, path, method } = ctx

  if (path === '/api/marveen' && method === 'GET') {
    const claudeMd = readFileOr(join(PROJECT_ROOT, 'CLAUDE.md'), '')
    const soulMd = readFileOr(join(PROJECT_ROOT, 'SOUL.md'), '')
    const mcpJson = readFileOr(join(PROJECT_ROOT, '.mcp.json'), '')
    const soulSection = claudeMd.match(/## Személyiség\n\n([\s\S]*?)(?=\n## )/)?.[1]?.trim()
      || claudeMd.match(/## Szemelyiseg\n\n([\s\S]*?)(?=\n## )/)?.[1]?.trim()
      || ''
    const firstLine = claudeMd.match(/^Te .+$/m)?.[0]?.trim() || ''
    const descFromPersonality = soulSection.split('\n').filter(l => l.trim()).slice(0, 2).join(' ').slice(0, 200)
    const description = firstLine || descFromPersonality || `${OWNER_NAME} AI asszisztense`
    const tg = readMarveenTelegramConfig()
    json(res, {
      name: BOT_NAME,
      description,
      model: 'claude-opus-4-8',
      running: true,
      hasTelegram: tg.hasTelegram,
      telegramBotUsername: tg.botUsername,
      role: 'main',
      personality: soulSection,
      claudeMd,
      soulMd,
      mcpJson,
      readonly: true,
    })
    return true
  }

  // Intentionally read-only: Marveen's CLAUDE.md / SOUL.md / .mcp.json must be
  // edited from the filesystem or via a Telegram request to Marveen herself,
  // not through the dashboard. A leaked dashboard token would otherwise allow
  // remote identity rewrite of the live agent.
  if (path === '/api/marveen' && method === 'PUT') {
    json(res, { ok: true, readonly: true })
    return true
  }

  if (path === '/api/marveen/restart' && method === 'POST') {
    const result = hardRestartMarveenChannels()
    if (!result.ok) { json(res, { error: result.error || 'Restart failed' }, 500); return true }
    json(res, { ok: true })
    return true
  }

  if (path === '/api/marveen/avatar' && method === 'GET') {
    for (const ext of ['.png', '.jpg', '.jpeg', '.webp']) {
      const p = join(PROJECT_ROOT, 'store', `marveen-avatar${ext}`)
      if (existsSync(p)) { serveFile(res, p); return true }
    }
    const fallback = join(webDir, 'avatars', '01_robot.png')
    if (existsSync(fallback)) { serveFile(res, fallback); return true }
    res.writeHead(404); res.end()
    return true
  }

  if (path === '/api/marveen/avatar' && method === 'POST') {
    const body = await readBody(req)
    const contentType = req.headers['content-type'] || ''

    for (const ext of ['.png', '.jpg', '.jpeg', '.webp']) {
      const p = join(PROJECT_ROOT, 'store', `marveen-avatar${ext}`)
      if (existsSync(p)) unlinkSync(p)
    }

    if (contentType.includes('application/json')) {
      const { galleryAvatar } = JSON.parse(body.toString()) as { galleryAvatar: string }
      if (!galleryAvatar) { json(res, { error: 'No avatar specified' }, 400); return true }
      if (galleryAvatar.includes('..') || galleryAvatar.includes('/') || galleryAvatar.includes('\\')) {
        json(res, { error: 'Invalid avatar name' }, 400)
        return true
      }
      const srcPath = join(webDir, 'avatars', galleryAvatar)
      if (!existsSync(srcPath)) { json(res, { error: 'Avatar not found' }, 404); return true }
      const destPath = join(PROJECT_ROOT, 'store', `marveen-avatar${extname(galleryAvatar) || '.png'}`)
      copyFileSync(srcPath, destPath)
      sendMarveenAvatarChange(destPath).catch(() => {})
    } else {
      const { file } = parseMultipart(body, contentType)
      if (!file) { json(res, { error: 'No file uploaded' }, 400); return true }
      const destPath = join(PROJECT_ROOT, 'store', `marveen-avatar${extname(file.name) || '.png'}`)
      writeFileSync(destPath, file.data)
      sendMarveenAvatarChange(destPath).catch(() => {})
    }
    json(res, { ok: true })
    return true
  }

  // Beágyazott chat - tmux inject + notify.sh log figyelése
  if (path === '/api/marveen/chat' && method === 'POST') {
    const body = await readBody(req, { maxBytes: 32 * 1024 })
    const { message } = JSON.parse(body.toString()) as { message: string }
    if (!message?.trim()) { json(res, { error: 'Üres üzenet' }, 400); return true }
    try {
      const { spawnSync } = await import('node:child_process')
      const { readFileSync, existsSync, statSync } = await import('node:fs')
      // Dedikalt dashboard-chat session -- Telegram plugin NELKUL fut, igy
      // Marveen valasza NEM megy automatikusan Telegramba, csak notify.sh-n at.
      const SESSION = 'marveen-dashboard-chat'
      const LOG = '/home/userzoltan/marveen/store/notify.log'

      const startSize = existsSync(LOG) ? statSync(LOG).size : 0
      const startTime = Math.floor(Date.now() / 1000)

      // FONTOS: a send-keys szovegben NEM lehet \n (newline) -- a Claude Code CLI
      // multi-line inputnak ertelmezi, es Enter-rel csak sort tor, nem submitol.
      // Minden newline-t szokozzze alakitunk, igy egyetlen sorban erkezik az uzenet.
      const singleLineMsg = message.trim().replace(/\r?\n/g, ' ')
      // NE hasznalj <channel> taget -- az aktivalna a Telegram plugin valasz-utvonalat
      // es Marveen a teljes valaszt Telegramon kuldene, a dashboardon csak osszefoglalo jelenne meg.
      // Helyette: direkt szoveg, explicit notify.sh instrukcioval.
      const wrapped = '[DASHBOARD UZENET - Zoltan irja]: ' + singleLineMsg +
        ' [FONTOS: a teljes valaszodat kizarolag a notify.sh-val kuld:' +
        ' bash /home/userzoltan/marveen/scripts/notify.sh "teljes valasz".' +
        ' NE hasznald a Telegram plugint erre az uzenetre.]'

      const TMUX = '/usr/bin/tmux'

      // Session-ellenőrzés: ha a watchdog épp újraindítja a marveen-channels-t,
      // várjunk max 30s-t, mielőtt kriptikus "can't find pane" hibát dobnánk.
      const SESSION_WAIT_MS = 30000
      const sessionStart = Date.now()
      while (true) {
        const check = spawnSync(TMUX, ['has-session', '-t', SESSION], { timeout: 3000 })
        if (check.status === 0) break
        if (Date.now() - sessionStart > SESSION_WAIT_MS) {
          throw new Error('Marveen session nem elérhető — újraindítás folyamatban, próbáld újra 30 másodperc múlva.')
        }
        await new Promise(r => setTimeout(r, 3000))
      }

      // A szoveget es az Enter-t KULON send-keys hivasban kell kuldeni: ha egy
      // hivasban mennek, a Claude Code TUI bracketed-paste modban a zaro Enter-t
      // beszivja a paste-be es nem submital -- az uzenet beragad a promptba.
      const r1 = spawnSync(TMUX, ['send-keys', '-t', SESSION, '-l', wrapped], { timeout: 5000 })
      if (r1.status !== 0) {
        const errMsg = r1.stderr?.toString().trim() || 'tmux hiba'
        throw new Error(errMsg)
      }
      await new Promise(r => setTimeout(r, 700))
      const r2 = spawnSync(TMUX, ['send-keys', '-t', SESSION, 'Enter'], { timeout: 5000 })
      if (r2.status !== 0) {
        const errMsg = r2.stderr?.toString().trim() || 'tmux Enter hiba'
        throw new Error(errMsg)
      }

      const TIMEOUT_MS = 300000
      const POLL_INTERVAL = 2000
      const start = Date.now()
      let reply = ''

      while (Date.now() - start < TIMEOUT_MS) {
        await new Promise(r => setTimeout(r, POLL_INTERVAL))
        if (!existsSync(LOG)) continue
        const sz = statSync(LOG).size
        if (sz <= startSize) continue
        const content = readFileSync(LOG, 'utf-8')
        const allLines = content.split('\n').filter(l => l.trim())
        const newMessages: { ts: number; msg: string }[] = []
        for (const l of allLines) {
          const idx = l.indexOf('|')
          if (idx < 0) continue
          const ts = parseInt(l.slice(0, idx))
          const msg = l.slice(idx + 1)
          if (ts >= startTime) newMessages.push({ ts, msg })
        }
        if (newMessages.length > 0) {
          // Elso uzenet erkezett -- varunk meg 4 masodpercet hogy tobbreszus
          // valasz eseten az osszes notify.sh hivas begyuljon, ne csak az elso.
          await new Promise(r => setTimeout(r, 4000))
          const content2 = readFileSync(LOG, 'utf-8')
          const allLines2 = content2.split('\n').filter(l => l.trim())
          const allNew: string[] = []
          for (const l of allLines2) {
            const idx = l.indexOf('|')
            if (idx < 0) continue
            const ts = parseInt(l.slice(0, idx))
            if (ts >= startTime) allNew.push(l.slice(idx + 1))
          }
          // Visszaalakitas: escaped \n literal -> valodi sortores
          reply = allNew.map(m => m.replace(/\\n/g, '\n')).join('\n\n')
          break
        }
      }

      if (!reply) {
        json(res, { error: 'Időtúllépés - Marveen 5 perc után nem válaszolt.' }, 504)
      } else {
        json(res, { reply })
      }
    } catch (e: any) {
      json(res, { error: e.message || 'Hiba' }, 500)
    }
    return true
  }

  // Remote Control URL kinyerése a marveen-channels tmux session-ből
  if (path === '/api/marveen/remote-url' && method === 'GET') {
    try {
      const { execSync } = await import('node:child_process')
      const out = execSync(
        "tmux capture-pane -t marveen-channels -p -S -100 2>/dev/null | grep -o 'https://claude.ai/code/session_[A-Za-z0-9]*' | tail -1",
        { encoding: 'utf-8', timeout: 3000 }
      ).trim()
      if (out) {
        json(res, { url: out })
      } else {
        json(res, { url: null, error: 'Session nem fut vagy nincs Remote Control URL' })
      }
    } catch {
      json(res, { url: null, error: 'tmux hiba' })
    }
    return true
  }

  return false
}
