import { createClient } from 'npm:@supabase/supabase-js@2'

// ============================================================
// ban-users — 계정 이용정지 (운영정책 위반) 일괄 처리
// 작성일: 2026-08-23
//
// reset-user-password/index.ts와 동일한 인증 패턴을 그대로 재사용한다:
//   1) 호출자 JWT를 anon 클라이언트로 1차 검증
//   2) service_role 클라이언트로 호출자 레코드를 다시 조회해
//      raw_app_meta_data.role만 신뢰 (user_metadata는 본인이 위조 가능)
//   3) admin이 아니면 즉시 403
//
// 처리 내용 (계정당):
//   - auth.admin.updateUserById(id, { ban_duration: '876000h' })
//     GoTrue에는 "영구"라는 개념이 없어 100년(876000시간)을
//     사실상 무기한으로 사용한다 (Supabase 공식 문서 권장 방식).
//   - admin_logs 기록 (target_name은 user_profiles.nickname →
//     raw_user_meta_data.display_name/nickname → 이메일 @ 앞부분 순 fallback)
//
// ⚠️ "즉시 강제 로그아웃"에 대한 정확한 한계:
//   @supabase/auth-js(GoTrueAdminApi)에는 user_id 기준으로 세션을 전부
//   무효화하는 Admin API가 없다. auth.admin.signOut(jwt, scope)은 "대상의
//   access token(jwt)"을 인자로 받는 함수라, 관리자가 그 계정의 토큰을
//   들고 있지 않은 이상 호출할 수 없다 (node_modules/@supabase/auth-js/
//   dist/main/GoTrueAdminApi.d.ts로 직접 확인함). 그래서 이 함수는 그
//   API를 호출하지 않는다.
//   ban_duration은 확실히 보장된다: 신규 로그인(signInWithPassword)과
//   토큰 리프레시를 즉시 차단한다. 다만 밴 시점에 이미 발급되어 있던
//   access token은 자체 만료 시간(기본 1시간)까지는 그대로 유효할 수
//   있고, 그 토큰으로 리프레시를 시도하는 순간부터 막힌다 — 즉 최악의
//   경우 최대 1시간 정도의 유예가 있을 수 있고 그 이후로는 확실히 차단된다.
//
// 건드리지 않는 것: species/characters/adoptions/user_wallets/auth.users 삭제.
// 이 함수는 auth.users에 대한 UPDATE(ban_duration)만 수행하며 DELETE는 전혀 하지 않는다.
//
// 응답: 계정별로 banSuccess/logSuccess를 분리해서 반환한다. 한 계정이 실패해도
// 나머지는 계속 처리한다.
//
// banSuccess와 logSuccess를 분리하는 이유: admin_logs INSERT 실패(RLS/네트워크 등)
// 때문에 이미 걸린 ban까지 "실패"로 잘못 판단해 같은 계정을 다시 ban 호출하는
// 상황을 막기 위함이다. ban은 멱등적이라 재호출해도 위험하지는 않지만, 로그가
// 안 남은 걸 "밴이 안 걸렸다"고 오인해 재확인 없이 넘어가는 게 더 위험하다.
// banSuccess=true, logSuccess=false인 계정은 ban은 확실히 걸렸으니 재호출하지
// 말고, admin_logs 기록만 수동으로 보완하면 된다.
// ============================================================

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

// 사실상 무기한 — GoTrue ban_duration은 문자열 duration만 받고 "infinite"가 없다
const PERMANENT_BAN_DURATION = '876000h'

function jsonResponse(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

function isValidUuid(v: unknown): v is string {
  return typeof v === 'string' &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(v)
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) return jsonResponse(401, { error: 'Unauthorized' })

    const supabaseUrl    = Deno.env.get('SUPABASE_URL')!
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const anonKey        = Deno.env.get('SUPABASE_ANON_KEY')!

    const callerClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    })
    const { data: { user: caller }, error: authError } = await callerClient.auth.getUser()
    if (authError || !caller) return jsonResponse(401, { error: 'Unauthorized' })

    const adminClient = createClient(supabaseUrl, serviceRoleKey)

    const { data: { user: callerUser }, error: callerError } = await adminClient.auth.admin.getUserById(caller.id)
    if (callerError || !callerUser) return jsonResponse(401, { error: 'Unauthorized' })

    const callerRole = callerUser.app_metadata?.role
    const callerNickname =
      callerUser.user_metadata?.display_name || callerUser.user_metadata?.nickname || ''

    if (callerRole !== 'admin') {
      return jsonResponse(403, { error: 'Forbidden: admin only' })
    }

    // 요청 파싱 — userIds 배열, 각 요소는 UUID
    let body: { userIds?: unknown; reason?: unknown }
    try {
      body = await req.json()
    } catch {
      return jsonResponse(400, { error: 'Invalid request body' })
    }
    const { userIds, reason } = body

    if (!Array.isArray(userIds) || userIds.length === 0) {
      return jsonResponse(400, { error: 'Missing or invalid required field: userIds (non-empty array)' })
    }
    if (userIds.length > 50) {
      return jsonResponse(400, { error: 'Too many userIds in a single request (max 50)' })
    }

    // 중복 제거 + 형식 검증
    const uniqueIds = [...new Set(userIds)]
    const invalidIds = uniqueIds.filter((id) => !isValidUuid(id))
    if (invalidIds.length > 0) {
      return jsonResponse(400, { error: `Invalid userId format: ${invalidIds.join(', ')}` })
    }

    const banReason = typeof reason === 'string' && reason.trim() ? reason.trim() : '운영정책 위반'

    type BanResult = {
      id: string
      nickname: string | null
      banSuccess: boolean
      logSuccess: boolean
      error?: string
    }
    const results: BanResult[] = []

    for (const userId of uniqueIds as string[]) {
      try {
        // 대상 존재 확인
        const { data: { user: targetUser }, error: targetError } = await adminClient.auth.admin.getUserById(userId)
        if (targetError || !targetUser) {
          results.push({ id: userId, nickname: null, banSuccess: false, logSuccess: false, error: 'Target user not found' })
          continue
        }

        // target_name fallback: user_profiles.nickname → user_metadata → 이메일 @ 앞부분
        let targetName: string | null = null
        const { data: profileRow } = await adminClient
          .from('user_profiles')
          .select('nickname')
          .eq('user_id', userId)
          .maybeSingle()
        targetName =
          (profileRow?.nickname && String(profileRow.nickname).trim()) ||
          targetUser.user_metadata?.display_name ||
          targetUser.user_metadata?.nickname ||
          (targetUser.email ? targetUser.email.split('@')[0] : null) ||
          null

        // 무기한 ban — 신규 로그인/토큰 리프레시를 즉시 차단한다
        const { error: banError } = await adminClient.auth.admin.updateUserById(userId, {
          ban_duration: PERMANENT_BAN_DURATION,
        })
        if (banError) {
          results.push({ id: userId, nickname: targetName, banSuccess: false, logSuccess: false, error: `ban failed: ${banError.message}` })
          continue
        }

        // 로그 기록 — 이 단계가 실패해도 위의 ban은 이미 걸린 상태이므로 재시도(재-ban) 대상이 아니다.
        // banSuccess=true를 그대로 두고 logSuccess만 false로 보고한다.
        const { error: logError } = await adminClient.from('admin_logs').insert({
          admin_id:       caller.id,
          admin_nickname: callerNickname,
          action_type:    'user_ban',
          target_type:    'user',
          target_id:      userId,
          target_name:    targetName,
          details:        { reason: banReason, ban_duration: PERMANENT_BAN_DURATION },
        })

        if (logError) {
          results.push({ id: userId, nickname: targetName, banSuccess: true, logSuccess: false, error: `admin_logs insert failed: ${logError.message}` })
          continue
        }

        results.push({ id: userId, nickname: targetName, banSuccess: true, logSuccess: true })
      } catch (err) {
        // 이 catch는 getUserById/updateUserById 등 위 단계에서 던진 예외를 잡는다 —
        // 여기 도달했다는 것은 ban 성공 여부를 이 함수가 확인하지 못했다는 뜻이므로
        // banSuccess를 false로 보고해 호출자가 auth.users를 직접 재확인하도록 한다.
        const message = err instanceof Error ? err.message : String(err)
        results.push({ id: userId, nickname: null, banSuccess: false, logSuccess: false, error: message })
      }
    }

    return jsonResponse(200, {
      // admin_logs 기록 실패는 배치 전체의 실패로 보지 않는다 — ban 자체의 성공 여부만 집계한다.
      success: results.every((r) => r.banSuccess),
      results,
    })
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err)
    return jsonResponse(400, { error: message })
  }
})
