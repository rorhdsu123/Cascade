/**
 * BlockCastle 계측 수집기 — 구글 앱스 스크립트 (스프레드시트 바인딩)
 *
 * 이 파일은 저장소 사본이다. 실제로 도는 것은 rorhdsu123 계정의 스프레드시트에 붙은 스크립트다.
 * ⚠고쳤으면 **양쪽 다** 갱신할 것. 저장소만 고치면 아무 일도 안 일어나고,
 *   시트만 고치면 그 코드는 이 계정이 날아가는 순간 같이 사라진다.
 * ⚠시트에서 코드를 고친 뒤에는 **배포 → 새 배포**를 해야 반영된다(저장만으론 안 바뀐다).
 *   주소는 그대로 유지된다: 배포 관리 → 편집(연필) → 버전 '새 버전' → 배포.
 *
 * 게임 쪽 짝: analytics.gd `_remote_flush()` — sendBeacon으로 text/plain을 던지고 응답을 안 읽는다.
 *   그래서 여기서 무엇을 돌려주든 게임은 모른다. 실패해도 조용하다 = 로그로만 드러난다.
 */

const DATA_SHEET = '이벤트';
const DICT_SHEET = '데이터 사전';
const DASH_SHEET = '대시보드';

// 시트 열 구성. ⚠순서를 바꾸면 대시보드 수식이 통째로 어긋난다 — 늘릴 땐 반드시 뒤에 붙일 것.
//   '원본'은 항상 마지막이다(모든 값을 통째로 담는 그물 — 지금 안 뽑은 값이 나중에 필요해질 때를 위해).
const COLUMNS = [
  '받은시각', 'install_id', 'session_id', '이벤트', '빌드', '플랫폼', '모드',
  't_ms', 'duration_ms', 'runs_played', 'stage_id', 'cause', 'beat', 'max_combo', '원본'
];

function doPost(e) {
  // 여러 명이 동시에 보내면 줄이 겹쳐 쓰인다. 자물쇠로 순서를 준다.
  const lock = LockService.getScriptLock();
  lock.waitLock(30000);
  try {
    const body = JSON.parse(e.postData.contents);
    const events = body.events || [];
    if (!events.length) return _ok();

    const sheet = _dataSheet();
    const now = new Date();
    const rows = events.map(function (ev) {
      return [
        now,                    // 이벤트엔 절대 시각이 없다(t_ms는 게임 켠 뒤 경과) → 여기서 찍는다
        body.install_id || ev.install_id || '',
        ev.session_id || '',
        ev.event || '',
        ev.build_version || '',
        ev.platform || '',
        ev.mode || '',
        _num(ev.t_ms),
        _num(ev.duration_ms),
        _num(ev.runs_played),
        _num(ev.stage_id),
        ev.cause || '',
        _num(ev.beat),
        _num(ev.max_combo),
        JSON.stringify(ev)
      ];
    });
    sheet.getRange(sheet.getLastRow() + 1, 1, rows.length, COLUMNS.length).setValues(rows);
    return _ok();
  } catch (err) {
    // 게임엔 못 알린다(응답을 안 읽으므로). 실행 기록에만 남는다 — 데이터가 안 보이면 거기부터 본다.
    console.error('doPost 실패: ' + err + ' / 본문=' + (e && e.postData ? e.postData.contents : '없음'));
    return _ok();
  } finally {
    lock.releaseLock();
  }
}

function doGet() {
  // 살아 있는지 브라우저로 확인하는 용도. 데이터는 안 준다(주소를 아는 사람이 다 읽으면 곤란하다).
  return ContentService.createTextOutput('ok');
}

// ⚠'받은시각'은 **시각까지** 보여야 한다. 기본 서식이 날짜만이면 CSV로 내려받았을 때
//   `2026. 8. 13`처럼 날짜뿐이라, **세션을 시간 간격으로 묶을 수가 없다** — 폰은 한 방문이
//   여러 세션으로 쪼개지므로(가려짐), 그걸 되붙이는 유일한 단서가 시각이다.
//   2026-08-14 첫 판독에서 실제로 막혔다. 값은 원래 datetime이고 표시만 날짜였다.
function _fixTimeFormat(sheet) {
  try {
    sheet.getRange(2, 1, Math.max(sheet.getMaxRows() - 1, 1), 1)
         .setNumberFormat('yyyy-mm-dd hh:mm:ss');
  } catch (err) {
    console.error('시각 서식 적용 실패: ' + err);
  }
}

// 숫자 칸엔 숫자를 넣는다 — 문자열로 들어가면 AVERAGEIF 같은 게 조용히 0을 센다.
function _num(v) {
  return (v === undefined || v === null || v === '') ? '' : Number(v);
}

function _ok() {
  return ContentService.createTextOutput(JSON.stringify({ ok: true }))
    .setMimeType(ContentService.MimeType.JSON);
}

function _dataSheet() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  let sheet = ss.getSheetByName(DATA_SHEET);
  if (!sheet) {
    sheet = ss.insertSheet(DATA_SHEET);
    sheet.appendRow(COLUMNS);
    sheet.setFrozenRows(1);
    sheet.getRange(1, 1, 1, COLUMNS.length).setFontWeight('bold');
  }
  _fixTimeFormat(sheet);
  return sheet;
}

/* ────────────────────────────────────────────────────────────────
   시트 메뉴 — 사전과 대시보드를 만든다. 한 번만 돌리면 된다.
   ──────────────────────────────────────────────────────────────── */

function onOpen() {
  SpreadsheetApp.getUi()
    .createMenu('BlockCastle')
    .addItem('사전·대시보드 만들기(다시 만들기)', 'setupSheets')
    .addItem('시험 줄 지우기(install_id가 probe-)', 'clearProbeRows')
    .addToUi();
}

function setupSheets() {
  const msg = _repairHeader();
  _buildDict();
  _buildDashboard();
  SpreadsheetApp.getActiveSpreadsheet().toast('사전과 대시보드를 만들었습니다. ' + msg, 'BlockCastle', 8);
}

// 머리글이 COLUMNS와 다르면 고친다.
// ⚠열을 늘린 뒤 머리글이 옛 상태로 남으면 **대시보드 수식이 통째로 엉뚱한 열을 읽는다** —
//   에러가 아니라 '그럴듯한 0'이 나오므로 안 드러난다. 그래서 여기서 강제로 맞춘다.
// ⚠옛 열 구성으로 쌓인 줄은 위치가 어긋난 채 남는다. 지우는 건 사람이 판단할 일이라 알리기만 한다.
function _repairHeader() {
  const sheet = _dataSheet();
  const width = sheet.getLastColumn();
  const head = width ? sheet.getRange(1, 1, 1, width).getValues()[0] : [];
  const same = head.length === COLUMNS.length && COLUMNS.every(function (c, i) { return head[i] === c; });
  if (same) return '';

  sheet.getRange(1, 1, 1, COLUMNS.length).setValues([COLUMNS]).setFontWeight('bold');
  sheet.setFrozenRows(1);
  const rows = Math.max(0, sheet.getLastRow() - 1);
  return rows
    ? '⚠머리글을 새 구성으로 바꿨습니다. 이전 ' + rows + '줄은 열이 어긋나 있으니 지우세요(메뉴 → 시험 줄 지우기).'
    : '머리글을 새 구성으로 맞췄습니다.';
}

// 시험용으로 넣은 줄을 지운다. 진짜 데이터와 섞이면 첫 측정이 오염된다.
function clearProbeRows() {
  const sheet = _dataSheet();
  const last = sheet.getLastRow();
  if (last < 2) return;
  const ids = sheet.getRange(2, 2, last - 1, 1).getValues();
  let removed = 0;
  // 뒤에서부터 지운다 — 앞에서 지우면 행 번호가 밀려 엉뚱한 줄이 지워진다.
  for (let i = ids.length - 1; i >= 0; i--) {
    if (String(ids[i][0]).indexOf('probe-') === 0) {
      sheet.deleteRow(i + 2);
      removed++;
    }
  }
  SpreadsheetApp.getActiveSpreadsheet().toast(removed + '줄 지웠습니다.', 'BlockCastle', 5);
}

/* ── 데이터 사전 ── */

// ⚠정본은 저장소의 docs/ANALYTICS_TAXONOMY.md다. 여기는 **시트에서 바로 보라고 둔 사본**이고,
//   택소노미를 고치면 이 표도 같이 고쳐야 한다. 둘이 어긋나면 저장소 쪽이 맞다.
const DICT_ROWS = [
  ['— 모든 줄에 붙는 값 —', '', ''],
  ['받은시각', '수집기가 받은 시각', '이벤트엔 날짜가 없다(t_ms는 게임 켠 뒤 경과 시간). 언제 왔는지는 이 열로만 안다'],
  ['install_id', '브라우저마다 무작위로 만든 문자열', '같은 사람이 다시 왔는지 = 재방문 판정. 개인정보 아님 — 누구인지 알 수 없다'],
  ['session_id', '앱을 켜서 끌 때까지 하나', '한 사람의 한 번 방문을 묶는다. 이탈 지점을 볼 때 이걸로 묶는다'],
  ['빌드', '예: 0.9.0-L1.1', '어느 루프의 어느 배포인지. ⚠비면 0.0.0-dev — 루프 비교가 불가능해진다'],
  ['플랫폼', 'web / android / desktop_*', '웹 플레이테스트인지 구분'],
  ['모드', 'campaign / endless / featured', '듀얼코어 어느 기둥인지 — 가장 중요한 축'],
  ['t_ms', '게임 켠 뒤 경과(ms)', '한 세션 안의 시간 흐름. 절대 시각이 아니다'],
  ['touch', '터치 화면 기기인가(true/false)', '⭐웹은 폰이든 PC든 플랫폼이 web 하나다. 폰만 겪는 문제를 가리려면 이 칸이 있어야 한다(2026-08-14 추가)'],
  ['', '', ''],
  ['— 이벤트 —', '', ''],
  ['app_opened', '앱을 켰다', '세션 시작. is_first_session=이 기기의 첫 실행인가 · resumed=자리를 비웠다 돌아와 다시 열린 세션인가'],
  ['session_ended', '앱을 껐다(탭 닫기·5분 넘게 자리 비움)', '⭐머문 시간(duration_ms)과 그 세션의 판 수(runs_played). ⚠짧게 가려진 것으론 안 끊는다 — 폰에서 한 방문이 조각나던 걸 2026-08-14에 고쳤다(그 전 데이터는 세션이 잘게 쪼개져 있다)'],
  ['run_started', '한 판 시작', '모드·시드·stage_id·attempt_n(그 판 몇 번째 시도) · is_tutorial(튜토리얼 완주율의 **분모**)'],
  ['stage_cleared', '스테이지 클리어', '스테이지 번호·걸린 시간·최대 콤보·잡은 수·샌 수·부활 썼나·2줄3줄 동시 클리어'],
  ['stage_failed', '스테이지 실패', '⭐스테이지 번호·왜 졌나·이 스테이지 몇 번째 실패인가. 같은 곳에서 3번이면 막힌 것'],
  ['run_failed', '판 실패', '왜 졌나 — core_death(거점 파괴) / stuck(놓을 자리 없음)'],
  ['endless_run_ended', '무한 모드 한 판 끝', '점수·개인기록 갱신 여부'],
  ['combo_peak', '판 끝날 때 최대 콤보', '스펙터클 축'],
  ['first_line_cleared', '첫 줄을 지웠다(세션 1회)', '첫 쾌감까지 걸린 시간 = TTF쾌감'],
  ['tutorial_beat_completed', '튜토리얼 박자', '⭐beat 1=배치 · 2=처치(=완주, tut_phase가 여기서 끝난다) · 3=적을 통과시킴. 🔴**1·2·3을 퍼널로 세우지 말 것** — 3은 과제가 아니라 사건이라 잘 하면 영영 안 뜬다(optional=true). bail=true는 처치 없이 밸브로 빠진 것'],
  ['revive_offered', '부활 제안이 떴다', '광고가 준비돼 있었는지도 같이'],
  ['revive_taken', '부활을 봤다', '광고를 볼 사람인가 = 수익 축의 원재료'],
  ['revive_declined', '부활을 거절했다', '위와 짝'],
  ['ad_*', '광고 관련 7종', '⚠웹에도 온다 — AdMob은 네이티브지만 웹은 목(mock) 광고가 돌아 ad_requested·ad_filled가 찍힌다(2026-08-14 실측 정정). 진짜 수익 신호는 클로즈드 테스트부터'],
  ['', '', ''],
  ['— 안 남기는 것 —', '', ''],
  ['개인정보', '전부 안 받는다', '이름·이메일·위치·아이피 없음. install_id는 무작위 문자열이라 역추적이 안 된다'],
  ['화면 이동', '안 찍는다', '"설정을 열었다" 같은 건 없다. 이탈 지점은 마지막 이벤트로 추론한다'],
];

function _buildDict() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  let sh = ss.getSheetByName(DICT_SHEET);
  if (sh) ss.deleteSheet(sh);
  sh = ss.insertSheet(DICT_SHEET, 1);

  sh.getRange(1, 1, 1, 3).setValues([['이름', '무엇', '왜 / 어떻게 읽나']])
    .setFontWeight('bold').setBackground('#EFF1F6');
  sh.getRange(2, 1, DICT_ROWS.length, 3).setValues(DICT_ROWS);

  // 구분줄(— 로 시작)은 굵게
  for (let i = 0; i < DICT_ROWS.length; i++) {
    if (String(DICT_ROWS[i][0]).indexOf('—') === 0) {
      sh.getRange(i + 2, 1, 1, 3).setFontWeight('bold').setBackground('#F6F7FB');
    }
  }
  sh.setFrozenRows(1);
  sh.setColumnWidth(1, 190);
  sh.setColumnWidth(2, 230);
  sh.setColumnWidth(3, 520);
  sh.getRange(1, 1, DICT_ROWS.length + 1, 3).setVerticalAlignment('top').setWrap(true);

  sh.getRange(DICT_ROWS.length + 3, 1).setValue(
    '정본은 저장소의 docs/ANALYTICS_TAXONOMY.md다. 택소노미를 고치면 이 표도 같이 고칠 것 — 어긋나면 저장소 쪽이 맞다.'
  ).setFontColor('#5B6274').setFontSize(11);
}

/* ── 대시보드 ── */

function _buildDashboard() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  let sh = ss.getSheetByName(DASH_SHEET);
  if (sh) ss.deleteSheet(sh);
  sh = ss.insertSheet(DASH_SHEET, 0);

  const D = "'" + DATA_SHEET + "'";
  const put = function (row, col, value, opts) {
    const r = sh.getRange(row, col);
    if (String(value).indexOf('=') === 0) r.setFormula(value); else r.setValue(value);
    if (opts && opts.bold) r.setFontWeight('bold');
    if (opts && opts.size) r.setFontSize(opts.size);
    if (opts && opts.color) r.setFontColor(opts.color);
    if (opts && opts.bg) r.setBackground(opts.bg);
    if (opts && opts.fmt) r.setNumberFormat(opts.fmt);
    return r;
  };

  put(1, 1, 'BlockCastle — 웹 플레이테스트 현황', { bold: true, size: 16 });
  put(2, 1, '숫자는 이벤트 시트가 채워질 때마다 저절로 다시 계산된다. 손댈 것 없다.', { color: '#5B6274' });

  // ── 핵심 넷 ──
  put(4, 1, '핵심', { bold: true, size: 13 });
  const head = { bold: true, bg: '#F6F7FB' };
  put(5, 1, '지표', head); put(5, 2, '지금', head); put(5, 3, '목표', head); put(5, 4, '무엇인가', head);

  put(6, 1, '사람 수');
  put(6, 2, '=IFERROR(COUNTA(UNIQUE(FILTER(' + D + '!B2:B,' + D + '!B2:B<>""))),0)');
  put(6, 3, '15~20');
  put(6, 4, '고유 install_id. 루프 1의 모집 목표');

  put(7, 1, '세션 수');
  put(7, 2, '=COUNTIF(' + D + '!D:D,"session_ended")');
  put(7, 3, '—');
  put(7, 4, '끝까지 관측된 방문 수');

  put(8, 1, '60초 넘긴 비율');
  put(8, 2, '=IFERROR(COUNTIFS(' + D + '!D:D,"session_ended",' + D + '!I:I,">60000")/COUNTIF(' + D + '!D:D,"session_ended"),0)',
      { fmt: '0.0%' });
  put(8, 3, '—');
  put(8, 4, '⭐루프 1이 묻는 것 — 낯선 사람이 60초를 넘기나');

  put(9, 1, '세션당 판 수');
  put(9, 2, '=IFERROR(AVERAGEIF(' + D + '!D:D,"session_ended",' + D + '!J:J),0)', { fmt: '0.00' });
  put(9, 3, '3.0');
  put(9, 4, '⭐최대 갭. 봇 실측 1.0판 vs 게이트 3판');

  put(10, 1, '평균 체류(초)');
  put(10, 2, '=IFERROR(AVERAGEIF(' + D + '!D:D,"session_ended",' + D + '!I:I)/1000,0)', { fmt: '0.0' });
  put(10, 3, '—');
  put(10, 4, '');

  put(11, 1, '한 판도 안 한 세션');
  put(11, 2, '=IFERROR(COUNTIFS(' + D + '!D:D,"session_ended",' + D + '!J:J,0)/COUNTIF(' + D + '!D:D,"session_ended"),0)',
      { fmt: '0.0%' });
  put(11, 3, '—');
  put(11, 4, '켜고 시작조차 안 한 비율 — 첫 화면 문제의 신호');

  // ── 이탈 지점 ──
  // ⚠**COUNTIF가 아니라 COUNTUNIQUEIFS다.** COUNTIF는 이벤트를 센다 — 한 사람이 튜토리얼을
  //   다시 하면 박자1이 두 번 찍히고, 그러면 아래 칸이 위 칸보다 커져서 '퍼널'이 아니게 된다.
  //   퍼널은 **각 단계에 도달한 세션 수**로만 말이 된다(C190).
  // 🔴**박자 1·2·3을 한 퍼널로 세우면 안 된다.** 박자3은 과제가 아니라 사건이다 — 적을 한 번
  //   통과시켰을 때만 뜨고, 잘 하면 영영 안 뜬다. 옛 대시보드는 셋을 세로로 늘어놓고
  //   "줄어드는 폭이 곧 이탈"이라고 적어놨는데, 그 문구를 믿고 2026-08-14에 실제로 오독했다
  //   (10→9→4를 "박자3이 벽"으로 읽었으나 박자3이 뜬 4세션은 **전원 스테이지1을 깼다**).
  //   완주는 박자2에서 난다. 그래서 진짜 퍼널과 사건을 **표를 갈라** 놓는다.
  put(13, 1, '온보딩 — 튜토리얼을 끝냈나', { bold: true, size: 13 });
  put(14, 1, '단계', head); put(14, 2, '세션', head); put(14, 3, '비율', head);
  put(15, 1, '튜토리얼 진입');
  put(15, 2, '=COUNTUNIQUEIFS(' + D + '!C:C,' + D + '!D:D,"run_started",' + D + '!K:K,1)');
  put(16, 1, '박자1 — 배치');
  put(16, 2, '=COUNTUNIQUEIFS(' + D + '!C:C,' + D + '!D:D,"tutorial_beat_completed",' + D + '!M:M,1)');
  put(17, 1, '박자2 — 처치 = 완주');
  put(17, 2, '=COUNTUNIQUEIFS(' + D + '!C:C,' + D + '!D:D,"tutorial_beat_completed",' + D + '!M:M,2)');
  put(18, 1, '스테이지1 클리어');
  put(18, 2, '=COUNTUNIQUEIFS(' + D + '!C:C,' + D + '!D:D,"stage_cleared",' + D + '!K:K,1)');
  for (var r = 15; r <= 18; r++) put(r, 3, '=IFERROR(B' + r + '/$B$15,0)', { fmt: '0.0%' });
  put(19, 1, '⚠진입은 stage_id=1 기준이라 최초 클리어 뒤 재도전도 섞인다(그땐 박자가 안 뜬다). 정확한 값은 tools/funnel.py.',
      { color: '#5B6274' });

  put(21, 1, '박자3 — 손해 학습(사건, 퍼널 아님)', { bold: true, size: 13 });
  put(22, 1, '적을 통과시킨 세션');
  put(22, 2, '=COUNTUNIQUEIFS(' + D + '!C:C,' + D + '!D:D,"tutorial_beat_completed",' + D + '!M:M,3)');
  put(23, 1, '첫 줄 지움');
  put(23, 2, '=COUNTUNIQUEIFS(' + D + '!C:C,' + D + '!D:D,"first_line_cleared")');
  put(24, 1, '🔴이 숫자가 낮은 건 나쁜 게 아니다 — 아무도 안 뚫렸다는 뜻일 수 있다. 실패 수와 함께 읽을 것.',
      { color: '#A63118' });

  // ── 이탈 퍼널 ──
  // 여기 숫자는 **눈으로 훑는 용도**다. 판독은 `tools/funnel.py`가 한다 — 시트 수식으로는
  // '앞 단계를 전부 통과한 세션'을 누적으로 셀 수 없어서, 아래는 단계별 독립 집계다.
  // 그래서 중간을 건너뛴 세션이 아래 칸에 되살아날 수 있다(그 차이를 보는 게 funnel.py 몫).
  put(27, 1, '이탈 퍼널 (세션 단위)', { bold: true, size: 13 });
  put(28, 1, '⚠누적이 아니다. 정식 판독은 시트를 CSV로 내려받아 `python3 tools/funnel.py 파일.csv`.',
      { color: '#5B6274' });
  put(29, 1, '단계', head); put(29, 2, '세션', head); put(29, 3, '비율', head);
  const steps = [
    ['세션 시작',  '=COUNTUNIQUEIFS(' + D + '!C:C,' + D + '!C:C,"<>")'],
    ['첫 판 시작', '=COUNTUNIQUEIFS(' + D + '!C:C,' + D + '!D:D,"run_started")'],
    ['60초 넘김',  '=COUNTUNIQUEIFS(' + D + '!C:C,' + D + '!D:D,"session_ended",' + D + '!I:I,">60000")'],
    ['첫 클리어',  '=COUNTUNIQUEIFS(' + D + '!C:C,' + D + '!D:D,"stage_cleared")'],
    ['두 번째 판', '=COUNTUNIQUEIFS(' + D + '!C:C,' + D + '!D:D,"session_ended",' + D + '!J:J,">=2")'],
  ];
  for (let i = 0; i < steps.length; i++) {
    put(30 + i, 1, steps[i][0]);
    put(30 + i, 2, steps[i][1]);
    put(30 + i, 3, '=IFERROR(B' + (30 + i) + '/$B$30,0)', { fmt: '0.0%' });
  }

  // ── 빌드별 = 루프별 비교 ──
  put(21, 1, '빌드별 비교 — 처방이 먹었나', { bold: true, size: 13 });
  put(22, 1, '⚠빌드를 안 올리고 재배포하면 처방 전후가 한 줄로 합쳐져 비교가 통째로 죽는다. RELEASE.md 웹 굽기 절차 참조.',
      { color: '#A63118' });
  put(23, 1, '=IFERROR(QUERY(' + D + '!A2:O,"select E, count(C), avg(I), avg(J) where D = \'session_ended\' group by E order by E label E \'빌드\', count(C) \'세션\', avg(I) \'평균 체류(ms)\', avg(J) \'세션당 판 수\'",0),"아직 없다")');

  // ⚠아래로 길게 뻗는 표(스테이지 20개)는 **오른쪽에** 둔다. 밑에 두면 다른 절을 밀어낸다.
  put(4, 6, '어디서 막히나 — 스테이지별 실패', { bold: true, size: 13 });
  put(5, 6, '=IFERROR(QUERY(' + D + '!A2:O,"select K, count(K) where D = \'stage_failed\' and K is not null group by K order by count(K) desc label K \'스테이지\', count(K) \'실패 수\'",0),"아직 실패 기록이 없다")');

  put(4, 9, '왜 졌나', { bold: true, size: 13 });
  put(5, 9, '=IFERROR(QUERY(' + D + '!A2:O,"select L, count(L) where D = \'run_failed\' and L is not null group by L order by count(L) desc label L \'원인\', count(L) \'수\'",0),"아직 없다")');
  put(9, 9, 'core_death = 거점이 뚫림 · stuck = 놓을 자리가 없음', { color: '#5B6274' });

  sh.setColumnWidth(1, 170);
  sh.setColumnWidth(2, 130);
  sh.setColumnWidth(3, 90);
  sh.setColumnWidth(4, 380);
  sh.setColumnWidth(5, 30);
  sh.setColumnWidth(6, 110);
  sh.setColumnWidth(7, 90);
  sh.setColumnWidth(8, 30);
  sh.setColumnWidth(9, 130);
  sh.setColumnWidth(10, 70);
  sh.getRange(6, 2, 6, 1).setHorizontalAlignment('right');
  sh.setFrozenRows(2);
}
