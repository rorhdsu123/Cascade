#!/usr/bin/env python3
"""계측기 자체를 검사한다 (C203).

    python3 tools/instrument_check.py 이벤트.csv
    python3 tools/instrument_check.py 이벤트.csv --since "2026-08-14 15:00"

`funnel.py`와 하는 일이 다르다. 저쪽은 **플레이어가 어땠나**를 읽고, 이쪽은 **자가 맞나**를 본다.

왜 필요한가 — 2026-08-14에 첫 코호트(10명)를 판독하다 계측 결함을 여섯 개 찾았는데, 그중 다섯이
"데이터가 틀렸다"가 아니라 **"데이터를 읽는 방식이 틀렸다"**였다(세션 정의 · 완주율 공식 ·
박자3의 성격 · 판독 단위 · 대시보드 문구). 숫자는 정직하게 쌓이는데 해석 장치가 어긋나 있었고,
그게 사람 8명을 쓰고 나서야 드러났다. **표본을 쓰기 전에 자를 재는 절차**가 없었던 게 원인이다.

그래서 새 빌드를 낼 때마다 개발자가 혼자 몇 판 돌리고 이 검사를 통과시킨 뒤에 사람을 부른다.
"""

import argparse
import csv
import json
import sys
from collections import Counter, defaultdict
from datetime import datetime


def load(path):
    rows = []
    with open(path, newline="", encoding="utf-8-sig") as f:
        for r in csv.DictReader(f):
            ev = {}
            if r.get("원본"):
                try:
                    ev.update(json.loads(r["원본"]))
                except json.JSONDecodeError:
                    pass
            ev["_received"] = r.get("받은시각", "")
            rows.append(ev)
    return rows


def parse_time(v):
    s = str(v).strip().replace("T", " ")
    for fmt in ("%Y-%m-%d %H:%M:%S", "%Y. %m. %d %H:%M:%S", "%Y-%m-%d %H:%M",
                "%Y. %m. %d %H:%M", "%Y-%m-%d", "%Y. %m. %d"):
        try:
            return datetime.strptime(s, fmt)
        except ValueError:
            continue
    return None


def truthy(v):
    return v in (True, 1, "TRUE", "true", "True", "1")


class Report:
    def __init__(self):
        self.fail = 0
        self.warn = 0

    def ok(self, label, detail=""):
        print("  ok   %s%s" % (label, ("  — " + detail) if detail else ""))

    def bad(self, label, detail=""):
        self.fail += 1
        print("  FAIL %s%s" % (label, ("  — " + detail) if detail else ""))

    def note(self, label, detail=""):
        self.warn += 1
        print("  ⚠    %s%s" % (label, ("  — " + detail) if detail else ""))


def main():
    ap = argparse.ArgumentParser(description="계측기 건강 검사")
    ap.add_argument("path")
    ap.add_argument("--since", help='이 시각 이후만 (예: "2026-08-14 15:00")')
    ap.add_argument("--build", help="이 빌드만")
    args = ap.parse_args()

    evs = load(args.path)
    if args.since:
        t0 = parse_time(args.since)
        if t0 is None:
            sys.exit("--since 를 못 읽었다: %s" % args.since)
        evs = [e for e in evs if (parse_time(e["_received"]) or datetime.min) >= t0]
    if args.build:
        evs = [e for e in evs if e.get("build_version") == args.build]
    if not evs:
        sys.exit("조건에 맞는 이벤트가 없다.")

    builds = Counter(e.get("build_version") for e in evs)
    print("── %d 이벤트 · 빌드 %s ──" % (len(evs), dict(builds)))
    r = Report()

    # ① 기기 종류가 붙나 — 이게 없으면 폰만 겪는 문제를 영영 못 가른다
    print("\n[1] 기기 구분")
    miss = [e for e in evs if "touch" not in e]
    if miss:
        r.bad("모든 이벤트에 touch", "%d건 누락 (C198 이전 빌드가 섞였다)" % len(miss))
    else:
        r.ok("모든 이벤트에 touch")
    split = Counter(truthy(e.get("touch")) for e in evs if "touch" in e)
    print("       폰(터치) %d · PC %d" % (split.get(True, 0), split.get(False, 0)))
    if len(split) < 2:
        r.note("한 종류만 있다", "폰·PC 양쪽에서 한 번씩 돌려야 이 칸이 검증된다")

    # ② 첫 실행이 사람당 한 번인가 — 옛 버그는 한 페이지 로드의 모든 세션에 true를 달았다
    print("\n[2] is_first_session")
    firsts = defaultdict(int)
    for e in evs:
        if e.get("event") == "app_opened" and truthy(e.get("is_first_session")):
            firsts[e.get("install_id")] += 1
    dup = {k: v for k, v in firsts.items() if v > 1}
    if dup:
        r.bad("사람당 최대 1회", "%s ← 옛 버그(C198 이전) 재발" % {k[:10]: v for k, v in dup.items()})
    else:
        r.ok("사람당 최대 1회", "첫 실행 %d명" % len(firsts))

    # ③ resumed가 붙나 — 파편과 진짜 재방문을 가르는 칸
    print("\n[3] resumed")
    opened = [e for e in evs if e.get("event") == "app_opened"]
    if opened and all("resumed" not in e for e in opened):
        r.bad("app_opened에 resumed", "%d건 전부 없다" % len(opened))
    else:
        n_res = sum(1 for e in opened if truthy(e.get("resumed")))
        r.ok("app_opened에 resumed", "복귀로 열린 세션 %d/%d" % (n_res, len(opened)))

    # ④ 세션이 조각나지 않았나 — 이 수정의 본체
    print("\n[4] 세션 파편화")
    dur = [float(e["duration_ms"]) for e in evs
           if e.get("event") == "session_ended" and e.get("duration_ms") not in (None, "")]
    per_install = defaultdict(set)
    for e in evs:
        per_install[e.get("install_id")].add(e.get("session_id"))
    if dur:
        tiny = sum(1 for d in dur if d < 4000)
        dur.sort()
        med = dur[len(dur) // 2] / 1000.0
        detail = "세션 %d · 중앙값 %.0f초 · 4초 미만 %d건" % (len(dur), med, tiny)
        if tiny > len(dur) * 0.25:
            r.bad("짧은 파편이 넘친다", detail + " ← 유예가 안 걸렸다")
        else:
            r.ok("짧은 파편 적음", detail)
    spm = {k: len(v) for k, v in per_install.items()}
    worst = max(spm.values()) if spm else 0
    print("       사람당 세션: %s" % {k[:10]: v for k, v in sorted(spm.items(), key=lambda x: -x[1])[:5]})
    if worst >= 5:
        r.note("한 사람이 세션 %d개" % worst, "의도한 재방문인지 파편인지 resumed로 확인할 것")

    # ⑤ 튜토리얼 분모 — 완주율을 재려면 이 칸이 있어야 한다
    print("\n[5] 튜토리얼")
    runs = [e for e in evs if e.get("event") == "run_started"]
    stage_runs = [e for e in runs if str(e.get("stage_id", "")) != ""]
    if stage_runs and all("is_tutorial" not in e for e in stage_runs):
        r.bad("run_started에 is_tutorial", "%d건 전부 없다 (C201 이전 빌드)" % len(stage_runs))
    elif stage_runs:
        n = sum(1 for e in stage_runs if truthy(e.get("is_tutorial")))
        r.ok("run_started에 is_tutorial", "튜토리얼 진입 %d/%d판" % (n, len(stage_runs)))
    else:
        r.note("스테이지 판이 없다", "캠페인을 한 번은 돌려야 이 칸이 검증된다")

    beats = [e for e in evs if e.get("event") == "tutorial_beat_completed"]
    b3 = [e for e in beats if str(e.get("beat")) == "3"]
    if b3 and not all(truthy(e.get("optional")) for e in b3):
        r.bad("박자3에 optional", "표시가 없으면 또 퍼널로 오독된다")
    elif b3:
        r.ok("박자3에 optional", "%d건" % len(b3))
    else:
        r.note("박자3이 안 떴다", "적을 한 번 통과시켜야 뜬다 — 안 떠도 정상이다")
    for b in (1, 2):
        n = sum(1 for e in beats if str(e.get("beat")) == str(b))
        print("       박자%d: %d건" % (b, n))

    # ⑥ 회계 — 시작한 판이 끝났나
    print("\n[6] 판 회계")
    started = sum(1 for e in evs if e.get("event") == "run_started")
    ended = sum(1 for e in evs if e.get("event") in ("run_failed", "stage_cleared", "endless_run_ended"))
    if started and ended < started * 0.5:
        r.note("끝이 안 찍힌 판이 많다", "시작 %d · 종료 %d (판 도중 이탈)" % (started, ended))
    else:
        r.ok("판 시작/종료", "시작 %d · 종료 %d" % (started, ended))

    # ⑦ 택소노미 밖 이름
    print("\n[7] 이벤트 이름")
    unknown = Counter(e.get("event") for e in evs if truthy(e.get("unknown_event")))
    if unknown:
        r.bad("택소노미 밖 이름", str(dict(unknown)))
    else:
        r.ok("택소노미 밖 이름 없음")

    print("\n%s (실패 %d · 주의 %d)" % ("PASS" if r.fail == 0 else "FAIL", r.fail, r.warn))
    return 0 if r.fail == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
