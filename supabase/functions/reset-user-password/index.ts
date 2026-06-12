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

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) throw new Error('Unauthorized')

    const supabaseUrl    = Deno.env.get('SUPABASE_URL')!
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const anonKey        = Deno.env.get('SUPABASE_ANON_KEY')!

    // 호출자 JWT 검증
    const callerClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    })
    const { data: { user: caller }, error: authError } = await callerClient.auth.getUser()
    if (authError || !caller) throw new Error('Unauthorized')

    // service_role 클라이언트 생성
    const adminClient = createClient(supabaseUrl, serviceRoleKey)

    // 호출자 정보를 auth.admin API로 직접 조회 (별도 users 테이블 없음)
    const { data: { user: callerUser }, error: callerError } = await adminClient.auth.admin.getUserById(caller.id)
    if (callerError || !callerUser) throw new Error('Unauthorized')

    // role/nickname은 raw_user_meta_data 기준
    const callerRole     = callerUser.user_metadata?.role
    const callerNickname = callerUser.user_metadata?.nickname || ''

    if (callerRole !== 'admin') throw new Error('Forbidden: admin only')

    // 요청 파싱 — 프론트는 userId, targetNickname만 전달
    const { userId, targetNickname } = await req.json()
    if (!userId) throw new Error('Missing required field: userId')

    // 임시 비밀번호 서버에서 생성 (프론트에서 생성하지 않음)
    const tempPassword = generateTempPassword()

    // 비밀번호 강제 변경
    const { error: updateError } = await adminClient.auth.admin.updateUserById(userId, {
      password: tempPassword,
    })
    if (updateError) throw updateError

    // 관리자 로그 기록 (비밀번호 자체는 저장하지 않음)
    await adminClient.from('admin_logs').insert({
      admin_id:       caller.id,
      admin_nickname: callerNickname,
      action_type:    'password_reset',
      target_type:    'user',
      target_id:      userId,
      target_name:    targetNickname || null,
      details:        {},
    })

    // 임시 비밀번호를 1회 응답으로 반환 (DB에는 저장되지 않음)
    return new Response(JSON.stringify({ success: true, tempPassword }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err)
    return new Response(JSON.stringify({ error: message }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
