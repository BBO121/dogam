window.isAdmin        = (role) => role === 'admin';
window.isStaff        = (role) => role === 'staff';
window.isAdminOrStaff = (role) => role === 'admin' || role === 'staff';

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

// 스크립트 파싱 즉시 fetch 시작 — DOMContentLoaded 대기 없이 최대한 일찍 실행
const _userPromise = sb.auth.getUser().then(({ data: { user } }) => user);
async function getUser() { return _userPromise; }

// ── 종족 목록 공통 캐시 (auth.js에 정의 — 모든 파일보다 먼저 로드됨) ──
// sidebar.js, main.js, 모든 페이지가 공유. 파싱 즉시 정의, 첫 호출 시 fetch 시작.
;(function() {
  let _p = null;
  window._getSpeciesData = function() {
    if (!_p) {
      const cached = sessionStorage.getItem('_sb_species_list');
      _p = cached
        ? Promise.resolve(JSON.parse(cached))
        : sb.from('species').select('id, name').order('name').then(({ data, error }) => {
            if (!error && data) sessionStorage.setItem('_sb_species_list', JSON.stringify(data));
            return data;
          });
    }
    return _p;
  };
})();

// 종족주 여부 — 페이지당 1회만 쿼리, 이후 캐시 반환
let _spOwnerPromise = null;
window._cachedIsSpeciesOwner = async function(userId, roleIsSpeciesOwner) {
  if (roleIsSpeciesOwner) return true;
  if (!userId) return false;
  if (!_spOwnerPromise) {
    _spOwnerPromise = sb.from('species').select('id')
      .eq('owner_user_id', userId).limit(1)
      .then(({ data }) => !!data?.length);
  }
  return _spOwnerPromise;
};

// 관리자/스태프 여부
async function isAdmin() {
  const user = await getUser();
  return isAdminOrStaff(user?.user_metadata?.role);
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

// 내 캐릭터 조회 — owner_user_id 기준만, 오프사이트 제외
async function getMyCharacters(userId, nickname) {
  if (!userId) return { data: [], error: null };
  const { data, error } = await sb
    .from('characters').select('*')
    .eq('owner_user_id', userId)
    .neq('owner_is_offsite', true)
    .order('created_at', { ascending: false });
  return { data, error };
}

// 내 종족 조회 — owner_user_id 기준
async function getMySpecies(userId) {
  if (!userId) return { data: [], error: null };
  const { data, error } = await sb
    .from('species').select('*')
    .eq('owner_user_id', userId)
    .order('created_at', { ascending: false });
  return { data: data ?? [], error };
}

// 관리자 액션 로그 기록 (공통 — 모든 페이지에서 호출 가능)
async function logAdminAction(actionType, targetType, targetId, targetName, details = {}) {
  const user = await getUser();
  if (!user || !isAdminOrStaff(user.user_metadata?.role)) return;
  try {
    await sb.from('admin_logs').insert({
      admin_id:       user.id,
      admin_nickname: user.user_metadata?.display_name || user.user_metadata?.nickname || '',
      action_type:    actionType,
      target_type:    targetType || null,
      target_id:      targetId ? String(targetId) : null,
      target_name:    targetName || null,
      details,
    });
  } catch (e) {
    console.warn('[logAdminAction] 로그 기록 실패:', e);
  }
}

// 캐릭터 이전 로그 기록
async function logTransfer({ character_name, species_name, from_nickname, from_user_id, to_nickname, to_user_id, method }) {
  const { error } = await sb.from('character_transfers').insert({
    character_name,
    species_name,
    from_nickname,
    from_user_id: from_user_id || null,
    to_nickname,
    to_user_id:   to_user_id   || null,
    method,
  });
  return { error };
}

// 이전 내역 조회 — user_id 기준 + 구 데이터 nickname fallback
async function getTransferHistory(userId, nicknames) {
  const orParts = userId ? [`from_user_id.eq.${userId}`, `to_user_id.eq.${userId}`] : [];
  const nicks = [...new Set([].concat(nicknames).filter(Boolean))];
  nicks.forEach(n => orParts.push(`from_nickname.eq.${n}`, `to_nickname.eq.${n}`));
  if (!orParts.length) return { data: [], error: null };
  const { data, error } = await sb
    .from('character_transfers')
    .select('*')
    .or(orParts.join(','))
    .order('created_at', { ascending: false });
  const seen = new Set();
  const unique = (data || []).filter(t => { if (seen.has(t.id)) return false; seen.add(t.id); return true; });
  return { data: unique, error };
}

// 내 지갑 잔액 조회
async function getMyWallet(userId) {
  if (!userId) return { data: null, error: null };
  const { data, error } = await sb
    .from('user_wallets')
    .select('research_records, keys, updated_at')
    .eq('user_id', userId)
    .single();
  return { data, error };
}

// 내 거래 내역 조회
async function getMyCurrencyLogs(userId) {
  if (!userId) return { data: [], error: null };
  const { data, error } = await sb
    .from('currency_logs')
    .select('*')
    .eq('user_id', userId)
    .order('created_at', { ascending: false });
  return { data: data ?? [], error };
}

// 재화 전송 RPC (research_records / keys)
async function transferCurrency(currencyType, toNickname, amount, note) {
  const { data, error } = await sb.rpc('transfer_currency', {
    p_to_nickname: toNickname,
    p_currency:    currencyType,
    p_amount:      amount,
    p_note:        note || null,
  });
  return { data, error };
}

// 헤더 상태 업데이트
async function updateHeader() {
  const user = await getUser();
  const admin = user?.user_metadata?.role === 'admin';
  const staff = user?.user_metadata?.role === 'staff';
  const loginBtn = document.querySelector('.btn-login');

  if (user) {
    const nickname = user.user_metadata?.display_name || user.user_metadata?.nickname || '유저';

    const TESTERS = ['Moulow', 'moulow', 'Sawol'];
    const roleIsSpeciesOwner = user.user_metadata?.role === 'species_owner';
    const isSpeciesOwner = await window._cachedIsSpeciesOwner(user.id, roleIsSpeciesOwner);
    const isTester = TESTERS.includes(nickname);

    if (loginBtn) {
      loginBtn.textContent = nickname;
      loginBtn.href = 'profile.html';
      loginBtn.classList.remove('btn-login');
      loginBtn.classList.add('btn-username');

      // 뱃지: 관리자 → 테스터 → 종족주 순으로 닉네임 앞에
      const headerBadges = [];
      if (admin)                                        headerBadges.push(`<a href="admin.html" class="badge-admin">관리자</a>`);
      if (staff)                                        headerBadges.push(`<a href="admin.html" class="badge-staff">스태프</a>`);
      if (isTester && !staff)                           headerBadges.push(`<span style="font-size:10px; padding:3px 8px; background:#dcfce7; color:#166534; border-radius:4px; font-weight:700; display:inline-block; margin-right:4px;">테스터</span>`);
      if (isSpeciesOwner)                               headerBadges.push(`<span class="badge-role">종족주</span>`);
      if (!admin && !staff && !isTester && !isSpeciesOwner) headerBadges.push(`<span class="badge-user">일반유저</span>`);
      if (headerBadges.length) {
        loginBtn.insertAdjacentHTML('beforebegin', headerBadges.join(''));
      }

      // 로그아웃은 닉네임 뒤에
      loginBtn.insertAdjacentHTML('afterend',
        `<button class="btn-logout" onclick="signOut()">로그아웃</button>`
      );
    }
  }
}

document.addEventListener('DOMContentLoaded', updateHeader);

// 상단바 재화 숫자 즉시 갱신 (페이지 새로고침 없이)
// 사용: updateHeaderCurrencyDisplay({ research_records: N, keys: N })
function updateHeaderCurrencyDisplay({ research_records, keys } = {}) {
  const researchEl = document.getElementById('headerResearchAmount');
  const keysEl     = document.getElementById('headerKeysAmount');
  if (researchEl && research_records != null) {
    researchEl.textContent = Number(research_records).toLocaleString();
  }
  if (keysEl && keys != null) {
    keysEl.textContent = Number(keys).toLocaleString();
  }
}
