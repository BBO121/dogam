const fs = require('fs');
const path = process.argv[2];
const raw = fs.readFileSync(path, 'utf8');
const lines = raw.split(/\r\n|\r|\n/);

// Find start of entity list: after "-발견된 개체-"
let startIdx = lines.findIndex(l => l.includes('발견된 개체'));
if (startIdx === -1) startIdx = 0;

// Regex for entity header: optional leading spaces, number, '.', space, name
const headerRe = /^\s*(\d+)\.\s*(.*)$/;

// Collect header line indices (only within the entity section, and only lines where name part non-trivial OR could be empty stub)
const headers = [];
for (let i = startIdx; i < lines.length; i++) {
  const m = lines[i].match(headerRe);
  if (m) {
    headers.push({ idx: i, num: m[1], name: m[2].trim() });
  }
}

const entities = [];
for (let h = 0; h < headers.length; h++) {
  const cur = headers[h];
  const next = headers[h + 1];
  const blockStart = cur.idx;
  const blockEnd = next ? next.idx : lines.length;
  const block = lines.slice(blockStart + 1, blockEnd); // lines after header, before next header

  entities.push({
    num: cur.num,
    name: cur.name,
    rawBlock: block,
  });
}

// Now parse each block for owner, tags, classification, description
const results = [];
for (const e of entities) {
  const block = e.rawBlock.map(l => l.trim()).filter((l, idx) => true);
  // Remove trailing/leading fully blank lines but keep structure with index
  let ownerLine = null;
  let classification = null;
  let classIdx = -1;
  let preTags = []; // tags before classification (e.g. <디자인권 사용>)
  let ownerFound = false;
  let notes = [];

  // find owner line (starts with [파트너)
  let i = 0;
  // skip leading blank lines
  while (i < block.length && block[i] === '') i++;

  // scan for owner
  for (let j = i; j < block.length; j++) {
    if (block[j].startsWith('[파트너')) {
      ownerLine = block[j];
      i = j + 1;
      ownerFound = true;
      break;
    }
    if (block[j] !== '') {
      // non-owner, non-blank content before owner found unexpectedly
      break;
    }
  }

  // after owner, collect any bracket tag lines (e.g. <디자인권 사용>) until classification or blank
  const classLineRe = /^(cold|hot)(\s*&\s*(cold|hot))?\s*$/i;
  while (i < block.length) {
    const l = block[i];
    if (l === '') { i++; continue; }
    if (classLineRe.test(l)) {
      classification = l; // preserve raw text/casing
      classIdx = i;
      i++;
      break;
    }
    if (l.startsWith('<')) {
      preTags.push(l);
      i++;
      continue;
    }
    // unexpected content before classification found
    notes.push('UNEXPECTED_BEFORE_CLASS: ' + l);
    i++;
  }

  // remaining lines = description (could include more <tag> lines, blank lines, and stray '  ' separator lines)
  let descLines = [];
  for (; i < block.length; i++) {
    descLines.push(block[i]);
  }
  // trim trailing blank lines
  while (descLines.length && descLines[descLines.length - 1] === '') descLines.pop();
  while (descLines.length && descLines[0] === '') descLines.shift();

  const description = descLines.filter(l => l !== '').join(' ');

  let owner = null;
  if (ownerLine) {
    const om = ownerLine.match(/^\[파트너\s*:\s*(.*)\]\s*$/);
    if (om) owner = om[1].trim();
    else notes.push('OWNER_FORMAT_UNRECOGNIZED: ' + ownerLine);
  } else {
    notes.push('OWNER_MISSING');
  }

  if (!classification) {
    notes.push('CLASSIFICATION_MISSING_OR_UNRECOGNIZED');
  } else if (classification !== 'cold' && classification !== 'hot') {
    notes.push('CLASSIFICATION_INVALID: ' + classification);
  }

  if (!description) {
    notes.push('DESCRIPTION_EMPTY');
  }

  if (!e.name) {
    notes.push('NAME_EMPTY');
  }

  if (preTags.length) {
    notes.push('PRE_TAGS: ' + preTags.join(' | '));
  }

  results.push({
    num: e.num,
    name: e.name,
    owner,
    ownerLineRaw: ownerLine,
    classification,
    description,
    notes,
  });
}

fs.writeFileSync(path + '.parsed.json', JSON.stringify(results, null, 2), 'utf8');
console.log('Total entities parsed:', results.length);
console.log('First:', JSON.stringify(results[0], null, 2));
console.log('Last:', JSON.stringify(results[results.length-1], null, 2));
