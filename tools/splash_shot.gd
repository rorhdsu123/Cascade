extends SceneTree
# 부트 스플래시(엔진 로고 자리) 시안 렌더 — 정지 프레임 6종.
#   godot --path . --script tools/splash_shot.gd -- <출력디렉터리>
#
# 워드마크는 새로 그리지 않는다 — 클리어 연출에서 확정된 시안②(Main.gd `WM_*`)를 그대로 쓴다.
#   스플래시는 게임이 뜨기 직전 0.x초짜리 첫 프레임이라, 다른 얼굴을 새로 만들면 브랜드가 둘이 된다.
#   시안이 가르는 축은 워드마크 자체가 아니라 **주변**(태그라인·아이콘·배경 명도·블록 띠)이다.
#
# ⚠창 모드 필수 — --headless는 렌더 텍스처가 null이라 크래시한다.
# 해상도는 SubViewport로 논리 800x1280의 S배를 뜬다(폰트를 확대하지 않고 큰 치수로 새로 조판).

const S: float = 2.0                       # 출력 배율 → 1600x2560
const C_BG := Color("#0d0d1a")             # = project.godot default_clear_color / boot_splash bg_color
const C_CREAM := Color("#f4e6c8")          # 2차 납품 패널 톤(밝은 판)
const C_GOLD := Color("#ffd23b")
const C_TAG := Color(0.55, 0.72, 0.95)

var out_dir: String = ""


class SplashCanvas extends Node2D:
	var fnt: Font
	var variant: int = 0
	var icon_tex: Texture2D = null
	var block_tex: Texture2D = null
	var tag_text: String = ""      # 변형 8(문구 후보)에서 갈아 끼운다. 빈 문자열 = 문구 없음

	const S: float = 2.0
	const C_BG := Color("#0d0d1a")
	const C_CREAM := Color("#f4e6c8")
	const C_GOLD := Color("#ffd23b")
	const C_TAG := Color(0.55, 0.72, 0.95)
	const C_BLOB := Color("#7a45d6")
	const C_BLOB_D := Color("#2b1660")
	const C_GRAD_TOP := Color("#2a2358")   # 런처 아이콘 배경 위쪽과 같은 인디고
	const C_TAG_CREAM := Color("#cbc0a8")  # 태그라인 저채도 — 색은 워드마크가 독점한다
	const OPTICAL_Y: float = 1280.0 * 2.0 * 0.47   # 광학 중심(기하 50%가 아니라 47%)
	const CONT_MAXW: float = 560.0                 # = Main.gd MENU_WM_MAXW. 둘은 같이 움직인다

	const L1: String = "BLOCK"
	const L2: String = "CASTLE"
	const TAG: String = "PACKING DEFENSE"
	# 팔레트 6색(Main.gd COLORS 순) + 확정 배치: 1행 웜·쿨 교차 5색, 2행 골드 단색.
	var PAL: Array = [Color("#ff5a52"), Color("#ff8c1a"), Color("#ffd23b"),
					  Color("#35cf7a"), Color("#4a90ff"), Color("#d94fc8")]
	const L1_IDX: Array = [0, 3, 1, 4, 5]
	const TILT: Array = [-5.0, 3.0, -2.0, 4.0, -3.5, 2.5]
	const BOB: Array = [4.0, -6.0, 2.0, -4.0, 5.0, -3.0]
	const MAXW: float = 680.0
	const TRACK_EM: float = -0.03
	const DEPTH_EM: float = 0.11

	func _track(size: int) -> float:
		return float(size) * TRACK_EM

	func _line_w(text: String, size: int) -> float:
		var w: float = 0.0
		for i in range(text.length()):
			w += fnt.get_string_size(text[i], HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + _track(size)
		return w - _track(size)

	# 두 줄을 같은 폭으로 채운다 = 직사각 락업. 글자 수가 적은 BLOCK이 자동으로 커져 1행 우위가 생긴다.
	func _fit(text: String, maxw: float) -> int:
		var s: int = int(800.0 * S)
		while s > 40:
			if _line_w(text, s) <= maxw:
				return s
			s -= 2
		return s

	func _draw_line(text: String, size: int, baseline: float, cols: Array, bob_amp: float) -> void:
		var x: float = 400.0 * S - _line_w(text, size) * 0.5
		var xs: Array = []
		for i in range(text.length()):
			xs.append(x)
			x += fnt.get_string_size(text[i], HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + _track(size)
		var dep: int = int(round(float(size) * DEPTH_EM))
		var blob_o: int = int(round(float(size) * 0.20))
		var blob_i: int = int(round(float(size) * 0.15))

		# 패스1 — 보라 블롭(어두운 받침 → 밝은 링). 패스를 나눠야 뒤 글자의 블롭이 앞 글자 면을 안 덮는다.
		for i in range(text.length()):
			var ch: String = text[i]
			var cw: float = fnt.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
			var piv: Vector2 = Vector2(xs[i] + cw * 0.5, baseline - float(size) * 0.32 + BOB[i % BOB.size()] * bob_amp)
			draw_set_transform(piv, deg_to_rad(TILT[i % TILT.size()]), Vector2.ONE)
			var base: Vector2 = Vector2(xs[i], baseline) - piv
			draw_string_outline(fnt, base + Vector2(0.0, float(dep) + 10.0 * S), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size, blob_o, C_BLOB_D)
			draw_string_outline(fnt, base + Vector2(0.0, float(dep)), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size, blob_i, C_BLOB)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

		# 패스2 — 압출 몸통(깊이 램프) → 윗면 림라이트 → 면
		for i2 in range(text.length()):
			var ch2: String = text[i2]
			var cw2: float = fnt.get_string_size(ch2, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
			var piv2: Vector2 = Vector2(xs[i2] + cw2 * 0.5, baseline - float(size) * 0.32 + BOB[i2 % BOB.size()] * bob_amp)
			draw_set_transform(piv2, deg_to_rad(TILT[i2 % TILT.size()]), Vector2.ONE)
			var base2: Vector2 = Vector2(xs[i2], baseline) - piv2
			var col: Color = cols[i2 % cols.size()]
			for d in range(dep, 0, -1):
				var k: float = float(d) / float(dep)
				draw_string(fnt, base2 + Vector2(0.0, float(d)), ch2, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col.darkened(0.30 + 0.34 * k))
			draw_string(fnt, base2 + Vector2(0.0, -float(size) * 0.022), ch2, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col.lightened(0.55))
			draw_string(fnt, base2, ch2, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 락업 치수만 계산한다(그리기 전에 위치를 잡아야 하므로 분리).
	#   {s1, s2, gap, top_rel, bot_rel} — top/bot은 1행 베이스라인 기준 상대 좌표.
	func _wm_metrics(maxw: float) -> Dictionary:
		var s1: int = _fit(L1, maxw)
		var s2: int = _fit(L2, maxw)
		var gap: float = float(s1) * 0.72              # 2행은 1행 밑단을 살짝 파고든다
		return {"s1": s1, "s2": s2, "gap": gap,
				"top_rel": -0.75 * float(s1), "bot_rel": gap + 0.22 * float(s2)}

	func _draw_wordmark_at(b1: float, m: Dictionary) -> void:
		var cols: Array = []
		for idx in L1_IDX:
			cols.append(PAL[int(idx)])
		_draw_line(L1, int(m["s1"]), b1, cols, 1.0)
		_draw_line(L2, int(m["s2"]), b1 + float(m["gap"]), [C_GOLD], 0.3)   # 2행 흔들림 0.3배 = 오정렬로 안 읽힘

	# 락업을 center_y에 앉히고 [윗변, 아랫변]을 돌려준다(주변 요소를 붙일 기준).
	func _draw_wordmark(center_y: float, maxw: float) -> Array:
		var m: Dictionary = _wm_metrics(maxw)
		var b1: float = center_y - (float(m["top_rel"]) + float(m["bot_rel"])) * 0.5
		_draw_wordmark_at(b1, m)
		return [b1 + float(m["top_rel"]), b1 + float(m["bot_rel"])]

	# 세로 그라데이션 — 런처 아이콘 배경(adaptive_bg)과 같은 재질.
	#   순평면 어두운 화면은 OLED에서 '꺼진 화면'과 구분이 안 된다(웹은 이 화면이 수 초 떠 있다).
	func _draw_gradient_bg(top: Color, bot: Color) -> void:
		var w: float = 800.0 * S
		var h: float = 1280.0 * S
		var pts := PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(0, h)])
		draw_polygon(pts, PackedColorArray([top, top, bot, bot]))

	# 워드마크 뒤만 밝은 타원 발광. **가장자리는 네 변 모두 C_BG**다.
	#   왜 세로 그라데이션이 아니라 이것인가 — 엔진은 스플래시를 화면 비율에 맞춰 '레터박스'로 앉히고
	#   남는 자리를 bg_color로 칠한다. 그림 가장자리가 bg_color와 다르면 그 경계가 화면을 가로지르는
	#   띠로 보인다(5:8 그림 + 9:19.5 폰 = 위아래 13%씩). 네 변이 전부 bg_color면 어떤 비율에서도
	#   이음매가 안 생긴다 — 웹의 가로 창까지 포함해서.
	func _draw_glow_bg(center: Color, edge: Color, cy: float) -> void:
		var w: float = 800.0 * S
		var h: float = 1280.0 * S
		draw_rect(Rect2(0, 0, w, h), edge)
		# ⚠rx는 화면 반폭을 넘기면 안 된다 — 넘기면 좌우 가장자리가 bg_color보다 밝아져 위 목적이 깨진다.
		var rx: float = w * 0.52
		var ry: float = h * 0.58
		var rings: int = 48                      # 48단계면 8비트에서 계단이 안 보인다
		for i in range(rings, 0, -1):
			var k: float = float(i) / float(rings)     # 1=가장 바깥
			var pts := PackedVector2Array()
			for a in range(40):
				var th: float = TAU * float(a) / 40.0
				pts.append(Vector2(w * 0.5 + cos(th) * rx * k, cy + sin(th) * ry * k))
			# 바깥은 edge, 안쪽은 center. 제곱으로 밀어 중심 근처를 넓게 밝힌다.
			draw_polygon(pts, PackedColorArray([edge.lerp(center, (1.0 - k) * (1.0 - k))]))

	# 자간 넓힌 소문자 없는 태그라인. 밝은 판에선 색을 내려야 뜬다.
	func _draw_tag(y: float, col: Color, track: float = 6.0, text: String = TAG) -> void:
		if text.is_empty():
			return
		var size: int = int(26.0 * S)
		var w: float = 0.0
		for i in range(text.length()):
			w += fnt.get_string_size(text[i], HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + track * S
		w -= track * S
		var x: float = 400.0 * S - w * 0.5
		for i2 in range(text.length()):
			draw_string(fnt, Vector2(x, y), text[i2], HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
			x += fnt.get_string_size(text[i2], HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + track * S

	func _draw_blocks_row(y: float, w: float, gap: float) -> void:
		var cols: Array = [PAL[0], PAL[2], PAL[4]]     # 앱 아이콘의 빨·노·파와 같은 3색
		var total: float = w * 3.0 + gap * 2.0
		var x: float = 400.0 * S - total * 0.5
		for i in range(3):
			var r := Rect2(x, y, w, w)
			if block_tex != null:
				draw_texture_rect(block_tex, r, false, cols[i])
			else:
				draw_rect(r, cols[i])
			x += w + gap

	func _draw() -> void:
		var full := Rect2(0.0, 0.0, 800.0 * S, 1280.0 * S)
		match variant:
			0:      # A · 워드마크만 — 클리어 연출과 같은 얼굴
				draw_rect(full, C_BG)
				_draw_wordmark(640.0 * S, MAXW * S)
			1:      # B · 워드마크 + 태그라인
				draw_rect(full, C_BG)
				var e1: Array = _draw_wordmark(600.0 * S, MAXW * S)
				_draw_tag(float(e1[1]) + 96.0 * S, C_TAG)
			2:      # C · 조용한 안 — 허브 화면과 같은 골드 한 줄
				draw_rect(full, C_BG)
				var t: String = "BLOCK CASTLE"    # ⚠화면에선 띄어 쓴다(붙이면 단어 경계가 사라진다)
				var ts: int = _fit(t, 700.0 * S)
				var tw: float = _line_w(t, ts)
				draw_string(fnt, Vector2(400.0 * S - tw * 0.5, 620.0 * S), t, HORIZONTAL_ALIGNMENT_LEFT, -1, ts, C_GOLD)
				_draw_tag(700.0 * S, C_TAG)
			3:      # D · 앱 아이콘 + 워드마크 — 스토어 아이콘과 첫 화면을 잇는다
				draw_rect(full, C_BG)
				# 아이콘은 배경 있는 icon_512 대신 **투명 전경**(adaptive_fg)을 쓴다 —
				#   사각 판을 얹으면 배경색이 미묘하게 달라 '붙여놓은 스티커'로 읽힌다.
				#   ⚠전경 PNG는 캔버스 여백이 커서(432 중 모티프 ~60%) 파일 크기 그대로 두면 작아 보인다.
				var isz: float = 620.0 * S
				if icon_tex != null:
					draw_texture_rect(icon_tex, Rect2(400.0 * S - isz * 0.5, 190.0 * S, isz, isz), false)
				_draw_wordmark(870.0 * S, 640.0 * S)
			4:      # E · 밝은 크림 배경 — 2차 납품 패널 톤(bg_color도 같이 바꿔야 함)
				draw_rect(full, C_CREAM)
				var e4: Array = _draw_wordmark(600.0 * S, MAXW * S)
				_draw_tag(float(e4[1]) + 96.0 * S, Color(0.35, 0.30, 0.45))
			5:      # F · 워드마크 + 블록 3개 띠 — '이건 블록 게임이다'를 한 줄로
				draw_rect(full, C_BG)
				var e5: Array = _draw_wordmark(580.0 * S, MAXW * S)
				_draw_blocks_row(float(e5[1]) + 90.0 * S, 130.0 * S, 22.0 * S)
			6:      # A′ · B를 세 군데 고친 것 — 감사(analysis) 결과 반영본
				#   ① 인디고 그라데이션 배경 ② 광학 중심 47%(기하 중심 50%는 처져 보인다)
				#   ③ 태그라인을 저채도 크림으로 — 하늘색은 팔레트에서 유일한 '차가운 소품'이라
				#     워드마크와 색 주도권을 나눠 갖는다. 스플래시에서 색을 쓰는 요소는 하나여야 한다.
				_draw_gradient_bg(C_GRAD_TOP, C_BG)
				var m6: Dictionary = _wm_metrics(MAXW * S)
				var tgap: float = 104.0 * S
				var tcap: float = 26.0 * S * 0.72                      # 태그라인 캡 높이 근사
				var blk_t: float = float(m6["top_rel"])
				var blk_b: float = float(m6["bot_rel"]) + tgap + tcap
				var b6: float = OPTICAL_Y - (blk_t + blk_b) * 0.5
				_draw_wordmark_at(b6, m6)
				_draw_tag(b6 + float(m6["bot_rel"]) + tgap, C_TAG_CREAM, 7.0)
			7:      # D′ · 아이콘안을 두 덩어리로 정리한 것
				#   원안은 아이콘↔워드마크 간격이 워드마크 두 줄 사이 간격과 경쟁해 3덩어리로 읽혔다.
				#   전경 PNG의 투명 여백(432 중 모티프는 x102~333 · y83~333)을 잘라내야 간격을 실제로 쥔다.
				_draw_gradient_bg(C_GRAD_TOP, C_BG)
				var m7: Dictionary = _wm_metrics(600.0 * S)
				var iw: float = 300.0 * S                              # 모티프 실폭
				var ih: float = iw * (250.0 / 231.0)
				var igap: float = 132.0 * S                            # 두 덩어리 사이 = 워드마크 내부 간격의 몇 배
				var tot_t: float = -ih - igap                          # 1행 베이스라인 기준
				var b7: float = OPTICAL_Y - (tot_t + float(m7["bot_rel"]) + float(m7["top_rel"])) * 0.5
				if icon_tex != null:
					var dst := Rect2(400.0 * S - iw * 0.5, b7 + float(m7["top_rel"]) - igap - ih, iw, ih)
					draw_texture_rect_region(icon_tex, dst, Rect2(102, 83, 231, 250))
				_draw_wordmark_at(b7, m7)
			8:      # 연속성 안 — 워드마크 폭을 허브(MENU_WM_MAXW)와 같은 560으로 맞춘 것.
				#   레퍼런스 실측: 스플래시와 홈이 **같은 크기** 로고를 쓰고 위치만 다르다(폭 71%).
				#   우리 기존 안은 85%라 홈에 그대로 못 올린다 → 둘 다 70%로 내린다.
				#   문구는 tag_text로 갈아 끼운다(후보 비교).
				_draw_glow_bg(C_GRAD_TOP, C_BG, OPTICAL_Y)
				var m8: Dictionary = _wm_metrics(CONT_MAXW * S)
				var tg8: float = 92.0 * S
				var tc8: float = 26.0 * S * 0.72
				var bt8: float = float(m8["top_rel"])
				var bb8: float = float(m8["bot_rel"]) + (tg8 + tc8 if not tag_text.is_empty() else 0.0)
				var b8: float = OPTICAL_Y - (bt8 + bb8) * 0.5
				_draw_wordmark_at(b8, m8)
				_draw_tag(b8 + float(m8["bot_rel"]) + tg8, C_TAG_CREAM, 7.0, tag_text)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else "/tmp"
	if not out_dir.ends_with("/"):
		out_dir += "/"

	var sf: Font = ThemeDB.fallback_font
	var baloo := load("res://fonts/Baloo2.ttf") as FontFile
	var f: Font = sf
	if baloo != null:
		baloo.fallbacks = [sf]
		var fv := FontVariation.new()
		fv.base_font = baloo
		var ts := TextServerManager.get_primary_interface()
		fv.variation_opentype = {ts.name_to_tag("wght"): 800}
		f = fv

	var vp := SubViewport.new()
	vp.size = Vector2i(int(800.0 * S), int(1280.0 * S))
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)

	var canvas := SplashCanvas.new()
	canvas.fnt = f
	canvas.icon_tex = load("res://icons/adaptive_fg_432.png") as Texture2D
	canvas.block_tex = load("res://art/block.png") as Texture2D
	vp.add_child(canvas)
	await process_frame

	var names: Array = ["A_wordmark", "B_tagline", "C_quiet_gold", "D_icon", "E_cream", "F_blocks",
					   "Ap_refined", "Dp_icon_refined"]
	for v in range(names.size()):
		canvas.variant = v
		canvas.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		vp.get_texture().get_image().save_png("%s%d_%s.png" % [out_dir, v, names[v]])
		print("shot ", names[v])

	# 문구 후보 — 구조는 전부 같고 셋째 줄만 다르다. 판단할 축이 문구 하나가 되도록 나머지를 고정한다.
	var tags: Array = [["keeper", "CASTLE KEEPER"], ["defender", "ENDLESS DEFENDER"],
					   ["keepthe", "KEEP THE CASTLE"], ["none", ""]]
	canvas.variant = 8
	for t in tags:
		canvas.tag_text = String(t[1])
		canvas.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		vp.get_texture().get_image().save_png("%s8_tag_%s.png" % [out_dir, String(t[0])])
		print("shot tag ", t[0])
	print("DONE")
	quit()
