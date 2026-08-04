#!/usr/bin/env python3
"""적 basic 마스터 **임시본** 생성기 — art/enemies/basic.png (180×180).

    python3 tools/make_basic_placeholder.py

`make_enemy_placeholder.py`와 목적이 다르다. 저쪽은 **이음새가 도는지 확인**하려고 일부러 지금
도형과 다르게(눈·링·꼬리) 그리는 물건이라 출고에 못 쓴다. 이건 UI_ART_PLAN §6이 말하는
**최후 수단** = 디자이너 납품이 안 왔을 때 그대로 나가는 그림이다(`make_block_placeholder.py`와 같은 급).
⚠**둘 다 같은 파일에 쓴다** — 저쪽을 기본 인자로 돌리면 이 그림이 덮인다.

## 왜 basic만인가

P0 중 자리지킴이가 없는 유일한 항목이었다. 블록·빈 셀은 라운드+베벨+광택인데 적만 평면 원이라
**짝이 깨져 있었다.** 노출은 최대다 — 스테이지1 적의 100%.

## 왜 회색조가 아닌가 (블록과 다른 점)

블록은 흰 마스터 한 장에 코드가 6색을 곱한다. 적은 아니다 — `_blit_enemy()`가 받는 tint는
`_hp_tint(C_E_BASIC, bcol)`이고 **HP 만땅이면 정확히 흰색(=곱셈 항등)** 이다. 즉 **색을 그림이 갖는다.**
그래서 여기서 `#a855f7`을 직접 칠한다. HP가 닳을 때의 명암만 코드가 곱해 얹는다.

## 조리법을 블록에서 그대로 가져온 이유

'한 벌로 읽히는가'가 이 그림의 유일한 합격 조건이라, 빛의 방향을 블록과 **같게** 맞췄다:
위에서 오는 빛 → 세로 그라디언트 + 상단 광택 + 하단 안쪽 그림자. 구(sphere)처럼 좌상단에서
비추면 더 입체적이지만 블록과 광원이 어긋나 오히려 따로 논다.

## 지키는 제약 셋

1. **모양은 원 그대로** — 블록이 라운드 사각이라 적을 같은 모양으로 만들면 둘이 안 갈린다.
   실루엣이 '적 vs 블록'을 가르는 채널이다(`Main.gd:188`).
2. **크기도 그대로** — 몸통 반지름을 화면 30px(파일 60)로 잡아 지금 원과 같게 뒀다. 이번에
   바뀌는 건 **명암뿐**이어야 전/후 비교에서 무엇이 좋아졌는지가 읽힌다. 신호 링이 도는
   `ENEMY_TEX_RAD`(36)보다 안쪽이라 전진 링·조준 링이 몸통 밖에 그대로 선다.
3. **어두운 외곽선을 그림이 갖는다** — 도형 시절 `C_E_RIM`(검정 85%, 3px)이 그리던 것이다.
   스프라이트가 붙으면 코드는 이걸 안 그린다. 빼면 밝은 블록 위에서 윤곽이 녹는다.

명암을 lerp로 주는 이유: 채널을 직접 곱하면 파랑(247)이 먼저 포화해 **색상이 돌아간다.**
그래서 밝은 쪽은 흰색으로, 어두운 쪽은 진보라로 섞는다 — HP 명암(`C_E_BASIC.lerp(...)`)과 같은 셈이다.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

OUT = Path(__file__).resolve().parent.parent / "art" / "enemies" / "basic.png"

S = 180          # 한 칸(90px)의 2배 = §5 배율 규칙
SS = 4           # 슈퍼샘플링 — 원 가장자리 계단 제거
W = S * SS
C = W // 2

# 실루엣 바깥날 반지름(파일 px) = 화면 31px. 도형 시절은 반지름 29.7 원 위에 3px 테를
#   **중심 정렬**로 얹어 바깥날이 31.2였다 — 지름을 픽셀로 맞춰 전/후에서 크기가 안 변하게 했다.
R_BODY = 62
RIM_W = 6        # 외곽선 두께(파일 px) = 화면 3px = C_E_RIM_W

BASE = (168, 85, 247)    # #a855f7 = C_E_BASIC
DARK = (77, 26, 122)     # HP 명암이 향하는 진보라와 같은 값(0.30,0.10,0.48)
RIM = (14, 9, 24, 255)   # 외곽선 — C_E_RIM(검정 85%)을 배경 위에서 본 값에 맞춤

HI_MAX = 58      # 상단 광택이 흰색으로 섞이는 상한(0~255). 세게 주면 색 신호가 죽는다
# 하단 그림자가 진보라로 섞이는 상한. 블록(255→214)보다 폭이 넓다 — 같은 낙차라도 원이
#   사각보다 평평해 보여서다. ⚠**여기서 한 번 과했다**: 118로 잡으니 밑면이 어두운 배경·검은
#   외곽선과 뭉개져 **실루엣 아래쪽이 사라졌다.** 적을 블록에서 가르는 건 색이 아니라
#   어두운 rim + 실루엣이라(`Main.gd:188`) 이건 입체감이 아니라 신호를 깎은 것이다.
LO_MAX = 84
# 밑면 반사광(bounce). 어두운 배경 위의 구를 다시 떼어내는 고전적인 수단이고, 여기선
#   **입체감보다 실루엣 복구가 목적**이다 — 안쪽 가장자리를 따라 얇게 밝혀 아래쪽 윤곽을 되살린다.
BOUNCE = 46
BOUNCE_W = 9     # 반사광 띠 두께(파일 px)


def disc(r):
    """반지름 r(파일 px)의 원 마스크."""
    m = Image.new("L", (W, W), 0)
    ImageDraw.Draw(m).ellipse(
        [C - r * SS, C - r * SS, C + r * SS, C + r * SS], fill=255)
    return m


# ── 그림자 = 세로 그라디언트 + 바닥 안쪽 그림자 ──
lo = Image.new("L", (W, W), 0)
d = ImageDraw.Draw(lo)
top, bot = C - R_BODY * SS, C + R_BODY * SS
for y in range(W):
    t = min(1.0, max(0.0, (y - top) / (bot - top)))
    d.line([(0, y), (W, y)], fill=int(LO_MAX * (t ** 1.5)))   # 아래로 갈수록 가속 = 구의 밑면

floor = Image.new("L", (W, W), 0)
ImageDraw.Draw(floor).ellipse(
    [C - R_BODY * SS * 0.82, C + R_BODY * SS * 0.34,
     C + R_BODY * SS * 0.82, C + R_BODY * SS * 1.02], fill=60)
floor = floor.filter(ImageFilter.GaussianBlur(9 * SS))
pl, pf = lo.load(), floor.load()
for y in range(W):
    for x in range(W):
        pl[x, y] = min(255, pl[x, y] + pf[x, y])

# ── 광택 = 상단 캡. 블록과 같은 자리(위쪽 1/3), 같은 성격(뭉갠 밝은 덩어리) ──
hi = Image.new("L", (W, W), 0)
ImageDraw.Draw(hi).ellipse(
    [C - R_BODY * SS * 0.62, C - R_BODY * SS * 0.86,
     C + R_BODY * SS * 0.62, C - R_BODY * SS * 0.10], fill=HI_MAX)
hi = hi.filter(ImageFilter.GaussianBlur(7 * SS))

# ── 반사광 = 외곽선 **안쪽** 가장자리를 따라 도는 아래쪽 초승달 ──
inner = R_BODY - RIM_W
band = disc(inner)
sub = disc(inner - BOUNCE_W).load()
pb = band.load()
for y in range(W):
    # 위쪽 절반은 광택이 맡는다. 중심 아래로만, 바닥에 가까울수록 세게.
    k = max(0.0, min(1.0, (y - C) / float(inner * SS)))
    for x in range(W):
        if pb[x, y] and not sub[x, y]:
            pb[x, y] = int(BOUNCE * (k ** 0.7))
        else:
            pb[x, y] = 0
band = band.filter(ImageFilter.GaussianBlur(3 * SS))

# ── 합성: 기본색 → 그림자 → 반사광 → 광택 순. paste(mask=)가 곧 lerp다 ──
img = Image.new("RGBA", (W, W), BASE + (255,))
img.paste(Image.new("RGBA", (W, W), DARK + (255,)), (0, 0), lo)
img.paste(Image.new("RGBA", (W, W), (255, 255, 255, 255)), (0, 0), band)
img.paste(Image.new("RGBA", (W, W), (255, 255, 255, 255)), (0, 0), hi)

# 알파 경계와 외곽선 바깥날이 **정확히 같아야 한다.**
#   ⚠PIL의 `width`는 경계 상자에서 **안쪽으로** 그린다(중심 정렬이 아니다). 알파를 조금이라도
#   크게 잡으면 그 틈으로 몸통 보라가 새어 검은 테 바깥에 보라 후광이 생긴다(실제로 그랬다).
img.putalpha(disc(R_BODY))
ImageDraw.Draw(img).ellipse(
    [C - R_BODY * SS, C - R_BODY * SS, C + R_BODY * SS, C + R_BODY * SS],
    outline=RIM, width=int(RIM_W * SS))

out = img.resize((S, S), Image.LANCZOS)
OUT.parent.mkdir(parents=True, exist_ok=True)
out.save(OUT)
print("wrote", OUT, out.size)
