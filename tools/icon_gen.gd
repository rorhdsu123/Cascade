extends SceneTree
# 앱 아이콘 생성기 (출시 배관 — project.godot에 config/icon이 없어 기본 Godot 아이콘으로 출고되던 걸 막는다).
#   godot --path . --script tools/icon_gen.gd            # 3안 비교 시트
#   godot --path . --script tools/icon_gen.gd -- --emit=B # 확정안으로 실제 에셋 산출
#
# ⚠창 모드 필수 — 헤드리스는 렌더 텍스처가 null이다([[godot-pixel-verify-needs-window]]).
#   그래서 SubViewport에 그린다: 루트 뷰포트는 project.godot의 stretch(800x1280 canvas_items)에 물려
#   정사각 아이콘이 찌그러진다.
#
# 왜 코드로 그리나: 아트 트랙(별도 디자이너) 산출물이 없고, 아이콘이 없으면 export가
#   `No project icon specified`만 흘리고 기본 Godot 아이콘으로 출고된다(종료코드 0 = 조용한 사고).
#   나중에 디자이너 산출물로 교체하면 된다 — 이건 자리를 채우는 게 아니라 '게임 자체의 form'을 쓴다.
#
# form 근거: 블록 = Main._draw_piece_cells의 실제 문법(pad 8% + 흰 내부선 + 드롭섀도),
#   해골 = Main._draw_enemy_icon의 '타입 중립 처치 대상' 기호. 성 실루엣·브릭 스터드는 기각된 언어라 안 쓴다.

const DIR: String = "/private/tmp/claude-501/-Users-im-yujin-Desktop-Cascade-worktrees-stage/4b17b509-e199-47ac-b935-323c71fffd62/scratchpad/icon/"
const OUT: String = "res://icons/"
const SIDE: int = 1024

# 게임 팔레트에서 그대로(Main.gd 색상 상수)
const C_RED := Color("#ff5a52")
const C_ORANGE := Color("#ff8c1a")
const C_YELL := Color("#ffd23b")
const C_GREEN := Color("#35cf7a")
const C_BLUE := Color("#4a90ff")
const C_PURPLE := Color("#d94fc8")
const C_BG := Color("#0d0d1a")
const C_BG_HI := Color("#2a2470")   # 밤하늘 존1 인디고 — 배경 그라데이션 상단


class Drawer:
	extends Node2D
	var variant: String = "A"
	var mode: String = "flat"   # flat | fg | bg | mono
	var S: float = 1024.0

	# ── 게임의 블록 문법 (Main._draw_piece_cells) ──
	func blk(tl: Vector2, cs: float, col: Color) -> void:
		var pad: float = cs * 0.08
		if mode != "mono":
			draw_rect(Rect2(tl.x + pad + cs * 0.05, tl.y + pad + cs * 0.075,
					cs - pad * 2.0, cs - pad * 2.0), Color(0, 0, 0, 0.33))
		var r := Rect2(tl.x + pad, tl.y + pad, cs - pad * 2.0, cs - pad * 2.0)
		draw_rect(r, Color.WHITE if mode == "mono" else col)
		if mode != "mono":
			draw_rect(r, Color(1, 1, 1, 0.5), false, maxf(1.5, cs * 0.03))

	# ── 게임의 해골 문법 (Main._draw_enemy_icon) ──
	#   part: "" = 통째로 / "body" = 뼈 실루엣만 / "features" = 눈·코·이빨만(모노 레이어의 '구멍' 마스크)
	func skull(center: Vector2, s: float, part: String = "") -> void:
		var bone: Color = Color(0.95, 0.93, 0.86)
		var dark: Color = Color(0.10, 0.08, 0.08)
		var cx: float = center.x
		var cy: float = center.y
		if part == "body":
			bone = Color.WHITE
		if part == "features":
			dark = Color.WHITE
		if part != "features":
			if part != "body":
				# 어두운 후광 — 밝은 블록 위에서도 해골 윤곽이 선다(적의 rim 문법 재사용)
				draw_circle(Vector2(cx, cy - s * 0.06), s * 0.50, Color(0, 0, 0, 0.45))
				draw_rect(Rect2(cx - s * 0.30, cy + s * 0.06, s * 0.60, s * 0.38), Color(0, 0, 0, 0.45))
			draw_rect(Rect2(cx - s * 0.24, cy + s * 0.08, s * 0.48, s * 0.32), bone)
			draw_circle(Vector2(cx, cy - s * 0.06), s * 0.42, bone)
			if part == "body":
				return
		var eye: float = s * 0.17
		draw_circle(Vector2(cx - s * 0.19, cy - s * 0.04), eye, dark)
		draw_circle(Vector2(cx + s * 0.19, cy - s * 0.04), eye, dark)
		draw_colored_polygon(PackedVector2Array([
			Vector2(cx, cy + s * 0.06),
			Vector2(cx - s * 0.06, cy + s * 0.17),
			Vector2(cx + s * 0.06, cy + s * 0.17),
		]), dark)
		for i in range(3):
			var tx: float = cx - s * 0.16 + float(i) * s * 0.16
			draw_rect(Rect2(tx - s * 0.015, cy + s * 0.22, s * 0.03, s * 0.16), dark)

	func bg_paint() -> void:
		# 밤하늘 그라데이션(존 언어) — 위가 인디고, 아래가 거의 검정
		var bands: int = 64
		for i in range(bands):
			var t: float = float(i) / float(bands - 1)
			var col: Color = C_BG_HI.lerp(C_BG, pow(t, 0.75))
			draw_rect(Rect2(0, S * t, S, S / float(bands) + 1.0), col)

	# 마크의 실측 세로 범위(정규화) — 안전영역 계산의 근거. draw_e 기준:
	#   해골 원 top = (0.38 - 0.58*0.06 - 0.58*0.42) = 0.101 / 블록 bottom = 0.60 + 0.25 = 0.85
	const MARK_TOP: float = 0.101
	const MARK_BOT: float = 0.850

	func _draw() -> void:
		if mode == "bg":
			bg_paint()
			return
		if mode == "flat":
			bg_paint()

		# ⚠적응형 아이콘(전경·모노)은 런처가 마스크로 깎는다 — 안전하게 보이는 건 중앙 66%뿐이다.
		#   마크는 세로 75%를 쓰므로 전경 레이어에선 줄여야 블록 밑단이 안 잘린다.
		#   동시에 마크 중심(0.475)을 프레임 중심(0.5)으로 맞춘다 — flat에도 이득이라 항상 적용.
		#   ⚠사각 안전영역(66%)만 맞추면 부족하다 — Pixel 런처는 **원형**으로 깎아서, 마크 밑변의
		#     좌우 모서리(빨강·파랑 블록)가 잘린다. 실제 마스킹 렌더로 확인해 0.72까지 조인 값이다
		#     (tools/icon_gen.gd --emit → check_masked_432.png).
		var sc: float = 1.0 if mode == "flat" else 0.72
		var mid: float = (MARK_TOP + MARK_BOT) * 0.5
		draw_set_transform(
				Vector2(S * 0.5 * (1.0 - sc), S * 0.5 * (1.0 - sc) + sc * (0.5 - mid) * S),
				0.0, Vector2(sc, sc))

		# 모노(Android 13+ 테마 아이콘)는 단색 실루엣이라 블록까지 흰색이면 해골과 한 덩이로 뭉갠다
		#   → 해골만 남긴다. 형태 하나가 남는 게 색 없는 레이어의 유일한 승리 조건.
		#   ⚠눈·코·이빨은 '구멍'이어야 한다 — 안 뚫으면 눈구멍 없는 둥근 덩어리가 된다(실제로 그랬다).
		#     2D 캔버스에선 지우기가 안 되므로 body/features를 따로 렌더해 Image에서 알파를 뺀다(_mono_compose).
		if mode == "mono" or mode == "monocut":
			skull(Vector2(S * 0.5, S * 0.38), S * 0.58,
					"features" if mode == "monocut" else "body")
			return

		match variant:
			"A": draw_a()
			"B": draw_b()
			"C": draw_c()
			"D": draw_d()
			"E": draw_e()
			"F": draw_f()

	# A — 블록 2x2 무더기 + 그 위 해골. 2요소 서술("블록으로 이걸 치운다").
	func draw_a() -> void:
		var cs: float = S * 0.20
		var ox: float = S * 0.5 - cs
		var oy: float = S * 0.56
		var cols: Array = [C_RED, C_YELL, C_BLUE, C_GREEN]
		var k: int = 0
		for ry in range(2):
			for rx in range(2):
				blk(Vector2(ox + rx * cs, oy + ry * cs), cs, cols[k])
				k += 1
		skull(Vector2(S * 0.5, S * 0.34), S * 0.30)

	# B — 해골이 주인공(크게 중앙) + 하단에 블록 한 줄. 48px에서 가장 강한 형태 가설.
	func draw_b() -> void:
		skull(Vector2(S * 0.5, S * 0.42), S * 0.46)
		var cs: float = S * 0.175
		var cols: Array = [C_RED, C_ORANGE, C_YELL, C_GREEN, C_BLUE]
		var n: int = cols.size()
		var ox: float = S * 0.5 - cs * float(n) * 0.5
		for i in range(n):
			blk(Vector2(ox + float(i) * cs, S * 0.70), cs, cols[i])

	# C — 실제 조각 form(L자) + 해골. 대각 구성으로 '놓아서 치운다'의 동작을 암시.
	func draw_c() -> void:
		var cs: float = S * 0.19
		var ox: float = S * 0.20
		var oy: float = S * 0.44
		# L 조각 (게임의 조각 셋에 있는 모양)
		for o in [Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)]:
			blk(Vector2(ox + float(o.x) * cs, oy + float(o.y) * cs), cs, C_BLUE)
		skull(Vector2(S * 0.68, S * 0.34), S * 0.30)

	# D — B의 스케일업. 프레임을 꽉 채우고 블록은 3개로 크게(48px서 5칸은 띠로 뭉갠다).
	func draw_d() -> void:
		skull(Vector2(S * 0.5, S * 0.40), S * 0.56)
		var cs: float = S * 0.235
		var cols: Array = [C_RED, C_YELL, C_BLUE]
		var ox: float = S * 0.5 - cs * 1.5
		for i in range(3):
			blk(Vector2(ox + float(i) * cs, S * 0.665), cs, cols[i])

	# E — 블록 벽이 해골 하단을 가린다 = 두 요소가 한 덩이 마크로 붙는다(깊이도 생김).
	func draw_e() -> void:
		skull(Vector2(S * 0.5, S * 0.38), S * 0.58)
		var cs: float = S * 0.25
		var cols: Array = [C_RED, C_YELL, C_BLUE]
		var ox: float = S * 0.5 - cs * 1.5
		for i in range(3):
			blk(Vector2(ox + float(i) * cs, S * 0.60), cs, cols[i])

	# F — 조각이 해골 위로 떨어지는 순간(대각 겹침). 동작을 담되 한 덩이로 읽히는지 시험.
	func draw_f() -> void:
		skull(Vector2(S * 0.44, S * 0.52), S * 0.56)
		var cs: float = S * 0.235
		# 2칸 조각이 우상단에서 내려온다
		blk(Vector2(S * 0.52, S * 0.13), cs, C_YELL)
		blk(Vector2(S * 0.52 + cs, S * 0.13), cs, C_RED)
		blk(Vector2(S * 0.52 + cs, S * 0.13 + cs), cs, C_BLUE)


# ── 피처 그래픽(1024×500) ──
# Play 등록정보 필수 에셋. 알파 없음. 여러 화면에서 잘려 나가므로 콘텐츠를 가장자리에 두지 않는다.
#   구성 = 왼쪽에 아이콘 마크(해골+블록), 오른쪽에 워드마크 + 태그라인. 인게임 허브 로고와 같은 문구·색을 쓴다
#   (Main._draw_menu: "BLOCK CASTLE" 금색 + "PACKING DEFENSE" 연청색).
class Feature:
	extends Node2D
	var W: float = 1024.0
	var H: float = 500.0
	var fnt: Font = null
	var mark: Drawer = null

	func _draw() -> void:
		# 밤하늘 그라데이션 — 아이콘·무한모드 존과 같은 언어(가로 방향으로 눕힌다)
		var bands: int = 96
		for i in range(bands):
			var t: float = float(i) / float(bands - 1)
			var col: Color = Color("#2a2470").lerp(Color("#0d0d1a"), pow(t, 0.8))
			draw_rect(Rect2(W * t, 0.0, W / float(bands) + 1.0, H), col)
		if fnt == null:
			return
		# 워드마크 — 화면에선 띄어 쓴다(붙이면 단어 경계가 사라져 한눈에 안 읽힘, Main._draw_menu 주석과 동일 근거)
		#   ⚠글자 크기를 고정하면 프레임 밖으로 나간다(92px에선 오른쪽 끝에 딱 붙어 잘렸다).
		#     Play는 피처 그래픽을 여러 비율로 **잘라서** 쓰므로 여백을 확보하고 폭에 맞춰 줄인다.
		var left: float = 400.0        # 마크가 차지하는 왼쪽 영역
		var margin: float = 56.0
		var avail: float = W - left - margin * 2.0
		var title: String = "BLOCK CASTLE"
		var tfs: int = 92
		while tfs > 40 and fnt.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs).x > avail:
			tfs -= 2
		var tw: float = fnt.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs).x
		var tx: float = left + margin + (avail - tw) * 0.5
		_outlined(Vector2(tx, 268.0), title, tfs, Color("#ffd700"))
		var tag: String = "PACKING DEFENSE"
		var gfs: int = 34
		var gw: float = fnt.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, gfs).x
		_outlined(Vector2(left + margin + (avail - gw) * 0.5, 330.0), tag, gfs, Color(0.55, 0.72, 0.95))

	func _outlined(p: Vector2, s: String, size: int, col: Color) -> void:
		for d in [Vector2(-3, 0), Vector2(3, 0), Vector2(0, -3), Vector2(0, 3)]:
			draw_string(fnt, p + d, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, 0.85))
		draw_string(fnt, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _initialize() -> void:
	_run.call_deferred()

func _render(variant: String, mode: String, side: int) -> Image:
	var vp := SubViewport.new()
	vp.size = Vector2i(side, side)
	vp.transparent_bg = (mode == "fg" or mode == "mono" or mode == "monocut")
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.disable_3d = true
	var d := Drawer.new()
	d.variant = variant
	d.mode = mode
	d.S = float(side)
	vp.add_child(d)
	root.add_child(vp)
	await process_frame
	await RenderingServer.frame_post_draw
	await process_frame
	var img: Image = vp.get_texture().get_image()
	root.remove_child(vp)
	vp.queue_free()
	return img

# 48px로 줄인 뒤 nearest로 되키워 붙인다 — 런처 크기에서 형태가 남는지 보는 유일한 방법
#   ([[zoom-renders-to-judge-ui]] 등배로는 셀 단위 결함이 안 보인다).
func _sheet(imgs: Array, names: Array) -> void:
	var cell: int = 320
	var sheet := Image.create(cell * imgs.size(), cell * 2, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.5, 0.5, 0.5, 1.0))
	for i in range(imgs.size()):
		var big: Image = (imgs[i] as Image).duplicate()
		big.resize(cell, cell, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(big, Rect2i(0, 0, cell, cell), Vector2i(i * cell, 0))
		var small: Image = (imgs[i] as Image).duplicate()
		small.resize(48, 48, Image.INTERPOLATE_LANCZOS)   # 실제 런처 크기
		small.resize(cell, cell, Image.INTERPOLATE_NEAREST)  # 판단용 확대
		sheet.blit_rect(small, Rect2i(0, 0, cell, cell), Vector2i(i * cell, cell))
	sheet.save_png(DIR + "sheet.png")
	print("sheet: %s  (상단=원본축소 / 하단=48px→nearest 확대)  순서=%s" % [DIR + "sheet.png", names])

func _save(img: Image, side: int, path: String) -> void:
	var o: Image = img.duplicate()
	if o.get_width() != side:
		o.resize(side, side, Image.INTERPOLATE_LANCZOS)
	o.save_png(path)
	print("  %s  %dx%d" % [path, side, side])

# 적응형 아이콘이 런처 마스크에 잘리는지 실제로 깎아서 본다 — 안전영역은 계산이 아니라 프레임으로 확인.
#   원형 마스크(가장 공격적인 흔한 마스크) 밖은 마젠타로 칠해 '무엇이 잘렸는지'를 눈에 보이게 한다.
func _mask_check(bg: Image, fg: Image) -> void:
	var side: int = 432
	var b: Image = bg.duplicate(); b.resize(side, side, Image.INTERPOLATE_LANCZOS)
	var f: Image = fg.duplicate(); f.resize(side, side, Image.INTERPOLATE_LANCZOS)
	b.convert(Image.FORMAT_RGBA8)
	f.convert(Image.FORMAT_RGBA8)
	b.blend_rect(f, Rect2i(0, 0, side, side), Vector2i.ZERO)
	var c: float = float(side) * 0.5
	var r: float = c   # 원형 마스크 반지름 = 프레임 절반(108dp 중 72dp 가시영역보다도 관대)
	for y in range(side):
		for x in range(side):
			if Vector2(float(x) - c, float(y) - c).length() > r * (72.0 / 108.0):
				b.set_pixel(x, y, Color(1, 0, 1, 1))
	b.save_png(DIR + "check_masked_432.png")
	var small: Image = b.duplicate()
	small.resize(48, 48, Image.INTERPOLATE_LANCZOS)
	small.resize(384, 384, Image.INTERPOLATE_NEAREST)
	small.save_png(DIR + "check_masked_48.png")
	print("  마스크 검증: %s (마젠타 = 런처가 깎아내는 영역)" % (DIR + "check_masked_432.png"))

# 모노 레이어 = 뼈 실루엣에서 눈·코·이빨을 알파로 뚫는다(2D 캔버스엔 지우기가 없어 Image에서 처리).
func _mono_compose(body: Image, cut: Image) -> Image:
	var o: Image = body.duplicate()
	o.convert(Image.FORMAT_RGBA8)
	var c: Image = cut.duplicate()
	c.convert(Image.FORMAT_RGBA8)
	for y in range(o.get_height()):
		for x in range(o.get_width()):
			if c.get_pixel(x, y).a > 0.5:
				o.set_pixel(x, y, Color(1, 1, 1, 0))
	return o

func _emit_feature() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(1024, 500)
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.disable_3d = true
	var f := Feature.new()
	# 인게임과 같은 폰트를 쓴다 — 스토어 이미지와 실제 화면의 글자가 다르면 같은 게임처럼 안 보인다.
	var baloo := load("res://fonts/Baloo2.ttf") as FontFile
	if baloo != null:
		var fv := FontVariation.new()
		fv.base_font = baloo
		fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("weight"): 800}
		f.fnt = fv
	else:
		f.fnt = load("res://fonts/NotoSans-Regular.ttf") as FontFile
	vp.add_child(f)
	# 마크는 아이콘과 같은 Drawer를 재사용해 왼쪽에 얹는다(같은 그림이어야 브랜드가 하나로 읽힌다).
	var m := Drawer.new()
	m.variant = "E"
	m.mode = "fg"
	m.S = 420.0
	m.position = Vector2(20.0, 40.0)
	vp.add_child(m)
	root.add_child(vp)
	await process_frame
	await RenderingServer.frame_post_draw
	await process_frame
	var img: Image = vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)   # 피처 그래픽은 알파 없음
	# 앱 아이콘(icons/)과 달리 이건 **스토어 등록 에셋**이라 store/에 둔다 — 앱에는 안 실린다.
	var store: String = ProjectSettings.globalize_path("res://store/")
	DirAccess.make_dir_recursive_absolute(store)
	img.save_png(store + "feature_1024x500.png")
	img.save_png(DIR + "feature_1024x500.png")
	print("피처 그래픽: store/feature_1024x500.png (1024x500, 알파 없음)")
	root.remove_child(vp)
	vp.queue_free()

func _emit(variant: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var flat: Image = await _render(variant, "flat", SIDE)
	var fg: Image = await _render(variant, "fg", SIDE)
	var bg: Image = await _render(variant, "bg", SIDE)
	var mono_body: Image = await _render(variant, "mono", SIDE)
	var mono_cut: Image = await _render(variant, "monocut", SIDE)
	var mono: Image = _mono_compose(mono_body, mono_cut)
	print("확정안 %s 에셋 산출:" % variant)
	_save(flat, 512, OUT + "icon_512.png")           # Play 스토어 등록 아이콘 + config/icon
	_save(flat, 192, OUT + "icon_192.png")           # 레거시 런처
	_save(fg, 432, OUT + "adaptive_fg_432.png")      # 적응형 전경
	_save(bg, 432, OUT + "adaptive_bg_432.png")      # 적응형 배경
	_save(mono, 432, OUT + "adaptive_mono_432.png")  # Android 13+ 테마 아이콘
	_save(flat, 512, DIR + "preview_512.png")
	# 모노는 흰색-투명이라 그대로는 판단이 안 된다 — 런처처럼 단색 위에 얹어 본다.
	var mprev := Image.create(432, 432, false, Image.FORMAT_RGBA8)
	mprev.fill(Color(0.25, 0.30, 0.45, 1.0))
	var m432: Image = mono.duplicate()
	m432.resize(432, 432, Image.INTERPOLATE_LANCZOS)
	m432.convert(Image.FORMAT_RGBA8)
	mprev.blend_rect(m432, Rect2i(0, 0, 432, 432), Vector2i.ZERO)
	mprev.save_png(DIR + "preview_mono.png")
	_mask_check(bg, fg)

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("헤드리스에선 렌더 텍스처가 null이다 — 창 모드로 실행할 것")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(DIR)
	var emit: String = ""
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--emit="):
			emit = String(a).substr(7)
	if OS.get_cmdline_user_args().has("--feature"):
		await _emit_feature()
	elif emit != "":
		await _emit(emit)
	else:
		var names: Array = ["E"]
		var imgs: Array = []
		for n in names:
			imgs.append(await _render(n, "flat", SIDE))
			_save(imgs[-1], SIDE, DIR + "v%s.png" % n)
		_sheet(imgs, names)
	print("DONE")
	quit()
