// Optional development tool: compile the locally pinned Tailwind runtime once.
// The delivered page uses only the resulting CSS, with no runtime compiler.
const {chromium}=require(process.env.PLAYWRIGHT_MODULE || 'C:/Users/user/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const fs=require('fs');const path=require('path');
(async()=>{
 const browser=await chromium.launch({executablePath:process.env.CHROME_PATH||'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true});
 const page=await browser.newPage();await page.goto('http://127.0.0.1:5000');
 if(!await page.locator('script[src$="tailwind-browser.js"]').count())await page.addScriptTag({path:path.resolve(__dirname,'../static/vendor/tailwind-browser.js')});
 await page.waitForFunction(()=>[...document.querySelectorAll('style')].some(e=>e.textContent.includes('tailwindcss')));
 const css=await page.evaluate(()=>[...document.querySelectorAll('style')].map(e=>e.textContent).filter(t=>t.includes('tailwindcss')).join('\n'));
 fs.writeFileSync(path.resolve(__dirname,'../static/css/tailwind.css'),css);await browser.close();console.log('Compiled Tailwind CSS: '+css.length+' bytes');
})().catch(e=>{console.error(e);process.exit(1)});
