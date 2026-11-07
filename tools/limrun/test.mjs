// 蒜數 iOS 版：在 Limrun 雲端 iPhone 模擬器走一遍主流程，截圖存到 shots/。第五版：座標點元件、自己做滑動、鍵盤偵測與收鍵盤、只看 x 判斷在哪一頁、輸入用英文。
// 用法：node test.mjs <Suanshu-simulator.app.zip> [截圖資料夾名，預設 shots]
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import Limrun, { Ios } from '@limrun/api';

const HERE = dirname(fileURLToPath(import.meta.url));
const OUT = join(HERE, process.argv[3] ?? 'shots');
mkdirSync(OUT, { recursive: true });
const home = process.env.USERPROFILE ?? process.env.HOME;
const cfg = readFileSync(join(home, '.lim', 'config.yaml'), 'utf8');
const apiKey = process.env.LIM_API_KEY ?? (cfg.match(/api-key:\s*(\S+)/) ?? [])[1];
if (!apiKey) { console.error('no api key'); process.exit(2); }
const ZIP = process.argv[2];
if (!ZIP) { console.error('usage: node test.mjs <app.zip> [outdir]'); process.exit(2); }
const BUNDLE = 'org.domyweb.suanshu';
const lim = new Limrun({ apiKey });
const t0 = Date.now();
const log = (...a) => console.log(((Date.now() - t0) / 1000).toFixed(1).padStart(6) + 's', ...a);
const sleep = ms => new Promise(r => setTimeout(r, ms));
let inst = null;
let c = null;
let W = 402;
let H = 874;

function flat(n, out = []) {
  if (Array.isArray(n)) { for (const x of n) flat(x, out); return out; }
  if (!n || typeof n !== 'object') return out;
  out.push(n);
  for (const ch of n.children ?? []) flat(ch, out);
  return out;
}
const typeOf = n => String(n.type ?? '').toLowerCase();
const isBtn = n => typeOf(n).includes('button');
const isField = n => /text ?field|text ?view|textfield|textview|searchfield|textarea/.test(typeOf(n));
const center = n => ({ x: n.frame.x + n.frame.width / 2, y: n.frame.y + n.frame.height / 2 });
function visible(n, limitY = H) {
  if (!n.frame || n.frame.width <= 0 || n.frame.height <= 0) return false;
  const p = center(n);
  return p.x >= 0 && p.x <= W && p.y >= 0 && p.y <= limitY;
}
async function nodes() {
  const t = await c.elementTree();
  return flat(t).filter(n => n.frame);
}
async function has(label) {
  try { return (await nodes()).some(n => n.AXLabel && n.AXLabel.includes(label)); } catch { return false; }
}
async function visibleHas(label) {
  try { return (await nodes()).some(n => n.AXLabel && n.AXLabel.includes(label) && visible(n, H)); } catch { return false; }
}
async function tapNode(n, what) {
  const p = center(n);
  await c.tap(p.x, p.y);
  log('tap', what, typeOf(n), Math.round(p.x) + ',' + Math.round(p.y));
}

// 自己做的滑動：按下、分段移動、停一下再放開（不甩出去）
async function swipe(x0, y0, x1, y1, { steps = 14, stepWait = 6, hold = 60 } = {}) {
  const a = [{ type: 'touchDown', x: x0, y: y0 }, { type: 'wait', durationMs: hold }];
  for (let i = 1; i <= steps; i++) {
    a.push({ type: 'touchMove', x: Math.round(x0 + (x1 - x0) * i / steps), y: Math.round(y0 + (y1 - y0) * i / steps) });
    a.push({ type: 'wait', durationMs: stepWait });
  }
  a.push({ type: 'wait', durationMs: 120 });
  a.push({ type: 'touchUp', x: x1, y: y1 });
  try { await c.performActions(a, { timeoutMs: 20000 }); } catch (e) { log('swipe failed', e?.message); }
  await sleep(700);
}
const KEYISH = /^(Passwords|q|Q|space|shift|delete|Return|return|done|next|go|Search)$/;
async function keyboardTop() { try { const ns = await nodes(); const ks = ns.filter(n => n.frame && n.frame.width > 0 && (typeOf(n).includes('keyboard') || (isBtn(n) && n.AXLabel && KEYISH.test(n.AXLabel)))); if (!ks.length) return H; return Math.min(...ks.map(n => n.frame.y)); } catch { return H; } }
async function dismissKeyboard() { const top = await keyboardTop(); if (top >= H) return; log('keyboard up (top ' + Math.round(top) + '), dragging down to dismiss'); await swipe(Math.round(W / 2), Math.round(top - 160), Math.round(W / 2), Math.round(Math.min(H - 40, top + 160)), { steps: 16, stepWait: 10 }); const t2 = await keyboardTop(); log('keyboard after drag:', t2 >= H ? 'gone' : 'still at ' + Math.round(t2)); }
async function logField() { try { const f = (await nodes()).filter(n => isField(n) && visible(n, H))[0]; log('field value now:', JSON.stringify(String(f?.AXValue ?? '(none)').slice(0, 60))); } catch {} }
const scrollDown = async (px = 320) => { const top = await keyboardTop(); const y0 = Math.round(Math.min(H * 0.72, top - 70)); await swipe(Math.round(W / 2), y0, Math.round(W / 2), Math.max(y0 - px, 120)); };
const scrollUp = (px = 320) => swipe(Math.round(W / 2), Math.round(H * 0.3), Math.round(W / 2), Math.round(H * 0.3) + px);
const swipeToNextPage = () => swipe(Math.round(W * 0.85), Math.round(H * 0.5), Math.round(W * 0.15), Math.round(H * 0.5));
const swipeToPrevPage = () => swipe(Math.round(W * 0.15), Math.round(H * 0.5), Math.round(W * 0.85), Math.round(H * 0.5));

async function tapL(label, opts = {}) {
  const { contains = false, type = null, pick = 'only', wait = 500, attempts = 4, minY = 0 } = opts;
  const pred = n => !!n.AXLabel && (contains ? n.AXLabel.includes(label) : n.AXLabel === label) && (!type || typeOf(n).includes(type));
  for (let i = 0; i < attempts; i++) {
    const ns = await nodes();
    const limitY = await keyboardTop();
    let cands = ns.filter(pred).filter(n => visible(n, limitY) && n.frame.y >= minY);
    if (cands.length > 1) {
      if (pick === 'top') cands = [cands.reduce((a, b) => (a.frame.y <= b.frame.y ? a : b))];
      else if (pick === 'bottom') cands = [cands.reduce((a, b) => (a.frame.y >= b.frame.y ? a : b))];
      else { const b = cands.filter(isBtn); if (b.length === 1) cands = b; }
    }
    if (cands.length === 1) { await tapNode(cands[0], JSON.stringify(label)); await sleep(wait); return true; }
    if (cands.length > 1) { log('tap AMBIGUOUS', JSON.stringify(label), cands.map(n => typeOf(n) + '@' + Math.round(n.frame.y)).join(' ')); return false; }
    const any = ns.filter(pred).filter(n => n.frame.x + n.frame.width > 0 && n.frame.x < W);
    if (!any.length) { log('tap NOT FOUND', JSON.stringify(label)); return false; }
    const ty = center(any[0]).y;
    await dismissKeyboard();
    log('scroll', ty > H / 2 ? 'down' : 'up', 'to reach', JSON.stringify(label), 'y=' + Math.round(ty));
    if (ty > H / 2) await scrollDown(320); else await scrollUp(320);
  }
  log('tap GAVE UP', JSON.stringify(label));
  return false;
}
async function tapField(index = 0, wait = 500) {
  const ns = await nodes();
  const fields = ns.filter(n => isField(n) && visible(n, H)).sort((a, b) => a.frame.y - b.frame.y);
  const n = fields[index];
  if (!n) {
    log('no text field on screen; visible types:', JSON.stringify([...new Set(ns.filter(x => visible(x, H)).map(typeOf))].slice(0, 40)));
    return false;
  }
  await tapNode(n, 'field#' + index + ' label=' + JSON.stringify(n.AXLabel ?? '') + ' value=' + JSON.stringify(String(n.AXValue ?? '').slice(0, 30)));
  await sleep(wait);
  return true;
}
async function type(text) {
  try { await c.typeText(text); log('typed', JSON.stringify(text)); await sleep(300); }
  catch (e) { log('type FAILED', e?.message); }
}
async function shot(name) {
  try {
    const s = await c.screenshot({ format: 'jpeg', size: 'scaled' });
    W = s.width; H = s.height;
    writeFileSync(join(OUT, name + '.jpg'), Buffer.from(s.base64, 'base64'));
    log('shot', name, W + 'x' + H);
  } catch (e) { log('shot failed', name, e?.message); }
}
async function dumpNodes(name, max = 60) {
  try {
    const ns = await nodes();
    const vis = ns.filter(n => visible(n, H));
    log('nodes@' + name + ' (' + vis.length + ' visible of ' + ns.length + ')');
    for (const n of vis.slice(0, max)) {
      log('    ', typeOf(n).padEnd(16), JSON.stringify(n.AXLabel ?? ''), n.AXValue != null ? 'val=' + JSON.stringify(String(n.AXValue).slice(0, 40)) : '', [n.frame.x, n.frame.y, n.frame.width, n.frame.height].map(Math.round).join(','));
    }
  } catch (e) { log('dump failed', e?.message); }
}
async function simctl(args) {
  try {
    const ex = c.simctl(args);
    let r;
    if (ex && typeof ex.wait === 'function') r = await ex.wait();
    else if (ex && ex.waitPromise) r = await ex.waitPromise;
    else r = await ex;
    log('simctl', args.join(' '), 'exit=' + JSON.stringify(r?.exitCode ?? r ?? '').slice(0, 80), 'err=' + JSON.stringify((ex?.stderrChunks ?? []).join('')).slice(0, 120));
    return r;
  } catch (e) { log('simctl FAILED', args.join(' '), e?.message); }
}
const dot = name => tapL(name, { type: 'button', pick: 'top', wait: 900 });
const PAGES = ['籃子', '剝今天', '設定'];
const MARK = { '籃子': '上個月', '剝今天': '用說的', '設定': '每天' };
const xVisible = n => n.frame && n.frame.width > 0 && (n.frame.x + n.frame.width / 2) >= 0 && (n.frame.x + n.frame.width / 2) <= W;
async function currentPage() {
  const ns = await nodes();
  return PAGES.findIndex(p => ns.some(n => n.AXLabel === MARK[p] && xVisible(n)));
}
async function goPage(name) {
  const want = PAGES.indexOf(name);
  await dot(name);
  if ((await currentPage()) === want) return true;
  for (let i = 0; i < 3; i++) {
    const cur = await currentPage();
    if (cur === want) return true;
    if (cur < 0) break;
    log('page dot did not switch (at', PAGES[cur], ') swiping');
    await dismissKeyboard();
    if (want > cur) await swipeToNextPage(); else await swipeToPrevPage();
  }
  const ok = (await currentPage()) === want;
  log('goPage', name, ok ? 'ok' : 'FAILED');
  return ok;
}
async function closeSheet() {
  for (let i = 0; i < 7; i++) {
    if (await tapL('關閉', { wait: 700 })) return true;
    if (!(await tapL('上一步', { wait: 500 }))) break;
  }
  return false;
}

try {
  log('uploading', ZIP);
  const asset = await lim.assets.getOrUpload({ path: ZIP, name: 'suanshu-sim-' + Date.now() + '.zip', platform: 'ios', kind: 'App', ttl: '2h' });
  log('asset', asset.name);
  inst = await lim.iosInstances.create({
    wait: true,
    spec: {
      model: 'iphone',
      inactivityTimeout: '5m',
      hardTimeout: '25m',
      initialAssets: [{ kind: 'App', source: 'AssetName', assetName: asset.name, launchMode: 'RelaunchIfRunning' }],
    },
  });
  log('instance', inst.metadata?.id, inst.status?.state, 'region', inst.spec?.region);
  c = await Ios.createInstanceClient({ apiUrl: inst.status.apiUrl, token: inst.status.token, logLevel: 'none' });
  await sleep(4000);
  await shot('01-launch');
  if (!(await has('好')) && !(await has('剝今天'))) {
    await simctl(['launch', 'booted', BUNDLE]);
    await sleep(3000);
    await shot('01b-launch');
  }

  // 首次打開三步
  if (await has('好')) {
    await tapL('好');
    await shot('02-ob2');
    await tapL('關燈前');
    await tapL('下一步');
    await shot('03-ob3');
    await tapL('記住了，開始', { wait: 1200 });
  }
  await shot('04-after-onboarding');
  log('page right after onboarding:', PAGES[await currentPage()] ?? 'unknown (' + (await currentPage()) + ')');
  await goPage('剝今天');
  await shot('05-main');
  await dumpNodes('main', 40);

  // 記一句
  if (await tapField(0)) {
    await type('Meeting with partner at 2pm');
    await logField();
    await shot('06-typed');
    await tapL('記下', { wait: 1000 });
    await dismissKeyboard();
  }
  await shot('07-fragment');

  // 剝三瓣
  await dismissKeyboard();
  await tapL('剝今天', { type: 'button', minY: 150, wait: 900 });
  await shot('08-peel1');
  await dumpNodes('peel1', 30);
  await tapL('上午：順');
  await tapL('下午：普通');
  await shot('09-peel3');
  await tapL('晚上：卡', { wait: 1500 });
  await shot('10-done');
  await sleep(2500);
  await shot('11-pile');
  await dumpNodes('done', 30);

  // 籃子頁 + 週對帳
  await goPage('籃子');
  await shot('12-basket');
  await tapL('做這週的對帳', { contains: true, wait: 1000, attempts: 8 });
  await shot('13-review-mem');
  await dumpNodes('review-mem', 20);
  if (await tapField(0)) { await type('OK week, Wednesday was rough'); await logField(); }
  await shot('14-review-mem-filled');
  await tapL('打開這週的紀錄', { wait: 800 });
  await shot('15-review-rec');
  await tapL('下一步', { wait: 700 });
  await shot('16-review-gap');
  await tapL('看不出差別');
  await tapL('下一步', { wait: 700 });
  await shot('17-review-act');
  if (await tapField(0)) await type('Tuesday afternoon');
  if (await tapField(1)) await type('Open the project file for 15 min');
  await shot('18-review-act-filled');
  await tapL('完成對帳', { wait: 1000 });
  await shot('19-review-done');
  await tapL('好', { wait: 900 });
  await shot('20-basket-after-review');

  // 關掉重開：資料有沒有留著
  try { await c.terminateApp(BUNDLE); log('terminated'); } catch (e) { log('terminate failed', e?.message); }
  await sleep(800);
  await simctl(['launch', 'booted', BUNDLE]);
  await sleep(3000);
  await shot('21-relaunch');
  log('page after relaunch:', PAGES[await currentPage()] ?? 'unknown');
  await goPage('剝今天');
  await shot('22-relaunch-main');

  // 設定：清掉、載示範
  await goPage('設定');
  await shot('23-settings');
  await tapL('清除全部資料', { attempts: 10, wait: 700 });
  await tapL('再按一次，清除全部', { wait: 1300 });
  await shot('24-after-wipe');
  await tapL('看看一個月後的樣子', { contains: true, attempts: 10, wait: 2200 });
  await shot('25-demo-basket');
  log('page after demo load:', PAGES[await currentPage()] ?? 'unknown');
  await goPage('剝今天');
  await sleep(1500);
  await shot('26-demo-main');
  await goPage('籃子');
  await tapL('做這週的對帳', { contains: true, wait: 1000, attempts: 8 });
  if (await tapField(0)) await type('demo');
  await tapL('打開這週的紀錄', { wait: 800 });
  await tapL('下一步', { wait: 700 });
  await tapL('看不出差別');
  await tapL('下一步', { wait: 900 });
  await shot('27-demo-ai-step');
  if (await has('請 AI 讀這四週')) {
    await tapL('請 AI 讀這四週', { wait: 1800 });
    await shot('28-ai-nokey');
  }
  await closeSheet();

  // 深色模式
  await simctl(['ui', 'booted', 'appearance', 'dark']);
  await sleep(1200);
  await goPage('剝今天');
  await shot('29-dark-main');
  await goPage('籃子');
  await shot('30-dark-basket');
  await goPage('設定');
  await shot('31-dark-settings');

  log('DONE');
} catch (e) {
  log('ERROR', e?.message ?? String(e));
  if (e?.status) log('http', e.status, JSON.stringify(e.error ?? e.body ?? '').slice(0, 400));
  process.exitCode = 1;
} finally {
  if (c) { try { c.disconnect(); } catch {} }
  if (inst?.metadata?.id) {
    try { await lim.iosInstances.delete(inst.metadata.id); log('instance deleted', inst.metadata.id); }
    catch (e) { log('DELETE FAILED (clean up manually!)', inst.metadata.id, e?.message); }
  }
  log('total', ((Date.now() - t0) / 1000).toFixed(0) + 's');
}
