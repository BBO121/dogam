const fs = require('fs');

function parseListPage(html) {
  const ariaRe = /aria-label="(\d+)\.((?:(?!").)*)"/g;
  const items = [];
  let m;
  while ((m = ariaRe.exec(html))) {
    items.push({ num: m[1], name: m[2], pos: m.index });
  }

  const mediaRe = /f0522b_([0-9a-fA-F]{20,40})~mv2\.(png|jpg|jpeg|gif)/g;
  const mediaHits = [];
  while ((m = mediaRe.exec(html))) {
    mediaHits.push({ hash: m[1], ext: m[2], pos: m.index });
  }

  // dedupe consecutive same-hash hits, keep first pos of each run
  const mediaDeduped = [];
  for (const hit of mediaHits) {
    const last = mediaDeduped[mediaDeduped.length - 1];
    if (!last || last.hash !== hit.hash) mediaDeduped.push(hit);
  }

  return { items, mediaDeduped };
}

function parseListPageWithPairing(html) {
  const ariaRe = /aria-label="(\d+)\.((?:(?!").)*)"/g;
  const items = [];
  let m;
  while ((m = ariaRe.exec(html))) {
    items.push({ num: m[1], name: m[2], pos: m.index });
  }

  const mediaRe = /f0522b_([0-9a-fA-F]{20,40})~mv2\.(png|jpg|jpeg|gif)/g;
  const mediaHits = [];
  while ((m = mediaRe.exec(html))) {
    mediaHits.push({ hash: m[1], ext: m[2], pos: m.index });
  }

  const paired = items.map((it) => {
    const hit = mediaHits.find((h) => h.pos > it.pos);
    return { ...it, hash: hit ? hit.hash : null, ext: hit ? hit.ext : null };
  });
  return paired;
}

if (require.main === module) {
  const file = process.argv[2];
  const html = fs.readFileSync(file, 'utf8');
  const paired = parseListPageWithPairing(html);
  paired.forEach((p) => console.log(p.num, '|', p.name, '|', p.hash, p.ext));
}

module.exports = { parseListPageWithPairing };
