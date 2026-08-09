# 테일스 개체 소유권 일괄 이전

수동으로 받은 소유권 신청 목록(사이트 유저 + 테일스 개체번호)을
한 건씩 DB를 직접 수정하지 않고 안전하게 처리하기 위한 도구.

**이 도구는 "내가 입력한 유저 + 내가 입력한 개체번호" 조합만 처리한다.**
`characters.owner_nickname` / `owner_contact` 같은 기존 오프사이트 소유주
정보를 근거로 사이트 계정을 자동으로 찾아 연결하는 기능은 없다.

대상 종족은 항상 `species_name = '테일스'`로 고정.

## 흐름

```
입력 파일(txt)
   │
   ▼
1) validate.js   ── DB 읽기 전용(SELECT)만 수행 ──▶ 검증 결과 JSON
   │
   │  (뽀가 직접 결과 파일을 확인 — "이전 가능" / "확인 필요" 분리)
   ▼
2) generate-sql.js  ── DB에 연결하지 않음, JSON만 읽음 ──▶ .sql 파일 생성
   │
   │  (뽀가 직접 .sql 내용을 검토)
   ▼
Supabase SQL Editor에서 직접 실행 (BEGIN ~ COMMIT, 문제 시 ROLLBACK)
```

두 스크립트 모두 `characters`/`character_transfers`에 대한
UPDATE/INSERT/DELETE 코드를 포함하지 않는다. 실제 DB 변경은 항상
Supabase SQL Editor에서 사람이 직접 실행한다.

## 준비

```bash
cp .env.example .env
# .env에 SUPABASE_SERVICE_ROLE_KEY 채워넣기 (Supabase 대시보드 > Project Settings > API)
```

`.env`는 `.gitignore`에 등록되어 있어 커밋되지 않는다.
`service_role` 키는 이 스크립트에서 조회(SELECT) 용도로만 쓰인다.

## 1) 검증

입력 파일 예시 (`input.txt`):

```
뽀 / 101, 205, 333
ms1sharklee / 510, 511
```

- 줄 형식: `닉네임또는아이디 / 개체번호, 개체번호, ...`
- 개체번호는 앞자리 0 유무와 무관하게 매칭됨 (`001`, `01`, `1` 모두 동일 취급)
- 빈 줄, 앞뒤 공백은 무시
- 같은 유저가 여러 줄에 걸쳐 나와도 자동으로 합쳐서 처리됨
- 개체명은 입력하지 않아도 됨 (이번 버전은 개체번호 + 유저만 사용)

실행:

```bash
node scripts/tails-transfer/validate.js input.txt
```

콘솔에 표로 결과가 출력되고, `scripts/tails-transfer/output/validation_<시각>.json`
파일로도 저장된다. 각 행에는 다음 정보가 포함된다.

- 입력유저 / 입력개체번호
- 매칭계정_user_id / nickname / login_id
- DB_char_id / DB_char_number / DB_name
- 현재_owner_user_id / 현재_owner_nickname
- (이전 가능 시) 변경될_owner_user_id / 변경될_owner_nickname
- 판정 (`이전 가능` / `확인 필요`)
- 사유

"확인 필요"로 분류되는 경우: 유저 미검출/후보 다수, 개체번호 미검출/중복,
입력 목록 내 동일 개체번호가 서로 다른 유저에게 중복 지정, 이미 다른 유저
(또는 동일 유저) 소유로 설정되어 있는 경우, 대상 개체가 오프사이트 상태
(`owner_is_offsite=true`)가 아닌 경우, 입력 형식 오류 등.
이 경우는 자동으로 이전 대상에 포함되지 않는다.

## 2) SQL 생성

1단계 결과 파일을 사람이 직접 확인한 뒤:

```bash
node scripts/tails-transfer/generate-sql.js scripts/tails-transfer/output/validation_<시각>.json
```

`scripts/tails-transfer/output/transfer_<시각>.sql` 파일이 생성된다.
"이전 가능" 건만 대상으로, 각 건마다:

- `characters` UPDATE: `owner_user_id`,
  `owner_nickname`(실행 시점에 `auth.users`를 직접 조회하는 서브쿼리로 채움 — 검증 시점
  스냅샷을 신뢰하지 않음), `owner_is_offsite = false`, `owner_contact = NULL`,
  `folder_id = NULL`, `pending_transfer = NULL`
  (`WHERE id = ... AND char_number = ... AND species_name = '테일스'
  AND owner_user_id IS NULL AND owner_is_offsite = true` — 검증 이후 상태가
  바뀐 경우 안전하게 0건 처리됨)
- `character_transfers` INSERT: `method = '일괄 소유권 연결'`,
  `from_nickname`에 기존 `owner_nickname`만 보존 (연락처 등 개인정보는 남기지 않음)

전체가 `BEGIN ~ COMMIT`으로 감싸져 있고, 끝에 실행 후 검증용 `SELECT`
쿼리(주석 처리됨)가 함께 생성된다.

## 3) 실행

생성된 `.sql` 파일을 직접 열어 검토한 뒤, Supabase SQL Editor에 붙여넣어
실행한다. 문제가 있으면 `COMMIT` 전에 `ROLLBACK`으로 되돌릴 수 있다.
실행 후에는 파일 하단의 검증용 `SELECT`로 결과를 확인한다.

## 주의

- `scripts/tails-transfer/output/`에는 유저 닉네임 등이 포함된 결과 파일이
  쌓이므로 `.gitignore`에 등록되어 커밋되지 않는다.
- 이 도구로 처리되는 대상은 오직 사람이 입력 파일에 명시한
  (유저, 개체번호) 조합뿐이다. DB에 남아있는 오프사이트 소유주 정보를
  기준으로 유저를 추측하거나 일괄 매칭하는 로직은 절대 추가하지 않는다.
