// 운영정책 위반 5계정 이용정지 — 2026-08-23
// 관리자(admin) 계정으로 로그인된 상태에서, 종족연구소 페이지(예: admin.html)의
// 브라우저 콘솔에 붙여넣어 실행하세요. supabase/functions/ban-users/index.ts가
// 먼저 배포되어 있어야 합니다 (supabase functions deploy ban-users).
//
// 대상 5계정 (닉네임 → user_id, 뽀가 직접 확인한 UUID):
//   캐로로캐    4d442bfc-2d4d-4d24-86d4-02a0b85af563
//   히사        090105d8-585a-4976-8874-b997b710a26e
//   liiiiiiii   38cc536e-66e3-4b16-84b1-39a00c9a20e3
//   행복한 냥이  849eb780-12c3-42ed-aedb-8722e88fe9ff
//   xp          179f8e39-b581-4262-9ef0-cbce7fa6fc74
//
// 처리 내용: 서버(ban-users Edge Function)가 계정별로
//   1) auth.admin.updateUserById(ban_duration: '876000h') — 사실상 무기한 ban
//   2) admin_logs 기록
// 을 수행하고, 계정별 성공/실패 결과를 반환합니다.
//
// 즉시 강제 로그아웃 관련 한계: Supabase Admin API(@supabase/auth-js)에는
// user_id 기준으로 세션을 전부 무효화하는 기능이 없습니다(auth.admin.signOut은
// 대상의 access token 자체를 인자로 받아야 해서 admin이 호출할 수 없음).
// ban_duration은 신규 로그인/토큰 리프레시를 즉시 막지만, 밴 시점에 이미
// 발급되어 있던 access token은 자체 만료(기본 1시간)까지 살아있을 수 있고
// 그 이후부터는 확실히 차단됩니다.
//
// 종족/개체/지갑/auth.users 삭제는 이 스크립트가 절대 건드리지 않습니다.
(async () => {
  const TARGET_IDS = [
    '4d442bfc-2d4d-4d24-86d4-02a0b85af563', // 캐로로캐
    '090105d8-585a-4976-8874-b997b710a26e', // 히사
    '38cc536e-66e3-4b16-84b1-39a00c9a20e3', // liiiiiiii
    '849eb780-12c3-42ed-aedb-8722e88fe9ff', // 행복한 냥이
    '179f8e39-b581-4262-9ef0-cbce7fa6fc74', // xp
  ];

  const { data: { session } } = await sb.auth.getSession();
  if (!session) { console.error('로그인이 필요합니다.'); return; }

  const EDGE_FN_URL = `${SUPABASE_URL}/functions/v1/ban-users`;

  const res = await fetch(EDGE_FN_URL, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${session.access_token}`,
    },
    body: JSON.stringify({
      userIds: TARGET_IDS,
      reason: '운영정책 위반',
    }),
  });

  const json = await res.json();

  if (!res.ok) {
    console.error('요청 실패:', res.status, json);
    return;
  }

  console.log('전체 ban 성공 여부:', json.success);
  console.table(json.results);

  const banFailed = (json.results || []).filter(r => !r.banSuccess);
  const logOnlyFailed = (json.results || []).filter(r => r.banSuccess && !r.logSuccess);

  if (banFailed.length) {
    console.warn('ban 자체가 실패한 계정 — 원인 확인 후 재시도 필요:', banFailed);
  }
  if (logOnlyFailed.length) {
    console.warn('ban은 성공했지만 admin_logs 기록만 실패한 계정 — 재-ban 하지 말고 admin_logs만 수동 보완:', logOnlyFailed);
  }
  if (!banFailed.length && !logOnlyFailed.length) {
    console.log('5계정 모두 이용정지 + 로그 기록까지 완료.');
  }
})();
