const fs = require('fs');
const path = require('path');
const { parseListPageWithPairing } = require('./parse_list_page.js');

const BASE = 'https://sq1222.wixsite.com/tails';
const LIST_PATH = encodeURIComponent('개체-리스트');
const TOTAL_PAGES = 47;
const OUT_DIR = path.join(__dirname, 'crawl_pages');
const MANIFEST_PATH = path.join(__dirname, 'tails_full_manifest.json');

const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36';

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

async function fetchPage(n) {
  const url = n === 1
    ? `${BASE}/${LIST_PATH}`
    : `${BASE}/${LIST_PATH}/page/${n}`;
  const res = await fetch(url, { headers: { 'User-Agent': UA } });
  if (!res.ok) throw new Error(`page ${n}: HTTP ${res.status}`);
  return res.text();
}

async function main() {
  if (!fs.existsSync(OUT_DIR)) fs.mkdirSync(OUT_DIR, { recursive: true });

  const all = [];
  const errors = [];

  for (let n = 1; n <= TOTAL_PAGES; n++) {
    let html;
    let attempt = 0;
    while (true) {
      attempt++;
      try {
        html = await fetchPage(n);
        break;
      } catch (e) {
        if (attempt >= 3) {
          errors.push(`page ${n}: ${e.message}`);
          html = null;
          break;
        }
        await sleep(1000 * attempt);
      }
    }
    if (html) {
      fs.writeFileSync(path.join(OUT_DIR, `p${n}.html`), html, 'utf8');
      const items = parseListPageWithPairing(html);
      items.forEach((it) => all.push({ ...it, page: n }));
      console.log(`page ${n}: ${items.length} items`);
    } else {
      console.log(`page ${n}: FAILED`);
    }
    await sleep(300);
  }

  // dedupe by num (keep first occurrence)
  const seen = new Map();
  const dupes = [];
  for (const it of all) {
    if (seen.has(it.num)) {
      dupes.push(it.num);
    } else {
      seen.set(it.num, it);
    }
  }

  const manifest = Array.from(seen.values()).sort((a, b) => Number(a.num) - Number(b.num));

  fs.writeFileSync(MANIFEST_PATH, JSON.stringify(manifest, null, 2), 'utf8');

  console.log('\n총 파싱된 항목(중복 포함):', all.length);
  console.log('고유 char_number 수:', manifest.length);
  console.log('중복 발견:', dupes.length, dupes.slice(0, 20));
  console.log('페이지 오류:', errors.length, errors);
  console.log('최소 번호:', manifest[0]?.num, '최대 번호:', manifest[manifest.length - 1]?.num);

  const nums = new Set(manifest.map((m) => m.num));
  const maxNum = Number(manifest[manifest.length - 1]?.num || 0);
  const missing = [];
  for (let i = 0; i <= maxNum; i++) {
    const s = String(i).padStart(4, '0');
    if (!nums.has(s)) missing.push(s);
  }
  console.log('0~최대 사이 결번(삭제된 개체로 추정) 개수:', missing.length);
  fs.writeFileSync(path.join(__dirname, 'tails_missing_numbers.json'), JSON.stringify(missing, null, 2), 'utf8');
}

main().catch((e) => {
  console.error('FATAL', e);
  process.exit(1);
});
