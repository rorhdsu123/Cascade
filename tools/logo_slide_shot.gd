extends SceneTree
# 로고 화면 → 홈 **미끄러짐** 확인(boot_shot의 하드컷 대조판).
#   godot --path . --script tools/logo_slide_shot.gd -- <출력디렉터리>   (창 모드 — 헤드리스는 렌더텍스처 null)
#
# 이 도구가 답해야 하는 건 셋이다:
#   ① 이음매: k=0 프레임의 로고가 로고 화면과 **같은 절대 좌표**인가(어긋나면 첫 프레임에 튄다).
#   ② 배경: 미끄러지는 동안 배경이 변하나(로고 말고 딴 게 움직이면 그게 새 깜빡임이다).
#   ③ 도착: 마지막이 평상시 홈과 픽셀 단위로 같은가.
# 눈이 아니라 숫자로 본다 — 140px 어긋난 것도 스크린샷으로는 못 골라냈다(그린 자리 vs 판정 rect 교훈).
var g: Node = null
var out_dir: String = "/tmp/"

func _initialize() -> void:
	_run.call_deferred()

func _shot(name: String) -> Image:
	if DisplayServer.get_name() == "headless":
		return null
	g.call("queue_redraw")
	await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	img.save_png(out_dir + name)
	return img

# 찍을 지점(k=0~1) — 버튼이 들어오는 문턱(MENU_INTRO_SLOTS=0.35) 앞뒤를 반드시 낀다.
const KS: Array = [0.0, 0.2, 0.34, 0.36, 0.6]
# 배경만 있는 자리 = 좌우 가장자리와 최상·최하단. 로고(중앙)·버튼(하단 중앙)을 피한다.
const BG_PROBES: Array = [Vector2i(12, 12), Vector2i(788, 40), Vector2i(20, 640),
		Vector2i(780, 900), Vector2i(400, 6), Vector2i(400, 1274)]

func _bg_diff(a: Image, b: Image) -> int:
	var worst: int = 0
	for p in BG_PROBES:
		var ca: Color = a.get_pixelv(p)
		var cb: Color = b.get_pixelv(p)
		for ch in [ca.r - cb.r, ca.g - cb.g, ca.b - cb.b]:
			worst = maxi(worst, int(round(absf(ch) * 255.0)))
	return worst

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = String(args[0])
	if not out_dir.ends_with("/"):
		out_dir += "/"
	DirAccess.make_dir_recursive_absolute(out_dir)

	g = load("res://Main.tscn").instantiate()
	root.add_child(g)
	g.set("persist_enabled", false)   # 실유저 진행도 보호 — 창 모드 probe 공통 규약
	await process_frame
	DisplayServer.window_set_size(Vector2i(800, 1280))
	await process_frame
	await process_frame
	g.set("_locale", "en")
	# ⚠Main의 _process를 끈다. 안 그러면 _shot이 기다리는 프레임 동안 menu_intro가 밀려(실측 +0.08초)
	#   내가 놓은 k가 아니라 지나간 k를 찍는다 — 첫 시도의 이음매 233은 그 오염이었다.
	#   (Engine.time_scale=0은 못 쓴다 — 이 하네스가 기다리는 프레임 자체가 안 온다.)
	g.set_process(false)

	# 0) 로고 화면 — 이음매의 기준 프레임
	g.set("mode", "logo")
	g.set("logo_t", 0.0)
	var f_logo: Image = await _shot("s0_logo.png")

	# 1) 미끄러짐 — k를 직접 놓고 찍는다. _process가 한 프레임분 더 얹으므로 실제 값을 같이 인쇄한다.
	g.call("_logo_done")
	var mi: float = 0.28   # = Main.MENU_INTRO. 상수를 바꾸면 여기도 바꿀 것(k를 절대초로 환산하는 데만 쓴다)
	var frames: Array = []
	for k in KS:
		g.set("menu_intro", mi * k)
		var im: Image = await _shot("s1_slide_%02d.png" % int(k * 100.0))
		frames.append(im)
		print("k=", k, " menu_intro_after=", g.get("menu_intro"))

	# 2) 도착 = 평상시 홈(전환 아님)
	g.set("menu_intro", -1.0)
	var f_home: Image = await _shot("s2_home.png")

	if f_home == null:
		print("SKIP(headless)")
		quit()
		return

	# ① 이음매 — k=0 프레임과 로고 화면이 로고 띠에서 같아야 한다. 배경 자리가 아니라 로고가 있는 밴드를 본다.
	var seam: int = 0
	var band_y: int = int(round(1280.0 * 0.47))
	for x in range(120, 680, 8):
		for dy in [-40, -10, 20]:
			var ca: Color = f_logo.get_pixel(x, band_y + dy)
			var cb: Color = frames[0].get_pixel(x, band_y + dy)
			for ch in [ca.r - cb.r, ca.g - cb.g, ca.b - cb.b]:
				seam = maxi(seam, int(round(absf(ch) * 255.0)))
	print("seam_max_diff(8bit)=", seam)          # 0에 가까워야 한다 = 컷 순간 로고가 안 튄다

	# ② 배경 — 미끄러지는 매 프레임의 배경이 홈과 같아야 한다(덮개가 배경을 안 건드림)
	for i in range(frames.size()):
		print("bg_diff k=", KS[i], " -> ", _bg_diff(frames[i], f_home))

	# ③ 도착 — k=1 직전과 평상시 홈. 여기선 로고가 제자리, 버튼도 다 나와 있어야 한다.
	g.set("menu_intro", mi * 0.999)
	var f_end: Image = await _shot("s1_slide_end.png")
	print("end_vs_home_bg_diff=", _bg_diff(f_end, f_home))

	# ④ 폭 불변 — 미끄러지는 동안 로고 **크기는 변하지 않아야 한다**(로고 화면도 홈과 같은 380).
	#   크기를 애니메이션하면 프레임마다 글리프를 다시 구워 10fps로 주저앉는다(Main의 MENU_WM_MAXW_HOME
	#   주석에 실측). 그래서 이 값은 0이어야 한다 — 0이 아니면 크기 애니메이션이 되살아난 것이다.
	var prev_w: int = -1
	var worst_step: int = 0
	for i in range(14):
		g.set("menu_intro", mi * float(i) / 13.0)
		g.call("queue_redraw")
		await process_frame
		await RenderingServer.frame_post_draw
		var im2: Image = root.get_texture().get_image()
		var lo: int = 800
		var hi: int = 0
		# ⚠y 상한은 버튼(736~1040)보다 위여야 한다. 처음엔 900까지 재서 버튼이 등장하는 프레임의
		#   폭 540을 로고 폭으로 읽었고, 그게 '한 프레임에 70px' 가짜 계단으로 나왔다.
		for y in range(120, 725, 3):
			for x in range(0, 800, 2):
				var c: Color = im2.get_pixel(x, y)
				if maxf(maxf(c.r, c.g), c.b) > 0.55 and c.v > 0.45:
					lo = mini(lo, x)
					hi = maxi(hi, x)
		var wpx: int = maxi(0, hi - lo)
		if prev_w >= 0:
			worst_step = maxi(worst_step, absi(prev_w - wpx))
		prev_w = wpx
	print("width_worst_step(px/frame)=", worst_step, "  (0이어야 한다)")

	# ⑤ 실시간 — 위 셋은 내가 k를 손으로 놓고 본 것이다. 부팅을 **실제로** 굴려(_process가 logo_t·menu_intro를
	#   밀게) 상태가 logo → menu(미끄러짐) → 평상시 홈으로 흘러가고 **끝나는지** 본다.
	#   여기서 안 끝나면(menu_intro가 -1로 안 돌아오면) 홈이 영영 전환 중인 화면이 된다.
	g.set_process(true)
	g.set("mode", "logo")
	g.set("logo_t", 0.0)
	g.set("menu_intro", -1.0)
	var t: float = 0.0
	var seen_slide: bool = false
	var settled: float = -1.0
	while t < 1.6:
		await process_frame
		t += get_root().get_process_delta_time()
		var mi_now: float = float(g.get("menu_intro"))
		if mi_now >= 0.0:
			seen_slide = true
		elif seen_slide and settled < 0.0:
			settled = t
	print("saw_slide=", seen_slide, " settled_at=", "%.2f" % settled, "s  mode=", g.get("mode"))
	print("DONE")
	quit()
