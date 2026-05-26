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

// 더미 데이터 (나중에 서버 데이터로 교체)
const characters = [
  { name: '루나',   species: '드래곤',   url: 'character.html' },
  { name: '루리',   species: '요정',     url: 'character.html' },
  { name: '루',     species: '슬라임',   url: 'character.html' },
  { name: '세라',   species: '드래곤',   url: 'character.html' },
  { name: '아르',   species: '엘프',     url: 'character.html' },
  { name: '모글',   species: '슬라임',   url: 'character.html' },
  { name: '제르',   species: '늑대인간', url: 'character.html' },
  { name: '티아',   species: '요정',     url: 'character.html' },
  { name: '바루',   species: '골렘',     url: 'character.html' },
  { name: '핀',     species: '엘프',     url: 'character.html' },
  { name: '이그니스', species: '드래곤', url: 'character.html' },
  { name: '아쿠아', species: '드래곤',   url: 'character.html' },
  { name: '테라',   species: '드래곤',   url: 'character.html' },
  { name: '베노',   species: '드래곤',   url: 'character.html' },
  { name: '섀도',   species: '드래곤',   url: 'character.html' },
  { name: '글레이스', species: '드래곤', url: 'character.html' },
  { name: '미르',   species: '드래곤',   url: 'character.html' },
  { name: '크로',   species: '골렘',     url: 'character.html' },
];

// 검색
const searchInput    = document.getElementById('searchInput');
const searchDropdown = document.getElementById('searchDropdown');

if (searchInput) {
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
