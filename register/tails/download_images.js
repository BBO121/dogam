const fs = require('fs');
const path = require('path');

const SITEMAP_URL = 'https://sq1222.wixsite.com/tails/blog-posts-sitemap.xml';
const OUT_DIR = path.join(__dirname, '..', '..', 'images', 'register', 'tails');
const LOG_PATH = path.join(__dirname, 'download_log.jsonl');
const SUMMARY_PATH = path.join(__dirname, 'download_summary.json');

const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36';

const START_NUM = 101;
const END_NUM = 1108;
const DELAY_MS = 350;

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

function log(obj) {
  fs.appendFileSync(LOG_PATH, JSON.stringify(obj) + '\n', 'utf8');
}

async function fetchText(url, attempts = 5) {
  let lastErr;
  for (let i = 0; i < attempts; i++) {
    try {
      const res = await fetch(url, { headers: { 'User-Agent': UA } });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      return await res.text();
    } catch (e) {
      lastErr = e;
      await sleep(e.message === 'HTTP 429' ? 5000 * (i + 1) : 800 * (i + 1));
    }
  }
  throw lastErr;
}

async function fetchBuffer(url, attempts = 5) {
  let lastErr;
  for (let i = 0; i < attempts; i++) {
    try {
      const res = await fetch(url, { headers: { 'User-Agent': UA } });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const ab = await res.arrayBuffer();
      return Buffer.from(ab);
    } catch (e) {
      lastErr = e;
      await sleep(e.message === 'HTTP 429' ? 5000 * (i + 1) : 800 * (i + 1));
    }
  }
  throw lastErr;
}

async function main() {
  if (!fs.existsSync(OUT_DIR)) fs.mkdirSync(OUT_DIR, { recursive: true });

  console.log('사이트맵 가져오는 중...');
  const sitemapXml = await fetchText(SITEMAP_URL);
  const locRe = /<loc>(https:\/\/sq1222\.wixsite\.com\/tails\/post\/(\d+)-[^<]*)<\/loc>/g;
  const posts = new Map(); // num(as int) -> url
  let m;
  while ((m = locRe.exec(sitemapXml))) {
    const num = parseInt(m[2], 10);
    posts.set(num, m[1]);
  }
  console.log('사이트맵 총 게시물 수:', posts.size);

  const targets = [];
  for (let n = START_NUM; n <= END_NUM; n++) {
    if (posts.has(n)) targets.push({ num: n, url: posts.get(n) });
  }
  console.log(`다운로드 대상: ${targets.length}개 (범위 ${START_NUM}~${END_NUM} 중 사이트맵에 존재하는 것)`);

  const missingInSitemap = [];
  for (let n = START_NUM; n <= END_NUM; n++) {
    if (!posts.has(n)) missingInSitemap.push(n);
  }
  if (missingInSitemap.length) {
    console.log('사이트맵에 없는 번호(결번):', missingInSitemap.length, missingInSitemap.slice(0, 30));
  }

  const results = { success: [], failed: [], skippedExisting: [] };

  for (const t of targets) {
    const numStr = String(t.num).padStart(4, '0');
    const existing = fs.readdirSync(OUT_DIR).find((f) => f.startsWith(`tails_${numStr}.`));
    if (existing) {
      results.skippedExisting.push(t.num);
      continue;
    }

    try {
      const html = await fetchText(t.url);
      const ogMatch = html.match(/property="og:image"\s+content="([^"]+)"/);
      if (!ogMatch) throw new Error('og:image 메타 태그를 찾지 못함');
      const ogUrl = ogMatch[1];
      const mediaMatch = ogUrl.match(/\/media\/(f0522b_[0-9a-fA-F]+~mv2\.([a-zA-Z]+))/);
      if (!mediaMatch) throw new Error(`media 경로 파싱 실패: ${ogUrl}`);
      const ext = mediaMatch[2].toLowerCase();
      const originalUrl = `https://static.wixstatic.com/media/${mediaMatch[1]}`;

      await sleep(DELAY_MS);
      const buf = await fetchBuffer(originalUrl);
      if (buf.length < 500) throw new Error(`파일 크기가 너무 작음: ${buf.length} bytes`);

      const outPath = path.join(OUT_DIR, `tails_${numStr}.${ext}`);
      fs.writeFileSync(outPath, buf);

      results.success.push(t.num);
      log({ num: t.num, url: t.url, image: originalUrl, size: buf.length, status: 'ok' });
      console.log(`[OK] ${numStr} (${buf.length} bytes)`);
    } catch (e) {
      results.failed.push({ num: t.num, url: t.url, error: e.message });
      log({ num: t.num, url: t.url, status: 'error', error: e.message });
      console.log(`[FAIL] ${numStr}: ${e.message}`);
    }

    await sleep(DELAY_MS);
  }

  fs.writeFileSync(SUMMARY_PATH, JSON.stringify(results, null, 2), 'utf8');
  console.log('\n=== 완료 ===');
  console.log('성공:', results.success.length);
  console.log('실패:', results.failed.length);
  console.log('이미 존재해서 건너뜀:', results.skippedExisting.length);
  if (results.failed.length) {
    console.log('실패 목록:', results.failed.map((f) => f.num));
  }
}

main().catch((e) => {
  console.error('FATAL', e);
  process.exit(1);
});
