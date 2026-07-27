import { createClient } from 'npm:@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

function generateTempPassword(): string {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789'
  let pw = ''
  const bytes = crypto.getRandomValues(new Uint8Array(12))
  for (const b of bytes) pw += chars[b % chars.length]
  return pw
}

function jsonResponse(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

// auth.users.id는 uuid 형식만 허용 — 잘못된 형식은 바로 거부한다
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

    // 호출자 JWT 검증 (서명·만료만 확인 — 이 토큰의 클레임으로 권한을 판단하지 않는다)
    const callerClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    })
    const { data: { user: caller }, error: authError } = await callerClient.auth.getUser()
    if (authError || !caller) return jsonResponse(401, { error: 'Unauthorized' })

    // service_role 클라이언트 — 아래 권한/대상 조회·변경은 전부 서버에서 이 클라이언트로 직접 수행한다
    const adminClient = createClient(supabaseUrl, serviceRoleKey)

    // 호출자 레코드를 auth.admin API로 다시 조회한다.
    // (JWT를 디코딩해서 그 안의 값을 믿는 게 아니라, 서버가 auth.users를 다시 조회해 확인한다)
    const { data: { user: callerUser }, error: callerError } = await adminClient.auth.admin.getUserById(caller.id)
    if (callerError || !callerUser) return jsonResponse(401, { error: 'Unauthorized' })

    // ── 권한 판단: raw_app_meta_data.role만 신뢰한다 ──
    // raw_user_meta_data(= user_metadata)는 본인이 supabase.auth.updateUser()로
    // 직접 수정 가능한 필드라, 이 값으로 admin 여부를 판단하면 누구든 자기
    // user_metadata.role을 'admin'으로 바꿔치기해 이 함수(비밀번호 강제 변경)를
    // 통과할 수 있다. app_metadata는 Admin API로만 쓸 수 있어 안전하다.
    // (참고: 현재는 role 권한 모델 전체가 raw_user_meta_data 기준이라, 이
    //  app_metadata.role은 별도 시드 스크립트로 채워둔 값이다 — 전체 마이그레이션
    //  전까지는 set_user_role로 새로 부여된 role이 여기 자동 반영되지 않으니,
    //  새 관리자를 추가하면 시드를 다시 돌려야 한다.)
    const callerRole = callerUser.app_metadata?.role
    const callerNickname =
      callerUser.user_metadata?.display_name || callerUser.user_metadata?.nickname || ''

    // 본인 비밀번호를 초기화하는 요청이라도 예외를 두지 않고 동일하게 admin만 허용한다
    if (callerRole !== 'admin') {
      return jsonResponse(403, { error: 'Forbidden: admin only' })
    }

    // 요청 파싱 — 프론트는 userId, targetNickname만 전달
    let body: { userId?: unknown; targetNickname?: unknown }
    try {
      body = await req.json()
    } catch {
      return jsonResponse(400, { error: 'Invalid request body' })
    }
    const { userId, targetNickname } = body

    if (!isValidUuid(userId)) {
      return jsonResponse(400, { error: 'Missing or invalid required field: userId' })
    }

    // 대상 유저 유효성 검증 — 존재하지 않으면 비밀번호 변경 로직에 절대 진입하지 않는다
    const { data: { user: targetUser }, error: targetError } = await adminClient.auth.admin.getUserById(userId)
    if (targetError || !targetUser) {
      return jsonResponse(404, { error: 'Target user not found' })
    }

    // 로그에 남길 이름은 서버가 조회한 값을 우선 사용 (클라이언트 값은 그게 없을 때만 보조로 사용)
    const targetNameForLog =
      targetUser.user_metadata?.display_name ||
      targetUser.user_metadata?.nickname ||
      (typeof targetNickname === 'string' ? targetNickname : null)

    // 임시 비밀번호는 서버에서만 생성한다 (프론트에서 생성하지 않음)
    const tempPassword = generateTempPassword()

    // 비밀번호 강제 변경
    const { error: updateError } = await adminClient.auth.admin.updateUserById(userId, {
      password: tempPassword,
    })
    if (updateError) {
      return jsonResponse(400, { error: updateError.message })
    }

    // 관리자 로그 기록 — 요청자·대상자 ID를 모두 남기고, 임시 비밀번호 원문은 절대 남기지 않는다
    await adminClient.from('admin_logs').insert({
      admin_id:       caller.id,
      admin_nickname: callerNickname,
      action_type:    'password_reset',
      target_type:    'user',
      target_id:      userId,
      target_name:    targetNameForLog,
      details:        {},
    })

    // 임시 비밀번호는 이 응답에만 1회 담아 반환한다 (DB·로그 어디에도 저장하지 않음)
    return jsonResponse(200, { success: true, tempPassword })
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err)
    return jsonResponse(400, { error: message })
  }
})
