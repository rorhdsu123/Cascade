#!/usr/bin/env python3
"""다음 결정 ID를 찍는다. 추측하지 말고 이걸 돌릴 것.

    python3 tools/next_id.py           # 현재 워크트리의 다음 ID
    python3 tools/next_id.py --list    # 이 트랙이 쓴 ID 전부

왜 있나: 전역 C번호 하나를 여러 세션이 나눠 쓰다가 2026-08-03 하루에만 세 번 겹쳤다.
정보가 없어서가 아니다 — `git log --all`이면 다 보인다. 문제는 **확인과 커밋 사이의 틈**이다.
두 세션이 같은 분에 각자 확인해도 둘 다 같은 번호를 읽는다. 그래서 수열을 트랙마다 쪼갰다:
자기 트랙 번호는 자기 브랜치에만 있으니 조율할 상대가 없다.

ID는 병합돼도 안 바뀐다 — 손잡이는 영구적이고, 접두사가 출처를 말해준다.
"""

import re
import subprocess
import sys

# 브랜치 → 접두사. 트렁크만 기존 C를 이어간다(C127까지 씀).
PREFIX = {
    "main": "C",
    "track/audio": "A",
    "track/juice": "J",
    "track/stage": "S",
    "track/endless": "E",
    "track/plumbing": "P",
    "track/haptic": "H",
    "track/color": "L",       # C가 트렁크 몫이라 L(color의 두 번째 글자 아님, 그냥 안 겹치는 글자)
}


def sh(*args: str) -> str:
    return subprocess.run(args, capture_output=True, text=True, check=True).stdout


def used_ids(prefix: str) -> set[int]:
    """전 브랜치의 커밋 제목에서 이 접두사의 번호를 긁는다.

    ⚠괄호 안만 본다. 제목 본문의 'P1 이음새', 'R13' 같은 말이 ID로 오인되면 안 되기 때문이다
    (실제로 juice의 "feat: P1 이음새 전량 … (C124)"가 plumbing의 P1로 잡혔을 뻔했다).
    괄호 안은 쉼표·물결·공백으로 쪼갠다 — "(C112~C114, C124)"·"(C121 재작업)" 같은 옛 표기 때문.
    """
    out = sh("git", "log", "--all", "--format=%s")
    found: set[int] = set()
    token = re.compile(rf"^{re.escape(prefix)}(\d+)$")
    for subject in out.splitlines():
        for group in re.findall(r"\(([^()]*)\)", subject):
            for piece in re.split(r"[,~\s]+", group):
                m = token.match(piece)
                if m:
                    found.add(int(m.group(1)))
    return found


def main() -> int:
    branch = sh("git", "rev-parse", "--abbrev-ref", "HEAD").strip()
    prefix = PREFIX.get(branch)
    if prefix is None:
        print(f"⚠ 모르는 브랜치입니다: {branch}", file=sys.stderr)
        print("  tools/next_id.py의 PREFIX 표에 글자를 하나 추가하세요"
              " (다른 트랙과 안 겹치는 글자면 무엇이든).", file=sys.stderr)
        return 1

    ids = used_ids(prefix)
    nxt = (max(ids) + 1) if ids else 1

    if "--list" in sys.argv:
        print(f"{branch} ({prefix}) 가 쓴 ID {len(ids)}개:")
        print("  " + (", ".join(f"{prefix}{i}" for i in sorted(ids)) if ids else "(아직 없음)"))
        print()

    print(f"{prefix}{nxt}")
    if "--list" not in sys.argv:
        print(f"  ({branch} 트랙 · 직전 = "
              f"{prefix + str(max(ids)) if ids else '없음(이 트랙 첫 번호)'})", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
