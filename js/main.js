/* ── 서버 시간 유틸 ────────────────────────── */
let _serverTimerInterval = null;
let _serverResyncInterval = null;

async function initServerClock() {
  if (typeof sb === 'undefined') return;

  async function fetchAndTick() {
    const { data, error } = await sb.rpc('get_server_time');
    if (error || !data) return;

    // UTC → KST (+9)
    let serverMs = new Date(data).getTime() + 9 * 60 * 60 * 1000;

    clearInterval(_serverTimerInterval);
    _serverTimerInterval = setInterval(() => {
      serverMs += 1000;
      const d   = new Date(serverMs);
      const hh  = String(d.getUTCHours()).padStart(2, '0');
      const mm  = String(d.getUTCMinutes()).padStart(2, '0');
      const ss  = String(d.getUTCSeconds()).padStart(2, '0');
      const txt = `KST ${hh}:${mm}:${ss}`;
      document.querySelectorAll('.server-clock').forEach(el => el.textContent = txt);
    }, 1000);
  }

  await fetchAndTick();
  clearInterval(_serverResyncInterval);
  _serverResyncInterval = setInterval(fetchAndTick, 5 * 60 * 1000); // 5분마다 재동기화
}

/* ── 페이지네이션 유틸 ─────────────────────── */
const PER_PAGE = 30;

function createPager(renderFn, wrapId = 'paginationWrap', pageParam = 'page') {
  let page = 1;
  let data = [];

  const pager = {
    load(arr) {
      data = arr; page = 1;
      const url = new URL(location.href);
      url.searchParams.delete(pageParam);
      history.replaceState(null, '', url);
      pager._draw();
    },
    // 초기 로드 시 URL의 ?page= 값으로 복원
    init(arr) {
      data = arr;
      const p     = parseInt(new URLSearchParams(location.search).get(pageParam));
      const total = Math.ceil(arr.length / PER_PAGE);
      page = (p >= 1 && p <= (total || 1)) ? p : 1;
      pager._draw();
    },
    go(p) {
      const total = Math.ceil(data.length / PER_PAGE);
      page = Math.max(1, Math.min(p, total || 1));
      const url = new URL(location.href);
      if (page === 1) url.searchParams.delete(pageParam);
      else            url.searchParams.set(pageParam, page);
      history.replaceState(null, '', url);
      pager._draw();
      window.scrollTo({ top: 0, behavior: 'smooth' });
    },
    _draw() {
      const slice = data.slice((page - 1) * PER_PAGE, page * PER_PAGE);
      renderFn(slice);

      const wrap = document.getElementById(wrapId);
      if (!wrap) return;

      const total = Math.ceil(data.length / PER_PAGE);
      if (total <= 1) { wrap.innerHTML = ''; return; }

      // 표시할 페이지 번호 목록 (현재 ±2, 항상 1·끝 포함)
      const set = new Set([1, total]);
      for (let i = Math.max(1, page - 2); i <= Math.min(total, page + 2); i++) set.add(i);
      const nums = [...set].sort((a, b) => a - b);

      let html = '<nav class="pagination">';
      html += `<button class="pg-btn" data-p="${page - 1}" ${page === 1 ? 'disabled' : ''}>‹</button>`;
      let prev = 0;
      for (const n of nums) {
        if (n - prev > 1) html += '<span class="pg-gap">…</span>';
        html += `<button class="pg-btn${n === page ? ' active' : ''}" data-p="${n}">${n}</button>`;
        prev = n;
      }
      html += `<button class="pg-btn" data-p="${page + 1}" ${page === total ? 'disabled' : ''}>›</button>`;
      html += '</nav>';

      wrap.innerHTML = html;
      wrap.querySelectorAll('.pg-btn:not([disabled])').forEach(btn =>
        btn.addEventListener('click', () => pager.go(+btn.dataset.p))
      );
    }
  };
  return pager;
}
/* ─────────────────────────────────────────── */

// 개체 목록 페이지: URL 쿼리로 필터링
const grid = document.getElementById('characterGrid');
const noResult = document.getElementById('noResult');

if (grid) {
  const q = new URLSearchParams(window.location.search).get('q');
  if (q) {
    const cards = grid.querySelectorAll('.character-card');
    let visible = 0;
    cards.forEach(card => {
      if (card.dataset.name.toLowerCase().includes(q.toLowerCase())) {
        card.style.display = 'block';
        visible++;
      } else {
        card.style.display = 'none';
      }
    });
    if (noResult) noResult.style.display = visible === 0 ? 'block' : 'none';

    const titleEl = document.querySelector('.list-page-title');
    const countEl = document.querySelector('.list-page-count');
    if (titleEl) titleEl.textContent = `"${q}" 검색 결과`;
    if (countEl) countEl.textContent = `${visible}개의 개체`;
  }
}

let characters = [];
let speciesList = [];
let siteUsers   = [];
let userIdMap   = {};
let speciesOwnerNicksSet = new Set();

async function loadSearchData() {
  const [
    { data: chars,   error: charErr },
    { data: userList },
    { data: spList },
  ] = await Promise.all([
    sb.from('characters').select('id, name, species_name'),
    sb.rpc('get_all_users'),
    sb.from('species').select('id, name, owner_nickname'),
  ]);
  if (charErr) { console.error('[검색] 데이터 로드 실패:', charErr); return; }

  if (spList) {
    spList.forEach(s => { if (s.owner_nickname) speciesOwnerNicksSet.add(s.owner_nickname); });
    speciesList = spList.map(s => ({
      name: s.name,
      url:  `species.html?id=${s.id}`,
    }));
  }

  if (userList) {
    siteUsers = userList
      .filter(u => u.login_id !== 'admin')
      .map(u => ({
        name:           u.nickname  || '',
        id:             u.id        || '',
        loginId:        u.login_id || u.nickname || '',
        role:           u.role     || '',
        isSpeciesOwner: u.role === 'species_owner' || speciesOwnerNicksSet.has(u.nickname || ''),
      }));
    userList.forEach(u => {
      const loginId     = (u.login_id  || u.nickname || '').toLowerCase();
      const displayName = (u.nickname  || '').toLowerCase();
      if (loginId) userIdMap[loginId] = displayName;
    });
  }

  if (chars) {
    characters = chars.map(c => ({
      name:    c.name,
      species: c.species_name || '',
      url:     `character.html?id=${c.id}`,
    }));
  }
}

const searchInput    = document.getElementById('searchInput');
const searchDropdown = document.getElementById('searchDropdown');

if (searchInput && searchDropdown) {
  loadSearchData();

  searchInput.addEventListener('input', () => {
    const q = searchInput.value.trim();
    if (!q) { closeDropdown(); return; }

    const qLow = q.toLowerCase();

    const matchedUsers = siteUsers.filter(u =>
      u.name.toLowerCase().includes(qLow) ||
      u.loginId.toLowerCase().includes(qLow)
    );
    const matchedSpecies = speciesList.filter(s =>
      s.name.toLowerCase().includes(qLow)
    );
    const matchedChars = characters.filter(c =>
      c.name.toLowerCase().includes(qLow)
    );

    renderDropdown(q, matchedUsers, matchedSpecies, matchedChars);
  });

  searchInput.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') {
      const q = searchInput.value.trim();
      if (q) goToSearch(q);
    }
    if (e.key === 'Escape') closeDropdown();
  });

  document.addEventListener('click', (e) => {
    if (!e.target.closest('.search-box')) closeDropdown();
  });
}

function userPriority(u) {
  if (u.role === 'admin') return 1;
  if (u.role === 'staff') return 2;
  if (u.isSpeciesOwner)   return 3;
  return 4;
}

function getUserBadgesHtml(u) {
  const badges = [];
  if (u.role === 'admin') badges.push('<span class="dd-badge dd-badge--admin">관리자</span>');
  if (u.role === 'staff') badges.push('<span class="dd-badge dd-badge--staff">스태프</span>');
  if (u.isSpeciesOwner)   badges.push('<span class="dd-badge dd-badge--species-owner">종족주</span>');
  if (!badges.length)     badges.push('<span class="dd-badge dd-badge--user">일반유저</span>');
  return badges.join('');
}

function renderDropdown(q, matchedUsers, matchedSpecies, matchedChars) {
  const total = matchedUsers.length + matchedSpecies.length + matchedChars.length;
  if (!total) { closeDropdown(); return; }

  const sortedUsers = [...matchedUsers].sort((a, b) => userPriority(a) - userPriority(b));

  const p = {
    users:   sortedUsers.slice(0, 4),
    species: matchedSpecies.slice(0, 2),
    chars:   matchedChars.slice(0, 3),
  };

  const userHtml = p.users.map(u => `
    <li>
      <a href="profile.html?user=${u.id || encodeURIComponent(u.name)}">
        ${getUserBadgesHtml(u)}
        <span class="dd-label">${highlight(u.name, q)}</span>
      </a>
    </li>
  `).join('');

  const speciesHtml = p.species.map(s => `
    <li>
      <a href="${s.url}">
        <span class="dd-badge dd-badge--species">종족</span>
        <span class="dd-label">${highlight(s.name, q)}</span>
      </a>
    </li>
  `).join('');

  const charHtml = p.chars.map(c => `
    <li>
      <a href="${c.url}">
        <span class="dd-badge dd-badge--char">캐릭터</span>
        <span class="dd-label">${c.species ? `${escapeHtml(c.species)}: ` : ''}${highlight(c.name, q)}</span>
      </a>
    </li>
  `).join('');

  searchDropdown.innerHTML = userHtml + speciesHtml + charHtml;

  const shown = p.users.length + p.species.length + p.chars.length;
  if (total > shown) {
    const li = document.createElement('li');
    li.className = 'dd-enter';
    li.textContent = `'${q}' 검색 결과 ${total}개 전체 보기 →`;
    li.addEventListener('click', () => goToSearch(q));
    searchDropdown.appendChild(li);
  }

  searchDropdown.classList.add('active');
}

function escapeHtml(str) {
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function highlight(name, q) {
  const safeName = escapeHtml(name);
  const escaped  = q.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  return safeName.replace(
    new RegExp(`(${escaped})`, 'gi'),
    '<mark style="background:var(--sky-light);color:var(--sky-deep);border-radius:2px;">$1</mark>'
  );
}

function closeDropdown() {
  searchDropdown.classList.remove('active');
  searchDropdown.innerHTML = '';
}

function goToSearch(q) {
  window.location.href = `character-list.html?q=${encodeURIComponent(q)}`;
}
