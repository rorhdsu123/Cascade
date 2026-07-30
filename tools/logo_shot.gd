extends SceneTree
# 클리어 연출 워드마크 시안 — 정지 프레임 렌더. 창 모드 필수(--headless는 렌더 텍스처 null).
#   레퍼런스(Block Blast 클리어): 1행=다색 브릭 글자 조립, 2행=단색 통짜가 강펀치 오버슛.
#   여기선 최종 안착 상태만 그려 자간·크기·읽힘을 먼저 확정한다(애니·파티클은 합의 후).
const OUT: String = "/private/tmp/claude-501/-Users-im-yujin-Desktop-Cascade-worktrees-stage/da1f7fc4-8514-4560-89c7-00eb54dcada2/scratchpad/logo"

const C_BG    := Color("#0d0d1a")
const C_RED   := Color("#ff5a52")
const C_ORANGE:= Color("#ff8c1a")
const C_YELL  := Color("#ffd23b")
const C_GREEN := Color("#35cf7a")
const C_BLUE  := Color("#4a90ff")
const C_PURPLE:= Color("#d94fc8")
# 글자 뒤 보라 덩어리 — 레퍼런스의 '블롭'. 밝은 보라 링 + 그 아래 어두운 받침으로 두께를 만든다.
const C_BLOB  := Color("#7a45d6")
const C_BLOB_D:= Color("#2b1660")

var canvas: Node2D


class LogoCanvas extends Node2D:
	var fnt: Font
	var variant: int = 0   # 0=2행 색 대비(다색/단색), 1=2행 모두 다색
	var show_studs: bool = true

	const C_BG    := Color("#0d0d1a")
	const C_BLOB  := Color("#7a45d6")
	const C_BLOB_D:= Color("#2b1660")

	const L1: String = "BLOCK"
	const L2: String = "CASTLE"
	# 팔레트 6색(Main.gd COLORS 순). 1행은 5색, 2행은 6색을 그대로 쓴다.
	var PAL: Array = [Color("#ff5a52"), Color("#ff8c1a"), Color("#ffd23b"),
					  Color("#35cf7a"), Color("#4a90ff"), Color("#d94fc8")]
	# 글자별 기울기·높이 흔들림 — 레퍼런스는 글자마다 몇 도씩 틀어져 있고 그게 장난감 느낌의 절반이다.
	const TILT: Array = [-5.0, 3.0, -2.0, 4.0, -3.5, 2.5]
	const BOB: Array  = [4.0, -6.0, 2.0, -4.0, 5.0, -3.0]

	const MAXW: float = 680.0     # 논리 폭 800 - 좌우 여백(기울기로 바운딩이 커지므로 60씩)
	const DEPTH: int = 12         # 3D 압출 깊이(px)
	const TRACK_EM: float = -0.03  # 자간(em 비례). 절대 px로 두면 작은 줄에서 겹침이 풀려 두 줄 밀도가 어긋난다

	func _track(size: int) -> float:
		return float(size) * TRACK_EM

	# 두 줄을 '같은 폭'으로 채운다 = 직사각 락업. 글자 수가 적은 BLOCK이 자동으로 더 커져
	#   1행 우위의 위계가 생긴다(줄마다 상한을 두면 CASTLE이 더 커져 위계가 뒤집혔다).
	func _fit(text: String, cap: int) -> int:
		var s: int = cap
		while s > 40:
			var w: float = 0.0
			for i in range(text.length()):
				w += fnt.get_string_size(text[i], HORIZONTAL_ALIGNMENT_LEFT, -1, s).x + _track(s)
			if w <= MAXW:
				return s
			s -= 2
		return s

	func _line_w(text: String, size: int) -> float:
		var w: float = 0.0
		for i in range(text.length()):
			w += fnt.get_string_size(text[i], HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + _track(size)
		return w - _track(size)

	# 한 줄을 그린다. 패스를 나눠야 뒤 글자의 블롭이 앞 글자의 면을 덮지 않는다.
	func _draw_line(text: String, size: int, baseline: float, cols: Array, studs: bool, bob_amp: float = 1.0) -> void:
		var w: float = _line_w(text, size)
		var x: float = 400.0 - w * 0.5
		var xs: Array = []
		for i in range(text.length()):
			xs.append(x)
			x += fnt.get_string_size(text[i], HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + _track(size)

		var blob_o: int = int(round(float(size) * 0.20))
		var blob_i: int = int(round(float(size) * 0.15))

		# 패스1 — 보라 블롭(어두운 받침 → 밝은 링). 글자들이 겹쳐 하나의 덩어리로 읽힌다.
		for i in range(text.length()):
			var ch: String = text[i]
			var cw: float = fnt.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
			var piv: Vector2 = Vector2(xs[i] + cw * 0.5, baseline - float(size) * 0.32 + BOB[i % BOB.size()] * bob_amp)
			draw_set_transform(piv, deg_to_rad(TILT[i % TILT.size()]), Vector2.ONE)
			var base: Vector2 = Vector2(xs[i], baseline) - piv
			var dep0: int = int(round(float(size) * 0.11))
			draw_string_outline(fnt, base + Vector2(0, dep0 + 10), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size, blob_o, C_BLOB_D)
			draw_string_outline(fnt, base + Vector2(0, dep0), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size, blob_i, C_BLOB)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

		# 패스2 — 압출 몸통 + 윗면 + 스터드
		for i in range(text.length()):
			var ch2: String = text[i]
			var cw2: float = fnt.get_string_size(ch2, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
			var piv2: Vector2 = Vector2(xs[i] + cw2 * 0.5, baseline - float(size) * 0.32 + BOB[i % BOB.size()] * bob_amp)
			draw_set_transform(piv2, deg_to_rad(TILT[i % TILT.size()]), Vector2.ONE)
			var base2: Vector2 = Vector2(xs[i], baseline) - piv2
			var col: Color = cols[i % cols.size()]
			var dep: int = int(round(float(size) * 0.11))
			# ① 압출 몸통 — 단색이면 판판하다. 깊을수록 어둡게 램프를 줘야 원기둥처럼 말린다.
			for d in range(dep, 0, -1):
				var k: float = float(d) / float(dep)         # 1=가장 깊은 곳
				var body: Color = col.darkened(0.30 + 0.34 * k)
				draw_string(fnt, base2 + Vector2(0, d), ch2, HORIZONTAL_ALIGNMENT_LEFT, -1, size, body)
			# ② 윗면 림라이트 — 면보다 살짝 위에 밝은 복제를 깔면 윗변에만 밝은 테가 삐져나온다.
			if true:
				draw_string(fnt, base2 + Vector2(0, -float(size) * 0.022), ch2, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col.lightened(0.55))
			draw_string(fnt, base2, ch2, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
			# ③ 안쪽 베벨 — 면 위에 살짝 축소·상향한 밝은 복제. 면 중앙이 부풀어 보인다.
			if false:
				draw_set_transform(piv2, deg_to_rad(TILT[i % TILT.size()]), Vector2(0.93, 0.93))
				draw_string(fnt, base2 + Vector2(0, -float(size) * 0.03), ch2, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col.lightened(0.22))
				draw_set_transform(piv2, deg_to_rad(TILT[i % TILT.size()]), Vector2.ONE)
			if studs:
				# 브릭 스터드 — 글자 윗면에 '반쯤 박혀' 있어야 한다. 띄우면 눈알로 읽힌다(v0 실측).
				var top: float = base2.y - float(size) * 0.72   # Baloo2 캡 높이 근사
				var sr: float = float(size) * 0.062
				for k in range(2):
					var sx: float = base2.x + cw2 * (0.30 + 0.40 * float(k))
					draw_circle(Vector2(sx, top + sr * 0.55), sr, col.lightened(0.45))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 5시안 = (1행 색 배치) × (2행 색). 구조는 전부 동일, 색만 다르다.
	#   R빨 O주 Y노 G초 B파 P마젠타 / 골드=팔레트 노랑, 앰버=노랑을 주황 쪽으로 민 것, 크림=중성 흰기
	const GOLD  := Color("#ffd23b")
	const AMBER := Color("#ffab1f")
	const CREAM := Color("#fff1cf")

	# 확정안(시안②) — 1행 웜·쿨 교차 빨·초·주·파·마젠타 + 2행 골드.
	#   기각: 마젠타 L(보라 블롭에 먹힘) / 2행 앰버(전체 웜 쏠림) / 2행 크림(대비 최고라 위계가 2행으로 뒤집힘).
	func _scheme(_n: int) -> Dictionary:
		return {"l1": [0, 3, 1, 4, 5], "l2": GOLD}

	func _draw() -> void:
		draw_rect(Rect2(0, 0, 800, 1280), C_BG)
		var s1: int = _fit(L1, 400)
		var s2: int = _fit(L2, 400)
		# 2행은 1행 아래에 살짝 겹쳐 앉는다(레퍼런스: OUT!이 BLOCK 밑단을 파고든다).
		var b1: float = 520.0
		var b2: float = b1 + float(s1) * 0.72
		var sc: Dictionary = _scheme(variant)
		var c1: Array = []
		for idx in sc["l1"]:
			c1.append(PAL[int(idx)])
		_draw_line(L1, s1, b1, c1, false, 1.0)
		_draw_line(L2, s2, b2, [sc["l2"]], false, 0.3)                  # 2행 흔들림 0.3배 = 오정렬로 안 읽힘


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
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
	canvas = LogoCanvas.new()
	canvas.fnt = f
	root.add_child(canvas)
	await process_frame

	for v in [0]:
		canvas.variant = v
		canvas.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s_v%d.png" % [OUT, v])
		print("shot v", v)
	print("DONE")
	quit()
