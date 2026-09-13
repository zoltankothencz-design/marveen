import { join } from 'node:path'
import { execSync, execFileSync } from 'node:child_process'
import { resolveFromPath } from '../platform.js'
import { logger } from '../logger.js'
import {
  PROJECT_ROOT,
  MAIN_AGENT_ID,
  ALLOWED_CHAT_ID,
} from '../config.js'
import {
  appendTaskRun,
  hasTaskRunSince,
  hasPendingRetry,
  listPendingTaskRetries,
  deletePendingTaskRetry,
  updatePendingTaskRetry,
  insertPendingTaskRetryIfNew,
  markPendingTaskRetryAlert,
  clearPendingTaskRetryAlert,
} from '../db.js'
import { toPendingRetryView, type PendingRetryView } from '../pending-retries.js'
import {
  OPERATOR_TASK_PREAMBLE,
  wrapOperatorTask,
} from '../prompt-safety.js'
import { cronMatchesNow } from './cron.js'
import { CronExpressionParser } from 'cron-parser'
import {
  listScheduledTasks,
  type ScheduledTask,
} from './scheduled-tasks-io.js'
import { listAgentNames, readFileOr } from './agent-config.js'
import {
  agentSessionName,
  isAgentRunning,
  isSessionReadyForPrompt,
  sendPromptToSession,
  sendPromptViaPasteBuffer,
  capturePane,
} from './agent-process.js'
import { MAIN_CHANNELS_SESSION } from './main-agent.js'
import { sendTelegramMessage } from './telegram.js'

const TMUX = resolveFromPath('tmux')

// Ha egy session token-szama meghaladja ezt a hatart, /compact kuldunk
// a heartbeat prompt elott, hogy a feladat friss contexten fusson.
const SCHEDULER_COMPACT_THRESHOLD_K = 120

// --- Schedule Runner ---
// Checks every minute if any scheduled task is due and injects the prompt
// into the agent's tmux session.
//
// Tasks that matched their cron but found the target session busy are
// persisted in the `pending_task_retries` DB table and retried on every
// subsequent 60s tick until the session frees up or the operator cancels
// them from the UI. The previous design kept them in an in-memory Map
// and abandoned them after an hour -- which silently dropped business-
// critical schedules. The new policy never abandons; once the age
// crosses ALERT_THRESHOLD_MS the alerting layer stamps alert_sent_at
// before each Telegram send and clears the stamp on delivery failure,
// giving exactly-one stamp per attempt and at-least-once delivery until
// success. See sendPendingRetryAlert below.

const scheduleLastRun: Map<string, number> = new Map()

// Tracks occurrence keys already scheduled for a stale check so we don't
// double-schedule if the catchup window matches the same cron slot twice.
const staleCheckScheduled = new Set<string>()

// One-shot stale check fired 5 minutes after an occurrence becomes due.
// Alerts Marveen if the task has no task_runs entry for that occurrence AND
// is not already in the pending_task_retries queue (which has its own alerting).
function checkStaleOccurrence(taskName: string, occurrenceMs: number, occurrenceKey: string): void {
  staleCheckScheduled.delete(occurrenceKey)
  try {
    if (hasTaskRunSince(taskName, occurrenceMs)) return
    if (hasPendingRetry(taskName)) return
    const prevHHMM = new Date(occurrenceMs).toLocaleTimeString('hu-HU', { hour: '2-digit', minute: '2-digit' })
    const msg = `WATCHDOG: '${taskName}' utemezett feladat nem indult el a vart idoponttol (${prevHHMM}) szamitott 5 percen belul, task_runs-ban nincs nyoma. Vizsgald ki.`
    logger.warn({ task: taskName, occurrenceMs }, 'Stale scheduled task -- no task_run found after 5 min grace')
    execFileSync('/bin/bash', [join(PROJECT_ROOT, 'scripts', 'notify.sh'), msg], { timeout: 10_000 })
  } catch (err) {
    logger.warn({ err, task: taskName }, 'checkStaleOccurrence error')
  }
}

// Try to fire a task at a single target agent. Returns the outcome so the
// caller can decide whether to queue a retry. Splitting this out means the
// pendingTaskRetries loop and the normal cron loop share one code path.
//
// skipRecord: when true, does NOT call appendTaskRun. Used by the boot trigger
// which does a deferred post-fire verification before recording the run.
// usePasteBuffer: when true, uses sendPromptViaPasteBuffer instead of
// sendPromptToSession. Intended for boot triggers with long prompts (6k+ chars)
// where the chunked send-keys approach is less reliable.
function attemptFireTask(task: ScheduledTask, agentName: string, now: number, skipRecord = false, usePasteBuffer = false, firedSessionsThisTick?: Set<string>): 'fired' | 'busy' | 'missing' | 'error' {
  const isMainAgent = agentName === MAIN_AGENT_ID
  // Allow per-task session override via targetSession config field.
  // Falls back to the standard agent session name derivation.
  const session = task.targetSession
    ? task.targetSession
    : isMainAgent ? MAIN_CHANNELS_SESSION : agentSessionName(agentName)

  // Per-session serialisation within a single runCheck() tick. When multiple
  // pending retries flush at once (e.g. session restarts after a long busy
  // stretch), each task fires synchronously but the pane-state transition
  // from "idle" to "busy" lags the actual send-keys by ~100-300ms. Without
  // this guard every task sees isSessionReadyForPrompt=true and delivers in
  // quick succession, causing prompt interleaving or / rename contamination.
  // One delivery per session per tick is sufficient -- the rest stay in the
  // retry queue and get a fresh attempt on the next 60s tick.
  if (firedSessionsThisTick?.has(session)) {
    logger.info({ task: task.name, session }, 'Session already received a delivery this tick, deferring to next tick')
    return 'busy'
  }

  let sessionExists = false
  try {
    const sessions = execSync(`${TMUX} list-sessions -F "#{session_name}"`, { timeout: 3000, encoding: 'utf-8' })
    sessionExists = sessions.split('\n').some(s => s.trim() === session)
  } catch { /* no tmux */ }

  if (!sessionExists) {
    logger.warn({ task: task.name, agent: agentName, session }, 'Schedule target session not running, skipping')
    return 'missing'
  }

  // When forceSend is true, skip the busy-state check entirely and inject
  // the prompt regardless. The Claude session queues it internally and
  // will process it at the next idle slot. This prevents the infinite
  // retry loop observed when the target session stays busy for hours
  // (275 retries overnight in production).
  if (!task.forceSend && !isSessionReadyForPrompt(session)) {
    logger.warn({ task: task.name, agent: agentName, session }, 'Schedule target session busy or has pending input, will retry')
    return 'busy'
  }

  if (task.forceSend) {
    logger.info({ task: task.name, agent: agentName, session }, 'forceSend=true, bypassing busy-state check')
  }

  try {
    let prefix: string
    if (task.type === 'heartbeat') {
      prefix = `[Heartbeat: ${task.name}] *** KOTELEZO ELSO TEENDO MIELOTT BARMIT IRSZ: hivj meg pontosan EGY local-only tool-t (peldaul Bash 'echo keepalive >> /tmp/marveen-keepalive.log' VAGY Read tool egy meglevo fajlra mint ${join(PROJECT_ROOT, 'HEARTBEAT.md')}). NE Telegram-tool-t -- az zajt eredmenyezne. Ezt a Telegram-bun MCP-stdio-pipe keep-alive-ehez kell, ha kihagyod, a Telegram-conn 30 percen belul disconnect-el. *** Aztan: ez egy csendes ellenorzes. CSAK AKKOR irj Telegramon (chat_id: ${ALLOWED_CHAT_ID}), ha tenyleg fontos/surgos dolgot talalsz. Ha minden rendben, NE kuldj Telegram uzenetet -- a kotelezo no-op tool-call mar megfelelo aktivitas. Egy rovid 'csendes heartbeat' sor a transzkriptbe + a tool-call elég. `
    } else {
      prefix = `[Utemezett feladat: ${task.name}] Az eredmenyt kuldd el Telegramon (chat_id: ${ALLOWED_CHAT_ID}, reply tool). `
    }
    // Task prompts come from operator-authored SKILL.md files on disk
    // (editable only via the bearer-gated /api/schedules endpoint -- same
    // trust level as editing CLAUDE.md directly). They are designed
    // automation scripts that routinely contain literal shell/tmux
    // delegation steps, so they get the operator-task tier, not the
    // untrusted tier: follow them as written, but still escalate if a step
    // looks tampered with rather than authored. See prompt-safety.ts header
    // comment (2026-06-16 fix) for why wrapUntrusted broke the daily
    // engineer-restart and job-scan-fallback schedules.
    const fullPrompt =
      OPERATOR_TASK_PREAMBLE + '\n' +
      prefix.trimEnd() + '\n\n' +
      wrapOperatorTask(`scheduled-task:${task.name}`, task.prompt)
    // Ha a task-nak van goal mezo, injektaljuk /goal parancsként a prompt elott
    if (task.goal) {
      const goalCmd = `/goal ${task.goal}`
      execFileSync(TMUX, ['send-keys', '-t', session, goalCmd, 'Enter'], { timeout: 5000 })
      // Poll until the session is idle again after /goal -- a fixed 1s sleep was too
      // short: /goal involves a model round-trip (2-5s) and the prompt chunks arrived
      // while the goal text was still in the buffer, producing a "goal too long" error.
      // Brief initial pause so Claude Code has time to start processing before we poll.
      execFileSync('/bin/sleep', ['0.5'], { timeout: 2000 })
      const GOAL_MAX_WAIT_MS = 10_000
      const goalWaitStart = Date.now()
      let goalSettled = false
      while (Date.now() - goalWaitStart < GOAL_MAX_WAIT_MS) {
        if (isSessionReadyForPrompt(session)) { goalSettled = true; break }
        execFileSync('/bin/sleep', ['0.5'], { timeout: 2000 })
      }
      if (!goalSettled) logger.warn({ task: task.name, session }, '/goal did not settle within 10s, proceeding anyway')
    }
    // Token-check: ha a session >SCHEDULER_COMPACT_THRESHOLD_K tokennél jár,
    // /compact-ot küldünk előtte hogy a feladat friss contexten fusson.
    const paneForCompact = capturePane(session)
    if (paneForCompact) {
      const tokenMatch = paneForCompact.match(/~(\d+(?:\.\d+)?)k uncached|save (\d+(?:\.\d+)?)k tokens/)
      if (tokenMatch) {
        const tokenK = parseFloat(tokenMatch[1] ?? tokenMatch[2] ?? '0')
        if (tokenK >= SCHEDULER_COMPACT_THRESHOLD_K) {
          logger.info({ task: task.name, session, tokenK }, 'Pre-task /compact: session token count high')
          execFileSync(TMUX, ['send-keys', '-t', session, '/compact', 'Enter'], { timeout: 5000 })
          // Varunk hogy a /compact feldolgozodjon (max 30s)
          const compactStart = Date.now()
          while (Date.now() - compactStart < 30_000) {
            execFileSync('/bin/sleep', ['1'], { timeout: 2000 })
            if (isSessionReadyForPrompt(session)) break
          }
          logger.info({ task: task.name, session }, 'Pre-task /compact done, sending prompt')
        }
      }
    }
    if (usePasteBuffer) {
      sendPromptViaPasteBuffer(session, fullPrompt)
    } else {
      sendPromptToSession(session, fullPrompt)
    }
    scheduleLastRun.set(task.name, now)
    if (!skipRecord) appendTaskRun(task.name, agentName)
    firedSessionsThisTick?.add(session)
    logger.info({ task: task.name, agent: agentName, session, skipRecord }, 'Scheduled task fired')

    // Post-send verify: if the agent started a new turn during our chunk
    // stream, the Enter from sendPromptToSession might have landed while
    // the agent was thinking and Claude Code parked the bytes on the input
    // line. We want the prompt to run, not disappear -- so if the pane
    // still shows our marker below ❯ after a short wait, re-send Enter so
    // the submit sticks. We retry a couple of times before giving up.
    const marker = task.type === 'heartbeat'
      ? `[Heartbeat: ${task.name}]`
      : `[Utemezett feladat: ${task.name}]`
    const resubmit = (attempt: number) => {
      try {
        const pane = execFileSync(TMUX, ['capture-pane', '-t', session, '-p'], { timeout: 3000, encoding: 'utf-8' })
        const stuck = /❯\s+\S/.test(pane) && pane.includes(marker)
        if (!stuck) return
        if (attempt >= 5) {
          logger.warn({ task: task.name, session }, 'Scheduled prompt still stuck after 5 Enter retries -- giving up')
          return
        }
        execFileSync(TMUX, ['send-keys', '-t', session, 'Enter'], { timeout: 3000 })
        setTimeout(() => resubmit(attempt + 1), 3000)
      } catch (err) {
        logger.warn({ err, task: task.name }, 'Post-send resubmit failed')
      }
    }
    setTimeout(() => resubmit(0), 2000)
    return 'fired'
  } catch (err) {
    logger.warn({ err, task: task.name }, 'Failed to fire scheduled task')
    return 'error'
  }
}

// Fire a Telegram alert when a pending retry has been stuck past the
// threshold. Stamps `alert_sent_at` BEFORE the network call so concurrent
// ticks and crash-restarts cannot race into double-alerting on the same
// attempt. If the send fails, the stamp is cleared so the next tick can
// retry -- that way a transient Telegram outage or a bad token doesn't
// silently suppress every future alert on this row. Net semantics:
// exactly-one stamp per delivery attempt, at-least-once delivery with a
// 60s retry cadence until success.
function sendPendingRetryAlert(view: PendingRetryView, nowMs: number): void {
  // Stamp first. If another tick raced us, markPendingTaskRetryAlert
  // returns false (the WHERE alert_sent_at IS NULL guards it) and we
  // skip the send entirely.
  const claimed = markPendingTaskRetryAlert(view.taskName, view.agentName, nowMs)
  if (!claimed) return

  const ageMinutes = Math.floor(view.ageMs / 60000)
  const firstAttempt = new Date(view.firstAttempt).toLocaleString('hu-HU')
  const text = [
    `[Marveen scheduler] A(z) "${view.taskName}" (${view.agentName}) utemezett feladat ${ageMinutes} perce varakozik.`,
    `Elso probalkozas: ${firstAttempt}.`,
    'A rendszer tovabb probalkozik; a dashboard /Utemezesek oldalan visszavonhato.',
  ].join('\n')
  ;(async () => {
    try {
      const envPath = join(PROJECT_ROOT, '.env')
      const envContent = readFileOr(envPath, '')
      const tokenMatch = envContent.match(/TELEGRAM_BOT_TOKEN=(.+)/)
      const token = tokenMatch?.[1]?.trim()
      if (!token) {
        logger.warn({ task: view.taskName, agent: view.agentName }, 'Pending-retry alert skipped: no TELEGRAM_BOT_TOKEN, clearing stamp for retry')
        clearPendingTaskRetryAlert(view.taskName, view.agentName)
        return
      }
      await sendTelegramMessage(token, ALLOWED_CHAT_ID, text)
      logger.info({ task: view.taskName, agent: view.agentName, ageMinutes }, 'Pending-retry Telegram alert sent')
    } catch (err) {
      // Real send failure (network error, 4xx from Telegram). Clear the
      // per-attempt stamp so the next tick can legitimately retry --
      // otherwise a bad token silently wedges the alerting forever.
      logger.warn({ err, task: view.taskName, agent: view.agentName }, 'Pending-retry alert delivery failed, clearing stamp for retry')
      clearPendingTaskRetryAlert(view.taskName, view.agentName)
    }
  })()
}

export function startScheduleRunner(): NodeJS.Timeout {
  let firstRun = true

  function runCheck() {
    const tasks = listScheduledTasks()
    const now = Date.now()
    // On first run after restart, catch up missed tasks from last 30 min
    const catchUp = firstRun ? 30 * 60000 : 60000

    // Boot trigger: tasks with runOnBootIfMissedToday fire once per calendar
    // day on the first schedule-runner tick (= every machine/dashboard restart).
    // Designed for tasks whose cron time falls in typical off-hours (e.g. 02:07,
    // 07:30) so they always miss on a machine that boots at 08:00-10:30.
    // The cron field stays as a fallback for nights when the machine stays on.
    //
    // Race-prevention: attemptFireTask writes scheduleLastRun + appendTaskRun,
    // so the normal cron loop below skips the task even if cronMatchesNow fires.
    // We also skip tasks already in pending_task_retries (their retry handler
    // manages them) and tasks that already have a task_run for today.
    if (firstRun) {
      const todayStart = new Date()
      todayStart.setHours(0, 0, 0, 0)
      const todayStartMs = todayStart.getTime()

      const bootTasks = tasks.filter(t => t.enabled && t.runOnBootIfMissedToday)
      for (const task of bootTasks) {
        if (hasTaskRunSince(task.name, todayStartMs)) continue
        if (hasPendingRetry(task.name)) continue
        const agentName = task.agent === 'all' ? MAIN_AGENT_ID : (task.agent || MAIN_AGENT_ID)

        // reggeli-napindito fires 3 min after dream-engine so DREAM.md has
        // time to be generated (skill handles missing DREAM.md gracefully too).
        const delayMs = task.name === 'reggeli-napindito' ? 3 * 60_000 : 0

        const fire = () => {
          if (hasTaskRunSince(task.name, todayStartMs)) return
          if (hasPendingRetry(task.name)) return
          const t = Date.now()
          // Strip the `goal` field for boot fires: the /goal injection has a
          // 4000-char limit and boot time is not the right moment for goal-mode.
          // The task prompt itself drives the work; /goal is only for cron path.
          const taskForBoot = { ...task, goal: undefined }
          // skipRecord=true: we do NOT write appendTaskRun immediately.
          // Instead we verify the session actually started processing (busy)
          // 3s after prompt delivery. Writing task_runs speculatively causes
          // false-green status that silences the stale watchdog even when
          // the prompt was lost (e.g. session not ready at boot time).
          //
          // usePasteBuffer=true: long SKILL.md prompts (e.g. dream-engine ~6018
          // chars) are delivered via tmux load-buffer + paste-buffer instead of
          // chunked send-keys. Paste-buffer is more reliable for multi-kB prompts
          // and matches the proven pattern used by napi-igaming-karrier-scan.
          const result = attemptFireTask(taskForBoot, agentName, t, true, true)
          if (result === 'busy' && !task.skipIfBusy) {
            insertPendingTaskRetryIfNew(task.name, agentName, t, 'busy')
          }
          if (result === 'fired') {
            // Deferred record: give Claude Code 3s to transition to busy state.
            // If the session is busy, the prompt was received -- write task_runs.
            // If still idle, the prompt was likely lost; skip the record so the
            // stale watchdog can detect and alert the missed occurrence.
            const session = task.targetSession
              ? task.targetSession
              : agentName === MAIN_AGENT_ID ? MAIN_CHANNELS_SESSION : agentSessionName(agentName)
            setTimeout(() => {
              try {
                if (!isSessionReadyForPrompt(session)) {
                  appendTaskRun(task.name, agentName)
                  logger.info({ task: task.name, session }, 'Boot trigger: session busy after 3s -- task_runs written')
                } else {
                  logger.warn({ task: task.name, session }, 'Boot trigger: session still idle after 3s -- prompt may be lost, skipping task_runs write')
                }
              } catch (err) {
                logger.warn({ err, task: task.name }, 'Boot trigger deferred task_runs check failed')
              }
            }, 3000)
          }
          logger.info({ task: task.name, agentName, result, delayMs }, 'Boot trigger fired')
        }

        if (delayMs === 0) {
          fire()
        } else {
          setTimeout(fire, delayMs)
        }
        logger.info({ task: task.name, delayMs, todayStartMs }, 'Boot trigger: task not yet run today, scheduling fire')
      }
    }

    firstRun = false

    // Retry tasks that were busy-skipped on earlier ticks (persisted in
    // pending_task_retries so they survive dashboard restart). cronMatchesNow
    // only fires on an exact minute boundary, so without this the noon
    // check skipped because the session was busy at 12:00:50 would never
    // run that day. We NEVER abandon -- the operator can cancel from the
    // UI if a retry has become obsolete.
    // One delivery per session per tick. Prevents prompt interleaving when
    // multiple pending retries flush simultaneously after a session restart.
    const firedSessionsThisTick = new Set<string>()

    const pendingRows = listPendingTaskRetries()
    const pendingKeys = new Set<string>()
    for (const row of pendingRows) {
      // Locate the task definition. If it was deleted meanwhile, drop the
      // retry silently -- nothing to fire.
      const taskDef = tasks.find(t => t.name === row.task_name)
      if (!taskDef) {
        deletePendingTaskRetry(row.task_name, row.agent_name)
        continue
      }
      // Honor the operator's disable action: if the task was toggled off
      // while the retry sat in the queue, drop the retry so a long-stuck
      // task doesn't surprise-fire the moment the session frees up.
      if (!taskDef.enabled) {
        deletePendingTaskRetry(row.task_name, row.agent_name)
        continue
      }

      // Register the key only once we know the retry is live, so the cron
      // loop below doesn't treat a dead row as a reason to skip.
      const key = `${row.task_name}@${row.agent_name}`
      pendingKeys.add(key)

      const view = toPendingRetryView(row, now)
      const result = attemptFireTask(taskDef, row.agent_name, now, false, false, firedSessionsThisTick)
      if (result === 'fired' || result === 'missing') {
        deletePendingTaskRetry(row.task_name, row.agent_name)
        continue
      }
      // Still busy or errored: refresh the retry row and alert ONCE if
      // the age crossed the threshold. `updatePendingTaskRetry` returns
      // false when the row has been cancelled between load and now --
      // in that case, do not re-insert (the operator's cancel wins) and
      // do not alert.
      const stillPresent = updatePendingTaskRetry(row.task_name, row.agent_name, now, result)
      if (stillPresent && view.alertDue) sendPendingRetryAlert(view, now)
    }

    for (const task of tasks) {
      if (!task.enabled) continue
      if (!cronMatchesNow(task.schedule, catchUp)) continue

      // Prevent double-firing: skip if already ran within the catch-up window
      const lastRun = scheduleLastRun.get(task.name) || 0
      if (now - lastRun < catchUp) continue

      // Schedule a one-shot stale check 5 min after the occurrence becomes due.
      // If the task ran by then (task_runs entry exists) -- silent. If not and
      // not in pending_task_retries (which has its own alerting) -- notify Marveen.
      // delay = max(0, occurrenceTime + 5min - now): handles catchup restarts too.
      //
      // Skip for skipIfBusy=true tasks: a dropped tick there is intentional
      // (the session was busy) and does NOT mean the task is broken. Alerting
      // on a deliberate silent-drop is a false positive.
      if (!task.skipIfBusy) {
        try {
          const occurrenceMs = CronExpressionParser.parse(task.schedule).prev().getTime()
          const occurrenceKey = `${task.name}@${occurrenceMs}`
          if (!staleCheckScheduled.has(occurrenceKey)) {
            staleCheckScheduled.add(occurrenceKey)
            const delay = Math.max(0, occurrenceMs + 5 * 60_000 - now)
            setTimeout(() => checkStaleOccurrence(task.name, occurrenceMs, occurrenceKey), delay)
            logger.info({ task: task.name, occurrenceMs, delayMs: delay }, 'Stale check scheduled')
          }
        } catch { /* invalid cron -- skip stale check for this task */ }
      }

      let targetAgents: string[]

      if (task.agent === 'all') {
        // Broadcast to all running agents + main
        const running = listAgentNames().filter(a => isAgentRunning(a))
        targetAgents = [MAIN_AGENT_ID, ...running]
      } else {
        targetAgents = [task.agent || MAIN_AGENT_ID]
      }

      for (const agentName of targetAgents) {
        const key = `${task.name}@${agentName}`
        // If already queued for retry from an earlier tick, leave it to
        // the retry handler -- don't re-queue or double-fire.
        if (pendingKeys.has(key)) continue
        const result = attemptFireTask(task, agentName, now, false, false, firedSessionsThisTick)
        if (result === 'busy') {
          if (task.skipIfBusy) {
            // Opt-in skip for short-cadence tasks (e.g. 30-min heartbeats):
            // a single missed tick is harmless because the next one is
            // already on the way, and queueing them produces spurious
            // "60 perce varakozik" Telegram alerts whenever the operator
            // is having an active conversation in the channels session.
            // Daily/weekly schedules keep skipIfBusy=false so the queue
            // + alert path catches a long-running busy state.
            logger.info({ task: task.name, agent: agentName }, 'Schedule busy, skipIfBusy=true: dropping tick silently')
            continue
          }
          // First encounter -- insert a new pending row. If somehow a
          // row already exists (race with a just-cancelled retry), do
          // nothing so the cancel wins the tiebreak.
          insertPendingTaskRetryIfNew(task.name, agentName, now, 'busy')
        }
      }
    }
  }

  // Run immediately on start (catches missed tasks)
  setTimeout(runCheck, 5000)
  return setInterval(runCheck, 60000)
}
