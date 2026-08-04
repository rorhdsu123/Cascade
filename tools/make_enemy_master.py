#!/usr/bin/env python3
"""적 마스터 **임시본** 생성기 — art/enemies/{basic,swarm,fast}.png (각 180×180).

    python3 tools/make_enemy_master.py

`make_enemy_placeholder.py`와 목적이 다르다. 저쪽은 **이음새가 도는지 확인**하려고 일부러 지금
도형과 다르게(눈·링·꼬리) 그리는 물건이라 출고에 못 쓴다. 이건 UI_ART_PLAN §6이 말하는
**최후 수단** = 디자이너 납품이 안 왔을 때 그대로 나가는 그림이다(`make_block_placeholder.py`와 같은 급).
⚠**둘 다 같은 파일에 쓴다** — 저쪽을 기본 인자로 돌리면 이 그림들이 덮인다.

## 세 종뿐인 이유

이음새를 타는 적이 셋뿐이다(`Main.gd`의 `ENEMY_NAMES`). bomb·tank·split·thief는 P2라
배선이 없어서, 그려 넣어도 화면에 안 붙는다.

## 왜 회색조가 아닌가 (블록과 다른 점)

블록은 흰 마스터 한 장에 코드가 6색을 곱한다. 적은 아니다 — basic이 받는 tint는
`_hp_tint(C_E_BASIC, bcol)`이고 **HP 만땅이면 정확히 흰색(=곱셈 항등)**, swarm·fast는 아예
tint 인자가 없다(항상 흰색). 즉 **색을 그림이 갖는다.** 여기서 `#a855f7`·`#a3e635`·`#22d3ee`를
직접 칠하는 이유다. basic의 HP 명암만 코드가 곱해 얹는다.

## 조리법을 블록에서 그대로 가져온 이유

'한 벌로 읽히는가'가 이 그림들의 유일한 합격 조건이라, 빛의 방향을 블록과 **같게** 맞췄다:
위에서 오는 빛 → 세로 그라디언트 + 상단 광택 + 하단 안쪽 그림자 + 밑면 반사광.
좌상단에서 비추면 더 입체적이지만 블록과 광원이 어긋나 오히려 따로 논다.

## 지키는 제약 셋

1. **형태를 안 바꾼다** — 원(basic) · 원 셋(swarm) · 아래를 향한 삼각형(fast)은 서로를,
   그리고 블록(라운드 사각)을 가르는 채널이다. 명암만 얹는다.
2. **크기·중심도 안 바꾼다** — 도형 시절의 바깥날에 픽셀로 맞췄다. 도형은 외곽선을 경로에
   **중심 정렬**로 얹으므로(`draw_circle(..., false, w)`) 바깥날 = 반지름 + 선폭/2다.
   ⚠**PIL은 반대로 경계 상자에서 안쪽으로 그린다** — 알파를 그보다 크게 잡으면 그 틈으로
   몸통 색이 새어 검은 테 바깥에 후광이 생긴다(basic에서 실제로 그랬다).
3. **어두운 외곽선을 그림이 갖는다** — 도형 시절 `C_E_RIM`(검정 85%)이 그리던 것이다.
   스프라이트가 붙으면 코드는 이걸 안 그린다. 빼면 밝은 블록 위에서 윤곽이 녹는다.

명암을 lerp로 주는 이유: 채널을 직접 곱하면 포화한 채널이 먼저 막혀 **색상이 돌아간다.**
밝은 쪽은 흰색으로, 어두운 쪽은 어두운 동색으로 섞는다 — HP 명암(`C_E_BASIC.lerp(...)`)과 같은 셈이다.

⚠**명암을 세게 주면 실루엣이 죽는다.** basic에서 밑면을 46%까지 어둡게 했더니 어두운 배경·검은
외곽선과 뭉개져 아래쪽 윤곽이 사라졌다. 적을 블록에서 가르는 건 색이 아니라 **어두운 rim + 실루엣**
이라(`Main.gd:188`) 그건 입체감이 아니라 신호를 깎은 것이다 → 그림자를 줄이고 밑면 반사광을 넣는다.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

OUT_DIR = Path(__file__).resolve().parent.parent / "art" / "enemies"

S = 180          # 한 칸(90px)의 2배 = §5 배율 규칙
SS = 4           # 슈퍼샘플링 — 가장자리 계단 제거
W = S * SS
C = W // 2
CELL = 90.0      # 화면 한 칸. 아래 지오메트리는 전부 Main.gd의 도형 렌더에서 가져온 값이다
F = (S / CELL) * SS   # 화면 px → 이 캔버스의 px

RIM = (14, 9, 24, 255)   # 외곽선 — C_E_RIM(검정 85%)을 배경 위에서 본 값에 맞춤

HI_MAX = 58      # 상단 광택이 흰색으로 섞이는 상한(0~255). 세게 주면 색 신호가 죽는다
LO_MAX = 84      # 하단 그림자가 어두운 동색으로 섞이는 상한
BOUNCE = 46      # 밑면 반사광 — 입체감보다 **실루엣 복구**가 목적이다
BOUNCE_W = 9 * SS    # 반사광 띠 두께


def dark_of(rgb):
    """그림자가 향하는 색의 기본값 = 기준색의 0.45배.

    basic만 이 값을 안 쓴다 — 코드가 HP 명암으로 향하는 색이 `Color(0.30,0.10,0.48)`으로
    **이미 정해져 있어서**(`Main.gd`의 basic 렌더), 그림의 그림자를 거기 맞춰야 HP가 닳을 때
    명암이 한 방향으로 이어진다. swarm·fast는 HP 명암 자체가 없어(tint 인자 없음) 기준값을 쓴다.
    """
    return tuple(int(v * 0.45) for v in rgb)


def blur(img, r):
    return img.filter(ImageFilter.GaussianBlur(r * SS))


def _acc(dst, src, mask):
    """dst = min(255, dst + src), 단 mask 안에서만.

    덩어리(swarm의 원 셋)마다 자기 중심 기준으로 빛을 받아야 해서, 덩어리별로 만든 마스크를
    자기 실루엣 안으로 잘라 누적한다. 안 자르면 옆 덩어리의 그라디언트가 겹쳐 얼룩진다.
    """
    pd, ps, pm = dst.load(), src.load(), mask.load()
    for y in range(W):
        for x in range(W):
            if pm[x, y]:
                pd[x, y] = min(255, pd[x, y] + ps[x, y])


def _vgrad(top, bot, lo_max):
    """위에서 아래로 짙어지는 그림자. 아래로 갈수록 가속 = 구의 밑면."""
    g = Image.new("L", (W, W), 0)
    d = ImageDraw.Draw(g)
    for y in range(W):
        t = min(1.0, max(0.0, (y - top) / float(bot - top)))
        d.line([(0, y), (W, y)], fill=int(lo_max * (t ** 1.5)))
    return g


class Sprite:
    """마스크 세 장(그림자·반사광·광택)을 모아 두었다가 마지막에 한 번 합성한다."""

    def __init__(self, base, rim_w, dark=None, lo_max=LO_MAX):
        self.base = base
        self.lo_max = lo_max
        self.dark = dark if dark is not None else dark_of(base)
        self.rim_w = int(rim_w)
        self.alpha = Image.new("L", (W, W), 0)
        self.lo = Image.new("L", (W, W), 0)
        self.band = Image.new("L", (W, W), 0)
        self.hi = Image.new("L", (W, W), 0)
        self.rims = []       # 합성이 끝난 뒤 맨 위에 얹는다(색 위에 테가 와야 한다)

    def add_ball(self, cx, cy, r):
        """구 하나. r = 외곽선 **바깥날** 반지름."""
        disc = Image.new("L", (W, W), 0)
        ImageDraw.Draw(disc).ellipse([cx - r, cy - r, cx + r, cy + r], fill=255)

        _acc(self.lo, _vgrad(cy - r, cy + r, self.lo_max), disc)

        floor = Image.new("L", (W, W), 0)      # 바닥 안쪽 그림자 — 블록의 그것과 같은 자리
        ImageDraw.Draw(floor).ellipse(
            [cx - r * 0.82, cy + r * 0.34, cx + r * 0.82, cy + r * 1.02], fill=60)
        _acc(self.lo, blur(floor, 9), disc)

        hi = Image.new("L", (W, W), 0)         # 상단 광택
        ImageDraw.Draw(hi).ellipse(
            [cx - r * 0.62, cy - r * 0.86, cx + r * 0.62, cy - r * 0.10], fill=HI_MAX)
        _acc(self.hi, blur(hi, 7), disc)

        # 반사광 = 외곽선 안쪽 가장자리를 도는 **아래쪽 초승달**. 위쪽 절반은 광택이 맡는다.
        inner = r - self.rim_w
        band = Image.new("L", (W, W), 0)
        sub = Image.new("L", (W, W), 0)
        ImageDraw.Draw(band).ellipse([cx - inner, cy - inner, cx + inner, cy + inner], fill=255)
        ImageDraw.Draw(sub).ellipse(
            [cx - inner + BOUNCE_W, cy - inner + BOUNCE_W,
             cx + inner - BOUNCE_W, cy + inner - BOUNCE_W], fill=255)
        pb, psb = band.load(), sub.load()
        for y in range(W):
            k = max(0.0, min(1.0, (y - cy) / float(inner)))
            for x in range(W):
                pb[x, y] = int(BOUNCE * (k ** 0.7)) if (pb[x, y] and not psb[x, y]) else 0
        _acc(self.band, blur(band, 3), disc)

        self.alpha.paste(disc, (0, 0), disc)
        self.rims.append(("ellipse", [cx - r, cy - r, cx + r, cy + r]))

    def add_poly(self, pts):
        """다각형 하나(fast의 화살촉). 빛은 구와 같은 방향이되, 바닥이 뾰족해 반사광은 옆날에 붙는다."""
        shape = Image.new("L", (W, W), 0)
        ImageDraw.Draw(shape).polygon(pts, fill=255)
        xs = [p[0] for p in pts]
        ys = [p[1] for p in pts]
        top, bot = min(ys), max(ys)
        gx, gy = sum(xs) / len(xs), sum(ys) / len(ys)

        _acc(self.lo, _vgrad(top, bot, self.lo_max), shape)

        hi = Image.new("L", (W, W), 0)
        ImageDraw.Draw(hi).ellipse(
            [min(xs) + (max(xs) - min(xs)) * 0.18, top - (bot - top) * 0.10,
             max(xs) - (max(xs) - min(xs)) * 0.18, top + (bot - top) * 0.30], fill=HI_MAX)
        _acc(self.hi, blur(hi, 7), shape)

        # 안쪽으로 축소한 도형과의 차 = 테두리 안쪽 띠. 아래쪽만 남긴다.
        k = 1.0 - (self.rim_w + BOUNCE_W) * 2.2 / float(bot - top)
        inner = Image.new("L", (W, W), 0)
        ImageDraw.Draw(inner).polygon(
            [(gx + (x - gx) * k, gy + (y - gy) * k) for x, y in pts], fill=255)
        band = Image.new("L", (W, W), 0)
        pb, pi, ps = band.load(), inner.load(), shape.load()
        for y in range(W):
            w = max(0.0, min(1.0, (y - gy) / float(bot - gy)))
            for x in range(W):
                if ps[x, y] and not pi[x, y]:
                    pb[x, y] = int(BOUNCE * (w ** 0.7))
        _acc(self.band, blur(band, 3), shape)

        self.alpha.paste(shape, (0, 0), shape)
        self.rims.append(("polygon", pts))

    def render(self, name):
        img = Image.new("RGBA", (W, W), self.base + (255,))
        img.paste(Image.new("RGBA", (W, W), self.dark + (255,)), (0, 0), self.lo)
        img.paste(Image.new("RGBA", (W, W), (255, 255, 255, 255)), (0, 0), self.band)
        img.paste(Image.new("RGBA", (W, W), (255, 255, 255, 255)), (0, 0), self.hi)
        # 알파 경계와 외곽선 바깥날이 **정확히 같아야 한다**(위 제약 2의 ⚠).
        img.putalpha(self.alpha)
        d = ImageDraw.Draw(img)
        for r in self.rims:
            if r[0] == "ellipse":
                d.ellipse(r[1], outline=RIM, width=self.rim_w)
            else:
                d.polygon(r[1], outline=RIM, width=self.rim_w)
        out = img.resize((S, S), Image.LANCZOS)
        OUT_DIR.mkdir(parents=True, exist_ok=True)
        out.save(OUT_DIR / (name + ".png"))
        print("wrote", name, out.size)


# ── basic — 바이올렛 원 하나 ─────────────────────────────────────────────
# 도형: draw_circle(r = CELL*0.33 = 29.7) + 외곽선 3px 중심 정렬 → 바깥날 31.2 화면 px.
sp = Sprite((168, 85, 247), 6 * SS, dark=(77, 26, 122))   # #a855f7 = C_E_BASIC, 그림자는 코드의 HP 명암과 같은 색
sp.add_ball(C, C, 31.0 * F)
sp.render("basic")

# ── swarm — 라임 원 셋(군집) ────────────────────────────────────────────
# 군집 자체가 이 적의 form이라 셋을 **한 장으로** 받는다(개별로 받으면 배치를 코드가 쥐게 된다).
# 도형: 반지름 CELL*0.14 = 12.6 + 외곽선 2.5px 중심 정렬 → 바깥날 13.85 화면 px.
# 중심 오프셋도 코드 값 그대로 — 군집의 배치가 이 적의 실루엣이다.
sp = Sprite((163, 230, 53), 5 * SS)             # #a3e635 = C_E_SWARM
for ox, oy in ((-0.16, -0.12), (0.16, -0.10), (-0.02, 0.16)):
    sp.add_ball(C + ox * CELL * F, C + oy * CELL * F, 13.85 * F)
sp.render("swarm")

# ── fast — **일부러 안 만든다**(도형 렌더 유지) ─────────────────────────
# 두 번 시도하고 접었다. 화살촉은 얇고 뾰족해서 **구워 넣은 불투명 테가 면적을 크게 잡아먹는다** —
#   도형 시절의 테는 85% 검정이 경로에 중심 정렬돼 안쪽으로 1.5px만 먹었는데, 그림에 구우면
#   같은 3px이 전부 안쪽으로 들어간다. 실측으로 시안 면적이 42×35 → 36×31로 줄었고,
#   화면에서 적이 **작아 보였다.** 테를 굵히면 더 나빠지고, 얇게 하면 윤곽이 죽는다.
# 게다가 평평한 화살촉은 위에서 오는 빛으로 얻는 게 거의 없다(구·원은 크게 얻는다).
#   그림자를 세게 주면 가장 좁은 자리인 **꼭짓점이 배경에 먹혀 사라진다**(첫 판에서 실제로).
# → 이득 없이 실루엣만 깎는 거래라 접었다. `art/enemies/fast.png`가 없으면 이음새가 지금
#   도형 렌더로 그대로 떨어진다 — 디자이너 납품본이 오면 그때 갈아탄다(P1).
