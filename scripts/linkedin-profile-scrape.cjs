#!/usr/bin/env node
const { chromium } = require('playwright');
const fs = require('fs');

const SESSION_FILE = '/home/userzoltan/marveen/store/linkedin-session.json';
const PROFILE_URL = 'https://www.linkedin.com/in/zoltan-kothencz-200a0013';

(async () => {
  const browser = await chromium.launch({
    headless: true,
    executablePath: '/snap/bin/chromium',
    args: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-dev-shm-usage']
  });

  const context = await browser.newContext({
    storageState: SESSION_FILE,
    userAgent: 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
  });

  const page = await context.newPage();
  
  try {
    await page.goto(PROFILE_URL, { waitUntil: 'domcontentloaded', timeout: 30000 });
    await page.waitForTimeout(3000);
    
    const currentUrl = page.url();
    const title = await page.title();
    
    if (currentUrl.includes('login') || currentUrl.includes('authwall')) {
      console.log(JSON.stringify({ error: 'not_logged_in', url: currentUrl }));
      await browser.close();
      return;
    }

    // Extract profile data
    const profile = await page.evaluate(() => {
      const getText = (sel) => document.querySelector(sel)?.innerText?.trim() || '';
      
      // Headline
      const headline = getText('.text-body-medium.break-words') || 
                       getText('[data-field="headline"]') ||
                       getText('.pv-text-details__left-panel .text-body-medium');
      
      // Name
      const name = getText('h1');
      
      // Location  
      const location = getText('.text-body-small.inline.t-black--light.break-words') ||
                       getText('[data-field="location"]');
      
      // About/Summary
      const about = getText('.pv-shared-text-with-see-more span[aria-hidden="true"]') ||
                    getText('#about ~ div .visually-hidden ~ span') ||
                    document.querySelector('#about')?.closest('section')?.querySelector('.inline-show-more-text')?.innerText?.trim() || '';
      
      // Skills
      const skillEls = document.querySelectorAll('.pv-skill-category-entity__name, .pvs-entity .t-bold span[aria-hidden="true"]');
      const skills = Array.from(skillEls).map(el => el.innerText.trim()).filter(s => s.length > 0).slice(0, 30);
      
      // Experience
      const expSection = document.querySelector('#experience')?.closest('section');
      const expText = expSection?.innerText?.trim()?.substring(0, 2000) || '';
      
      // Recent activity
      const activitySection = document.querySelector('#activity')?.closest('section');
      const activityText = activitySection?.innerText?.trim()?.substring(0, 500) || '';
      
      // Full page text for fallback
      const fullText = document.body.innerText.substring(0, 5000);
      
      return { name, headline, location, about, skills, expText, activityText, fullText };
    });
    
    console.log(JSON.stringify({ success: true, url: currentUrl, title, profile }));
    
  } catch(e) {
    console.log(JSON.stringify({ error: e.message }));
  }
  
  await browser.close();
})();
