#!/usr/bin/env python3
# 새 샘플을 게임에 넣을 수 있는 상태로 다듬는다 (정본: AUDIO_PLAN.md §13 · §23)
#   실행: python3 tools/sfx_prep.py <입력> <출력.wav> [--drive N] [--tail-db N] [--gain-db N]
#                                          [--max-sec N] [--semi N]
#
# **왜 도구가 필요한가**: 이 처리는 규칙으로만 적혀 있었고 매번 손으로 했다. 그래서 두 번 샜다 —
#   R10의 hit.wav는 앞에 **60ms 무음**이 붙은 채로 들어가 삭제음이 섬광보다 3.6프레임 늦게 울렸고,
#   R16까지 "조용하다"의 원인을 레벨로 오해했다(실제 원인은 **크레스트 22dB**). 규칙만 적어 두고
#   도구를 안 남기면 그 규칙은 안 지켜진다(phone_sim.py와 같은 이유로 저장소에 둔다).
#
# 하는 일 셋:
#   ① **선행 무음·꼬리 절단** — 리드가 남으면 소리가 화면보다 늦고, 꼬리가 길면 보이스를 오래 문다.
#   ② **새추레이션(tanh)** — 자연 녹음은 전부 뾰족하다(크레스트 19~32dB). 크레스트로 후보를
#      거르면 신스만 남으므로(§23) **선별이 아니라 여기서** 눌러 넣는다. 리미터까지 여유가
#      3~4dB뿐이라 볼륨으로는 못 고친다.
#   ③ **피크 정규화** — 위계는 Main.gd의 db가 잡는다. 파일은 늘 같은 피크로 들어와야 그 표가 산다.
#
# ⚠음정이 의미를 나르는 자리(도레미)엔 **음정 있는 재질**을 쓸 것 — 노이즈성 재질은 pitch_scale을
#   올려도 음이 안 읽힌다(R16 실측). 이 도구는 그걸 못 고쳐 준다.
import math, os, struct, subprocess, sys, tempfile, wave

def load(path):
    """ogg·mp3·stereo·24bit 무엇이든 ffmpeg로 모노 44.1k 16bit를 거쳐 읽는다.
    ⚠wave 모듈로 바로 읽으면 스테레오·24bit에서 예외가 나고, 그게 try/except에 삼켜지면
      후보가 '탈락'이 아니라 '못 읽음'으로 조용히 사라진다(R12에서 종·차임 계열이 그렇게 증발했다)."""
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as t:
        tmp = t.name
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", path,
                    "-ac", "1", "-ar", "44100", "-c:a", "pcm_s16le", tmp], check=True)
    with wave.open(tmp, "rb") as w:
        n, rate = w.getnframes(), w.getframerate()
        raw = w.readframes(n)
    os.unlink(tmp)
    xs = struct.unpack("<%dh" % (len(raw) // 2), raw)
    return [v / 32768.0 for v in xs], rate

def crest_db(x):
    pk = max((abs(v) for v in x), default=0.0) or 1e-9
    rms = math.sqrt(sum(v * v for v in x) / max(1, len(x))) or 1e-9
    return 20.0 * math.log10(pk / rms)

def trim(x, lead_frac=0.02, tail_db=-40.0):
    """리드는 피크의 2%를 넘는 첫 샘플, 꼬리는 tail_db 아래로 내려간 뒤 안 돌아오는 지점."""
    pk = max((abs(v) for v in x), default=0.0) or 1e-9
    thr_l = pk * lead_frac
    thr_t = pk * (10.0 ** (tail_db / 20.0))
    i0 = next((i for i, v in enumerate(x) if abs(v) > thr_l), 0)
    i1 = next((i for i in range(len(x) - 1, -1, -1) if abs(x[i]) > thr_t), len(x) - 1)
    return x[i0:i1 + 1], i0

def saturate(x, drive):
    """tanh 소프트 포화 — 배음을 채우고 피크만 눌러 밀도를 올린다. drive=0이면 통과."""
    if drive <= 0.0:
        return x
    k = 1.0 + drive
    return [math.tanh(v * k) / math.tanh(k) for v in x]

def fade_out(x, rate, ms=8.0):
    """끝을 0으로 — 자른 자리에서 딸깍(불연속)이 나는 걸 막는다."""
    n = min(len(x), int(rate * ms / 1000.0))
    for i in range(n):
        x[len(x) - n + i] *= 1.0 - float(i) / float(n)
    return x

def save(path, x, rate):
    data = b"".join(struct.pack("<h", max(-32768, min(32767, int(round(v * 32767.0))))) for v in x)
    with wave.open(path, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(rate); w.writeframes(data)

def resample_semi(x, semi):
    """음정 이동 = 리샘플(길이도 같이 변한다). 원음의 조를 맞출 때만 쓴다 — 게임 안에서는
    `pitch_scale`이 같은 일을 하므로, 파일 단계에선 **기준음 정렬**이 목적이다."""
    if abs(semi) < 0.01:
        return x
    r = 2.0 ** (semi / 12.0)
    out, i = [], 0.0
    while i < len(x) - 1:
        k = int(i)
        out.append(x[k] + (x[k + 1] - x[k]) * (i - k))
        i += r
    return out

def prep(src, dst, drive=0.0, tail_db=-40.0, gain_db=0.0, peak=0.97, max_sec=0.0, semi=0.0):
    x, rate = load(src)
    c0, n0 = crest_db(x), len(x)
    x = resample_semi(x, semi)
    y, lead = trim(x, tail_db=tail_db)
    # ⚠**길이 상한**. 유음 악기 원본은 4~7초씩 가는데, 그대로 넣으면 보이스를 그만큼 물고 있어
    #   폴리포니가 말라 버린다(진흙 방어의 상한 8이 곧바로 찬다). 자른 자리는 fade_out이 받는다.
    if max_sec > 0.0 and len(y) > int(rate * max_sec):
        y = y[:int(rate * max_sec)]
    y = saturate(y, drive)
    pk = max((abs(v) for v in y), default=0.0) or 1e-9
    g = (peak / pk) * (10.0 ** (gain_db / 20.0))
    y = fade_out([v * g for v in y], rate, 8.0 if max_sec <= 0.0 else 60.0)
    save(dst, y, rate)
    print("%-22s 리드 %5.0fms 절단 · %5.0f→%5.0fms · 크레스트 %4.1f→%4.1fdB"
          % (os.path.basename(dst), lead / rate * 1000.0,
             n0 / rate * 1000.0, len(y) / rate * 1000.0, c0, crest_db(y)))

if __name__ == "__main__":
    a = sys.argv[1:]
    if len(a) < 2:
        print(__doc__ or "사용: tools/sfx_prep.py <입력> <출력.wav> [--drive N] [--tail-db N] [--gain-db N]")
        sys.exit(1)
    def opt(name, dv):
        return float(a[a.index(name) + 1]) if name in a else dv
    prep(a[0], a[1], drive=opt("--drive", 0.0), tail_db=opt("--tail-db", -40.0),
         gain_db=opt("--gain-db", 0.0), max_sec=opt("--max-sec", 0.0), semi=opt("--semi", 0.0))
