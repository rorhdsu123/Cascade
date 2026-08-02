#!/usr/bin/env python3
"""블록 마스터 **임시본** 생성기 — art/block.png (180×180).

    python3 tools/make_block_placeholder.py

이건 최종 아트가 아니라 UI_ART_PLAN §6이 말하는 **최후 수단**이다. 디자이너가 §0에서
(가) 기하학 / (나) 질감 중 무엇을 고르든 진짜 파일이 오면 art/block.png를 덮어쓰면 된다
— 코드는 안 건드린다. 지우면 평면 사각형 렌더로 되돌아간다.

회색조 근백색 마스터인 이유: 게임 코드가 modulate(곱셈)로 6색을 입힌다. 어두우면 색이 죽는다.
명암은 일부러 약하게 잡았다 — 세게 주면 노랑이 올리브로 탁해진다(1차 시안에서 실제로 그랬다).
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

OUT = Path(__file__).resolve().parent.parent / "art" / "block.png"

S = 180          # 셀 90px의 2배(§5 배율 규칙)
SS = 4           # 슈퍼샘플링 — 라운드 가장자리 계단 제거
R = 26           # 라운드 반경(등배 기준)
PAD = 4          # 블록 사이 간격도 이 180 안에서 정한다(§4 P0 비고)

TOP, BOTTOM = 255, 214   # 수직 그라디언트(베벨의 기본). 폭이 좁을수록 색이 안 탁해진다
GLOSS = 40               # 상단 광택 세기
SHADE = 26               # 하단 안쪽 그림자 세기

W = S * SS
box = [PAD * SS, PAD * SS, W - PAD * SS - 1, W - PAD * SS - 1]

mask = Image.new("L", (W, W), 0)
ImageDraw.Draw(mask).rounded_rectangle(box, radius=R * SS, fill=255)

lum = Image.new("L", (W, W), 0)
d = ImageDraw.Draw(lum)
for y in range(W):
    d.line([(0, y), (W, y)], fill=int(TOP + (BOTTOM - TOP) * (y / (W - 1))))

gloss = Image.new("L", (W, W), 0)
ImageDraw.Draw(gloss).rounded_rectangle(
    [box[0] + 8 * SS, box[1] + 6 * SS, box[2] - 8 * SS, box[1] + int((box[3] - box[1]) * 0.34)],
    radius=int(R * SS * 0.7), fill=GLOSS)
gloss = gloss.filter(ImageFilter.GaussianBlur(6 * SS))

shade = Image.new("L", (W, W), 0)
ImageDraw.Draw(shade).rounded_rectangle(
    [box[0] + 5 * SS, box[1] + int((box[3] - box[1]) * 0.78), box[2] - 5 * SS, box[3] - 4 * SS],
    radius=int(R * SS * 0.7), fill=SHADE)
shade = shade.filter(ImageFilter.GaussianBlur(7 * SS))

pl, pg, ps = lum.load(), gloss.load(), shade.load()
for y in range(W):
    for x in range(W):
        pl[x, y] = max(0, min(255, pl[x, y] + pg[x, y] - ps[x, y]))

img = Image.merge("RGBA", (lum, lum, lum, mask)).resize((S, S), Image.LANCZOS)
OUT.parent.mkdir(parents=True, exist_ok=True)
img.save(OUT)
print("wrote", OUT, img.size)
