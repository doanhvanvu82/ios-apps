import { chromium } from 'playwright';

const extPath = process.cwd() + '/WebExtension';

async function test() {
  console.log('Loading extension from:', extPath);
  
  const browser = await chromium.launch({
    headless: false,
    args: [
      `--disable-extensions-except=${extPath}`,
      `--load-extension=${extPath}`,
    ]
  });
  
  // Đợi extension load
  await new Promise(r => setTimeout(r, 3000));
  
  // Tạo context mới và page
  const context = await browser.newContext();
  const page = await context.newPage();
  
  console.log('Navigating to fapmanga...');
  await page.goto('https://fapmanga.com/truyen-hentai/khi-toi-tro-ve-nha-sau-quang-thoi-gian-dai-ban/chap-1');
  
  // Đợi load
  await page.waitForTimeout(5000);
  
  // Chụp màn hình
  await page.screenshot({ path: '/home/vudv/Documents/Code/ios/.state/ext-test.png', fullPage: true });
  console.log('Screenshot saved');
  
  // Kiểm tra overlay
  const overlay = await page.evaluate(() => {
    const els = document.querySelectorAll('*');
    for (const el of els) {
      const style = window.getComputedStyle(el);
      const text = el.innerText || '';
      if (style.position === 'fixed' && 
          (text.includes('adblock') || text.includes('quảng cáo') || text.includes('chặn'))) {
        return { tag: el.tagName, text: text.substring(0, 200), zIndex: style.zIndex };
      }
    }
    return null;
  });
  
  console.log('Overlay found:', overlay);
  
  // Kiểm tra scroll bị chặn
  const scrollInfo = await page.evaluate(() => {
    return {
      bodyOverflow: window.getComputedStyle(document.body).overflow,
      htmlOverflow: window.getComputedStyle(document.documentElement).overflow,
      scrollable: document.body.scrollHeight > window.innerHeight
    };
  });
  console.log('Scroll info:', scrollInfo);
  
  await browser.close();
  console.log('Done');
}

test().catch(e => { console.error(e); process.exit(1); });
