#!/usr/bin/env node
// LinkedIn bejelentkezes CDP-n keresztul (Windows Chrome-on)
const { chromium } = require('playwright');
const path = require('path');

const STATE_FILE = path.join(__dirname, '../store/linkedin-session.json');

(async () => {
  console.log('Csatlakozas a Chrome-hoz (port 9222)...');

  const browser = await chromium.connectOverCDP('http://localhost:9222');
  const contexts = browser.contexts();
  const context = contexts[0] || await browser.newContext();

  const pages = context.pages();
  const page = pages[0] || await context.newPage();

  console.log('Megnyitom a LinkedIn login oldalt...');
  await page.goto('https://www.linkedin.com/login');
  console.log('Jelentkezz be LinkedInre a Chrome ablakban!\n');

  // Var amig bejelentkezik (max 3 perc)
  for (let i = 0; i < 36; i++) {
    await page.waitForTimeout(5000);
    const url = page.url();
    if (url.includes('/feed') || url.includes('/in/') || url.includes('/home')) {
      console.log('Bejelentkezes sikeres! Session mentese...');
      await context.storageState({ path: STATE_FILE });
      console.log(`Session elmentve: ${STATE_FILE}`);
      console.log('Kesz! Bezarhatod a Chrome ablakot.');
      await browser.close();
      return;
    }
    process.stdout.write('.');
  }

  console.log('\nIdotullepes. Probald ujra.');
  await browser.close();
})().catch(err => {
  console.error('Hiba:', err.message);
  process.exit(1);
});
