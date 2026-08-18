#!/usr/bin/env python3
"""웹 플레이테스트 이탈 퍼널 판독기 (C190).

    python3 tools/funnel.py 이벤트.csv
    python3 tools/funnel.py 이벤트.csv --build 0.9.0-L1.1      # 한 루프만
    python3 tools/funnel.py 이벤트.csv --keep-mine             # 내 방문까지 섞어서(대볼 때만)
    python3 tools/funnel.py ~/…/analytics.jsonl                # 로컬 로그도 읽는다

**내가 확인한 방문은 기본으로 뺀다** — `tools/funnel_ignore.txt`에 적힌 install_id다(C206).
`probe-`만 걸러서는 안 걸린다. 내가 브라우저로 라이브를 열면 낯선 사람과 같은 모양의 id가 찍히기
때문이다. 뺐다는 사실은 화면 맨 위에 늘 찍는다 — 조용히 빼면 반대 방향의 같은 사고가 난다.

`tools/analytics_report.gd`와 **읽는 데이터가 다르다.** 그쪽은 기기에 쌓인 `analytics.jsonl`을
보고, 이쪽은 **구글 시트에 모인 남의 기기 데이터**를 본다. 웹 루프의 자료는 전부 시트로 오므로
(비콘 경로, C182) 루프 1~3 판독은 이 도구가 맡는다.
시트에서 꺼내는 법: 이벤트 시트 → 파일 → 다운로드 → CSV.

왜 따로 만들었나 — **시트 수식으로는 세션 단위를 셀 수 없다.** `COUNTIF(D:D,"run_started")`는
'판을 몇 번 시작했나'지 '몇 세션이 판을 시작했나'가 아니다. 한 사람이 다섯 판을 하면 다섯으로
세어져서, 퍼널의 아래 칸이 위 칸보다 커지는 일이 생긴다. 퍼널은 **각 단계에 도달한 세션 수**로만
말이 되고, 그건 세션별로 접어야 나온다.

⚠이 도구는 판정하지 않는다. 통과선은 `docs/ROADMAP.md` §3-C에 있고, 그걸 들이대는 건 사람이다.
"""

import argparse
import csv
import json
import os
import sys
from collections import Counter, defaultdict
from datetime import datetime, timedelta

# 시트 열 이름 → 이벤트 필드 이름. 시트는 사람이 읽는 표라 한글이고, 로컬 JSONL은 원본 필드명이다.
# 어느 쪽으로 들어오든 아래 필드 이름 하나로 통일해서 다룬다.
SHEET_COLUMNS = {
    "받은시각": "received_at",
    "install_id": "install_id",
    "session_id": "session_id",
    "이벤트": "event",
    "빌드": "build_version",
    "플랫폼": "platform",
    "모드": "mode",
    "t_ms": "t_ms",
    "duration_ms": "duration_ms",
    "runs_played": "runs_played",
    "stage_id": "stage_id",
    "cause": "cause",
    "beat": "beat",
    "max_combo": "max_combo",
}

SURVIVE_MS = 60_000  # 루프 1이 묻는 것 — "낯선 사람이 60초를 넘기나"

# 내 자신의 방문을 빼는 목록. 옆에 두고 같이 옮겨 다녀야 하므로 이 파일 기준으로 찾는다.
IGNORE_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "funnel_ignore.txt")


# ── 읽기 ───────────────────────────────────────────────────────────────────

def _num(v):
    if v is None or v == "":
        return None
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


def read_mine(path=IGNORE_PATH):
    """`funnel_ignore.txt` — 내가 확인하며 찍은 install_id. 한 줄에 하나, `#` 뒤는 설명.

    ⚠**없으면 조용히 넘어가지 않는다.** 파일이 사라진 채로 읽으면 내 방문이 표본에 섞인 숫자가
    나오는데, 그게 정확히 2026-08-17에 잡은 사고다(217행 중 71행이 내 것이었다). 그래서 없을 때는
    빈 집합을 돌려주되 부른 쪽이 그 사실을 화면에 찍는다."""
    if not os.path.exists(path):
        return set(), False
    out = set()
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.split("#", 1)[0].strip()
            if line:
                out.add(line)
    return out, True


def read_csv(path):
    """시트에서 내려받은 CSV. 마지막 '원본' 열에 이벤트 전체가 JSON으로 들어 있어서,
    시트가 열로 안 뽑아 둔 필드(is_first_session 등)도 여기서 되살릴 수 있다."""
    out = []
    with open(path, newline="", encoding="utf-8-sig") as f:
        for row in csv.DictReader(f):
            ev = {}
            raw = row.get("원본")
            if raw:
                try:
                    ev.update(json.loads(raw))
                except json.JSONDecodeError:
                    pass  # 원본이 깨졌어도 아래 열들로 대부분 복구된다
            for col, field in SHEET_COLUMNS.items():
                if row.get(col) not in (None, ""):
                    ev[field] = row[col]
            out.append(ev)
    return out


def read_jsonl(path):
    out = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                try:
                    out.append(json.loads(line))
                except json.JSONDecodeError:
                    pass
    return out


def parse_time(v):
    if not v:
        return None
    s = str(v).strip().replace("T", " ")
    # ⚠구글 시트 한국 로케일은 `2026. 8. 13 14:05:01`처럼 점과 공백을 섞어 내보낸다. 그리고
    #   열 서식이 날짜만이면 **시각이 통째로 빠진 채** 떨어진다(2026-08-14에 실제로 막혔다) —
    #   그때는 방문 병합이 '같은 날' 단위로 내려앉는다.
    for fmt in ("%Y-%m-%d %H:%M:%S.%f", "%Y-%m-%d %H:%M:%S", "%Y-%m-%d %H:%M",
                "%Y. %m. %d %H:%M:%S", "%Y. %m. %d %H:%M", "%Y. %m. %d",
                "%m/%d/%Y %H:%M:%S"):
        try:
            return datetime.strptime(s.split("+")[0].strip(), fmt)
        except ValueError:
            continue
    return None


# ── 세션으로 접기 ──────────────────────────────────────────────────────────

class Session:
    __slots__ = ("sid", "install", "build", "platform", "events", "duration_ms",
                 "runs_played", "max_t_ms", "ended", "first_seen", "modes",
                 "touch", "resumed", "first_session", "paused_ms", "paused_runs")

    def __init__(self, sid):
        self.sid = sid
        self.install = ""
        self.build = ""
        self.platform = ""
        self.events = Counter()
        self.duration_ms = None
        self.runs_played = None
        self.max_t_ms = 0.0
        self.ended = False
        self.first_seen = None
        self.modes = set()
        self.touch = None        # True/False/None(옛 빌드 = 필드 없음)
        self.resumed = False     # 자리 비웠다 돌아와 열린 세션인가
        self.first_session = False
        self.paused_ms = None      # 마지막 session_paused 스냅샷(탭을 안 닫고 떠난 사람용)
        self.paused_runs = None

    @property
    def lived_ms(self):
        """머문 시간. `session_ended`가 있으면 그 값이 정답이다.

        없으면 **마지막 `session_paused` 스냅샷**을 쓴다 — 폰에서 탭을 안 닫고 홈으로 내린
        사람이 그렇다(C205). 그것도 없으면 마지막 `t_ms`인데, 이건 **하한**이다(마지막 이벤트
        이후에 더 놀다 나갔을 수 있다). 그래서 아래 표가 대체한 세션 수를 따로 찍는다.
        웹에서 `session_ended`가 통째로 빠지는 건 실제로 겪은 사고다(C182·C205)."""
        if self.duration_ms is not None:
            return self.duration_ms
        if self.paused_ms is not None:
            return self.paused_ms
        return self.max_t_ms

    @property
    def runs(self):
        """판 수. `session_ended.runs_played`가 정답이고, 없으면 `run_started`를 센다."""
        if self.runs_played is not None:
            return int(self.runs_played)
        if self.paused_runs is not None:
            return int(self.paused_runs)
        return self.events["run_started"]


def fold(events):
    sessions = {}
    for ev in events:
        sid = str(ev.get("session_id") or "")
        if not sid:
            continue
        s = sessions.get(sid)
        if s is None:
            s = sessions[sid] = Session(sid)
        name = str(ev.get("event") or "")
        s.events[name] += 1
        s.install = s.install or str(ev.get("install_id") or "")
        s.build = s.build or str(ev.get("build_version") or "")
        s.platform = s.platform or str(ev.get("platform") or "")
        if ev.get("mode"):
            s.modes.add(str(ev["mode"]))
        t = _num(ev.get("t_ms"))
        if t is not None:
            s.max_t_ms = max(s.max_t_ms, t)
        when = parse_time(ev.get("received_at"))
        if when and (s.first_seen is None or when < s.first_seen):
            s.first_seen = when
        if ev.get("touch") is not None:
            s.touch = bool(ev["touch"]) if not isinstance(ev["touch"], str) \
                else ev["touch"].strip().lower() in ("true", "1")
        if name == "app_opened":
            if ev.get("resumed") in (True, "TRUE", "true", "1"):
                s.resumed = True
            if ev.get("is_first_session") in (True, "TRUE", "true", "1"):
                s.first_session = True
        if name == "session_paused":
            # 여러 번 온다(가려질 때마다). **마지막 것**이 그 세션의 최신 상태다.
            d = _num(ev.get("duration_ms"))
            if d is not None and (s.paused_ms is None or d > s.paused_ms):
                s.paused_ms = d
            rp = _num(ev.get("runs_played"))
            if rp is not None and (s.paused_runs is None or rp > s.paused_runs):
                s.paused_runs = rp
        if name == "session_ended":
            s.ended = True
            d = _num(ev.get("duration_ms"))
            if d is not None:
                s.duration_ms = d
            r = _num(ev.get("runs_played"))
            if r is not None:
                s.runs_played = r
    return list(sessions.values())



# ── 방문으로 접기 ──────────────────────────────────────────────────────────

VISIT_GAP_MIN = 5   # analytics.gd SESSION_GRACE_MS와 같은 값으로 둔다(둘이 다르면 해석이 어긋난다)


class Visit:
    """한 사람의 한 번 앉음. **세션이 아니라 이게 판정 단위다.**

    왜 필요한가 — 폰은 화면 잠금·알림·앱 전환마다 세션이 끊긴다. 2026-08-13 첫 코호트에서
    세션 33건 중 12건이 4초 미만이었고, 한 사람이 하루에 11개를 만들었다. 그 파편을 분모에
    넣으면 "한 판도 안 한 세션 69.7%"처럼 **사람 행동과 무관한 숫자**가 나온다(방문으로 접으면
    18%다). C198이 게임 쪽에서 유예를 넣었지만, **그 전에 쌓인 데이터는 여기서 되붙여야 한다.**

    ⚠`received_at`에 시각이 없으면(시트 열 서식이 날짜만인 경우) 같은 날 = 한 방문으로
      내려앉는다. 거친 근사이므로 그때는 그렇게 찍어 알린다."""

    __slots__ = ("install", "sessions", "day", "coarse")

    def __init__(self, install, day, coarse):
        self.install = install
        self.sessions = []
        self.day = day
        self.coarse = coarse

    # funnel()이 세션과 같은 얼굴로 다룰 수 있게 맞춘다
    @property
    def lived_ms(self):
        return sum(x.lived_ms for x in self.sessions)

    @property
    def runs(self):
        return sum(x.runs for x in self.sessions)

    @property
    def events(self):
        c = Counter()
        for x in self.sessions:
            c.update(x.events)
        return c

    @property
    def ended(self):
        return any(x.ended for x in self.sessions)

    @property
    def build(self):
        b = sorted({x.build for x in self.sessions if x.build})
        return b[-1] if b else ""

    @property
    def touch(self):
        for x in self.sessions:
            if x.touch is not None:
                return x.touch
        return None


def fold_visits(sessions, gap_min=VISIT_GAP_MIN):
    by_install = defaultdict(list)
    for s in sessions:
        by_install[s.install or "(없음)"].append(s)

    visits = []
    coarse_any = False
    for install, group in by_install.items():
        timed = [s for s in group if s.first_seen is not None]
        untimed = [s for s in group if s.first_seen is None]
        # 시각이 아예 없으면 묶을 근거가 없다 — 통째로 한 방문으로 본다(과소 계산 쪽으로 튄다)
        if untimed:
            v = Visit(install, None, True)
            v.sessions = untimed
            visits.append(v)
            coarse_any = True
        timed.sort(key=lambda s: s.first_seen)
        cur = None
        for s in timed:
            # 시각이 00:00:00뿐이면 날짜만 있는 것이다 → 같은 날끼리 묶는 거친 모드
            same_visit = (cur is not None
                          and (s.first_seen - cur.sessions[-1].first_seen).total_seconds() <= gap_min * 60)
            if cur is not None and s.first_seen.time() == cur.sessions[-1].first_seen.time() == \
                    datetime.min.time():
                same_visit = s.first_seen.date() == cur.sessions[-1].first_seen.date()
                cur.coarse = True
                coarse_any = True
            if same_visit:
                cur.sessions.append(s)
            else:
                cur = Visit(install, s.first_seen.date(), False)
                cur.sessions.append(s)
                visits.append(cur)
    return visits, coarse_any


def touch_split(units):
    """폰인가 PC인가. 이 칸이 없으면 폰만 겪는 문제를 데이터로 못 가른다(C198에서 추가)."""
    g = defaultdict(list)
    for u in units:
        g[{True: "폰(터치)", False: "PC", None: "모름(옛 빌드)"}[u.touch]].append(u)
    if len(g) <= 1 and "모름(옛 빌드)" in g:
        print("\n── 기기 ──\n  전부 `touch` 필드가 없는 옛 빌드다 — 폰/PC를 가를 수 없다(C198 이후 빌드부터 나온다).")
        return
    print("\n── 기기별 (방문 단위) ──")
    print("  %-14s %5s %9s %9s %10s" % ("기기", "방문", "첫판시작", "60초넘김", "판2회+"))
    for k in ("폰(터치)", "PC", "모름(옛 빌드)"):
        if k not in g:
            continue
        u = g[k]
        n = len(u)
        print("  %-14s %5d %8.0f%% %8.0f%% %9.0f%%" % (
            k, n,
            100.0 * sum(1 for x in u if x.runs >= 1) / n,
            100.0 * sum(1 for x in u if x.lived_ms >= SURVIVE_MS) / n,
            100.0 * sum(1 for x in u if x.runs >= 2) / n))


# ── 출력 ───────────────────────────────────────────────────────────────────

def bar(frac, width=24):
    n = int(round(frac * width))
    return "█" * n + "·" * (width - n)


def funnel(sessions, unit="세션"):
    total = len(sessions)
    # ⚠**순서가 인과 순서여야 한다.** 처음엔 "세션 → 60초 → 첫 판"으로 짰는데, 첫 실측에서
    #   60초 0세션인데 첫 판 1세션이 나왔다 — 봇이 60초 안에 여러 판을 굴렸기 때문이다.
    #   아래 칸이 위 칸보다 큰 표는 퍼널이 아니다. 판을 먼저 시작하고 그다음 1분을 넘기는 게
    #   실제 순서라 그렇게 고쳤다.
    # ⚠그리고 **누적으로 센다** — 각 칸은 '앞 칸을 전부 통과한 세션'이다. 독립 술어로 세면
    #   중간을 건너뛴 세션이 아래 칸에 되살아나서, 이 도구를 만든 이유가 사라진다.
    steps = [
        ("시작",            lambda s: True),
        ("첫 판 시작",      lambda s: s.runs >= 1),
        ("60초 넘김",       lambda s: s.lived_ms >= SURVIVE_MS),
        ("첫 클리어",       lambda s: s.events["stage_cleared"] >= 1),
        ("두 번째 판",      lambda s: s.runs >= 2),
    ]
    print("\n── 이탈 퍼널 (%s 단위·누적) ──" % unit)
    print("  %-12s %6s %8s %8s   %-24s %s" % ("단계", unit, "직전대비", "전체대비", "", "단독"))
    prev = None
    rows = []
    alive = list(sessions)
    for label, hit in steps:
        alive = [s for s in alive if hit(s)]
        n = len(alive)
        solo = sum(1 for s in sessions if hit(s))   # 앞 칸을 무시하고 이 조건만 만족한 세션
        rows.append((label, n))
        of_prev = "—" if prev in (None, 0) else "%5.0f%%" % (100.0 * n / prev)
        of_top = "—" if total == 0 else "%5.0f%%" % (100.0 * n / total)
        frac = 0.0 if total == 0 else n / total
        # '단독'은 누적이 감춘 것을 드러낸다 — 앞 칸에서 떨어졌지만 이 조건 자체는 만족한 세션.
        mark = "" if solo == n else "  %d" % solo
        print("  %-12s %6d %8s %8s   %-24s%s" % (label, n, of_prev, of_top, bar(frac), mark))
        prev = n

    # 가장 크게 꺾이는 칸 = 고칠 자리. 눈으로 표를 훑는 대신 도구가 지목한다.
    worst, worst_drop = None, -1
    for (a_label, a), (b_label, b) in zip(rows, rows[1:]):
        if a > 0:
            drop = (a - b) / a
            if drop > worst_drop:
                worst, worst_drop = (a_label, b_label, a - b, drop), drop
    if worst and worst[2] > 0:
        print("\n  ⇒ 가장 크게 꺾이는 곳: %s → %s 에서 %d%s(%.0f%%)이 빠진다."
              % (worst[0], worst[1], worst[2], unit, 100.0 * worst[3]))

    est = sum(1 for s in sessions if not s.ended and getattr(s, "paused_ms", None) is None)
    if est:
        print("  ⚠%d%s은 `session_ended`가 없어 마지막 t_ms로 대신했다(체류는 하한값)."
              % (est, unit))
        if total and est / total > 0.2:
            print("    비율이 20%를 넘는다 — 비콘 경로부터 의심할 것(C182와 같은 사고).")


def exits(sessions, top=8):
    """세션의 마지막 이벤트 분포. 어디서 손을 떼는지에 대한 가장 직접적인 신호다.
    ⚠`session_ended`로 끝난 건 '정상 종료'라 제외한다 — 그건 이탈 지점이 아니라 종료 그 자체다."""
    last = Counter()
    for s in sessions:
        names = [n for n in s.events if n != "session_ended"]
        if not names:
            continue
        # 이벤트 순서를 세션 안에서 다시 세울 만큼의 정보(t_ms)는 접는 과정에서 버렸다.
        # 여기서는 '그 세션이 도달한 가장 깊은 사건'을 근사로 쓴다.
        for depth_name in ("endless_run_ended", "stage_cleared", "stage_failed",
                           "run_failed", "first_line_cleared", "run_started",
                           "tutorial_beat_completed", "app_opened"):
            if s.events[depth_name]:
                last[depth_name] += 1
                break
    if not last:
        return
    print("\n── 가장 깊이 도달한 사건 (세션 수) ──")
    for name, n in last.most_common(top):
        print("  %-24s %4d" % (name, n))


def onboarding(sessions, beats_by_sid, tut_sids, s1_clear_sids):
    """튜토리얼 완주 = **박자2**다(거기서 tut_phase가 0이 되며 끝난다).

    🔴박자3을 여기 세우지 않는다. 그건 과제가 아니라 **사건**이다 — 적을 한 번 통과시켜야 뜨고
    잘 하면 영영 안 뜬다. 2026-08-14에 옛 표(1·2·3 세로 나열 + "줄어드는 폭이 곧 이탈")를 믿고
    10→9→4를 "박자3이 벽"으로 읽었는데, **박자3이 뜬 4세션은 전원 스테이지1을 깼다.**"""
    n0 = len(tut_sids)
    b1 = sum(1 for sid in beats_by_sid if 1 in beats_by_sid[sid])
    b2 = sum(1 for sid in beats_by_sid if 2 in beats_by_sid[sid])
    b3 = sum(1 for sid in beats_by_sid if 3 in beats_by_sid[sid])
    print("\n── 온보딩 (튜토리얼을 끝냈나) ──")
    pct = lambda k: "—" if n0 == 0 else "%5.0f%%" % (100.0 * k / n0)
    for label, k in [("튜토리얼 진입", n0), ("박자1 — 배치", b1),
                     ("박자2 — 처치 = 완주", b2), ("스테이지1 클리어", len(s1_clear_sids))]:
        print("  %-20s %4d  %s" % (label, k, pct(k)))
    print("  %-20s %4d  %s   ← 사건. 낮은 건 나쁜 게 아니다(안 뚫렸다는 뜻일 수 있다)"
          % ("박자3 — 손해 학습", b3, pct(b3)))
    print("  %-20s %4d"
          % ("첫 줄 지움", sum(1 for s in sessions if s.events["first_line_cleared"])))


def revisits(sessions):
    """루프 3이 묻는 것 — 다음 날 오나.
    ⚠`받은시각`이 있어야 계산된다 = **시트 CSV로만 나온다.** 로컬 JSONL엔 절대 시각이 없다."""
    by_install = defaultdict(list)
    for s in sessions:
        if s.install and s.first_seen:
            by_install[s.install].append(s.first_seen)
    if not by_install:
        print("\n── 재방문 ──\n  절대 시각이 없어 계산 불가(시트 CSV로 다시 읽을 것).")
        return
    multi = d1 = 0
    for times in by_install.values():
        times.sort()
        if len(times) >= 2:
            multi += 1
        first = times[0]
        # D1 = 첫 방문 **다음 날 이후**에 다시 온 사람. 같은 날 두 번은 재방문이지 복귀가 아니다.
        if any(t.date() >= (first + timedelta(days=1)).date() for t in times[1:]):
            d1 += 1
    n = len(by_install)
    print("\n── 재방문 (사람 단위, n=%d) ──" % n)
    print("  세션 2회 이상   %4d  (%.0f%%)" % (multi, 100.0 * multi / n))
    print("  다음 날 이후 복귀 %2d  (%.0f%%)  ← 웹 D1" % (d1, 100.0 * d1 / n))
    if n < 30:
        print("  ⚠표본 %d명은 비율로 읽기엔 작다 — 한 명이 %.0f%%p를 흔든다." % (n, 100.0 / n))


def by_build(sessions):
    """빌드별 비교 = 처방 전후 비교. 빌드를 안 올리고 재배포하면 여기서 한 줄로 합쳐진다."""
    groups = defaultdict(list)
    for s in sessions:
        groups[s.build or "(없음)"].append(s)
    if len(groups) < 2:
        return
    print("\n── 빌드별 ──")
    print("  %-18s %6s %9s %9s %10s" % ("빌드", "세션", "60초넘김", "판/세션", "두번째판"))
    for build in sorted(groups):
        g = groups[build]
        n = len(g)
        surv = sum(1 for s in g if s.lived_ms >= SURVIVE_MS)
        second = sum(1 for s in g if s.runs >= 2)
        avg = sum(s.runs for s in g) / n
        print("  %-18s %6d %8.0f%% %9.2f %9.0f%%"
              % (build, n, 100.0 * surv / n, avg, 100.0 * second / n))
    if "0.0.0-dev" in groups:
        print("  ⚠`0.0.0-dev`가 섞여 있다 — 루프 구분이 안 되는 줄이다(C186 이전 빌드).")


# ── 진입점 ─────────────────────────────────────────────────────────────────

def main():
    ap = argparse.ArgumentParser(description="웹 플레이테스트 이탈 퍼널 판독기")
    ap.add_argument("path", help="시트에서 내려받은 CSV, 또는 analytics.jsonl")
    ap.add_argument("--build", help="이 빌드만 본다(루프 하나만 떼어 읽을 때)")
    ap.add_argument("--platform", help="이 플랫폼만 본다 (web / android / …)")
    ap.add_argument("--keep-probe", action="store_true",
                    help="install_id가 probe-로 시작하는 시험 줄도 포함한다")
    ap.add_argument("--keep-mine", action="store_true",
                    help="tools/funnel_ignore.txt에 적힌 내 방문도 포함한다(앞뒤를 대볼 때)")
    args = ap.parse_args()

    if not os.path.exists(args.path):
        sys.exit("파일이 없다: %s" % args.path)

    events = read_jsonl(args.path) if args.path.endswith(".jsonl") else read_csv(args.path)
    if not events:
        sys.exit("이벤트가 없다: %s" % args.path)

    sessions = fold(events)
    total_before = len(sessions)
    if not args.keep_probe:
        # 우리가 배관을 시험하며 넣은 줄이 첫 측정에 섞이면 표본이 조용히 오염된다.
        sessions = [s for s in sessions if not s.install.startswith("probe-")]

    # 🔴내 방문도 같은 이유로 뺀다. `probe-`만 걸러서는 안 걸린다 — 내가 그냥 브라우저로 라이브를
    #   열면 낯선 사람과 똑같은 모양의 install_id가 찍히기 때문이다(2026-08-17에 잡음).
    mine, have_list = read_mine()
    mine_sessions = mine_people = 0
    if not args.keep_mine and mine:
        before = len(sessions)
        mine_people = len({s.install for s in sessions if s.install in mine})
        sessions = [s for s in sessions if s.install not in mine]
        mine_sessions = before - len(sessions)

    if args.build:
        sessions = [s for s in sessions if s.build == args.build]
    if args.platform:
        sessions = [s for s in sessions if s.platform == args.platform]

    if not sessions:
        sys.exit("걸러내고 나니 세션이 없다(원본 %d세션). 조건을 확인할 것." % total_before)

    installs = {s.install for s in sessions if s.install}
    dropped = total_before - len(sessions)
    print("── %s ──" % args.path)
    print("  이벤트 %d · 세션 %d · 사람 %d%s"
          % (len(events), len(sessions), len(installs),
             ("  (제외 %d세션)" % dropped) if dropped else ""))

    # ⚠뺐다는 것은 **반드시 화면에 남긴다.** 조용히 빼면 지금 고친 버그와 같은 종류의 사고가
    #   반대 방향으로 난다 — 낯선 사람을 내 것으로 잘못 적어 두고도 아무도 모르게 된다.
    if mine_sessions:
        print("  ⓘ내 방문 %d명 · %d세션을 뺐다 (%s). 포함해서 보려면 --keep-mine"
              % (mine_people, mine_sessions, os.path.basename(IGNORE_PATH)))
    elif args.keep_mine and mine:
        print("  ⚠--keep-mine — 내 방문 %d명이 **섞인 채**로 읽는다. 판정에 쓰지 말 것." % len(mine))
    elif not have_list:
        print("  ⚠%s 가 없다 — 내 방문이 안 걸러진 숫자다. 판정 전에 만들 것."
              % os.path.basename(IGNORE_PATH))

    visits, coarse = fold_visits(sessions)
    print("  → 방문 %d건으로 접었다 (세션 %d → 방문 %d, 유예 %d분)"
          % (len(visits), len(sessions), len(visits), VISIT_GAP_MIN))
    if coarse:
        print("  ⚠일부는 시각이 없어 **같은 날 = 한 방문**으로 접었다(거친 근사). "
              "시트 '받은시각' 열 서식에 시각을 넣을 것.")

    # 🔴판정 단위는 **방문**이다. 세션은 폰에서 한 앉음이 조각나므로 사람 행동을 못 나타낸다.
    #   세션 퍼널도 같이 찍는 건 둘이 얼마나 벌어지는지가 곧 파편화의 크기이기 때문이다.
    funnel(visits, unit="방문")
    touch_split(visits)
    print("\n(참고) 같은 자료를 세션 단위로 보면 —")
    funnel(sessions, unit="세션")
    exits(sessions)
    beats_by_sid = defaultdict(set)
    tut_sids, s1_clear_sids = set(), set()
    for ev in events:
        sid = str(ev.get("session_id") or "")
        name = str(ev.get("event") or "")
        if name == "tutorial_beat_completed" and ev.get("beat") not in (None, ""):
            beats_by_sid[sid].add(int(float(ev["beat"])))
        elif name == "run_started":
            # `is_tutorial`은 C201부터 붙는다. 없는 옛 자료는 stage_id==1로 근사한다
            # (그러면 최초 클리어 뒤 재도전까지 섞여 분모가 부푼다 — 그래서 새 칸을 넣었다).
            t = ev.get("is_tutorial")
            if t in (True, "TRUE", "true", "1") or (t is None and str(ev.get("stage_id")) == "1"):
                tut_sids.add(sid)
        elif name == "stage_cleared" and str(ev.get("stage_id")) == "1":
            s1_clear_sids.add(sid)
    onboarding(sessions, beats_by_sid, tut_sids, s1_clear_sids)
    revisits(sessions)
    by_build(sessions)
    print("\n통과선은 docs/ROADMAP.md §3-C(방문 단위로 읽을 것). 판정은 사람이 한다.")


if __name__ == "__main__":
    main()
