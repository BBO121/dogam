const SUPABASE_URL = 'https://tnvkfcqphdxdyvswbkfe.supabase.co';
const SUPABASE_KEY = 'sb_publishable_iaH_vCaDJfekUiZ85_JO7w_T_iDGNfg';

const { createClient } = supabase;
const sb = createClient(SUPABASE_URL, SUPABASE_KEY);

// 닉네임 → 가짜 이메일 변환
function toEmail(nickname) {
  return `${nickname}@dogam.com`;
}

// 회원가입
async function signUp(nickname, password) {
  const { data, error } = await sb.auth.signUp({
    email: toEmail(nickname),
    password,
    options: { data: { nickname } }
  });
  return { data, error };
}

// 로그인
async function signIn(nickname, password) {
  const { data, error } = await sb.auth.signInWithPassword({
    email: toEmail(nickname),
    password,
  });
  return { data, error };
}

// 로그아웃
async function signOut() {
  await sb.auth.signOut();
  window.location.href = 'index.html';
}

// 현재 로그인된 유저
async function getUser() {
  const { data: { user } } = await sb.auth.getUser();
  return user;
}

// 관리자 여부
async function isAdmin() {
  const user = await getUser();
  return user?.user_metadata?.role === 'admin';
}

// 헤더 상태 업데이트
async function updateHeader() {
  const user = await getUser();
  const admin = user?.user_metadata?.role === 'admin';
  const loginBtn   = document.querySelector('.btn-login');
  const loginItems = document.querySelectorAll('.sidebar-item--login');

  if (user) {
    const nickname = user.user_metadata?.nickname || '유저';

    // 헤더: 닉네임 + (관리자 뱃지) + 로그아웃
    if (loginBtn) {
      loginBtn.textContent = nickname;
      loginBtn.href = 'profile.html';
      loginBtn.classList.remove('btn-login');
      loginBtn.classList.add('btn-username');

      const adminBadge = admin
        ? `<span class="badge-admin">관리자</span>` : '';

      loginBtn.insertAdjacentHTML('afterend',
        `${adminBadge}<button class="btn-logout" onclick="signOut()">로그아웃</button>`
      );
    }

    // 사이드바 로그인 필요 항목 활성화
    loginItems.forEach(el => {
      el.classList.remove('sidebar-item--login');
      if (el.textContent.includes('내 캐릭터')) el.href = 'my-characters.html';
      if (el.textContent.includes('내 정보'))   el.href = 'profile.html';
    });
  }
}

document.addEventListener('DOMContentLoaded', updateHeader);
