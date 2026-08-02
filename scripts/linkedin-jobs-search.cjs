#!/usr/bin/env node
'use strict'

// LinkedIn Jobs search via public /jobs/search/ page (no login required).
// Node 22 native fetch is used -- no node-fetch dependency needed.

const KEYWORDS = [
  'operations manager',
  'casino manager',
  'BI analyst',
  'compliance manager',
  'general manager',
]

const LOCATION = 'Europe'
const DELAY_MS = 1500 // polite delay between requests

const HEADERS = {
  'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
  'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
  'Accept-Language': 'en-US,en;q=0.5',
  'Accept-Encoding': 'gzip, deflate, br',
  'Connection': 'keep-alive',
}

function sleep(ms) {
  return new Promise(r => setTimeout(r, ms))
}

function parseJobCards(html, keyword) {
  const jobs = []

  // Match each <li> containing a job-search-card
  const liPattern = /<li[^>]*>([\s\S]*?)<\/li>/g
  let liMatch
  while ((liMatch = liPattern.exec(html)) !== null) {
    const card = liMatch[1]
    if (!card.includes('job-search-card')) continue

    // Title from sr-only span (screen reader label)
    const titleM = card.match(/class="sr-only">\s*([\s\S]*?)\s*<\/span>/)
    const title = titleM ? titleM[1].replace(/\s+/g, ' ').trim() : ''
    if (!title) continue

    // Job URL
    const urlM = card.match(/base-card__full-link[^>]*href="([^"]+)"/)
    const url = urlM ? urlM[1].split('?')[0] : ''

    // Company name
    const compM = card.match(/class="hidden-nested-link"[^>]*>\s*([\s\S]*?)\s*<\/a>/)
    const company = compM ? compM[1].replace(/\s+/g, ' ').trim() : ''

    // Location
    const locM = card.match(/job-search-card__location[^>]*>\s*([\s\S]*?)\s*<\/span>/)
    const location = locM ? locM[1].replace(/\s+/g, ' ').trim() : ''

    // Job ID from entity URN
    const urnM = card.match(/data-entity-urn="urn:li:jobPosting:(\d+)"/)
    const jobId = urnM ? urnM[1] : ''

    jobs.push({ keyword, title, company, location, url, jobId })
  }

  return jobs
}

async function searchKeyword(keyword) {
  const params = new URLSearchParams({
    keywords: keyword,
    location: LOCATION,
  })
  const url = `https://www.linkedin.com/jobs/search/?${params}`

  let resp
  try {
    resp = await fetch(url, { headers: HEADERS })
  } catch (err) {
    console.error(`[ERROR] fetch failed for "${keyword}": ${err.message}`)
    return []
  }

  if (!resp.ok) {
    console.error(`[ERROR] HTTP ${resp.status} for keyword "${keyword}"`)
    return []
  }

  const html = await resp.text()
  const jobs = parseJobCards(html, keyword)
  console.error(`[INFO] "${keyword}": found ${jobs.length} jobs`)
  return jobs
}

async function main() {
  const allJobs = []
  const seen = new Set()

  for (let i = 0; i < KEYWORDS.length; i++) {
    if (i > 0) await sleep(DELAY_MS)
    const keyword = KEYWORDS[i]
    const jobs = await searchKeyword(keyword)
    for (const job of jobs) {
      const key = job.jobId || `${job.title}|${job.company}|${job.location}`
      if (!seen.has(key)) {
        seen.add(key)
        allJobs.push(job)
      }
    }
  }

  console.log(JSON.stringify(allJobs, null, 2))
  console.error(`[DONE] Total unique jobs: ${allJobs.length}`)
}

main().catch(err => {
  console.error('[FATAL]', err.message)
  process.exit(1)
})
