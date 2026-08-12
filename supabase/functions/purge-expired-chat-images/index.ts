// DM 채팅 첨부 이미지 30일 만료 배치.
// dm_message_attachments.expires_at < now() 이고 purged_at is null인 행을 찾아
// Storage 실제 파일만 지우고 purged_at을 기록한다. dm_messages/dm_message_attachments
// 행 자체는 절대 지우지 않는다 (메시지 기록은 유지, 첨부 파일만 만료).
//
// 이 함수는 로그인한 유저가 아니라 pg_cron(또는 Dashboard 예약 실행)이 호출하는
// 서버-서버 배치이므로, 유저 JWT 대신 CRON_SECRET이라는 이 함수 전용 시크릿으로
// 호출자를 인증한다. service_role 키는 Storage/DB 관리 작업에만 쓰고, 호출자
// 인증에는 쓰지 않는다 — pg_cron 쪽에 강력한 service_role 키를 넘길 필요가 없어진다.
// (서비스 롤 키/CRON_SECRET 둘 다 코드에 하드코딩하지 않고 항상 Deno.env로만 읽는다.)

import { createClient } from 'npm:@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

// 배치당 처리 상한 — 하루 1회 실행 기준으로 하루 예상 첨부 건수보다 넉넉히 잡되,
// Edge Function 실행시간 제한 안에서 끝나도록 상한을 둔다. 상한을 넘겨 못 지운
// 나머지는 purged_at이 계속 null이라 다음날 실행 때 자동으로 이어서 처리된다.
const BATCH_LIMIT = 300

function jsonResponse(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const cronSecret = Deno.env.get('CRON_SECRET')
    const authHeader = req.headers.get('Authorization') ?? ''
    if (!cronSecret || authHeader !== `Bearer ${cronSecret}`) {
      return jsonResponse(401, { error: 'Unauthorized' })
    }

    const supabaseUrl    = Deno.env.get('SUPABASE_URL')!
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const adminClient = createClient(supabaseUrl, serviceRoleKey)

    // 만료 대상만 조회. purged_at is null 조건이 멱등성의 핵심 — 이미 처리된 행은
    // 다시 뽑히지 않으므로 이 함수를 몇 번 재실행해도(같은 날 중복 트리거 등) 결과가
    // 달라지지 않는다.
    const { data: targets, error: selectError } = await adminClient
      .from('dm_message_attachments')
      .select('id, storage_path')
      .lt('expires_at', new Date().toISOString())
      .is('purged_at', null)
      .order('expires_at', { ascending: true })
      .limit(BATCH_LIMIT)

    if (selectError) {
      return jsonResponse(500, { error: selectError.message })
    }
    if (!targets || targets.length === 0) {
      return jsonResponse(200, { scanned: 0, purged: 0, failed: 0, message: 'no expired attachments' })
    }

    // 파일 하나씩 개별 삭제 — 하나 실패해도 나머지 처리에 영향 없도록 격리하고,
    // Storage 삭제가 "성공"으로 확인된 행만 purged_at을 기록한다. 실패한 행은
    // purged_at이 계속 null로 남아 다음 배치 실행 때 자동으로 재시도된다.
    let purgedCount = 0
    const failed: Array<{ id: number; storage_path: string; error: string }> = []

    for (const row of targets) {
      const { error: removeError } = await adminClient
        .storage
        .from('chat-attachments')
        .remove([row.storage_path])

      if (removeError) {
        failed.push({ id: row.id, storage_path: row.storage_path, error: removeError.message })
        continue
      }

      // is('purged_at', null)로 한 번 더 좁혀서, 혹시 겹쳐 실행된 다른 배치가 먼저
      // 처리했더라도 서로의 purged_at 기록을 덮어쓰지 않게 한다.
      const { error: updateError } = await adminClient
        .from('dm_message_attachments')
        .update({ purged_at: new Date().toISOString() })
        .eq('id', row.id)
        .is('purged_at', null)

      if (updateError) {
        failed.push({ id: row.id, storage_path: row.storage_path, error: updateError.message })
        continue
      }

      purgedCount++
    }

    return jsonResponse(200, {
      scanned: targets.length,
      purged: purgedCount,
      failed: failed.length,
      failedDetail: failed,
    })
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err)
    return jsonResponse(500, { error: message })
  }
})
