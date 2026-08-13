extends RefCounted
# 스크린샷 하네스의 출력 경로를 한 군데서 정한다 (C193).
#
# 왜 있나 — 샷 도구들이 각자 `const DIR = "/private/tmp/claude-501/…/<세션 uuid>/scratchpad/"`를
# 박아 두고 있었다. 그 경로는 **그 세션에서만 존재한다.** 2026-08-13에 세어보니 18개 도구가 쓰는
# 16개 경로 중 **15개가 이미 없는 디렉터리**였고, 그래서 도구를 돌리면 그림 없이
# `Can't save PNG at path`만 뱉었다. 실패가 조용해서(스크립트는 계속 돌고 종료 코드도 0) 도구가
# 살아 있는 줄 알고 인용하게 된다 — [[godot-pixel-verify-needs-window]]에 적어둔
# "하네스는 '있다'가 아니라 '최근에 초록이었다'가 확인돼야 근거다"의 바로 그 사례다.
#
# 규칙: 환경변수 `SHOT_DIR`이 있으면 거기로, 없으면 저장소 안 `build/shots/`로 떨어진다.
# `build/`는 gitignore돼 있어서 산출물이 커밋에 섞이지 않는다.
#   SHOT_DIR=/어디/ godot --path . --script tools/menu_shot.gd

static func resolve(sub: String = "") -> String:
	var base: String = OS.get_environment("SHOT_DIR")
	if base == "":
		base = ProjectSettings.globalize_path("res://build/shots/")
	if not base.ends_with("/"):
		base += "/"
	var out: String = base + sub
	# `sub`가 `cf_`처럼 **접두사**인 도구가 있다(파일 여러 장을 한 접두사로 낸다) —
	# 그럴 땐 마지막 조각을 빼고 디렉터리만 만든다.
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	return out
