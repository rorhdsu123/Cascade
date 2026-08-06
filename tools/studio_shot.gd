extends SceneTree
# 스튜디오(팀) 로고 화면 시안 렌더 — 정지 프레임.
#   godot --path . --script tools/studio_shot.gd -- <출력디렉터리>
#
# 팀명 = EggTart Studio.
#
# 이 화면은 부팅 순서의 **첫 칸**이다: 스튜디오 → 게임 로고 → 홈.
#   레퍼런스(Block Blast) 60fps 실측이 이 자리의 규격을 이미 정해뒀다 —
#     · 화면 세로 44~56%(게임 로고보다 아래 = 거의 정중앙)
#     · 가로 폭 63%(게임 로고는 71% → 스튜디오가 한 급 작다)
#     · **흰 글자 단색** · 배경은 게임 로고 화면과 픽셀 단위로 같은 것 · 전환은 하드컷 · 0.52초
#   그래서 배경(_draw_glow_bg)은 tools/splash_shot.gd 변형8·Main.gd _draw_bg_glow와 **같은 값**이다.
#   여기서 배경을 다르게 만들면 스튜디오→스플래시 컷이 그대로 눈에 보인다.
#
# 시안이 가르는 축은 둘뿐이다:
#   ① 글자만인가, 마크(에그타르트)를 얹는가
#   ② 마크를 얹는다면 흰 단색인가, 크림·골드 채색인가
#     — 채색은 "스플래시에서 색을 쓰는 요소는 하나여야 한다"는 기존 원칙과 정면으로 부딪힌다.
#       단 그 원칙이 지키려던 건 '게임 로고가 색을 독점한다'이고, 스튜디오 화면엔 게임 로고가 없다.
#       판단은 렌더를 보고 한다.
#
# ⚠창 모드 필수 — --headless는 렌더 텍스처가 null이라 크래시한다.

const S: float = 2.0                        # 출력 배율 → 1600x2560
const SHIP_VARIANT: int = 4                 # 확정안 D(채색 타르트 마크 + 두 줄 글자) — 2026-08-06 유저 선택


class StudioCanvas extends Node2D:
	var f_bold: Font
	var f_mid: Font
	var variant: int = 0

	const S: float = 2.0
	const C_BG := Color("#0d0d1a")
	const C_GRAD_TOP := Color("#2a2358")     # 발광 중심색 = 스플래시·홈과 동일
	const GLOW_CY: float = 1280.0 * 2.0 * 0.47
	const C_WHITE := Color("#ffffff")
	const C_CRUST := Color("#f4e6c8")        # 2차 납품 패널 톤 = 타르트 껍질
	const C_CUSTARD := Color("#ffd23b")      # 게임 골드 = 커스터드. 우연이 아니라 이름이 준 선물이다
	const C_SPOT := Color("#7a4a15")         # 그을음 — 밝은 캐러멜(#c98a2e)로 하면 초코칩 쿠키로 읽혔다
	const C_CRUST_D := Color("#cbb693")      # 껍질 안쪽 벽. darkened()는 크림을 회색으로 만든다(따뜻하게 직접 지정)

	const NAME1: String = "EGGTART"
	const NAME2: String = "STUDIO"
	const ONELINE: String = "EGGTART STUDIO"
	const ONELINE_SP: String = "EGG TART STUDIO"
	const BAND_W: float = 800.0 * 2.0 * 0.63     # 레퍼런스 실측 가로 폭 63%
	const CENTER_Y: float = 1280.0 * 2.0 * 0.50  # 44~56% 밴드의 중심

	# ── 조판 ──
	func _line_w(fnt: Font, text: String, size: int, track: float) -> float:
		var w: float = 0.0
		for i in range(text.length()):
			w += fnt.get_string_size(text[i], HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + track
		return w - track

	func _fit(fnt: Font, text: String, maxw: float, track_em: float) -> int:
		var s: int = int(400.0 * S)
		while s > 20:
			if _line_w(fnt, text, s, float(s) * track_em) <= maxw:
				return s
			s -= 2
		return s

	func _draw_tracked(fnt: Font, text: String, size: int, track: float, baseline: float, col: Color) -> void:
		var x: float = 400.0 * S - _line_w(fnt, text, size, track) * 0.5
		for i in range(text.length()):
			draw_string(fnt, Vector2(x, baseline), text[i], HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
			x += fnt.get_string_size(text[i], HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + track

	# ── 에그타르트 마크(위에서 본 모습) ──
	# 1차 렌더가 **해**로 읽혔다. 원인 셋: 주름이 깊고(진폭 7.5%) 개수가 적어 뾰족했고,
	#   껍질 테가 얇아 '고리'가 아니라 테두리 장식이 됐고, 반점 3개가 눈·코로 읽혔다.
	# 에그타르트를 에그타르트로 만드는 건 결국 둘이다:
	#   ① **두꺼운 껍질 고리**(반지름의 1/3) — 얕고 촘촘한 주름이 그 고리 위에 얹힌다
	#   ② **가장자리에 몰린 큰 그을음 자국** — 이게 없으면 그냥 노란 원이다. 중심을 피해야 얼굴이 안 된다.
	const FLUTES: int = 18
	const FLUTE_AMP: float = 0.038
	const CUSTARD_R: float = 0.66      # 껍질 고리 두께 = r의 34%

	func _scallop(c: Vector2, r: float, amp: float) -> PackedVector2Array:
		var pts := PackedVector2Array()
		var n: int = FLUTES * 10
		for i in range(n):
			var th: float = TAU * float(i) / float(n)
			var rr: float = r * (1.0 + amp * cos(float(FLUTES) * th))
			pts.append(c + Vector2(cos(th) * rr, sin(th) * rr))
		return pts

	func _ring(c: Vector2, r_out: float, r_in: float, col: Color) -> void:
		var outer: PackedVector2Array = _scallop(c, r_out, FLUTE_AMP)
		var n: int = outer.size()
		for i in range(n):
			var j: int = (i + 1) % n
			var a: Vector2 = outer[i]
			var b: Vector2 = outer[j]
			var ia: Vector2 = c + (a - c).normalized() * r_in
			var ib: Vector2 = c + (b - c).normalized() * r_in
			draw_colored_polygon(PackedVector2Array([a, b, ib, ia]), col)

	# 그을음 — 커스터드 **가장자리 고리**에 몰아 놓는다. 크기가 고르고 안쪽에 흩어지면 초코칩이 된다.
	#   원 두 개를 겹쳐 찌그러뜨린다(정원이면 물방울로 읽힌다).
	func _draw_char_spots(c: Vector2, r: float, col: Color) -> void:
		var spots: Array = [[-0.26, -0.40, 0.13, 0.09], [0.30, -0.28, 0.10, 0.07],
							[0.40, 0.16, 0.12, 0.08], [-0.05, 0.44, 0.09, 0.06],
							[-0.42, 0.06, 0.08, 0.055]]
		for s in spots:
			var p: Vector2 = c + Vector2(float(s[0]) * r, float(s[1]) * r)
			draw_circle(p, float(s[2]) * r, col)
			draw_circle(p + Vector2(float(s[2]) * r * 0.70, float(s[3]) * r * 0.40), float(s[3]) * r, col)

	func _draw_tart_color(c: Vector2, r: float) -> void:
		# 압출 그림자 — 게임 블록과 같은 언어(아래로 깊이 램프)
		var dep: int = int(r * 0.11)
		for d in range(dep, 0, -1):
			var k: float = float(d) / float(dep)
			draw_colored_polygon(_scallop(c + Vector2(0.0, float(d)), r, FLUTE_AMP),
								 C_CRUST.darkened(0.45 + 0.25 * k))
		draw_colored_polygon(_scallop(c, r, FLUTE_AMP), C_CRUST)
		# 껍질 안쪽 벽(그늘) → 커스터드. 벽이 보여야 '틀'이 되고 납작한 원이 안 된다.
		draw_circle(c, r * (CUSTARD_R + 0.055), C_CRUST_D)
		draw_circle(c + Vector2(0.0, -r * 0.015), r * CUSTARD_R, C_CUSTARD)
		_draw_char_spots(c, r, C_SPOT)

	# 흰 단색판 — 색을 뺀 자리를 명도로 메운다(고리는 solid, 커스터드는 반투명).
	func _draw_tart_mono(c: Vector2, r: float) -> void:
		_ring(c, r, r * (CUSTARD_R + 0.02), C_WHITE)
		draw_circle(c, r * CUSTARD_R, Color(1, 1, 1, 0.30))
		_draw_char_spots(c, r, Color(1, 1, 1, 0.80))

	# ── 배경 ── 스플래시·홈과 같은 발광. 네 변은 전부 C_BG(레터박스 이음매 방지).
	func _draw_glow_bg() -> void:
		var w: float = 800.0 * S
		var h: float = 1280.0 * S
		draw_rect(Rect2(0, 0, w, h), C_BG)
		var rx: float = w * 0.52
		var ry: float = h * 0.58
		var rings: int = 48
		for i in range(rings, 0, -1):
			var k: float = float(i) / float(rings)
			var pts := PackedVector2Array()
			for a in range(40):
				var th: float = TAU * float(a) / 40.0
				pts.append(Vector2(w * 0.5 + cos(th) * rx * k, GLOW_CY + sin(th) * ry * k))
			draw_polygon(pts, PackedColorArray([C_BG.lerp(C_GRAD_TOP, (1.0 - k) * (1.0 - k))]))

	# 두 줄 락업 치수 — 큰 이름 + 폭을 맞춘 작은 'STUDIO'.
	#   STUDIO의 자간을 벌려 이름과 **같은 폭**으로 만든다 = 두 줄이 하나의 직사각 덩어리가 된다.
	func _stack_metrics() -> Dictionary:
		var s1: int = _fit(f_bold, NAME1, BAND_W, 0.02)
		var s2: int = int(float(s1) * 0.30)
		var raw: float = _line_w(f_mid, NAME2, s2, 0.0)
		var track2: float = (BAND_W - raw) / float(NAME2.length() - 1)
		return {"s1": s1, "s2": s2, "t1": float(s1) * 0.02, "t2": track2,
				"gap": float(s1) * 0.46,
				"top_rel": -0.74 * float(s1), "bot_rel": float(s1) * 0.46 + 0.10 * float(s2)}

	func _draw_stack(b1: float, m: Dictionary, col: Color) -> void:
		_draw_tracked(f_bold, NAME1, int(m["s1"]), float(m["t1"]), b1, col)
		_draw_tracked(f_mid, NAME2, int(m["s2"]), float(m["t2"]), b1 + float(m["gap"]), col)

	func _draw() -> void:
		_draw_glow_bg()
		match variant:
			0:      # A · 한 줄, 글자만 — 레퍼런스를 글자 그대로 따른 안
				var s0: int = _fit(f_bold, ONELINE, BAND_W, 0.03)
				_draw_tracked(f_bold, ONELINE, s0, float(s0) * 0.03, CENTER_Y + float(s0) * 0.35, C_WHITE)
			1:      # A′ · 띄어 쓴 것 — 'EGG TART'로 읽히나 확인용(브랜드 표기는 EggTart 한 단어)
				var s1b: int = _fit(f_bold, ONELINE_SP, BAND_W, 0.03)
				_draw_tracked(f_bold, ONELINE_SP, s1b, float(s1b) * 0.03, CENTER_Y + float(s1b) * 0.35, C_WHITE)
			2:      # B · 두 줄 락업, 글자만 — 이름이 커지고 STUDIO가 밑단 자막이 된다
				var m2: Dictionary = _stack_metrics()
				var b2: float = CENTER_Y - (float(m2["top_rel"]) + float(m2["bot_rel"])) * 0.5
				_draw_stack(b2, m2, C_WHITE)
			3:      # C · 흰 단색 마크 + 두 줄 — 규약(흰 글자 단색)을 지키면서 형태를 준다
				var m3: Dictionary = _stack_metrics()
				var r3: float = BAND_W * 0.155
				var g3: float = r3 * 0.66
				var tot3: float = (r3 * 2.0 + g3) + (float(m3["bot_rel"]) - float(m3["top_rel"]))
				var top3: float = CENTER_Y - tot3 * 0.5
				_draw_tart_mono(Vector2(400.0 * S, top3 + r3), r3)
				_draw_stack(top3 + r3 * 2.0 + g3 - float(m3["top_rel"]), m3, C_WHITE)
			4:      # D · 채색 마크 + 흰 글자 — 이름값을 그림으로 갚는 안
				var m4: Dictionary = _stack_metrics()
				var r4: float = BAND_W * 0.165
				var g4: float = r4 * 0.64
				var tot4: float = (r4 * 2.0 + g4) + (float(m4["bot_rel"]) - float(m4["top_rel"]))
				var top4: float = CENTER_Y - tot4 * 0.5
				_draw_tart_color(Vector2(400.0 * S, top4 + r4), r4)
				_draw_stack(top4 + r4 * 2.0 + g4 - float(m4["top_rel"]), m4, C_WHITE)
			5:      # E · 가로 락업 — 마크 왼쪽, 글자 오른쪽. 문서·슬라이드에 그대로 쓰는 형태다
				var s5: int = int(BAND_W * 0.19)
				var t5: float = float(s5) * 0.02
				var s5b: int = int(float(s5) * 0.34)
				var w5: float = _line_w(f_bold, NAME1, s5, t5)
				var raw5: float = _line_w(f_mid, NAME2, s5b, 0.0)
				var tr5b: float = (w5 - raw5) / float(NAME2.length() - 1)
				var r5: float = float(s5) * 0.62
				var g5: float = r5 * 0.52
				var tot5: float = r5 * 2.0 + g5 + w5
				var x5: float = 400.0 * S - tot5 * 0.5
				_draw_tart_color(Vector2(x5 + r5, CENTER_Y), r5)
				var tx: float = x5 + r5 * 2.0 + g5
				var b5: float = CENTER_Y - float(s5) * 0.06
				for i in range(NAME1.length()):
					draw_string(f_bold, Vector2(tx, b5), NAME1[i], HORIZONTAL_ALIGNMENT_LEFT, -1, s5, C_WHITE)
					tx += f_bold.get_string_size(NAME1[i], HORIZONTAL_ALIGNMENT_LEFT, -1, s5).x + t5
				var tx2: float = x5 + r5 * 2.0 + g5
				var b5b: float = b5 + float(s5) * 0.40
				for j in range(NAME2.length()):
					draw_string(f_mid, Vector2(tx2, b5b), NAME2[j], HORIZONTAL_ALIGNMENT_LEFT, -1, s5b, C_WHITE)
					tx2 += f_mid.get_string_size(NAME2[j], HORIZONTAL_ALIGNMENT_LEFT, -1, s5b).x + tr5b
			6:      # 마크 확대 검수용 — 화면에 안 쓴다. 채색·단색을 나란히 크게.
				_draw_tart_color(Vector2(400.0 * S, 480.0 * S), 280.0 * S)
				_draw_tart_mono(Vector2(400.0 * S, 980.0 * S), 280.0 * S)


func _initialize() -> void:
	_run.call_deferred()


func _mkfont(weight: int) -> Font:
	var sf: Font = ThemeDB.fallback_font
	var baloo := load("res://fonts/Baloo2.ttf") as FontFile
	if baloo == null:
		return sf
	baloo.fallbacks = [sf]
	var fv := FontVariation.new()
	fv.base_font = baloo
	var ts := TextServerManager.get_primary_interface()
	fv.variation_opentype = {ts.name_to_tag("wght"): weight}
	return fv


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else "/tmp"
	if not out_dir.ends_with("/"):
		out_dir += "/"
	# `-- <dir> ship` = 확정안(D)을 부트 스플래시 그림으로 굽는다. 시안 렌더는 안 돈다.
	var ship: bool = args.size() > 1 and String(args[1]) == "ship"

	var vp := SubViewport.new()
	vp.size = Vector2i(int(800.0 * S), int(1280.0 * S))
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)

	var canvas := StudioCanvas.new()
	canvas.f_bold = _mkfont(800)
	canvas.f_mid = _mkfont(600)
	vp.add_child(canvas)
	await process_frame

	if ship:
		canvas.variant = SHIP_VARIANT
		canvas.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		var dst: String = ProjectSettings.globalize_path("res://art/studio.png")
		vp.get_texture().get_image().save_png(dst)
		print("ship -> ", dst)
		quit()
		return

	var names: Array = ["A_oneline", "Ap_spaced", "B_stack", "C_mark_mono",
						"D_mark_color", "E_horizontal", "Z_mark_zoom"]
	for v in range(names.size()):
		canvas.variant = v
		canvas.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		vp.get_texture().get_image().save_png("%s%d_%s.png" % [out_dir, v, names[v]])
		print("shot ", names[v])
	print("DONE")
	quit()
