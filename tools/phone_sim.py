#!/usr/bin/env python3
# 폰 스피커 통과 손실 시뮬 (stdlib만) — 정본: AUDIO_PLAN.md §9 P0 · §20.
#   실행: python3 tools/phone_sim.py        (저장소 루트에서)
#
# **왜 저장소에 있나**: §11이 "새 어휘를 만들 때마다 폰 시뮬을 돌릴 것"이라 못박는데, R1~R12 동안
#   이 도구는 매번 임시로 만들어 쓰고 버려졌다. 그래서 같은 병(저역에 정보를 실어 폰에서 사라짐)이
#   세 번 재발했다. 규칙만 적어 두고 도구를 안 남기면 그 규칙은 안 지켜진다.
#
# 방법: 파형의 파워스펙트럼을 한 번 뜨고, 재생 음정(반음)만큼 주파수 축을 곱한 뒤 폰 스피커 응답
#   H(f)를 곱해 RMS 손실(dB)을 낸다. 리샘플이 필요 없다 — 음정 = 주파수 축 스케일이기 때문.
#
# ⚠**이 도구도 한 번 틀렸다**(§20). 처음엔 1/12옥타브 **로그 간격** Goertzel로 스펙트럼을 떴는데,
#   로그 간격은 대역폭 보정이 없어(옥타브당 빈 개수는 같은데 실제 대역폭은 두 배씩 넓어진다)
#   저역을 체계적으로 과대평가한다. 광대역 파형은 중심 주파수가 통째로 틀렸다: chip_high를
#   535Hz로 읽었는데 실제는 5147Hz(문서 실측 4994Hz와 일치). → **선형 간격 FFT로 교체.**
#   계측이 이상한 결론을 내면 대상이 아니라 자를 먼저 의심할 것(§9의 해닝창 사고와 같은 종류).
#
# 어휘 표는 **Main.gd에서 파싱한다** — 하드코딩하면 상수를 고칠 때마다 조용히 어긋난다.
import wave, math, struct, os, re

def read_wav(path):
    with wave.open(path, 'rb') as w:
        n, sw, ch, rate = w.getnframes(), w.getsampwidth(), w.getnchannels(), w.getframerate()
        raw = w.readframes(n)
    assert sw == 2, f"{path}: 16bit만 지원 (sw={sw})"
    xs = struct.unpack("<%dh" % (len(raw) // 2), raw)
    if ch == 2:
        xs = [(xs[i] + xs[i + 1]) * 0.5 for i in range(0, len(xs) - 1, 2)]
    return [v / 32768.0 for v in xs], rate

def fft(a):
    """반복형 radix-2 FFT (stdlib complex만)."""
    n = len(a)
    j = 0
    for i in range(1, n):
        bit = n >> 1
        while j & bit:
            j ^= bit
            bit >>= 1
        j |= bit
        if i < j:
            a[i], a[j] = a[j], a[i]
    ln = 2
    while ln <= n:
        ang = -2.0 * math.pi / ln
        wl = complex(math.cos(ang), math.sin(ang))
        for i in range(0, n, ln):
            w = complex(1.0, 0.0)
            for k in range(i, i + ln // 2):
                u = a[k]
                v = a[k + ln // 2] * w
                a[k] = u + v
                a[k + ln // 2] = u - v
                w *= wl
        ln <<= 1
    return a

def spectrum(x, rate, fmax=16000.0):
    """⚠**선형 간격** 파워스펙트럼. 로그 간격으로 뜨면 대역폭 보정이 없어 저역이 과대평가되고
    (한 옥타브 안의 빈 개수가 위로 갈수록 같은데 실제 대역폭은 두 배씩 넓어진다),
    광대역 파형의 중심 주파수가 통째로 틀린다 — 이 도구가 처음에 그렇게 틀렸다."""
    n = len(x)
    win = [0.5 - 0.5 * math.cos(2.0 * math.pi * i / (n - 1)) for i in range(n)]
    npow = 1
    while npow < n:
        npow <<= 1
    a = [complex(x[i] * win[i], 0.0) for i in range(n)] + [0j] * (npow - n)
    a = fft(a)
    out = []
    df = rate / float(npow)
    for k in range(1, npow // 2):
        f = k * df
        if f > fmax:
            break
        out.append((f, abs(a[k]) ** 2))
    return out

def phone_h(f, corner=620.0, order=2.5, top=9000.0):
    """작은 폰 스피커 근사 — 코너 아래로 급격히 죽고, 9kHz 위도 완만히 죽는다."""
    hp = 1.0 / math.sqrt(1.0 + (corner / f) ** (2.0 * order))
    lp = 1.0 / math.sqrt(1.0 + (f / top) ** 4.0)
    return hp * lp

def loss_db(spec, semi):
    r = 2.0 ** (semi / 12.0)          # 재생 음정 = 주파수 축 배율
    num = den = 0.0
    for f, p in spec:
        fr = f * r
        h = phone_h(fr)
        den += p
        num += p * h * h
    return 10.0 * math.log10(num / den) if den > 0 else -99.0

def low_share(spec, semi, cut=300.0):
    r = 2.0 ** (semi / 12.0)
    lo = tot = 0.0
    for f, p in spec:
        tot += p
        if f * r < cut:
            lo += p
    return 100.0 * lo / tot if tot > 0 else 0.0

def centroid(spec, semi):
    r = 2.0 ** (semi / 12.0)
    num = den = 0.0
    for f, p in spec:
        num += f * r * p
        den += p
    return num / den if den > 0 else 0.0

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SFX = os.path.join(ROOT, "sfx")

def parse_main():
    """Main.gd에서 (어휘 → 파형·base) 표를 읽는다. 두 곳을 맞춰 본다:
       SFX_WORDS(base) + _sfx_build_bank(어느 파형을 쓰나)."""
    src = open(os.path.join(ROOT, "Main.gd"), encoding="utf-8").read()
    # const SFX_LOW: String = "res://sfx/pop_low.wav"  → 상수명 → 파일 stem
    consts = dict(re.findall(r'const\s+(SFX_\w+):\s*String\s*=\s*"res://sfx/(\w+)\.wav"', src))
    # var lo: AudioStream = load(SFX_LOW)              → 지역변수 → 상수명
    local = dict((v, consts[c]) for v, c in
                 re.findall(r'var\s+(\w+):\s*AudioStream\s*=\s*load\((SFX_\w+)\)', src) if c in consts)
    # _sfx_bank["place"] = lo                          → 어휘 → 파형
    bank = dict((w, local[v]) for w, v in
                re.findall(r'_sfx_bank\["(\w+)"\]\s*=\s*(\w+)', src) if v in local)
    # ⚠**뱅크를 코드로 못 읽는 어휘가 생길 수 있다** — R18의 fw_pop은 후보 목록에서 골라
    #   `_sfx_load_fw()`가 올리므로 위 정규식에 안 걸린다. 그냥 빠뜨리면 "새 단어마다 폰 시뮬"이
    #   **조용히 안 돌아간다**(§18의 '조용한 탈락'과 같은 사고) → 후보 목록도 같이 읽고,
    #   그래도 못 찾은 어휘는 아래에서 경고로 띄운다.
    picks = re.findall(r'\["res://sfx/(pick/\w+)\.wav",', src)
    loader = re.search(r'func _sfx_load_fw.*?_sfx_bank\["(\w+)"\]\s*=\s*st', src, re.S)
    if picks and loader:
        # ⚠어느 **어휘**가 후보를 쓰는지도 코드에서 읽는다 — R18에서 후보 목록이 fw_pop에서
        #   fw_rise로 옮겨 갔는데 여기 이름을 박아 뒀더니 표가 **옛 파형을 계속 보여줬다**.
        m0 = re.search(r'var\s+\w*pick:\s*int\s*=\s*(\d+)', src)
        bank[loader.group(1)] = picks[(int(m0.group(1)) if m0 else 0) % len(picks)]
    words, missing = [], []
    for name, body in re.findall(r'"(\w+)":\s*\{("gap".*?)\},', src):
        if name not in bank:
            # SFX_WORDS 항목인데 파형을 못 찾았다 = 진짜 누락일 수 있다(FB_MAP 항목은 gap이 없다)
            if '"db"' in body:
                missing.append(name)
            continue
        m = re.search(r'"base":\s*(-?\d+)', body)
        words.append((name, bank[name], int(m.group(1)) if m else 0))
    return words, missing

WORDS, MISSING = parse_main()

cache = {}
print("어휘        파형        base   중심F    <300Hz    폰 통과")
print("-" * 60)
worst = 0.0
for name, wav, semi in WORDS:
    if wav not in cache:
        x, rate = read_wav(os.path.join(SFX, wav + ".wav"))
        cache[wav] = (spectrum(x, rate), rate)
    spec, rate = cache[wav]
    d = loss_db(spec, semi)
    worst = min(worst, d)
    # ⚠−6dB = 기계 필터의 탈락선(§18) — 이보다 더 잃으면 폰에서 그 단어가 사실상 사라진다.
    warn = "  ⚠" if d < -6.0 else ""
    print("%-10s  %-10s %+3d   %6.0fHz  %5.1f%%   %+5.1f dB%s"
          % (name, wav, semi, centroid(spec, semi), low_share(spec, semi), d, warn))
print("-" * 60)
print("최악 %.1f dB · 경고선 −6.0 dB · 어휘 %d개" % (worst, len(WORDS)))
if MISSING:
    print("⚠파형을 못 찾은 어휘: %s — 표에서 빠졌다(배선을 확인할 것)" % ", ".join(MISSING))

# 선정 대기 중인 후보들(sfx/pick/)도 같은 자로 잰다 — 고르기 전에 폰에서 사라지는 걸 걸러야 한다.
pick_dir = os.path.join(SFX, "pick")
if os.path.isdir(pick_dir):
    print("\n후보(sfx/pick/) — 재생 음정 0 기준")
    print("-" * 60)
    for fn in sorted(os.listdir(pick_dir)):
        if not fn.endswith(".wav"):
            continue
        x, rate = read_wav(os.path.join(pick_dir, fn))
        spec = spectrum(x[:min(len(x), 65536)], rate)
        d = loss_db(spec, 0)
        print("%-22s %6.0fHz  %5.1f%%   %+5.1f dB%s"
              % (fn[:-4], centroid(spec, 0), low_share(spec, 0), d, "  ⚠" if d < -6.0 else ""))
