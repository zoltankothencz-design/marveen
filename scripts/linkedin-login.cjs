#!/usr/bin/env node
// LinkedIn bejelentkezes - egyszer futtatando script
// Megnyit egy Chrome ablakot, te bejelentkezel, elmenti a session-t

const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');

const STATE_FILE = path.join(__dirname, '../store/linkedin-session.json');

(async () => {
  console.log('LinkedIn bejelentkezes indul...');
  console.log('Megnyilik a Chrome ablak. Jelentkezz be LinkedInre, majd vard meg az automatikus mentést.\n');

  const browser = await chromium.launch({
    headless: false,
    executablePath: process.env.PLAYWRIGHT_BROWSERS_PATH
      ? `${process.env.PLAYWRIGHT_BROWSERS_PATH}/chromium-1226/chrome-linux64/chrome`
      : undefined,
    args: ['--no-sandbox', '--disable-setuid-sandbox']
  });

  const context = await browser.newContext();
  const page = await context.newPage();

  await page.goto('https://www.linkedin.com/login');
  console.log('LinkedIn login oldal megnyilt. Jelentkezz be...');

  // Var amig bejelentkezik (max 3 perc)
  let loggedIn = false;
  for (let i = 0; i < 36; i++) {
    await page.waitForTimeout(5000);
    const url = page.url();
    if (url.includes('linkedin.com/feed') || url.includes('linkedin.com/in/') || url.includes('linkedin.com/home')) {
      loggedIn = true;
      console.log('\nBejelentkezés sikeres! Session mentése...');
      break;
    }
    process.stdout.write('.');
  }

  if (loggedIn) {
    await context.storageState({ path: STATE_FILE });
    console.log(`\nSession elmentve: ${STATE_FILE}`);
    console.log('Job-hunter mostantól LinkedInre be van jelentkezve.');
  } else {
    console.log('\nIdőtúllépés - próbáld újra.');
  }

  await browser.close();
})().catch(err => {
  console.error('Hiba:', err.message);
  process.exit(1);
});
