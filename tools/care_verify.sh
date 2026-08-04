#!/bin/bash
# care_verify.sh — care_verify.gd를 실유저 진행도를 지키면서 돌린다.
#
# 왜 래퍼가 필요한가: ⑥ 영속 항목은 진짜 user://campaign.save에 쓴다. Godot에는 유저 데이터
#   디렉터리를 바꾸는 실행 플래그가 없어서(4.6 확인) 백업·복원 말고는 격리 수단이 없다.
#   이 저장소는 하네스가 실유저 세이브를 덮은 사고를 이미 한 번 겪었다.
# 워크트리마다 앱 이름이 갈려서 폴더가 둘이다(BlockCastle·Cascade) → 양쪽 다 지킨다.
set -u
BASE="$HOME/Library/Application Support/Godot/app_userdata"
DIRS=("$BASE/BlockCastle" "$BASE/Cascade")
TMP=$(mktemp -d)
declare -a SAVED=()

for d in "${DIRS[@]}"; do
  f="$d/campaign.save"
  if [ -f "$f" ]; then
    cp -p "$f" "$TMP/$(basename "$d").save"
    SAVED+=("$d")
    echo "[백업] $f"
  fi
done

godot --headless --path . --script tools/care_verify.gd 2>&1 \
  | grep -v "^ERROR\|^WARNING\|^   at:\|backtrace\|^       \["
RC=${PIPESTATUS[0]}

for d in "${SAVED[@]}"; do
  b="$TMP/$(basename "$d").save"
  cp -p "$b" "$d/campaign.save"
  echo "[복원] $d/campaign.save"
done
rm -rf "$TMP"          # 백업은 쓰고 바로 폐기 — 남겨두면 다음에 낡은 걸 덮어쓴다
exit $RC
