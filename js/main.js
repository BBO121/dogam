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

    // 페이지 타이틀 업데이트
    const titleEl = document.querySelector('.list-page-title');
    const countEl = document.querySelector('.list-page-count');
    if (titleEl) titleEl.textContent = `"${q}" 검색 결과`;
    if (countEl) countEl.textContent = `${visible}개의 개체`;
  }
}

// DB에서 불러온 개체 캐시
let characters = [];

async function loadSearchData() {
  const { data } = await sb
    .from('characters')
    .select('id, name, species_name');
  if (data) {
    characters = data.map(c => ({
      name:    c.name,
      species: c.species_name || '',
      url:     `character.html?id=${c.id}`,
    }));
  }
}

// 검색
const searchInput    = document.getElementById('searchInput');
const searchDropdown = document.getElementById('searchDropdown');

if (searchInput) {
  loadSearchData();

  searchInput.addEventListener('input', () => {
    const q = searchInput.value.trim();

    if (!q) {
      closeDropdown();
      return;
    }

    const matched = characters.filter(c =>
      c.name.includes(q)
    );

    renderDropdown(q, matched);
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

function renderDropdown(q, matched) {
  if (!matched.length) {
    closeDropdown();
    return;
  }

  // 최대 5개 미리보기
  const preview = matched.slice(0, 5);

  searchDropdown.innerHTML = preview.map(c => `
    <li>
      <a href="${c.url}">
        <span class="dd-name">${highlight(c.name, q)}</span>
        <span class="dd-species">${c.species}</span>
      </a>
    </li>
  `).join('');

  // 엔터 안내 (결과가 2개 이상이거나 미리보기가 전부가 아닐 때)
  if (matched.length > 1) {
    searchDropdown.innerHTML += `
      <li class="dd-enter" onclick="goToSearch('${q}')">
        '${q}' 포함 결과 ${matched.length}개 전체 보기 →
      </li>
    `;
  }

  searchDropdown.classList.add('active');
}

// 검색어 강조
function highlight(name, q) {
  return name.replace(
    new RegExp(`(${q})`, 'g'),
    '<mark style="background:var(--sky-light);color:var(--sky-deep);border-radius:2px;">$1</mark>'
  );
}

function closeDropdown() {
  searchDropdown.classList.remove('active');
  searchDropdown.innerHTML = '';
}

function goToSearch(q) {
  // 나중에 검색 결과 페이지로 이동. 지금은 전체 개체 페이지로
  window.location.href = `character-list.html?q=${encodeURIComponent(q)}`;
}
