#!/usr/bin/env python3
"""산출물이 지금 소스로 구워진 것인지 검사한다 (C204).

    python3 tools/check_build_fresh.py build/web/index.pck

왜 있나 — 2026-08-14에 **낡은 빌드를 올려놓고 검증까지 통과시켰다.** 13:37에 구운 zip을
올렸는데 14:00에 계측 두 칸을 더 넣고 다시 굽지 않았다. 그런데 "라이브 pck == 로컬 pck"를
바이트로 대조해 통과 판정을 냈다 — **같다는 건 증명했지만 최신이라는 건 증명하지 못했다.**
낡은 로컬 산출물과 비교하면 언제나 통과한다. 게다가 버전을 안 올려서 내용이 다른 두 빌드가
똑같이 `0.9.0-L1.3`을 달았다.

그래서 비교 대상을 **소스**로 바꾼다. 산출물보다 나중에 고친 소스가 하나라도 있으면 실패다.
"""

import os
import subprocess
import sys

# 굽는 데 실제로 들어가는 것만 본다. `build/`·`docs/`·`tools/`는 산출물에 영향이 없다
# (⚠`tools/`가 예외로 보일 수 있지만 하네스일 뿐 export에 안 실린다 — preset의 exclude_filter).
WATCH_SUFFIX = (".gd", ".tscn", ".tres", ".godot", ".import", ".png", ".ttf", ".ogg", ".wav", ".txt")
SKIP_PREFIX = ("build/", "docs/", "tools/", "worktrees/", ".git/")


def tracked_files():
    out = subprocess.run(["git", "ls-files"], capture_output=True, text=True, check=True).stdout
    for line in out.splitlines():
        if line.startswith(SKIP_PREFIX):
            continue
        if line.endswith(WATCH_SUFFIX):
            yield line
    # ⚠git이 모르는 파일도 구워진다. 수집 주소가 그렇다(공개 저장소라 gitignore인데 export엔 실린다).
    #   빠뜨리면 "주소를 바꿨는데 왜 안 바뀌지"로 한참 헤맨다.
    for extra in ("analytics_endpoint.txt",):
        if os.path.exists(extra):
            yield extra


def main():
    if len(sys.argv) < 2:
        sys.exit("사용법: check_build_fresh.py <산출물 경로>")
    artifact = sys.argv[1]
    if not os.path.exists(artifact):
        sys.exit("산출물이 없다: %s" % artifact)

    built = os.path.getmtime(artifact)
    newer = []
    for f in tracked_files():
        try:
            m = os.path.getmtime(f)
        except OSError:
            continue
        if m > built:
            newer.append((m - built, f))

    import time
    stamp = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(built))
    print("산출물: %s  (%s)" % (artifact, stamp))
    if not newer:
        print("✅ 산출물이 모든 소스보다 새것이다 — 지금 소스로 구워졌다.")
        return 0

    newer.sort(reverse=True)
    print("🔴 산출물보다 나중에 고친 소스가 %d개 있다 = **낡은 빌드다. 다시 구울 것.**" % len(newer))
    for delta, f in newer[:10]:
        print("   +%5.1f분  %s" % (delta / 60.0, f))
    if len(newer) > 10:
        print("   … 외 %d개" % (len(newer) - 10))
    print("\n⚠다시 굽기 전에 `project.godot`의 `application/config/version` 끝자리도 올릴 것 —")
    print("  안 올리면 내용이 다른 두 빌드가 같은 이름을 달고, 데이터에서 구분이 안 된다.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
