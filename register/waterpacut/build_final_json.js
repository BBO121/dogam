const XLSX = require('xlsx');
const fs = require('fs');

const SITE_USER_ID = '7b3deebd-0c37-4c13-963a-7b27108502c4';
const SITE_NICK = '언쿠';

const wb = XLSX.readFile('waterpacut_review_sheet_final.xlsx');
const ws = wb.Sheets[wb.SheetNames[0]];
const rows = XLSX.utils.sheet_to_json(ws, { header: 1, defval: '' });
const data = rows.slice(1).filter(r => String(r[0]).trim() !== ''); // 꼬리에 붙은 빈 행 제외

function parsePerson(raw) {
  raw = String(raw).trim();
  const contactMatch = raw.match(/@\S+/);
  const contact = contactMatch ? contactMatch[0] : null;
  const nickname = raw.replace(/@\S+/, '').replace(/님\s*$/, '').trim();
  return { nickname, contact };
}

function normClass(raw) {
  const v = String(raw).trim().toLowerCase();
  if (v === 'hot') return 'Hot';
  if (v === 'cold') return 'Cold';
  if (v === 'hot & cold' || v === 'hot&cold') return 'Hot & Cold';
  return null;
}

const items = [];
const issues = [];

for (const r of data) {
  const [num, name, ownerRaw, designerRaw, classRaw, indivClass, desc] = r;
  const numInt = parseInt(num, 10);
  const charNumber = String(numInt).padStart(3, '0'); // 워터파컷은 3자리 형식(001~) 사용

  let ownerNick, ownerContact, ownerIsOffsite, ownerUserId;
  const op = parsePerson(ownerRaw);
  if (op.nickname === SITE_NICK || !op.nickname) {
    ownerNick = SITE_NICK; ownerContact = null; ownerIsOffsite = false; ownerUserId = SITE_USER_ID;
    if (!op.nickname) issues.push({ num: numInt, field: 'owner', note: '소유주 빈칸 -> 언쿠로 대체', raw: ownerRaw });
  } else {
    ownerNick = op.nickname; ownerContact = op.contact; ownerIsOffsite = true; ownerUserId = null;
  }

  let designerNick, designerContact, designerUserIds;
  const dp = parsePerson(designerRaw);
  if (dp.nickname === SITE_NICK) {
    designerNick = SITE_NICK; designerContact = null; designerUserIds = [SITE_USER_ID];
  } else {
    designerNick = dp.nickname; designerContact = dp.contact; designerUserIds = [];
    if (!designerNick) issues.push({ num: numInt, field: 'designer', raw: designerRaw });
  }

  const clsNorm = normClass(classRaw);
  if (!clsNorm) issues.push({ num: numInt, field: 'classification', raw: classRaw });

  items.push({
    name: String(name).trim().normalize('NFC'),
    species_name: '워터파컷',
    char_number: charNumber,
    owner_nickname: ownerNick,
    owner_user_id: ownerUserId,
    owner_is_offsite: ownerIsOffsite,
    owner_contact: ownerContact,
    designer_nickname: designerNick,
    designer_user_ids: designerUserIds,
    designer_contact: designerContact,
    description: String(desc).trim(),
    custom_field_values: { 'Hot / Cold': clsNorm },
  });
}

fs.writeFileSync('waterpacut_final.json', JSON.stringify(items, null, 2), 'utf8');
console.log('written:', items.length, 'items');
console.log('issues:', issues.length);
if (issues.length) console.log(JSON.stringify(issues, null, 2));
