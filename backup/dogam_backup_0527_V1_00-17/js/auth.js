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

// 프로필 업데이트 (소개글 등)
async function updateProfile(data) {
  const { error } = await sb.auth.updateUser({ data });
  return { error };
}

// 비밀번호 변경
async function updatePassword(newPassword) {
  const { error } = await sb.auth.updateUser({ password: newPassword });
  return { error };
}

// 계정 탈퇴 (로그아웃 처리 - 실제 삭제는 서버사이드 필요)
async function deleteAccount() {
  await sb.auth.signOut();
  window.location.href = 'index.html';
}

// 내 캐릭터 조회
async function getMyCharacters(nickname) {
  const { data, error } = await sb
    .from('characters')
    .select('*')
    .eq('owner_nickname', nickname)
    .order('created_at', { ascending: false });
  return { data, error };
}

// 내 종족 조회
async function getMySpecies(nickname) {
  const { data, error } = await sb
    .from('species')
    .select('*')
    .eq('owner_nickname', nickname)
    .order('created_at', { ascending: false });
  return { data, error };
}

// 캐릭터 이전 로그 기록
async function logTransfer({ character_name, species_name, from_nickname, to_nickname, method }) {
  const { error } = await sb.from('character_transfers').insert({
    character_name,
    species_name,
    from_nickname,
    to_nickname,
    method,
  });
  return { error };
}

// 이전 내역 조회 (보낸 것 + 받은 것 모두)
async function getTransferHistory(nickname) {
  const { data, error } = await sb
    .from('character_transfers')
    .select('*')
    .or(`from_nickname.eq.${nickname},to_nickname.eq.${nickname}`)
    .order('created_at', { ascending: false });
  return { data, error };
}

// 헤더 상태 업데이트
async function updateHeader() {
  const user = await getUser();
  const admin = user?.user_metadata?.role === 'admin';
  const loginBtn = document.querySelector('.btn-login');

  if (user) {
    const nickname = user.user_metadata?.nickname || '유저';

    const isSpeciesOwner = user.user_metadata?.role === 'species_owner';

    if (loginBtn) {
      loginBtn.textContent = nickname;
      loginBtn.href = 'profile.html';
      loginBtn.classList.remove('btn-login');
      loginBtn.classList.add('btn-username');

      // 종족주 뱃지는 닉네임 앞에
      if (isSpeciesOwner) {
        loginBtn.insertAdjacentHTML('beforebegin', `<span class="badge-role">종족주</span>`);
      }

      // 관리자 뱃지 + 로그아웃은 닉네임 뒤에
      const adminBadge = admin
        ? `<a href="admin.html" class="badge-admin">관리자</a>` : '';
      loginBtn.insertAdjacentHTML('afterend',
        `${adminBadge}<button class="btn-logout" onclick="signOut()">로그아웃</button>`
      );
    }
  }
}

document.addEventListener('DOMContentLoaded', updateHeader);
