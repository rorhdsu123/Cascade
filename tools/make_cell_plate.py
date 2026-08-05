#!/usr/bin/env python3
"""빈 셀 판 생성 — art/cell.png.

레퍼런스(Block Blast 계열) 실측을 그대로 옮긴 물건이다. 왜 아트가 아니라 코드로 만드나:
**그릴 게 없다.** 레퍼런스의 빈 칸은 셀 안쪽 121px을 훑어도 색이 ±2밖에 안 움직인다
(그라데이션·하이라이트·텍스처 전부 0). 평면 사각형 + 라운드 + 어두운 홈이 전부다.

⚠**투명 여백이 아니라 홈을 칠한다**(캔버스 끝까지 불투명). 칸 사이를 뚫어 두면 뒤에 오는 것에
  따라 격자가 밝아졌다 어두워졌다 한다 — 존 색 전환(C_BG_PB)이 있어서 실제로 흔들린다.
  홈을 그림이 쥐면 배경이 뭐든 홈으로 읽힌다.

기하는 디자이너 v2 납품본과 같다: 타일이 캔버스 가장자리에서 3px 물러나 있어 이웃과 맞대면
6 텍스처px = 화면 3px 홈이 된다(레퍼런스 실측 2.7px).

    python3 tools/make_cell_plate.py
    godot --path . --import       # 새 PNG는 1회 필요
"""
from PIL import Image, ImageDraw

SIDE = 180
SS = 4                 # 슈퍼샘플 배율 — 라운드 모서리 계단 제거
GROOVE = (27, 34, 64)  # 홈 #1B2240 — 타일보다 어둡다(밝은 테가 아니라 파인 홈이어야 한다)
FACE = (33, 40, 74)    # 타일 면 #21284A
INSET = 3              # 캔버스 가장자리 → 타일. 이웃과 맞대면 홈 폭이 이 값의 2배가 된다
RADIUS = 26            # 셀의 ~15%. 레퍼런스 실측(134px 셀에 반경 20)과 같은 비율

OUT = "art/cell.png"


def main() -> None:
    im = Image.new("RGB", (SIDE * SS, SIDE * SS), GROOVE)
    d = ImageDraw.Draw(im)
    d.rounded_rectangle(
        [INSET * SS, INSET * SS, (SIDE - INSET) * SS - 1, (SIDE - INSET) * SS - 1],
        RADIUS * SS,
        fill=FACE,
    )
    im.resize((SIDE, SIDE), Image.LANCZOS).save(OUT)
    print(f"wrote {OUT}  {SIDE}x{SIDE}  face={FACE} groove={GROOVE} inset={INSET} r={RADIUS}")


if __name__ == "__main__":
    main()
