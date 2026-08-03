extends SceneTree
# 음색 청취용 굽기 (정본: AUDIO_PLAN.md §5·§13)
#   실행: godot --headless --path . --script tools/audio_bake.gd
#   결과: build/audio_preview/*.wav  (파인더에서 더블클릭해서 듣는다)
#
# R7부터 음원은 합성이 아니라 `res://sfx/`의 CC0 파형 둘이다. 그래도 이 도구가 필요한 이유:
#   게임 안에서만 들리던 **조립 결과**(사다리·아르페지오·2단 삭제음)를 파일 하나로 만들어
#   귀로 확인해야 하기 때문이다. 낱개 파형은 그냥 sfx/ 폴더에서 들으면 된다.
#
# ⚠ .wav는 커밋하지 않는다 — build/는 .gitignore.

const OUT_DIR: String = "res://build/audio_preview"

func _init() -> void:
	var m: Node = load("res://Main.gd").new()
	m._sfx_build_bank()
	if (m._sfx_bank as Dictionary).is_empty():
		print("뱅크가 비었다 — `godot --headless --path . --import` 먼저 돌릴 것")
		m.free(); quit(1); return

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	# 낱개 원본 둘(이름을 어휘로 바꿔 저장 — 어느 파형이 어디 쓰이는지 귀로 확인)
	for pair in [["pop_low__place_fail", "place"], ["pop_high__grab_score_tap", "grab"],
			["chip_low__clear", "clear"], ["chip_high__clear2", "clear2"]]:
		var w: AudioStreamWAV = m._sfx_bank[pair[1]]
		var path: String = "%s/%s.wav" % [OUT_DIR, pair[0]]
		if w.save_to_wav(path) == OK:
			print("  %-28s %5d 샘플 · %dHz · %d bytes" % [pair[0], w.data.size() / 2, w.mix_rate, w.data.size()])

	var lo: AudioStreamWAV = m._sfx_bank["clear"]      # 터지는 층
	var hi: AudioStreamWAV = m._sfx_bank["chain"]      # 반짝이는 층
	# ① 연쇄 사다리 — chain 파형을 5음계로 훑는다(연쇄가 음악으로 들리는지)
	_seq("%s/ladder.wav" % OUT_DIR, [[hi, 0], [hi, 2], [hi, 4], [hi, 7], [hi, 9], [hi, 12], [hi, 14], [hi, 16]], 0.11)
	# ② 판 닫는 아르페지오
	_seq("%s/fanfare.wav" % OUT_DIR, [[lo, 0], [lo, 4], [lo, 7], [lo, 12]], 0.10)
	# ③ 2단 삭제음 — 낮은 파형 타격 + 40ms 뒤 높은 파형. 게임에선 이게 한 사건으로 들린다.
	#   ⚠음정은 안 올린다(R10) — 둘째 층 파형이 이미 더 높다(748 → 4994Hz).
	_seq("%s/clear_2layer.wav" % OUT_DIR, [[lo, 0], [m._sfx_bank["clear2"], 0]], 0.040)
	# ④ 집기→착지 한 쌍(동작 계열)
	var g: AudioStreamWAV = m._sfx_bank["grab"]
	var pl: AudioStreamWAV = m._sfx_bank["place"]
	_seq("%s/grab_then_place.wav" % OUT_DIR, [[g, -2], [pl, 7]], 0.35)
	# ⑤ UI 탭 넷(R13) — 진입(+7) · 중립(0) · 뒤로(−5) · 잠김(−8). 한 파형에서 음정·레벨로만 갈린다.
	#   ⚠**상대 레벨을 보존해야 판정이 된다** → 음마다 db를 실어 넘긴다(정규화는 합친 뒤 한 번뿐).
	#   순서대로 들으면 "위로 들어가고 아래로 나온다"가 방향으로 읽혀야 한다.
	# ⑥ 전멸 3층(R14) — 타격 + 45ms 광택 + 135ms 상승 광택. clear(2층)과 나란히 들어 '더 큰가'를 본다.
	var sk2: AudioStreamWAV = m._sfx_bank["clear2"]
	_seq("%s/climax_3layer.wav" % OUT_DIR, [[lo, 0, -1.5], [sk2, 0, -11.0], [sk2, 5, -11.0]], 0.045)
	# ⑦ 누수·칭찬 — 둘 다 '작아야' 하는 소리다. 삭제음 뒤에 붙여 위계가 맞는지 듣는다.
	_seq("%s/leak_and_praise.wav" % OUT_DIR, [
			[lo, 0, -3.6], [m._sfx_bank["leak"], 3, -13.0],
			[lo, 0, -3.6], [m._sfx_bank["praise"], -5, -13.0]], 0.55)
	var ui: AudioStreamWAV = m._sfx_bank["tap"]
	var wds: Dictionary = m.SFX_WORDS
	_seq("%s/ui_taps.wav" % OUT_DIR, [
			[ui, int(wds["tap_go"].get("base", 0)), float(wds["tap_go"]["db"])],
			[ui, 0, float(wds["tap"]["db"])],
			[ui, int(wds["tap_back"].get("base", 0)), float(wds["tap_back"]["db"])],
			[ui, int(wds["tap_off"].get("base", 0)), float(wds["tap_off"]["db"])],
		], 0.45)
	# ⑧ 클리어 축하 무대 전체(R17) — 낱개가 아니라 **3.9초 타임라인**을 그대로 굽는다.
	#   왜 낱개가 아닌가: 이 라운드가 고친 건 음색이 아니라 **분포**다(무음 3.4초). 낱개를 들으면
	#   고쳐졌는지 알 수 없고, 겹침·위계도 시간축 위에서만 판정이 된다.
	#   ⚠**게임 안 '5'키가 정본 판정 수단이다**(§21 방법론: 파일 A/B는 소리 판정에 실패한다).
	#   이 파일은 클리핑·위계 감사와 "무엇을 붙였나"의 기록용이다.
	var tl: Array = []
	var hold: float = float(m.CLEAR_HOLD)
	var lad: Array = m.SFX_LADDER
	var wd: Dictionary = m.SFX_WORDS
	# 승리 아르페지오(무대시각 −hold부터 0.10초 간격 4음)
	for k in range(4):
		tl.append([lo, [0, 4, 7, 12][k], float(wd["fanfare"]["db"]), float(k) * 0.10])
	# 피니시 스윕 — 8행 전부 블록이 있다고 보고(가장 붐비는 경우) 아래→위로
	var sw: AudioStreamWAV = m._sfx_bank.get("sweep", null)
	if sw != null:
		for r in range(m.ROWS):
			tl.append([sw, int(lad[m.ROWS - 1 - r]), float(wd["sweep"]["db"]), float(m.ROWS - 1 - r) * float(m.CLEAR_SWEEP_STAGGER)])
		tl.append([m._sfx_bank["clear_hit"], 0, float(wd["clear_hit"]["db"]), float(m.ROWS - 1) * float(m.CLEAR_SWEEP_STAGGER)])
	# 로고 조립 + 강펀치(무대시각 0부터 = 파일에선 +hold)
	var lt: AudioStreamWAV = m._sfx_bank["letter"]
	var n1: int = String(m.WM_L1).length()
	for i in range(n1):
		tl.append([lt, int(lad[i]), float(wd["letter"]["db"]), hold + float(m.CLEAR_LOGO_IN) + float(i) * float(m.CLEAR_LETTER_GAP)])
	tl.append([lt, int(lad[n1]), float(wd["letter"]["db"]), hold + float(m.CLEAR_L2_IN)])
	tl.append([m._sfx_bank["logo"], 0, float(wd["logo"]["db"]), hold + float(m.CLEAR_L2_IN) + float(m.CLEAR_L2_PUNCH)])
	tl.append([sk2, 5, float(wd["clear2"]["db"]), hold + float(m.CLEAR_L2_IN) + float(m.CLEAR_L2_PUNCH) + 0.045])
	# 폭죽 — 발사 시각은 게임과 같은 균등 분포(랜덤 ±0.05는 뺀다: 프리뷰는 재현 가능해야 한다)
	var fr: AudioStreamWAV = m._sfx_bank.get("fw_rise", null)
	var fp: AudioStreamWAV = m._sfx_bank["fw_pop"]
	for i2 in range(int(m.CLEAR_ROCKET_N)):
		var f: float = float(i2) / float(maxi(1, int(m.CLEAR_ROCKET_N) - 1))
		var t0: float = hold + lerpf(float(m.CLEAR_ROCKET_FIRST), float(m.CLEAR_ROCKET_LAST), f)
		# 발사와 터짐은 **같은 음정**을 받는다(같은 발 = 같은 포탄 크기). Main.gd의 표를 그대로 읽는다.
		var fsemi: int = int(m.CLEAR_FW_SEMI[i2 % (m.CLEAR_FW_SEMI as Array).size()])
		if fr != null:
			tl.append([fr, fsemi, float(wd["fw_rise"]["db"]), t0])
		tl.append([fp, fsemi, float(wd["fw_pop"]["db"]), t0 + float(m.CLEAR_ROCKET_RISE)])
	_at("%s/CLEAR_STAGE.wav" % OUT_DIR, tl)
	m.free()
	quit()

# _seq의 절대시각 판 — 축하 무대처럼 간격이 불규칙한 타임라인용. [파형, 반음, dB, 시각(초)].
func _at(path: String, notes: Array) -> void:
	var rate: int = (notes[0][0] as AudioStreamWAV).mix_rate
	var end_t: float = 0.0
	for nt in notes:
		end_t = maxf(end_t, float(nt[3]) + float((nt[0] as AudioStreamWAV).data.size() / 2) / float(rate))
	var out_n: int = int((end_t + 0.25) * float(rate))
	var acc := PackedFloat32Array()
	acc.resize(out_n)
	var pk_raw: float = 0.0
	for nt2 in notes:
		var src: AudioStreamWAV = nt2[0]
		var n_src: int = src.data.size() / 2
		var ratio: float = pow(2.0, float(nt2[1]) / 12.0)
		var gain: float = db_to_linear(float(nt2[2]))
		var at: int = int(float(nt2[3]) * float(rate))
		var i: int = 0
		while true:
			var sp: float = float(i) * ratio
			var si: int = int(sp)
			if si + 1 >= n_src or at + i >= out_n:
				break
			var a: float = float(_s16(src.data, si)) / 32768.0
			var b: float = float(_s16(src.data, si + 1)) / 32768.0
			acc[at + i] += lerpf(a, b, sp - float(si)) * gain
			i += 1
	for i2 in range(out_n):
		pk_raw = maxf(pk_raw, absf(acc[i2]))
	# ⚠**정규화 전 피크를 같이 찍는다** — 게임에선 리미터가 −0.5dB에서 받는데, 프리뷰만 정규화하면
	#   "합이 얼마나 세게 때리는가"가 파일에서 사라진다(§18의 클리핑 감사가 그래서 필요했다).
	var g2: float = (0.85 / pk_raw) if pk_raw > 0.0001 else 1.0
	var data := PackedByteArray()
	data.resize(out_n * 2)
	for i3 in range(out_n):
		var v: int = clampi(int(round(clampf(acc[i3] * g2, -1.0, 1.0) * 32767.0)), -32768, 32767)
		if v < 0:
			v += 65536
		data[i3 * 2] = v & 0xff
		data[i3 * 2 + 1] = (v >> 8) & 0xff
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.loop_mode = AudioStreamWAV.LOOP_DISABLED
	w.data = data
	if w.save_to_wav(path) == OK:
		print("  %-28s %5d 샘플 (%.2fs) · 합산 피크 %+.1f dBFS(정규화 전)"
				% [path.get_file().get_basename(), out_n, float(out_n) / float(rate), linear_to_db(pk_raw)])

# 파형·음정 목록을 이어 붙여 한 파일로. 게임의 pitch_scale을 선형보간 리샘플로 흉내낸다.
func _seq(path: String, notes: Array, step: float) -> void:
	var rate: int = (notes[0][0] as AudioStreamWAV).mix_rate
	var step_n: int = int(step * float(rate))
	var longest: int = 0
	for nt in notes:
		longest = maxi(longest, (nt[0] as AudioStreamWAV).data.size() / 2)
	var out_n: int = step_n * notes.size() + longest + rate / 4
	var acc := PackedFloat32Array()
	acc.resize(out_n)
	for k in range(notes.size()):
		var src: AudioStreamWAV = notes[k][0]
		var n_src: int = src.data.size() / 2
		var ratio: float = pow(2.0, float(notes[k][1]) / 12.0)
		# 셋째 원소가 있으면 그 음의 dB — 게임의 위계를 프리뷰에 그대로 옮긴다(없으면 등레벨).
		var gain: float = db_to_linear(float((notes[k] as Array)[2])) if (notes[k] as Array).size() > 2 else 1.0
		var at: int = k * step_n
		var i: int = 0
		while true:
			var sp: float = float(i) * ratio
			var si: int = int(sp)
			if si + 1 >= n_src or at + i >= out_n:
				break
			var a: float = float(_s16(src.data, si)) / 32768.0
			var b: float = float(_s16(src.data, si + 1)) / 32768.0
			acc[at + i] += lerpf(a, b, sp - float(si)) * gain
			i += 1
	# ⚠합친 뒤 피크 정규화 — 안 하면 겹친 음이 프리뷰 파일 자체를 클립시켜 음색 판정이 왜곡된다.
	var pk: float = 0.0
	for i2 in range(out_n):
		pk = maxf(pk, absf(acc[i2]))
	var g: float = (0.85 / pk) if pk > 0.0001 else 1.0
	var data := PackedByteArray()
	data.resize(out_n * 2)
	for i3 in range(out_n):
		var v: int = clampi(int(round(clampf(acc[i3] * g, -1.0, 1.0) * 32767.0)), -32768, 32767)
		if v < 0:
			v += 65536
		data[i3 * 2] = v & 0xff
		data[i3 * 2 + 1] = (v >> 8) & 0xff
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.loop_mode = AudioStreamWAV.LOOP_DISABLED
	w.data = data
	if w.save_to_wav(path) == OK:
		print("  %-28s %5d 샘플 (%.2fs)" % [path.get_file().get_basename(), out_n, float(out_n) / float(rate)])

func _s16(d: PackedByteArray, i: int) -> int:
	var v: int = d[i * 2] | (d[i * 2 + 1] << 8)
	return v - 65536 if v >= 32768 else v
