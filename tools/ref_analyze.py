#!/usr/bin/env python3
# 레퍼런스 녹화 분석 (정본: AUDIO_PLAN.md §10 · §21③ · §26)
#   실행: python3 tools/ref_analyze.py <녹화.mov|wav> [시작초] [끝초]
#
# **왜 저장소에 있나**: 레퍼런스는 지금까지 네 번 분석했는데(§10 블록블라스트 · §16 벡터 매칭 ·
#   §21③ 시간 구조 · §26 Block Out!) 매번 임시 스크립트를 짜고 버렸다. 그래서 같은 실수를 반복했다:
#   ⚠**광고 구간을 안 걷어내 정반대 결론**(§10) · ⚠**스펙트럼만 보고 시간 구조를 안 봄**(§21③).
#   도구를 남기면 다음 녹화는 같은 자로 바로 잰다.
#
# ⚠**이 자는 앱의 출력이지 폰 스피커의 재생이 아니다.** 화면 녹화는 오디오를 내부에서 딴다 →
#   저역이 그대로 찍힌다. "레퍼런스는 저역을 쓴다"를 "폰에서 저역이 들린다"로 읽으면 안 된다.
# ⚠**프레임을 같이 볼 것.** 소리만 보면 무엇에 붙은 소리인지 모른다(§10에서 광고를 게임으로
#   착각할 뻔했다). 이 도구는 `--frames`로 컨택트 시트를 같이 뽑는다.
import math, os, subprocess, sys, tempfile, wave, struct

def load(path, t0=0.0, t1=None):
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as t:
        tmp = t.name
    cmd = ["ffmpeg", "-y", "-loglevel", "error", "-i", path, "-ac", "1", "-ar", "44100",
           "-c:a", "pcm_s16le", "-ss", "%.3f" % t0]
    if t1:
        cmd += ["-to", "%.3f" % t1]
    subprocess.run(cmd + [tmp], check=True)
    with wave.open(tmp, "rb") as w:
        raw = w.readframes(w.getnframes()); rate = w.getframerate()
    os.unlink(tmp)
    xs = struct.unpack("<%dh" % (len(raw) // 2), raw)
    return [v / 32768.0 for v in xs], rate

# ── FFT·스펙트럼은 phone_sim.py의 것을 그대로 쓴다(자를 두 벌 두면 반드시 어긋난다) ──
_H = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "phone_sim.py"),
          encoding="utf-8").read().split("ROOT = os.path.dirname")[0]
_NS = {}
exec(compile(_H, "phone_sim_head", "exec"), _NS)
spectrum, centroid, fft = _NS["spectrum"], _NS["centroid"], _NS["fft"]

BANDS = [(0, 300), (300, 800), (800, 2500), (2500, 5000), (5000, 20000)]
NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

def note_name(f):
    n = round(12 * math.log2(f / 440.0)) + 69
    return "%s%d" % (NAMES[n % 12], n // 12 - 1)

def envelope(x, rate, frame=0.02):
    n = int(rate * frame)
    return [math.sqrt(sum(v * v for v in x[i:i + n]) / n) for i in range(0, len(x) - n, n)]

def report_envelope(x, rate):
    env = envelope(x, rate, 0.05)
    pk = max(env) or 1e-9
    print("\n── 봉투(50ms) — 무음 구간이 어디인가")
    for i, e in enumerate(env):
        d = 20 * math.log10(e / pk) if e > 0 else -99
        print("  %5.2f %6.1f %s" % (i * 0.05, d, "#" * max(0, int((d + 50) / 1.5))))

def report_bands(x, rate, tag=""):
    tot = [0.0] * len(BANDS); allp = 0.0
    n = int(rate * 0.2)
    i = 0
    while i + n < len(x):
        sp = spectrum(x[i:i + n], rate)
        for k, (lo, hi) in enumerate(BANDS):
            tot[k] += sum(p for f, p in sp if lo <= f < hi)
        allp += sum(p for _, p in sp) or 1
        i += n // 2
    pk = max(abs(v) for v in x) or 1e-9
    rms = math.sqrt(sum(v * v for v in x) / len(x)) or 1e-9
    env = envelope(x, rate, 0.01)
    thr = pk * 10 ** (-35 / 20)
    gap = cur = 0
    for e in env:
        cur = cur + 1 if e < thr else 0
        gap = max(gap, cur)
    print("%-20s %5.2fs 크레스트 %4.1fdB 최장무음 %.2fs | %4.0f %4.0f %4.0f %4.0f %4.0f"
          % (tag, len(x) / rate, 20 * math.log10(pk / rms), gap * 0.01,
             *[100 * t / allp for t in tot]))

def report_melody(x, rate, t0=0.0):
    """지속음의 음이름 — ⚠광대역(폭죽)이 섞이면 피크가 튄다 → 협대역성으로 걸러 ♪만 믿을 것."""
    print("\n── 선율(50ms) — 협대역성 0.25 이상만 ♪(그 아래는 잡음에 묻힌 프레임)")
    i = 0.0
    while i * rate + int(rate * 0.06) < len(x):
        a = int(i * rate)
        seg = x[a:a + int(rate * 0.06)]
        rms = math.sqrt(sum(v * v for v in seg) / len(seg))
        if rms > 2e-3:
            sp = spectrum(seg, rate)
            band = [(f, p) for f, p in sp if 380 <= f <= 2600]
            if band:
                f, _ = max(band, key=lambda fp: fp[1])
                allp = sum(p for _, p in sp) or 1
                near = sum(p for g, p in sp if abs(g - f) < 50) / allp
                print("  %5.2f %6.0fHz %-4s %.2f %6.1fdB %s"
                      % (t0 + i, f, note_name(f), near, 20 * math.log10(rms),
                         "♪" if near > 0.25 else ""))
        i += 0.05

def report_onsets(x, rate, t0=0.0, thr=0.16):
    """온셋 = 스펙트럼 플럭스. ⚠봉투만 보면 겹친 사건을 하나로 센다(§21③)."""
    N, H = 1024, 256
    win = [0.5 - 0.5 * math.cos(2 * math.pi * k / (N - 1)) for k in range(N)]
    prev = None; flux = []
    for i in range(0, len(x) - N, H):
        a = [complex(x[i + k] * win[k], 0.0) for k in range(N)]
        m = [abs(v) for v in fft(a)[:N // 2]]
        if prev:
            flux.append((i / rate, sum(max(0.0, m[k] - prev[k]) for k in range(len(m)))))
        prev = m
    mx = max(f for _, f in flux) or 1e-9
    ons = []
    for i in range(2, len(flux) - 2):
        t, f = flux[i]
        if f / mx > thr and f >= max(flux[i - 2][1], flux[i - 1][1], flux[i + 1][1], flux[i + 2][1]):
            if not ons or t - ons[-1] > 0.040:
                ons.append(t)
    print("\n── 온셋 %d개 · 초당 %.1f개" % (len(ons), len(ons) / (len(x) / rate)))
    print("  " + " ".join("%.2f" % (t0 + t) for t in ons))

def frames(path, out_dir, fps=4, cols=8):
    os.makedirs(out_dir, exist_ok=True)
    sheet = os.path.join(out_dir, "sheet.png")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", path,
                    "-vf", "fps=%d,scale=200:-1,tile=%dx4" % (fps, cols),
                    "-frames:v", "1", sheet], check=True)
    print("컨택트 시트: %s  (프레임 간격 %.2fs — 소리를 화면에 붙여 볼 것)" % (sheet, 1.0 / fps))

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("사용: tools/ref_analyze.py <녹화> [시작초] [끝초]")
        sys.exit(1)
    src = sys.argv[1]
    t0 = float(sys.argv[2]) if len(sys.argv) > 2 else 0.0
    t1 = float(sys.argv[3]) if len(sys.argv) > 3 else None
    x, rate = load(src, t0, t1)
    print("── %s  %.2f초 · %dHz" % (os.path.basename(src), len(x) / rate, rate))
    print("구간                  길이   크레스트    최장무음   |<300 .3-.8k .8-2.5k 2.5-5k >5k")
    report_bands(x, rate, "전체")
    report_envelope(x, rate)
    report_onsets(x, rate, t0)
    report_melody(x, rate, t0)
    if src.lower().endswith((".mov", ".mp4", ".m4v")):
        frames(src, os.path.join(os.path.dirname(src) or ".", "ref_frames"))
