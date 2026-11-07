// 蒜數 iOS 版：在 Limrun 雲端 iPhone 模擬器走一遍主流程，截圖存到 shots/。
// 準備：npm install（這個資料夾）；~/.lim/config.yaml 要有 api-key；Limrun 帳號要有點數或訂閱。
// 用法：node test.mjs <Suanshu-simulator.app.zip>
//   zip 從 GitHub Actions 的 artifact「suanshu-build」下載（gh run download <run id> -n suanshu-build）。
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import Limrun, { Ios } from '@limrun/api';

const HERE = dirname(fileURLToPath(import.meta.url));
const OUT = join(HERE, 'shots');
mkdirSync(OUT, { recursive: true });

const home = process.env.USERPROFILE ?? process.env.HOME;
const cfg = readFileSync(join(home, '.lim', 'config.yaml'), 'utf8');
const apiKey = process.env.LIM_API_KEY ?? (cfg.match(/api-key:\s*(\S+)/) ?? [])[1];
if (!apiKey) { console.error('no api key in ~/.lim/config.yaml'); process.exit(2); }

const ZIP = process.argv[2];
if (!ZIP) { console.error('usage: node test.mjs <app.zip>'); process.exit(2); }
const BUNDLE = 'org.domyweb.suanshu';
const lim = new Limrun({ apiKey });
const t0 = Date.now();
const log = (...a) => console.log(((Date.now() - t0) / 1000).toFixed(1).padStart(6) + 's', ...a);
const sleep = ms => new Promise(r => setTimeout(r, ms));

let inst = null;
let c = null;

function flat(n, out = []) {
  if (Array.isArray(n)) { for (const x of n) flat(x, out); return out; }
  if (!n || typeof n !== 'object') return out;
  out.push(n);
  for (const ch of n.children ?? []) flat(ch, out);
  return out;
}
async function labels() {
  const t = await c.elementTree();
  return flat(t).filter(n => n.AXLabel).map(n => n.AXLabel);
}
async function dump(name) {
  try {
    const ls = await labels();
    log('labels@' + name + ' (' + ls.length + '):', JSON.stringify(ls.slice(0, 80)));
  } catch (e) { log('dump failed', e?.message); }
}
async function shot(name) {
  try {
    const s = await c.screenshot({ format: 'jpeg', size: 'scaled' });
    writeFileSync(join(OUT, name + '.jpg'), Buffer.from(s.base64, 'base64'));
    log('shot', name, s.width + 'x' + s.height);
  } catch (e) { log('shot failed', name, e?.message); }
}
async function tapLabel(l, { contains = false, wait = 500 } = {}) {
  try {
    const r = await c.tapElement(contains ? { AXLabelContains: l } : { AXLabel: l });
    log('tap', JSON.stringify(l), r && typeof r === 'object' ? JSON.stringify(r).slice(0, 120) : '');
    await sleep(wait);
    return true;
  } catch (e) {
    log('tap FAILED', JSON.stringify(l), (e?.message ?? String(e)).slice(0, 200));
    return false;
  }
}
async function type(text) {
  try { await c.typeText(text); log('typed', JSON.stringify(text)); await sleep(300); }
  catch (e) { log('type FAILED', e?.message); }
}
async function has(l) { try { return (await labels()).some(x => x === l || x.includes(l)); } catch { return false; } }

try {
  log('uploading', ZIP);
  const asset = await lim.assets.getOrUpload({ path: ZIP, name: 'suanshu-sim-' + Date.now() + '.zip', platform: 'ios', kind: 'App', ttl: '2h' });
  log('asset', asset.name, asset.id, 'md5', asset.md5);

  log('creating instance');
  inst = await lim.iosInstances.create({
    wait: true,
    spec: {
      model: 'iphone',
      inactivityTimeout: '5m',
      hardTimeout: '25m',
      initialAssets: [{ kind: 'App', source: 'AssetName', assetName: asset.name, launchMode: 'RelaunchIfRunning' }],
    },
  });
  log('instance', inst.metadata?.id, inst.status?.state, JSON.stringify({ spec: inst.spec, status: { ...inst.status, token: inst.status?.token ? '<redacted>' : undefined } }).slice(0, 600));

  c = await Ios.createInstanceClient({ apiUrl: inst.status.apiUrl, token: inst.status.token, logLevel: 'none' });
  log('connected');
  await sleep(4000);
  await shot('01-launch');
  await dump('launch');
  if (!(await has('好')) && !(await has('剝今天'))) {
    log('app not in front, launching via simctl');
    try { const r = await c.simctl(['launch', 'booted', BUNDLE]); log('simctl launch', JSON.stringify(r).slice(0, 200)); } catch (e) { log('simctl launch failed', e?.message); }
    await sleep(3000);
    await shot('01b-launch');
    await dump('launch2');
  }

  // 首次打開三步
  if (await has('好')) {
    await tapLabel('好');
    await shot('02-ob2');
    await tapLabel('關燈前');
    await tapLabel('下一步');
    await shot('03-ob3');
    await tapLabel('記住了，開始', { wait: 1200 });
  }
  await shot('04-main-empty');
  await dump('main');

  // 記一句
  await tapLabel('現在在做什麼？說一句就好');
  await type('下午跟合作方開會');
  await shot('05-typed');
  await tapLabel('記下', { wait: 900 });
  await shot('06-fragment-saved');

  // 剝三瓣
  await tapLabel('剝今天', { wait: 800 });
  await shot('07-peel1');
  await dump('peel1');
  await tapLabel('上午：順');
  await tapLabel('下午：普通');
  await shot('08-peel3');
  await tapLabel('晚上：卡', { wait: 1500 });
  await shot('09-done');
  await sleep(2500);
  await shot('10-pile-settled');
  await dump('done');

  // 籃子頁
  await tapLabel('籃子', { wait: 900 });
  await shot('11-basket');
  try { await c.scroll('down', 700); } catch (e) { log('scroll failed', e?.message); }
  await sleep(600);
  await shot('12-basket-bottom');
  await dump('basket');

  // 週對帳
  if (await tapLabel('做這週的對帳', { contains: true, wait: 900 })) {
    await shot('13-review-mem');
    await tapLabel('例如：這週還行，週三很爛。');
    await type('這週還行，週三很爛');
    await tapLabel('打開這週的紀錄', { wait: 700 });
    await shot('14-review-rec');
    await tapLabel('下一步', { wait: 600 });
    await shot('15-review-gap');
    await tapLabel('看不出差別');
    await tapLabel('下一步', { wait: 600 });
    await shot('16-review-act');
    await dump('act');
    await tapLabel('什麼時候？例如：週二、週四下午會議後');
    await type('週二下午');
    await tapLabel('做什麼？例如：先只打開專案檔十五分鐘');
    await type('先開專案檔十五分鐘');
    await shot('17-review-act-filled');
    await tapLabel('完成對帳', { wait: 900 });
    await shot('18-review-done');
    await tapLabel('好', { wait: 800 });
    await shot('19-basket-after-review');
  }

  // 關掉重開：資料有沒有留著
  try { await c.terminateApp(BUNDLE); log('terminated'); } catch (e) { log('terminate failed', e?.message); }
  await sleep(800);
  try { await c.simctl(['launch', 'booted', BUNDLE]); log('relaunched'); } catch (e) { log('relaunch failed', e?.message); }
  await sleep(3000);
  await shot('20-relaunch');
  await dump('relaunch');

  // 設定頁：清掉、載示範
  await tapLabel('設定', { wait: 900 });
  await shot('21-settings');
  try { await c.scroll('down', 1200); } catch {}
  await sleep(600);
  await shot('22-settings-bottom');
  await dump('settings');
  await tapLabel('清除全部資料', { wait: 600 });
  await tapLabel('再按一次，清除全部', { wait: 1200 });
  await shot('23-after-wipe');
  await tapLabel('看看一個月後的樣子', { contains: true, wait: 2000 });
  await shot('24-demo-basket');
  await tapLabel('剝今天', { wait: 2500 });
  await shot('25-demo-main');
  await tapLabel('籃子', { wait: 900 });
  await tapLabel('做這週的對帳', { contains: true, wait: 900 });
  await shot('26-demo-review-mem');
  await tapLabel('例如：這週還行，週三很爛。');
  await type('demo');
  await tapLabel('打開這週的紀錄', { wait: 700 });
  await shot('27-demo-review-rec');
  await tapLabel('下一步', { wait: 600 });
  await tapLabel('看不出差別');
  await tapLabel('下一步', { wait: 800 });
  await shot('28-demo-review-ai-step');
  await dump('ai-step');
  if (await has('請 AI 讀這四週')) {
    await tapLabel('請 AI 讀這四週', { wait: 1500 });
    await shot('29-ai-nokey');
  }
  await tapLabel('關閉', { wait: 800 });

  // 深色模式
  try {
    const r = await c.simctl(['ui', 'booted', 'appearance', 'dark']);
    log('appearance dark', JSON.stringify(r).slice(0, 160));
    await sleep(1200);
    await tapLabel('剝今天', { wait: 1500 });
    await shot('30-dark-main');
    await tapLabel('籃子', { wait: 900 });
    await shot('31-dark-basket');
  } catch (e) { log('appearance failed', e?.message); }

  log('DONE');
} catch (e) {
  log('ERROR', e?.message ?? String(e));
  if (e?.status) log('http', e.status, JSON.stringify(e.error ?? e.body ?? e.cause ?? '').slice(0, 500));
  process.exitCode = 1;
} finally {
  if (c) { try { c.disconnect(); } catch {} }
  if (inst?.metadata?.id) {
    try { await lim.iosInstances.delete(inst.metadata.id); log('instance deleted', inst.metadata.id); }
    catch (e) { log('DELETE FAILED (clean up manually!)', inst.metadata.id, e?.message); }
  }
  log('total', ((Date.now() - t0) / 1000).toFixed(0) + 's');
}
