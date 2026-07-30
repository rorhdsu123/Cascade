extends SceneTree
# Play 스토어 등록용 에셋 산출 (출시 배관).
#   godot --path . --script tools/store_shots.gd
# ⚠창 모드 필수 — 헤드리스는 렌더 텍스처가 null이다([[godot-pixel-verify-needs-window]]).
#
# 무엇을 만드나:
#   · 폰 스크린샷 1080×1920 (Play 요구: 2~8장 · 각 변 320~3840 · 종횡비 16:9~9:16 안)
#   · 피처 그래픽 1024×500 (등록정보 필수, 알파 없음)
#
# 원칙: **목업을 만들지 않는다.** 실제 Main.tscn을 봇으로 굴려 나온 화면만 찍는다 — 스토어 스크린샷이
#   실제 게임과 다르면 설치 후 이탈로 돌아오고, Play 정책에서도 오해를 유발하는 이미지는 금지다.
#
# 봇 수 선택은 tools/analytics_probe.gd의 것과 같은 로직이다(줄이 되는 수를 즉시 채택).

const DIR: String = "/private/tmp/claude-501/-Users-im-yujin-Desktop-Cascade-worktrees-stage/4b17b509-e199-47ac-b935-323c71fffd62/scratchpad/store/"
# 산출 규격 = 정확히 9:16(Play 폰 스크린샷 허용 종횡비의 끝값). 1080×1920.
const SHOT_W: int = 1080
const SHOT_H: int = 1920
# ⚠렌더는 창이 아니라 SubViewport에 한다. 이유 둘:
#   ① 창 크기는 OS가 디스플레이 높이로 깎는다(1920 요청 → 1572로 잘려 종횡비가 깨졌다).
#   ② Main은 **폭 800 고정**(VW_BASE)으로 그리고 화면 맞춤은 project.godot의 stretch가 한다.
#      stretch는 루트 뷰포트에만 걸리므로, SubViewport를 1080폭으로 잡으면 그림이 왼쪽 800px에만 그려진다.
#   → 800폭 그대로 9:16 높이(1422)로 그린 뒤 이미지를 1080×1920으로 키운다.
const SUB_W: int = 800
const SUB_H: int = 1422   # 800 × 16/9
# 실제 폰은 9:16보다 길다(요즘 대세 9:19.5~9:20). 스토어 규격은 9:16이지만 **레이아웃 점검**은 실기기
#   비율로 해야 한다 → `-- --tall`을 주면 9:19.5(800×1733)로 렌더해 별도 파일로 저장한다.
const SUB_H_TALL: int = 1733   # 800 × 19.5/9

# 고정 시드 — 스크린샷이 실행마다 달라지면 "어느 판이 잘 나왔지"를 다시 못 찾는다.
const SEED_CAMPAIGN: int = 20250123
const SEED_ENDLESS: int = 20250102

var g: Node = null
var vp: SubViewport = null
var tall: bool = false      # 실기기 비율(9:19.5) 점검 모드
var suffix: String = ""

func _initialize() -> void:
	_run.call_deferred()

func _headless() -> bool:
	return DisplayServer.get_name() == "headless"

func _settle() -> void:
	var s: int = 0
	while bool(g.get("resolving")) and s < 400:
		g._process(0.05)
		s += 1

# 해소를 '끝까지' 두지 않고 몇 프레임만 진행 — 줄 삭제 연출(폭발·칭찬어)이 화면에 살아 있는 순간을 잡는다.
func _step(frames: int, dt: float = 0.05) -> void:
	for _i in range(frames):
		g._process(dt)

func _shot(name: String) -> void:
	if _headless():
		return
	g.call("queue_redraw")
	await process_frame
	await RenderingServer.frame_post_draw
	await process_frame
	var img: Image = vp.get_texture().get_image()
	if not tall:
		img.resize(SHOT_W, SHOT_H, Image.INTERPOLATE_LANCZOS)   # 스토어 규격으로 승격
	img.save_png(DIR + suffix + name)
	if not tall:
		# 스토어 제출 파일은 저장소에도 남긴다 — Play에 올릴 '그 파일'이고, 잃으면 재현 조건을 다시 찾아야 한다.
		var store: String = ProjectSettings.globalize_path("res://store/")
		DirAccess.make_dir_recursive_absolute(store)
		img.save_png(store + name)
	print("  %s  %dx%d" % [name, img.get_width(), img.get_height()])

func _bot_move() -> Dictionary:
	var fallback: Dictionary = {}
	for slot in range(3):
		if (g.tray[slot] as Dictionary).is_empty():
			continue
		var offsets: Array = g.tray[slot]["offsets"]
		for r in range(g.ROWS):
			for c in range(g.COLS):
				var cells: Array = []
				var ok: bool = true
				for o in offsets:
					var ov: Vector2i = o as Vector2i
					var cc: Vector2i = Vector2i(c + ov.x, r + ov.y)
					if cc.x < 0 or cc.x >= g.COLS or cc.y < 0 or cc.y >= g.ROWS \
							or g.board[cc.y][cc.x] != "":
						ok = false
						break
					cells.append(cc)
				if not ok:
					continue
				var mv: Dictionary = {"slot": slot, "col": c, "row": r}
				if g._would_clear(cells):
					return mv
				if fallback.is_empty():
					fallback = mv
	return fallback

# 한 수 놓는다. clearing_only면 '줄이 되는 수'가 있을 때만 놓고, 없으면 false.
func _play_one(clearing_only: bool = false) -> bool:
	_settle()
	if bool(g.game_over) or bool(g.game_clear):
		return false
	var mv: Dictionary = _bot_move()
	if mv.is_empty():
		return false
	var cells: Array = []
	for o in (g.tray[mv["slot"]]["offsets"] as Array):
		var ov: Vector2i = o as Vector2i
		cells.append(Vector2i(int(mv["col"]) + ov.x, int(mv["row"]) + ov.y))
	if clearing_only and not g._would_clear(cells):
		return false
	g.sel = mv["slot"]
	g.hover_col = mv["col"]
	g.hover_row = mv["row"]
	g._place_piece()
	return true

func _play(n: int) -> int:
	var done: int = 0
	for _i in range(n):
		if not _play_one():
			break
		done += 1
	_settle()
	return done

func _run() -> void:
	if _headless():
		print("헤드리스에선 렌더 텍스처가 null이다 — 창 모드로 실행할 것")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(DIR)
	vp = SubViewport.new()
	tall = OS.get_cmdline_user_args().has("--tall")
	suffix = "tall_" if tall else ""
	vp.size = Vector2i(SUB_W, SUB_H_TALL if tall else SUB_H)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.disable_3d = true
	root.add_child(vp)
	g = load("res://Main.tscn").instantiate()
	vp.add_child(g)                   # Main이 get_viewport_rect()로 vh를 읽으므로 SubViewport 크기가 먹는다
	# ⚠실유저 진행도 보호(C100 확장): 이 probe는 Main.tscn을 띄우므로 _ready가 돌아
	#   persist_enabled=true가 된다. 아래서 cleared를 주입하거나 봇이 스테이지를 깨면 그 값이
	#   **실제 campaign.save에 각인**된다(전 스테이지 주입 = 16383 = "진행도가 저절로 전승됨"의 진범).
	#   C100은 campaign_flow.gd만 막았고 나머지 창 모드 probe는 새고 있었다 → 여기서 끈다.
	g.set("persist_enabled", false)
	await process_frame
	await process_frame
	g.set("_locale", "en")
	# 모바일에서 실제로 보이는 화면을 찍는다 — 입력 방식 토글은 PC 테스트용이라 폰에선 안 보인다.
	g.set("show_input_toggle", false)

	# ── ① 코어 루프: 캠페인 중반 스테이지. '블록을 놓아 밀려오는 적을 치운다'가 한 장에 보여야 한다.
	seed(SEED_CAMPAIGN)
	g.seed_game(SEED_CAMPAIGN)
	g.set("dev_unlock_all", true)     # 스크린샷용 해금(저장은 안 건드림 — 아래서 되돌린다)
	g._start_stage(3)
	await process_frame
	_play(9)
	await _shot("s1_core_loop.png")

	# ── ② 줄 삭제 순간: 폭발·칭찬어가 살아 있는 프레임. 해소를 끝까지 두면 아무 일도 없는 판이 찍힌다.
	var got: bool = false
	for _t in range(14):
		if _play_one(true):
			got = true
			break
		if not _play_one():
			break
	if got:
		_step(2)                      # 연출 2프레임만 — 폭발이 가장 큰 구간
		await _shot("s2_line_clear.png")
	else:
		print("  ⚠줄 삭제 순간을 못 잡음 — 시드/수 예산 조정 필요")

	# ── ③ 다른 목표(수집): 스테이지마다 '동사'가 바뀐다는 걸 보여준다.
	#    ⚠처음엔 인트로 배너 순간을 찍었는데 보드가 텅 빈 판(막 시작)이라 스토어 이미지로 약했다 →
	#      배너를 지나 실제로 보석을 모으는 중간 판을 찍는다.
	g._start_stage(4)
	await process_frame
	_play(9)
	await _shot("s3_collect.png")

	# ── ④ 무한 모드: 점수·깊이 + 밤하늘 존(절대점수 연출). 경쟁 천장이 있다는 신호.
	seed(SEED_ENDLESS)
	g.seed_game(SEED_ENDLESS)
	g._start_endless()
	await process_frame
	g.set("endless_score", 14200)     # 존2 진입선 위 — 밤하늘 색이 실제로 바뀐 상태를 찍는다
	_play(10)
	await _shot("s4_endless.png")

	# ── ⑤ 진행 리드아웃: 스테이지가 계속 이어진다는 것(깔때기). 여러 판 클리어한 모습.
	# ⚠dev 해금을 먼저 끈다 — 켜져 있으면 선택화면에 "DEV: unlock all" 주황 라벨이 찍힌다(첫 렌더서 밟음).
	#   라벨 자체는 dev_unlock_all 뒤에 제대로 게이팅돼 있어 출고 빌드엔 안 나온다(키보드 '0' 전용).
	g.set("dev_unlock_all", false)
	var cl: Dictionary = {}
	for i in range(5):
		cl[i] = true
	g.set("cleared", cl)
	g.set("mode", "select")
	g.call("_sel_enter")              # 해금·프런티어 재정렬(‘0’키 토글이 하는 것과 같은 갱신)
	await process_frame
	await _shot("s5_progress.png")
	print("스크린샷 완료 — %s" % DIR)
	print("DONE")
	quit()
