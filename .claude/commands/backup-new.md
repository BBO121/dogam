CLAUDE.md의 **새로백업해줘** 규칙을 실행합니다.

1. `date` 명령어로 현재 날짜(MMDD)와 시각(HH-MM)을 확인한다.
2. `/root/dogam/backup/` 안에서 오늘 날짜(MMDD)가 포함된 폴더 수를 확인해 다음 버전 번호(V1, V2, V3...)를 결정한다.
3. `dogam_backup_MMDD_VN_HH-MM` 형식으로 새 폴더를 `/root/dogam/backup/` 안에 생성한다.
4. `/root/dogam/` 전체를 새 폴더로 복사한다. 단, `/root/dogam/backup/` 폴더는 제외한다.
5. 완료 후 생성된 폴더명을 보고한다.
