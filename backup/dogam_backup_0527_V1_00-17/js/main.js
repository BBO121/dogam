// 개체 목록 페이지: URL 쿼리로 필터링
const grid = document.getElementById('characterGrid');
const noResult = document.getElementById('noResult');

if (grid) {
  const q = new URLSearchParams(window.location.search).get('q');
  if (q) {
    const cards = grid.querySelectorAll('.character-card');
    let visible = 0;
    cards.forEach(card => {
      if (card.dataset.name.includes(q)) {
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

async function loadSearchData() {
  const [
    { data: chars,   error: charErr },
    { data: userList },
    { data: spList },
  ] = await Promise.all([
    sb.from('characters').select('id, name, species_name'),
    sb.rpc('get_all_users'),
    sb.from('species').select('id, name'),
  ]);
  if (charErr) { console.error('[검색] 데이터 로드 실패:', charErr); return; }

  if (userList) {
    siteUsers = userList
      .filter(u => u.role !== 'admin')
      .map(u => ({
        name:    u.nickname  || '',
        loginId: u.login_id || u.nickname || '',
        role:    u.role     || '',
      }));
    userList.forEach(u => {
      const loginId     = (u.login_id  || u.nickname || '').toLowerCase();
      const displayName = (u.nickname  || '').toLowerCase();
      if (loginId) userIdMap[loginId] = displayName;
    });
  }

  if (spList) {
    speciesList = spList.map(s => ({
      name: s.name,
      url:  `species.html?id=${s.id}`,
    }));
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

    const matchedSpeciesOwners = siteUsers.filter(u =>
      u.role === 'species_owner' && (
        u.name.toLowerCase().includes(qLow) ||
        u.loginId.toLowerCase().includes(qLow)
      )
    );
    const matchedUsers = siteUsers.filter(u =>
      u.role !== 'species_owner' && (
        u.name.toLowerCase().includes(qLow) ||
        u.loginId.toLowerCase().includes(qLow)
      )
    );
    const matchedSpecies = speciesList.filter(s =>
      s.name.toLowerCase().includes(qLow)
    );
    const matchedChars = characters.filter(c =>
      c.name.toLowerCase().includes(qLow)
    );

    renderDropdown(q, matchedSpeciesOwners, matchedUsers, matchedSpecies, matchedChars);
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

function renderDropdown(q, matchedSpeciesOwners, matchedUsers, matchedSpecies, matchedChars) {
  const total = matchedSpeciesOwners.length + matchedUsers.length + matchedSpecies.length + matchedChars.length;
  if (!total) { closeDropdown(); return; }

  const p = {
    speciesOwners: matchedSpeciesOwners.slice(0, 2),
    users:         matchedUsers.slice(0, 2),
    species:       matchedSpecies.slice(0, 2),
    chars:         matchedChars.slice(0, 3),
  };

  const ownerHtml = p.speciesOwners.map(u => `
    <li>
      <a href="character-list.html?owner=${encodeURIComponent(u.name)}">
        <span class="dd-badge dd-badge--species-owner">종족주</span>
        <span class="dd-label">${highlight(u.name, q)}</span>
      </a>
    </li>
  `).join('');

  const userHtml = p.users.map(u => `
    <li>
      <a href="character-list.html?owner=${encodeURIComponent(u.name)}">
        <span class="dd-badge dd-badge--user">일반유저</span>
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
        <span class="dd-label">${c.species ? `${c.species}: ` : ''}${highlight(c.name, q)}</span>
      </a>
    </li>
  `).join('');

  searchDropdown.innerHTML = ownerHtml + userHtml + speciesHtml + charHtml;

  const shown = p.speciesOwners.length + p.users.length + p.species.length + p.chars.length;
  if (total > shown) {
    searchDropdown.innerHTML += `
      <li class="dd-enter" onclick="goToSearch('${q}')">
        '${q}' 검색 결과 ${total}개 전체 보기 →
      </li>
    `;
  }

  searchDropdown.classList.add('active');
}

function highlight(name, q) {
  const escaped = q.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  return name.replace(
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
