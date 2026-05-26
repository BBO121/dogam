async function initSidebar() {
  const sidebar = document.getElementById('sidebar');
  if (!sidebar) return;

  const path = window.location.pathname.split('/').pop();

  sidebar.innerHTML = `
    <nav class="sidebar-menu">
      <a href="index.html"        class="sidebar-item ${path === 'index.html' ? 'active' : ''}">홈</a>
      <a href="notice.html"       class="sidebar-item ${path === 'notice.html' || path === 'notice-detail.html' ? 'active' : ''}">공지사항</a>
      <a href="guide.html"        class="sidebar-item ${path === 'guide.html'  || path === 'guide-detail.html'  ? 'active' : ''}">가이드</a>
      <a href="adoption.html"     class="sidebar-item ${path === 'adoption.html' || path === 'adoption-detail.html' ? 'active' : ''}">분양란</a>
    </nav>

    <div class="sidebar-divider"></div>

    <div class="sidebar-accordion" id="accSpecies">
      <button class="sidebar-accordion-btn" onclick="toggleAccordion('accSpecies')">
        종족<span class="sidebar-accordion-arrow" id="arrSpecies"></span>
      </button>
      <div class="sidebar-accordion-body" id="bodySpecies">
        <p class="sidebar-loading">불러오는 중...</p>
      </div>
    </div>

    <div class="sidebar-divider"></div>

    <nav class="sidebar-menu">
      <a href="my-species.html"    class="sidebar-item sidebar-login ${path === 'my-species.html'    ? 'active' : ''}">내 종족</a>
      <a href="my-characters.html" class="sidebar-item sidebar-login ${path === 'my-characters.html' ? 'active' : ''}">내 캐릭터</a>
      <div class="sidebar-accordion sidebar-login" id="accMyInfo">
        <button class="sidebar-accordion-btn" onclick="toggleAccordion('accMyInfo')">
          내 정보<span class="sidebar-accordion-arrow" id="arrMyInfo"></span>
        </button>
        <div class="sidebar-accordion-body" id="bodyMyInfo">
          <a href="profile.html"           class="sidebar-subitem ${path === 'profile.html'           ? 'active' : ''}">프로필 설정</a>
          <a href="transfer-history.html" class="sidebar-subitem ${path === 'transfer-history.html' ? 'active' : ''}">캐릭터 이전 내역</a>
        </div>
      </div>
    </nav>

    <div class="sidebar-divider"></div>

    <nav class="sidebar-menu">
      <a href="#" class="sidebar-item">문의</a>
      <a href="#" class="sidebar-item">버그리포트</a>
    </nav>
  `;

  // 내 정보 하위 페이지면 아코디언 자동 열기
  if (path === 'profile.html' || path === 'transfer-history.html') {
    document.getElementById('bodyMyInfo').classList.add('open');
    document.getElementById('arrMyInfo').style.transform = 'rotate(180deg)';
  }

  loadSpeciesSidebar();
  updateSidebarLogin();
}

async function loadSpeciesSidebar() {
  const body = document.getElementById('bodySpecies');
  if (!body) return;

  const { data, error } = await sb.from('species').select('id, name').order('name');

  const allLink = `<a href="species-list.html" class="sidebar-subitem sidebar-subitem--all">전체보기</a>`;

  if (error || !data || data.length === 0) {
    const dummy = ['드래곤','엘프','요정','늑대인간','슬라임','골렘'];
    body.innerHTML = allLink + dummy.map(name =>
      `<a href="species-list.html" class="sidebar-subitem" style="opacity:0.45;">${name}</a>`
    ).join('');
    return;
  }

  const q    = new URLSearchParams(window.location.search);
  const curr = q.get('id');

  body.innerHTML = allLink + data.map(s =>
    `<a href="species-list.html?id=${s.id}" class="sidebar-subitem ${curr === String(s.id) ? 'active' : ''}">${s.name}</a>`
  ).join('');
}

async function updateSidebarLogin() {
  const user = await getUser();

  if (user) {
    document.querySelectorAll('.sidebar-login').forEach(el => el.classList.remove('sidebar-login'));
  }
}

function toggleAccordion(id) {
  const suffix  = id.replace('acc', '');
  const body    = document.getElementById('body' + suffix);
  const arrow   = document.getElementById('arr'  + suffix);
  if (!body) return;

  const isOpen = body.classList.toggle('open');
  if (arrow) arrow.style.transform = isOpen ? 'rotate(180deg)' : '';
}

document.addEventListener('DOMContentLoaded', initSidebar);
