#!/usr/bin/env node
'use strict'

// LinkedIn Jobs search via the public jobs-guest API (no login required).
// Uses /jobs-guest/jobs/api/seeMoreJobPostings/search -- returns structured HTML job cards,
// pageable with start=0,10,20... Rate limit kicks in after ~10 pages from a single IP,
// so keep to max 2 pages (20 results) per keyword for daily scans.
// Node 22 native fetch is used -- no node-fetch dependency needed.

const KEYWORDS = [
  'iGaming Operations Manager',
  'Casino Manager',
  'BI Analyst iGaming',
  'Compliance Manager casino',
  'General Manager iGaming',
]

const LOCATION = 'Europe'
const PAGES_PER_KEYWORD = 2   // 2 pages = 20 results, safe daily rate-limit margin
const DELAY_MS = 2000         // polite delay between requests
const F_TPR = 'r604800'       // past 7 days (r86400=24h, r2592000=30d)
const SORT_BY = 'DD'          // DD=most recent, R=relevance

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

async function fetchPage(keyword, start) {
  const params = new URLSearchParams({
    keywords: keyword,
    location: LOCATION,
    start: String(start),
    sortBy: SORT_BY,
    f_TPR: F_TPR,
  })
  const url = `https://www.linkedin.com/jobs-guest/jobs/api/seeMoreJobPostings/search?${params}`

  let resp
  try {
    resp = await fetch(url, { headers: HEADERS })
  } catch (err) {
    console.error(`[ERROR] fetch failed for "${keyword}" start=${start}: ${err.message}`)
    return null
  }

  if (!resp.ok) {
    console.error(`[ERROR] HTTP ${resp.status} for "${keyword}" start=${start}`)
    return null
  }

  return resp.text()
}

async function searchKeyword(keyword) {
  const allJobs = []
  for (let page = 0; page < PAGES_PER_KEYWORD; page++) {
    if (page > 0) await sleep(DELAY_MS)
    const html = await fetchPage(keyword, page * 10)
    if (!html) break
    const jobs = parseJobCards(html, keyword)
    allJobs.push(...jobs)
    if (jobs.length < 10) break  // fewer than full page = no more results
  }
  console.error(`[INFO] "${keyword}": found ${allJobs.length} jobs (${PAGES_PER_KEYWORD} pages)`)
  return allJobs
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
