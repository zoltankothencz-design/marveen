// cron-prev-fire.mjs -- reads a cron expression from stdin, prints prev fire as Unix seconds.
// Usage: echo "30 9 * * *" | node scripts/cron-prev-fire.mjs
import { CronExpressionParser } from 'cron-parser'
import { createInterface } from 'node:readline'

const rl = createInterface({ input: process.stdin, terminal: false })
const lines = []
for await (const line of rl) lines.push(line.trim())
const expr = lines.filter(Boolean)[0] ?? ''
try {
  const parsed = CronExpressionParser.parse(expr)
  process.stdout.write(Math.floor(parsed.prev().getTime() / 1000) + '\n')
} catch {
  process.stdout.write('0\n')
}
