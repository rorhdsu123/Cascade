#!/usr/bin/env python3
"""prompt_index.py — 사람이 AI에게 준 지시를 세션 대화록에서 뽑아 한 파일로 모은다.

대회 제출물 ④(AI 활용 기술 문서)가 "AI 대상 주요 프롬프트 및 지시 사항"을 요구한다.
그 1차 사료는 커밋 메시지가 아니라 Claude Code 세션 로그(~/.claude/projects/*.jsonl)다.
트렁크와 워크트리가 각자 다른 프로젝트 폴더를 쓰므로 전부 훑는다.

  python3 tools/prompt_index.py                 # 요약(세션·발화 수·기간)
  python3 tools/prompt_index.py --dump OUT.md   # 전문을 시간순 마크다운으로
  python3 tools/prompt_index.py --min 400       # 400자 이상 '긴 지시'만

⚠산출물은 개인 대화가 섞일 수 있으므로 저장소 밖이나 docs/local/(gitignore)에 둘 것.
"""
import argparse
import glob
import json
import os
import re

ROOT = os.path.expanduser("~/.claude/projects")
PATTERN = "*Cascade*"

# 사람 발화가 아닌 것들 — 훅·명령 출력·툴 결과·시스템 리마인더
SKIP_PREFIX = ("<", "Caveat:", "[Request interrupted")
SKIP_CONTAINS = ("<command-name>", "<local-command", "tool_use_id", "<system-reminder>")


def harvest():
    """모든 Cascade 프로젝트 폴더에서 사람 발화를 (시각, 트랙, 세션, 본문)으로 뽑는다."""
    out = []
    for d in sorted(glob.glob(os.path.join(ROOT, PATTERN))):
        track = os.path.basename(d).replace("-Users-im-yujin-Desktop-Cascade", "") or "-trunk"
        track = track.replace("-worktrees-", "").lstrip("-") or "trunk"
        for f in sorted(glob.glob(os.path.join(d, "*.jsonl"))):
            sid = os.path.basename(f)[:8]
            for line in open(f, errors="replace"):
                try:
                    rec = json.loads(line)
                except ValueError:
                    continue
                if rec.get("type") != "user" or rec.get("isMeta"):
                    continue
                content = rec.get("message", {}).get("content")
                if isinstance(content, list):
                    text = "".join(
                        p.get("text", "")
                        for p in content
                        if isinstance(p, dict) and p.get("type") == "text"
                    )
                else:
                    text = content or ""
                text = text.strip()
                if not text or text.startswith(SKIP_PREFIX):
                    continue
                if any(s in text for s in SKIP_CONTAINS):
                    continue
                out.append((rec.get("timestamp", "")[:16].replace("T", " "), track, sid, text))
    out.sort()
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dump", metavar="OUT.md", help="전문을 마크다운으로 저장")
    ap.add_argument("--min", type=int, default=0, help="이 길이 이상만")
    args = ap.parse_args()

    rows = [r for r in harvest() if len(r[3]) >= args.min]
    if not rows:
        print("발화 0건 — ROOT/PATTERN 확인")
        return

    tracks = {}
    for ts, track, _sid, text in rows:
        t = tracks.setdefault(track, {"n": 0, "chars": 0, "first": ts, "last": ts})
        t["n"] += 1
        t["chars"] += len(text)
        t["first"] = min(t["first"], ts)
        t["last"] = ts

    print(f"사람 발화 {len(rows)}건 · {sum(len(r[3]) for r in rows):,}자 · "
          f"{rows[0][0][:10]} ~ {rows[-1][0][:10]}")
    for name, t in sorted(tracks.items(), key=lambda kv: -kv[1]["n"]):
        print(f"  {name:<10} {t['n']:>4}건 {t['chars']:>8,}자  {t['first'][:10]}~{t['last'][:10]}")

    if args.dump:
        with open(args.dump, "w") as fp:
            fp.write(f"# 사람 지시 전문 — {len(rows)}건 ({rows[0][0][:10]} ~ {rows[-1][0][:10]})\n\n")
            fp.write("> `tools/prompt_index.py`가 세션 대화록에서 자동 추출. 편집 금지(재생성됨).\n\n")
            day = None
            for ts, track, sid, text in rows:
                if ts[:10] != day:
                    day = ts[:10]
                    fp.write(f"\n---\n\n## {day}\n")
                fp.write(f"\n### {ts[11:]} · {track} · {sid} · {len(text)}자\n\n")
                fp.write(re.sub(r"^", "> ", text, flags=re.M) + "\n")
        print(f"→ {args.dump}")


if __name__ == "__main__":
    main()
