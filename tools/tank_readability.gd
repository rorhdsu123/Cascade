extends SceneTree
# 장갑(tank) 도착 실루엣 비교 probe — basic / 현재탱크 / 강철+판(A) / 보라+판(B)를 나란히.
# 큰 스케일(디테일) + 실제 CELL=64(게임 내 가독성) 두 줄. [[zoom-renders-to-judge-ui]] 후처리로 확대.
#   godot --path . --script tools/tank_readability.gd
# ⚠Main.gd는 안 건드림 — 색·판 레시피를 여기서 직접 그려 디자인 확정 전 비교만.

const ShotDir = preload("res://tools/shot_dir.gd")
# 출력 경로 = SHOT_DIR 환경변수, 없으면 build/shots/ (tools/shot_dir.gd 참조).
var DIR: String = ShotDir.resolve("tank_")
# 게임 실제 색(Main.gd 상수 미러)
const C_BASIC := Color("#a855f7")
const C_TANK  := Color("#6d28d9")   # 현재
const C_RIM   := Color(0.0, 0.0, 0.0, 0.85)
# A안 강철
const C_STEEL := Color("#64748b")
const C_STEEL_HI := Color("#aab6c6")
const C_STEEL_DK := Color("#2f3b4d")
const C_RIVET := Color("#d7dee8")
# B안 보라+판
const C_VIOL_HI := Color("#8b5cf6")
const C_VIOL_DK := Color("#3b1478")

class Drawer extends Node2D:
	var font: Font

	func _label(s: String, pos: Vector2, size: int = 22, col: Color = Color(0.85, 0.87, 0.95)) -> void:
		draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)

	# ── 적 렌더 레시피 (center c, cell 크기) ──
	func d_basic(c: Vector2, cell: float) -> void:
		var rad: float = cell * 0.33
		draw_circle(c, rad, Color("#a855f7"))
		draw_arc(c, rad, 0.0, TAU, 32, C_RIM, cell * 0.047)

	func d_tank_current(c: Vector2, cell: float) -> void:
		var hs: float = cell * 0.42
		draw_rect(Rect2(c.x - hs, c.y - hs, hs * 2.0, hs * 2.0), Color("#6d28d9"))
		draw_rect(Rect2(c.x - hs, c.y - hs, hs * 2.0, hs * 2.0), C_RIM, false, cell * 0.062)

	# 공통 장갑판 레시피: 베벨 하이라이트 + 판 세그먼트(세로 2줄) + 코너 리벳 + 이중 테두리
	func d_plated(c: Vector2, cell: float, base: Color, hi: Color, dk: Color) -> void:
		var hs: float = cell * 0.44
		var full := Rect2(c.x - hs, c.y - hs, hs * 2.0, hs * 2.0)
		draw_rect(full, base)
		# 상단 베벨 하이라이트(윗 30%)
		draw_rect(Rect2(c.x - hs, c.y - hs, hs * 2.0, hs * 2.0 * 0.30), Color(hi.r, hi.g, hi.b, 0.55))
		# 하단 그림자 밴드
		draw_rect(Rect2(c.x - hs, c.y + hs * 0.55, hs * 2.0, hs * 0.45), Color(dk.r, dk.g, dk.b, 0.45))
		# 판 세그먼트 = 세로 이음선 2줄(장갑판 느낌)
		var seam_w: float = maxf(1.5, cell * 0.028)
		draw_line(Vector2(c.x - hs * 0.34, c.y - hs), Vector2(c.x - hs * 0.34, c.y + hs), Color(dk.r, dk.g, dk.b, 0.9), seam_w)
		draw_line(Vector2(c.x + hs * 0.34, c.y - hs), Vector2(c.x + hs * 0.34, c.y + hs), Color(dk.r, dk.g, dk.b, 0.9), seam_w)
		# 코너 리벳 4개
		var rv: float = cell * 0.055
		var inset: float = hs * 0.72
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				var rc := Vector2(c.x + sx * inset, c.y + sy * inset)
				draw_circle(rc, rv, C_RIVET)
				draw_circle(rc, rv, Color(dk.r, dk.g, dk.b, 0.9), false, maxf(1.0, cell * 0.012))
		# 이중 테두리(외곽 두껍게 + 안쪽 밝은 베벨선)
		draw_rect(full, C_RIM, false, cell * 0.062)
		draw_rect(full.grow(-cell * 0.05), Color(hi.r, hi.g, hi.b, 0.4), false, maxf(1.0, cell * 0.02))

	func d_tank_steel(c: Vector2, cell: float) -> void:
		d_plated(c, cell, Color("#64748b"), Color("#aab6c6"), Color("#2f3b4d"))

	func d_tank_violet_plate(c: Vector2, cell: float) -> void:
		d_plated(c, cell, Color("#6d28d9"), Color("#8b5cf6"), Color("#3b1478"))

	# C1: 강철 몸체 + 중앙 보라 코어(장갑 사이로 '적'이 비침 = 로스터 소속감)
	func d_tank_steel_core(c: Vector2, cell: float) -> void:
		d_plated(c, cell, Color("#64748b"), Color("#aab6c6"), Color("#2f3b4d"))
		var cr: float = cell * 0.16
		draw_circle(c, cr * 1.35, Color(0.66, 0.33, 0.97, 0.35))   # 소프트 보라 글로우
		draw_circle(c, cr, Color("#a855f7"))                        # 보라 코어(basic 색)
		draw_circle(c, cr, C_RIM, false, maxf(1.0, cell * 0.02))

	# C2: 강철 몸체 + 보라 엣지(안쪽 보라 테두리 + 바깥 소프트 헤일로 = 가장자리에서 '적' 신호)
	func d_tank_steel_glow(c: Vector2, cell: float) -> void:
		var hs: float = cell * 0.44
		var full := Rect2(c.x - hs, c.y - hs, hs * 2.0, hs * 2.0)
		# 바깥 소프트 보라 헤일로
		for k in range(3):
			var g: float = cell * (0.02 + 0.03 * k)
			draw_rect(full.grow(g), Color(0.66, 0.33, 0.97, 0.16 - 0.045 * k), false, maxf(1.0, cell * 0.03))
		d_plated(c, cell, Color("#64748b"), Color("#aab6c6"), Color("#2f3b4d"))
		# 안쪽 보라 베벨 테두리(강철 하이라이트 대신 보라)
		draw_rect(full.grow(-cell * 0.05), Color(0.66, 0.33, 0.97, 0.85), false, maxf(1.5, cell * 0.028))

	func _draw() -> void:
		# 배경
		draw_rect(Rect2(0, 0, 980, 620), Color("#0e0e16"))

		var cols := [
			{"t": "basic", "fn": "d_basic"},
			{"t": "A: 강철(순수)", "fn": "d_tank_steel"},
			{"t": "C1: 강철+보라코어", "fn": "d_tank_steel_core"},
			{"t": "C2: 강철+보라글로우", "fn": "d_tank_steel_glow"},
		]
		var xs := [150.0, 380.0, 610.0, 840.0]

		# 헤더
		_label("장갑 도착 실루엣 비교", Vector2(40, 44), 30, Color("#e2b13a"))
		for i in range(cols.size()):
			var w: float = font.get_string_size(cols[i]["t"], HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
			_label(cols[i]["t"], Vector2(xs[i] - w * 0.5, 96), 22)

		# 큰 스케일(디테일) — cell 200
		_label("확대(디테일)", Vector2(40, 200), 18, Color(0.6, 0.62, 0.72))
		var big_y: float = 250.0
		for i in range(cols.size()):
			callv(cols[i]["fn"], [Vector2(xs[i], big_y), 200.0])

		# 실제 게임 크기 CELL=64 — 보드 셀 배경 위에서(진짜 가독성)
		_label("실제 크기(CELL=64, 보드 위)", Vector2(40, 420), 18, Color(0.6, 0.62, 0.72))
		var small_y: float = 500.0
		for i in range(cols.size()):
			# 어두운 보드 셀 + 격자선
			var cell := 64.0
			var cellrect := Rect2(xs[i] - cell * 0.5, small_y - cell * 0.5, cell, cell)
			draw_rect(cellrect, Color("#15151f"))
			draw_rect(cellrect, Color(0.20, 0.20, 0.28), false, 1.0)
			callv(cols[i]["fn"], [Vector2(xs[i], small_y), cell])

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	DisplayServer.window_set_size(Vector2i(980, 620))
	await process_frame
	var d := Drawer.new()
	d.font = ThemeDB.fallback_font
	root.add_child(d)
	d.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(DIR + "compare.png")
	print("shot tank_compare.png")
	quit()
