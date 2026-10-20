// Renders every scene of the prototype in Chromium, screenshots it, scans the DOM for
// overlaps / clipped text and drives the main interactions (tap-select, resize, drag
// from backlog across days, drawer swipe, matrix drag). Writes a JSON report.
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const PORT = Number(process.env.PORT || 8765);
const OUT = process.argv[2];
const SCENES = ['Main', 'ThreeDays', 'List', 'Matrix', 'Backlog', 'Drag', 'Resize', 'Overdue', 'Voice'];
fs.mkdirSync(OUT, { recursive: true });

const report = { scenes: {}, interactions: [], console: [] };

// DOM scan: text that does not fit its box, and siblings whose boxes overlap.
const SCAN = `(() => {
  const root = document.querySelector('[data-root]');
  if (!root) return { error: 'no root' };
  const rr = root.getBoundingClientRect();
  const issues = [];
  const vis = (el) => { const r = el.getBoundingClientRect(); return r.width > 0 && r.height > 0 && r.bottom > rr.top && r.top < rr.bottom; };
  const desc = (el) => {
    const t = (el.textContent || '').trim().replace(/\\s+/g, ' ').slice(0, 40);
    const r = el.getBoundingClientRect();
    return el.tagName.toLowerCase() + (el.getAttribute('aria-label') ? '[' + el.getAttribute('aria-label').slice(0, 30) + ']' : '') + ' "' + t + '" @' + Math.round(r.left - rr.left) + ',' + Math.round(r.top - rr.top) + ' ' + Math.round(r.width) + 'x' + Math.round(r.height);
  };
  const clipRect = (el) => {
    let r = el.getBoundingClientRect();
    let x1 = r.left, y1 = r.top, x2 = r.right, y2 = r.bottom;
    let p = el.parentElement;
    while (p && p !== root.parentElement) {
      const cs = getComputedStyle(p);
      if (cs.overflow !== 'visible' || cs.overflowX !== 'visible' || cs.overflowY !== 'visible') {
        const pr = p.getBoundingClientRect();
        x1 = Math.max(x1, pr.left); y1 = Math.max(y1, pr.top); x2 = Math.min(x2, pr.right); y2 = Math.min(y2, pr.bottom);
      }
      p = p.parentElement;
    }
    return { left: x1, top: y1, right: x2, bottom: y2, width: Math.max(0, x2 - x1), height: Math.max(0, y2 - y1) };
  };
  const all = Array.from(root.querySelectorAll('*'));
  // 1. Text overflow: element whose scroll size exceeds its client size without hidden overflow / ellipsis.
  for (const el of all) {
    if (!vis(el)) continue;
    const cs = getComputedStyle(el);
    if (cs.overflowX === 'hidden' || cs.overflowY === 'hidden' || cs.overflowY === 'auto' || cs.overflowY === 'scroll') continue;
    if (el.scrollWidth > el.clientWidth + 1 && el.clientWidth > 0) {
      const r = el.getBoundingClientRect(), c = clipRect(el);
      if (c.width >= r.width - 1) issues.push({ kind: 'text-overflow-x', el: desc(el), by: el.scrollWidth - el.clientWidth, parent: el.parentElement.tagName.toLowerCase() + '/' + getComputedStyle(el.parentElement).overflow });
    }
    if (el.scrollHeight > el.clientHeight + 1 && el.clientHeight > 0 && cs.display !== 'inline') issues.push({ kind: 'overflow-y', el: desc(el), by: el.scrollHeight - el.clientHeight });
  }
  // 2. Overlapping siblings (both visible, not absolutely positioned on purpose, not inside svg).
  const seen = new Set();
  for (const el of all) {
    if (el.closest('svg')) continue;
    if (getComputedStyle(el).transform !== 'none') continue;
    const kids = Array.from(el.children).filter((k) => !k.closest('svg') && vis(k) && getComputedStyle(k).position !== 'absolute' && getComputedStyle(k).position !== 'fixed');
    for (let i = 0; i < kids.length; i++) for (let j = i + 1; j < kids.length; j++) {
      const a = clipRect(kids[i]), b = clipRect(kids[j]);
      const ox = Math.min(a.right, b.right) - Math.max(a.left, b.left);
      const oy = Math.min(a.bottom, b.bottom) - Math.max(a.top, b.top);
      if (ox > 1.5 && oy > 1.5) {
        const key = desc(kids[i]) + '|' + desc(kids[j]);
        if (!seen.has(key)) { seen.add(key); issues.push({ kind: 'sibling-overlap', a: desc(kids[i]), b: desc(kids[j]), ox: Math.round(ox), oy: Math.round(oy) }); }
      }
    }
  }
  // 3. Anything poking outside the 390x844 root.
  for (const el of all) {
    if (el.closest('svg') || !vis(el)) continue;
    const r = clipRect(el);
    if (r.width > 0 && (r.right > rr.right + 1 || r.left < rr.left - 1)) issues.push({ kind: 'outside-root-x', el: desc(el), parent: el.parentElement.tagName.toLowerCase() + '/' + getComputedStyle(el.parentElement).overflow });
  }
  return { issues, rootW: rr.width, rootH: rr.height };
})()`;

async function main() {
  const browser = await chromium.launch();
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, hasTouch: false });
  const page = await ctx.newPage();
  page.on('console', (m) => { if (m.type() === 'error' || m.type() === 'warning') report.console.push(m.type() + ': ' + m.text().slice(0, 300)); });
  page.on('pageerror', (e) => report.console.push('pageerror: ' + String(e).slice(0, 300)));

  async function open(scene) {
    await page.goto('http://127.0.0.1:' + PORT + '/' + scene + '.dc.html', { waitUntil: 'load' });
    await page.waitForSelector('[data-root]', { timeout: 15000 });
    await page.waitForTimeout(700);
  }
  async function shot(name) {
    await page.screenshot({ path: path.join(OUT, name + '.png') });
  }

  for (const scene of SCENES) {
    try {
      await open(scene);
      await shot(scene);
      report.scenes[scene] = await page.evaluate(SCAN);
    } catch (e) {
      report.scenes[scene] = { error: String(e).slice(0, 300) };
    }
  }

  // ---- Interactions on the main scene ----
  const log = (name, ok, detail) => report.interactions.push({ name, ok, detail });
  const box = async (sel) => { const h = await page.$(sel); return h ? await h.boundingBox() : null; };
  const blockByText = async (txt) => {
    const h = await page.$('[data-day] div:has-text("' + txt + '") >> nth=0');
    return h;
  };
  const drag = async (from, to, steps, holdMs) => {
    await page.mouse.move(from.x, from.y);
    await page.mouse.down();
    for (let i = 1; i <= steps; i++) {
      await page.mouse.move(from.x + (to.x - from.x) * i / steps, from.y + (to.y - from.y) * i / steps);
      await page.waitForTimeout(16);
    }
    if (holdMs) await page.waitForTimeout(holdMs);
  };

  try {
    await open('Main');
    // 1. Tap a block -> selection handle + chip appear.
    const diploma = await page.$('[data-day] >> text=Писать главу диплома');
    const b0 = await diploma.boundingBox();
    await page.mouse.click(b0.x + b0.width * 0.7, b0.y + b0.height * 0.5);
    await page.waitForTimeout(200);
    let chip = await page.$('[data-day] >> text=/14:30–16:00 · 1 ч 30 мин/');
    log('tap selects block (duration shown in block)', !!chip, chip ? await chip.textContent() : 'no label');
    const clamp = await page.evaluate(() => { const el = Array.from(document.querySelectorAll('[data-day] span')).find((x) => /Придумать контент/.test(x.textContent)); return el ? getComputedStyle(el).webkitLineClamp + '|' + getComputedStyle(el).display : 'none'; });
    log('tall block title uses line-clamp', /^\d+\|(-webkit-box|flow-root)$/.test(clamp), clamp);
    await shot('ix-01-selected');
    // 2. Resize by dragging the handle down 56px (= +60 min).
    const handle = await page.$('[data-day] div[style*="ns-resize"]');
    if (handle) {
      const hb = await handle.boundingBox();
      await drag({ x: hb.x + hb.width / 2, y: hb.y + hb.height / 2 }, { x: hb.x + hb.width / 2, y: hb.y + hb.height / 2 + 56 }, 8, 100);
      await shot('ix-02-resizing');
      await page.mouse.up();
      await page.waitForTimeout(200);
      chip = await page.$('[data-day] >> text=/14:30–17:00 · 2 ч 30 мин/');
      const txt = chip ? await chip.textContent() : '';
      log('resize handle +56px => 2 ч 30 мин', /2 ч 30 мин/.test(txt), txt);
      await shot('ix-03-resized');
    } else log('resize handle present', false, 'no handle element');
    // 3. Tap empty timeline -> deselect.
    const col = await box('[data-day]');
    const lbl = await box('[data-tl] >> text=21:00');
    await page.mouse.click(col.x + col.width * 0.8, lbl.y - 20);
    await page.waitForTimeout(150);
    log('tap empty area deselects', !(await page.$('[data-day] div[style*="ns-resize"]')), '');

    // 4. Drag a backlog item up to the timeline, hover a weekday tab to switch day, drop at a time.
    await page.click('[data-backlog] button[aria-expanded]');
    await page.waitForTimeout(450);
    const row = await page.$('[data-backlog] >> text=Записаться к стоматологу');
    const rb = await row.boundingBox();
    const tab = await page.$('[data-wday="2"]');
    const tb = await tab.boundingBox();
    const titleBefore = await page.textContent('h1');
    await drag({ x: rb.x + rb.width * 0.6, y: rb.y + rb.height / 2 }, { x: tb.x + tb.width / 2, y: tb.y + tb.height / 2 }, 14, 650);
    const titleAfter = await page.textContent('h1');
    await shot('ix-04-spring-day');
    log('hover weekday tab while dragging switches day', titleBefore !== titleAfter, titleBefore + ' -> ' + titleAfter);
    // Now move down into the timeline and drop at ~16:00.
    const col2 = await box('[data-day]');
    await page.mouse.move(col2.x + col2.width * 0.5, col2.y + col2.height * 0.55, { steps: 10 });
    await page.waitForTimeout(120);
    const pv = await page.$('[data-day] div[style*="dashed"]');
    log('time preview shown while over column', !!pv, pv ? await pv.textContent() : '');
    await shot('ix-05-drag-over-column');
    await page.mouse.up();
    await page.waitForTimeout(250);
    const dropped = await page.$('[data-day] >> text=Записаться к стоматологу');
    log('dropped task appears on timeline', !!dropped, '');
    const chip2 = await page.$('[data-day] >> text=/^15 мин$/');
    log('dropped task auto-selected (duration label)', !!chip2, chip2 ? await chip2.textContent() : '');
    await shot('ix-06-dropped');

    // 5. Drag the timeline block back to the drawer -> backlog, and it should be first in the list.
    const blk = await page.$('[data-day] >> text=Записаться к стоматологу');
    const bb = await blk.boundingBox();
    const dw = await box('[data-backlog]');
    await drag({ x: bb.x + bb.width * 0.25, y: bb.y + bb.height / 2 }, { x: dw.x + 200, y: dw.y + 30 }, 12, 150);
    await shot('ix-07-over-drawer');
    await page.mouse.up();
    await page.waitForTimeout(300);
    await page.click('[data-backlog] button[aria-expanded]');
    await page.waitForTimeout(450);
    const firstRow = await page.$('[data-backlog] div[style*="height: 50px"] >> nth=0');
    const firstTxt = firstRow ? await firstRow.textContent() : '';
    log('returned task is first in backlog', /стоматологу/.test(firstTxt), firstTxt.slice(0, 60));
    log('short block drag did not resize it', !(await page.$('[data-day] >> text=16:00–21:30')), '');
    // Grabbing a short selected block at its centre must still MOVE it (handle is only the centre pill zone)
    const row2 = await page.$('[data-backlog] >> text=Записаться к стоматологу');
    const rb2 = await row2.boundingBox();
    const col3 = await box('[data-day]');
    await drag({ x: rb2.x + rb2.width * 0.6, y: rb2.y + rb2.height / 2 }, { x: col3.x + col3.width * 0.5, y: col3.y + col3.height * 0.6 }, 14, 150);
    await page.mouse.up();
    await page.waitForTimeout(250);
    const blk2 = await page.$('[data-day] >> text=Записаться к стоматологу');
    const bb2 = await blk2.boundingBox();
    const chipB = await page.$('[data-day] >> text=/^15 мин$/');
    const chipTxtBefore = chipB ? await chipB.textContent() : '';
    await drag({ x: bb2.x + bb2.width * 0.15, y: bb2.y + bb2.height * 0.75 }, { x: bb2.x + bb2.width * 0.15, y: bb2.y + bb2.height * 0.75 - 112 }, 10, 150);
    await page.mouse.up();
    await page.waitForTimeout(250);
    const blk3 = await page.$('[data-day] >> text=Записаться к стоматологу');
    const bb3b = await blk3.boundingBox();
    const chipA = await page.$('[data-day] >> text=/^15 мин$/');
    const chipTxtAfter = chipA ? await chipA.textContent() : '';
    log('grabbing lower-left of a short selected block moves it (-2h), keeps 15 min', Math.abs((bb2.y - bb3b.y) - 112) < 6 && /15 мин/.test(chipTxtAfter), bb2.y + ' -> ' + bb3b.y + ' | ' + chipTxtBefore + ' -> ' + chipTxtAfter);
    await shot('ix-07b-moved-short-block');

    // 6. Swipe the drawer handle up -> opens.
    const hdr = await page.$('[data-backlog] button[aria-expanded]');
    if ((await box('[data-backlog]')).height > 200) { await hdr.click(); await page.waitForTimeout(450); }
    const hb2 = await hdr.boundingBox();
    const hBefore = (await box('[data-backlog]')).height;
    await drag({ x: hb2.x + hb2.width / 2, y: hb2.y + 20 }, { x: hb2.x + hb2.width / 2, y: hb2.y - 200 }, 10, 100);
    await page.mouse.up();
    await page.waitForTimeout(450);
    const hAfter = (await box('[data-backlog]')).height;
    log('swipe up opens drawer', hAfter > hBefore + 100, hBefore + ' -> ' + hAfter);
    await shot('ix-08-drawer-open');
    report.scenes['ix-08-drawer-open'] = await page.evaluate(SCAN);
    // 7. Swipe down closes.
    const hb3 = await hdr.boundingBox();
    await drag({ x: hb3.x + hb3.width / 2, y: hb3.y + 20 }, { x: hb3.x + hb3.width / 2, y: hb3.y + 260 }, 10, 100);
    await page.mouse.up();
    await page.waitForTimeout(450);
    const hAfter2 = (await box('[data-backlog]')).height;
    log('swipe down closes drawer', hAfter2 < hAfter - 100, hAfter + ' -> ' + hAfter2);
    // 8. Tap header toggles (click path, not double toggled by swipe logic).
    await hdr.click();
    await page.waitForTimeout(450);
    const hAfter3 = (await box('[data-backlog]')).height;
    log('tap header opens drawer', hAfter3 > hAfter2 + 100, hAfter2 + ' -> ' + hAfter3);
    await hdr.click();
    await page.waitForTimeout(450);

    // 9. Quick add parses date/time/quadrant.
    await page.fill('#pln-add', 'завтра в 9:30 написать научруку на 45 минут, важно');
    await page.keyboard.press('Enter');
    await page.waitForTimeout(300);
    const toast = await page.$('[role="status"]');
    const tt = toast ? await toast.textContent() : '';
    log('quick add toast', /завтра · 9:30–10:15/.test(tt), tt);
    await shot('ix-09-quick-add');

    // 10. Matrix: open menu, pick matrix, drag a task between quadrants.
    await page.click('button[aria-label="Переключить вид"]');
    await page.waitForTimeout(200);
    await shot('ix-10-view-menu');
    report.scenes['ix-10-view-menu'] = await page.evaluate(SCAN);
    await page.click('text=Матрица Эйзенхауэра');
    await page.waitForTimeout(300);
    const q4 = await page.$('[data-quad="4"]');
    const item = await page.$('[data-quad="3"] >> text=Забрать посылку');
    const ib = await item.boundingBox();
    const qb = await q4.boundingBox();
    await drag({ x: ib.x + ib.width * 0.6, y: ib.y + ib.height / 2 }, { x: qb.x + qb.width / 2, y: qb.y + qb.height / 2 }, 12, 150);
    await shot('ix-11-matrix-drag');
    await page.mouse.up();
    await page.waitForTimeout(300);
    const moved = await page.$('[data-quad="4"] >> text=Забрать посылку');
    log('matrix drag moves task to another quadrant', !!moved, '');
    await shot('ix-12-matrix-after');
    report.scenes['ix-12-matrix-after'] = await page.evaluate(SCAN);

    // 11. Overdue sheet -> fit today.
    await page.click('button[aria-label^="Просрочено"]');
    await page.waitForTimeout(300);
    await page.click('text=Перенести');
    await page.waitForTimeout(300);
    await page.click('text=На сегодня — в свободные окна');
    await page.waitForTimeout(400);
    const toast2 = await page.$('[role="status"]');
    const tt2 = toast2 ? await toast2.textContent() : '';
    log('fit overdue into today', /Разложил на сегодня/.test(tt2), tt2);
    log('overdue chip hidden after fit', !(await page.$('button[aria-label^="Просрочено"]')), '');
    await shot('ix-13-after-fit');

    // 11b. Cross-day drag of a SCHEDULED task (the element unmounts when the day switches).
    await page.click('button[aria-label="К сегодняшнему дню"]');
    await page.waitForTimeout(200);
    const dip = await page.$('[data-day] >> text=Писать главу диплома');
    const db = await dip.boundingBox();
    const tab23 = await page.$('[data-wday="3"]');
    const t3b = await tab23.boundingBox();
    await drag({ x: db.x + db.width * 0.2, y: db.y + db.height * 0.5 }, { x: t3b.x + t3b.width / 2, y: t3b.y + t3b.height / 2 }, 14, 650);
    const colX = await box('[data-day]');
    await page.mouse.move(colX.x + colX.width * 0.5, colX.y + colX.height * 0.45, { steps: 10 });
    await page.waitForTimeout(150);
    await page.mouse.up();
    await page.waitForTimeout(300);
    const ghostGone = !(await page.$('div[style*="rotate(-2deg)"]'));
    const landed = await page.$('[data-day="3"] >> text=Писать главу диплома');
    log('scheduled task dragged across days lands on the new day, ghost cleared', ghostGone && !!landed, 'ghostGone=' + ghostGone + ' landed=' + !!landed + ' title=' + (await page.textContent('h1')));
    await shot('ix-11b-cross-day-scheduled');

    // 11c. Touch: a quick swipe over a task must NOT start a drag; a long-press must.
    await page.click('button[aria-label="К сегодняшнему дню"]');
    await page.waitForTimeout(200);
    const tr = await page.$('[data-day] >> text=Тренировка');
    const trb = await tr.boundingBox();
    const fire = async (sel, type, x, y, extra) => page.evaluate(({ sel, type, x, y, extra }) => {
      const el = sel ? document.querySelector(sel) : document.elementFromPoint(x, y);
      el.dispatchEvent(new PointerEvent(type, Object.assign({ bubbles: true, cancelable: true, composed: true, pointerId: 7, pointerType: 'touch', isPrimary: true, clientX: x, clientY: y, button: type === 'pointerdown' ? 0 : -1, buttons: type === 'pointerup' || type === 'pointercancel' ? 0 : 1 }, extra || {})));
    }, { sel, type, x, y, extra });
    const cx = trb.x + trb.width * 0.5, cy = trb.y + trb.height * 0.5;
    await fire(null, 'pointerdown', cx, cy);
    await page.waitForTimeout(60);
    await fire('[data-root]', 'pointermove', cx, cy - 40);
    await page.waitForTimeout(60);
    const ghostDuringSwipe = !!(await page.$('div[style*="rotate(-2deg)"]'));
    await fire('[data-root]', 'pointercancel', cx, cy - 40);
    await page.waitForTimeout(400);
    const ghostAfterSwipe = !!(await page.$('div[style*="rotate(-2deg)"]'));
    log('touch swipe over a task does not start a drag', !ghostDuringSwipe && !ghostAfterSwipe, 'during=' + ghostDuringSwipe + ' after=' + ghostAfterSwipe);
    await fire(null, 'pointerdown', cx, cy);
    await page.waitForTimeout(420);
    const ghostAfterHold = !!(await page.$('div[style*="rotate(-2deg)"]'));
    await fire('[data-root]', 'pointermove', cx, cy - 112);
    await page.waitForTimeout(120);
    await shot('ix-11c-touch-longpress-drag');
    await fire('[data-root]', 'pointerup', cx, cy - 112);
    await page.waitForTimeout(300);
    const dumpT = await page.evaluate(() => ({ h1: document.querySelector('h1').textContent, blocks: Array.from(document.querySelectorAll('[data-day] > div[style*="cursor: grab"]')).map((d) => d.textContent.trim().slice(0, 36)), ghost: !!document.querySelector('div[style*="rotate(-2deg)"]'), toast: (document.querySelector('[role=status]') || {}).textContent || '' }));
    const movedT = dumpT.blocks.find((x) => /^Тренировка/.test(x) && !/18:30/.test(x));
    log('touch long-press starts a drag and the task moves', ghostAfterHold && !!movedT && !dumpT.ghost, 'ghostAfterHold=' + ghostAfterHold + ' ' + JSON.stringify(dumpT));

    // 11d. Resize auto-scrolls when the handle is held near the bottom edge; end of day reads 24:00.
    const sp = await page.$('[data-day] >> text=Спортзал');
    if (sp) { /* not today */ }
    const tr2 = await page.$('[data-day] >> text=/^Тренировка/');
    const tr2b = await tr2.boundingBox();
    if (!(await page.$('[data-day] div[style*="ns-resize"]'))) { await page.mouse.click(tr2b.x + tr2b.width * 0.2, tr2b.y + tr2b.height * 0.5); await page.waitForTimeout(200); }
    const h2 = await page.$('[data-day] div[style*="ns-resize"]');
    const h2b = await h2.boundingBox();
    const tlb = await box('[data-tl]');
    const st0 = await page.evaluate(() => document.querySelector('[data-tl]').scrollTop);
    await drag({ x: h2b.x + h2b.width / 2, y: h2b.y + h2b.height / 2 }, { x: h2b.x + h2b.width / 2, y: tlb.y + tlb.height - 20 }, 10, 900);
    const st1 = await page.evaluate(() => document.querySelector('[data-tl]').scrollTop);
    await shot('ix-11d-resize-autoscroll');
    await page.mouse.up();
    await page.waitForTimeout(250);
    const lblEnd = await page.$('[data-day] >> text=/Тренировка/');
    log('resize near the bottom edge auto-scrolls the timeline', st1 > st0 + 40, st0 + ' -> ' + st1 + ' label=' + (lblEnd ? await lblEnd.textContent() : 'none'));
    await page.click('button[aria-label="К сегодняшнему дню"]');

    // 12. Three-day view with a selected task (resize handle in narrow column).
    await page.click('button[aria-label="Переключить вид"]');
    await page.waitForTimeout(150);
    await page.click('text=3 дня');
    await page.waitForTimeout(300);
    const b3 = await page.$('[data-day="0"] >> text=Писать главу диплома');
    if (b3) {
      const bb3 = await b3.boundingBox();
      await page.mouse.click(bb3.x + bb3.width * 0.7, bb3.y + bb3.height * 0.5);
      await page.waitForTimeout(200);
    }
    await shot('ix-14-three-selected');
    report.scenes['ix-14-three-selected'] = await page.evaluate(SCAN);
  } catch (e) {
    report.interactions.push({ name: 'interaction script crashed', ok: false, detail: String(e.stack || e).slice(0, 600) });
    try { await shot('ix-crash'); } catch (e2) {}
  }

  await browser.close();
  fs.writeFileSync(path.join(OUT, 'report.json'), JSON.stringify(report, null, 2));
  console.log(JSON.stringify(report.interactions, null, 1));
  for (const k of Object.keys(report.scenes)) {
    const sc = report.scenes[k];
    console.log('== ' + k + ': ' + (sc.error ? 'ERROR ' + sc.error : (sc.issues.length + ' issues')));
    if (sc.issues) sc.issues.slice(0, 25).forEach((i) => console.log('   ' + JSON.stringify(i)));
  }
  console.log('console:', report.console.slice(0, 20));
}

main().catch((e) => { console.error(e); process.exit(1); });
