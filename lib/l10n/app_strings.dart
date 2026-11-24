import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../data/models/match_rules.dart';
import '../data/models/saved_match.dart';
import '../engine/engine.dart';
import '../features/game/controller/game_state.dart';

/// Type-safe Korean / English localization strings driven automatically by the
/// device locale (`ko` -> Korean, all other locales -> English).
class AppStrings {
  const AppStrings(this.locale);

  final Locale locale;

  bool get isKo => locale.languageCode == 'ko';

  static const List<Locale> supportedLocales = [
    Locale('en'),
    Locale('ko'),
  ];

  static const LocalizationsDelegate<AppStrings> delegate =
      _AppStringsDelegate();

  static Locale resolveLocale(
    Locale? deviceLocale,
    Iterable<Locale> supported,
  ) {
    if (deviceLocale?.languageCode == 'ko') {
      return const Locale('ko');
    }
    return const Locale('en');
  }

  static AppStrings of(BuildContext context) {
    final found = Localizations.of<AppStrings>(context, AppStrings);
    if (found != null) return found;
    return AppStrings(Localizations.maybeLocaleOf(context) ?? const Locale('en'));
  }

  // ── App / Common ──────────────────────────────────────────────────────────
  String get appTitle => isKo ? '오목' : 'Omok';
  String get settingsTooltip => isKo ? '환경 설정' : 'Settings';
  String get cancel => isKo ? '취소' : 'Cancel';
  String get confirm => isKo ? '확인' : 'Done';
  String get decline => isKo ? '거절' : 'Decline';
  String get accept => isKo ? '수락' : 'Accept';
  String get leave => isKo ? '나가기' : 'Leave';
  String get home => isKo ? '홈으로' : 'Home';
  String get refresh => isKo ? '새로고침' : 'Refresh';
  String get join => isKo ? '참가' : 'Join';

  // ── Enum Labels ───────────────────────────────────────────────────────────
  String gameModeLabel(GameMode mode) => switch (mode) {
        GameMode.vsAi => isKo ? 'AI 대전' : 'vs AI',
        GameMode.localTwoPlayer => isKo ? '로컬 2인' : 'Local 2P',
        GameMode.nearbyP2p => isKo ? '근거리 2인' : 'Nearby 2P',
      };

  String ruleTypeLabel(RuleType type) => switch (type) {
        RuleType.renju => isKo ? '렌주룰' : 'Renju',
        RuleType.freestyle => isKo ? '자유룰' : 'Freestyle',
      };

  String ruleTypeDescription(RuleType type) => switch (type) {
        RuleType.renju => isKo
            ? '흑 금수(3-3 · 4-4 · 장목) 적용, 흑은 정확히 5목만 승리'
            : 'Black forbidden moves (3-3, 4-4, overline); Black wins with exact 5 only',
        RuleType.freestyle => isKo
            ? '흑·백 모두 금수 없음, 5목 이상(6목 포함) 모두 승리'
            : 'No forbidden moves for either side; 5 or more in a row wins',
      };

  String difficultyLabel(AiDifficulty d) => switch (d) {
        AiDifficulty.beginner => isKo ? '초급' : 'Beginner',
        AiDifficulty.intermediate => isKo ? '중급' : 'Intermediate',
        AiDifficulty.advanced => isKo ? '고급' : 'Advanced',
        AiDifficulty.expert => isKo ? '전문가' : 'Expert',
      };

  String difficultyDescription(AiDifficulty d) => switch (d) {
        AiDifficulty.beginner =>
          isKo ? '입문자를 위한 편안한 난이도' : 'Relaxed play ideal for newcomers',
        AiDifficulty.intermediate => isKo
            ? '기본 공방과 3·4 위협을 대응하는 난이도'
            : 'Balanced offense and defense against 3 & 4 threats',
        AiDifficulty.advanced => isKo
            ? '띈 패턴과 4-3 전술까지 읽는 본격 난이도'
            : 'Reads broken patterns and 4-3 tactical traps',
        AiDifficulty.expert => isKo
            ? '연속 4목(VCF)과 깊은 수읽기를 구사하는 최고 난이도'
            : 'Deep search with Victory by Continuous Fours (VCF)',
      };

  String undoLimitLabel(UndoLimit limit) => switch (limit) {
        UndoLimit.unlimited => isKo ? '무제한' : 'Unlimited',
        UndoLimit.three => isKo ? '3회' : '3x',
        UndoLimit.one => isKo ? '1회' : '1x',
        UndoLimit.none => isKo ? '금지' : 'Off',
      };

  String stonePreferenceLabel(StonePreference pref) => switch (pref) {
        StonePreference.black => isKo ? '흑돌' : 'Black',
        StonePreference.white => isKo ? '백돌' : 'White',
        StonePreference.random => isKo ? '무작위' : 'Random',
      };

  String stoneShortLabel(Stone stone) => stone == Stone.black
      ? (isKo ? '흑' : 'Black')
      : (isKo ? '백' : 'White');

  String stoneFullLabel(Stone stone) => stone == Stone.black
      ? (isKo ? '흑돌' : 'Black')
      : (isKo ? '백돌' : 'White');

  String secondsShort(int seconds) => isKo ? '$seconds초' : '${seconds}s';

  // ── Home Screen ───────────────────────────────────────────────────────────
  String heroTitle(RuleType ruleType) =>
      isKo ? '${ruleTypeLabel(ruleType)} 오목' : '${ruleTypeLabel(ruleType)} Omok';
  String get heroSubtitle => isKo
      ? '비행기 모드 지원 · AI & 2인 대전'
      : '100% Offline · AI & 2-Player';

  String get ruleSettingsTitle => isKo ? '룰 설정' : 'Match Rules';
  String get changeLabel => isKo ? '변경' : 'Edit';
  String timeLimitPill(MatchRules rules) => rules.useTimeLimit
      ? (isKo
          ? '제한시간 ${rules.turnTimeLimitSeconds}초'
          : 'Timer ${rules.turnTimeLimitSeconds}s')
      : (isKo ? '제한시간 없음' : 'No Timer');
  String undoPill(UndoLimit limit) =>
      isKo ? '무르기 ${undoLimitLabel(limit)}' : 'Undo ${undoLimitLabel(limit)}';

  String get resumeCardTitle => isKo ? '진행 중인 대국' : 'Ongoing Match';
  String resumeCardSubtitle(SavedMatch saved) {
    final diff = difficultyLabel(saved.difficulty);
    final rule = ruleTypeLabel(saved.rules.ruleType);
    final stone = stoneShortLabel(saved.humanStone);
    return isKo
        ? '$diff · $rule · 내 돌($stone) · ${saved.moveCount}수'
        : '$diff · $rule · $stone (#${saved.moveCount})';
  }

  String get discardSavedTooltip => isKo ? '기록 삭제' : 'Discard match';
  String get resumeButton => isKo ? '이어하기' : 'Resume';

  String get selectDifficultyTitle => isKo ? 'AI 난이도 선택' : 'AI Difficulty';
  String statsBadge(int wins, int losses, int winRatePercent) =>
      isKo ? '$wins승 $losses패 ($winRatePercent%)' : '${wins}W ${losses}L ($winRatePercent%)';

  String get selectStoneTitle => isKo ? '내 돌 선택' : 'Your Stone';
  String get stoneBlackTitle => isKo ? '흑돌' : 'Black';
  String stoneBlackSubtitle(RuleType ruleType) => ruleType == RuleType.renju
      ? (isKo ? '선공 · 금수' : '1st · Renju')
      : (isKo ? '선공 · 자유' : '1st · Free');
  String get stoneWhiteTitle => isKo ? '백돌' : 'White';
  String get stoneWhiteSubtitle => isKo ? '후공 · 자유' : '2nd · Free';
  String get stoneRandomTitle => isKo ? '무작위' : 'Random';
  String get stoneRandomSubtitle => isKo ? '흑/백 랜덤' : 'Black / White';

  String startAiMatchButton(AiDifficulty difficulty) => isKo
      ? '${difficultyLabel(difficulty)} AI와 대국 시작'
      : 'Play vs ${difficultyLabel(difficulty)} AI';

  // Local 2P Panel
  String get local2pTitle => isKo ? '한 기기에서 둘이서 대국' : 'Pass & Play on One Device';
  String local2pDescription(MatchRules rules) {
    final rule = ruleTypeLabel(rules.ruleType);
    final timer = rules.useTimeLimit
        ? (isKo
            ? '턴 제한시간(${rules.turnTimeLimitSeconds}초)'
            : '${rules.turnTimeLimitSeconds}s turn timer')
        : (isKo ? '제한시간 없음' : 'no turn timer');
    final undo = undoLimitLabel(rules.undoLimit);
    return isKo
        ? '흑돌(선공)과 백돌(후공)이 한 화면에서 번갈아 착수합니다. 위에서 설정한 $rule, $timer, 무르기($undo) 룰이 그대로 적용됩니다.'
        : 'Black (1st) and White (2nd) take turns on the same screen. Uses your active rules: $rule, $timer, Undo ($undo).';
  }

  String forbiddenChip(RuleType ruleType) => ruleType == RuleType.renju
      ? (isKo ? '흑 금수 표시' : 'Forbidden markers')
      : (isKo ? '금수 없음' : 'No restrictions');
  String get replaySupportedChip => isKo ? '대국 후 복기 지원' : 'Post-game replay';
  String get startLocal2pButton => isKo ? '로컬 2인 대국 시작' : 'Start Local 2P Match';

  // Nearby P2P Panel
  String get nearbyP2pTitle =>
      isKo ? '근거리 Wi-Fi / 핫스팟 2인 대전' : 'Nearby Wi-Fi / Hotspot 2P';
  String nearbyP2pDescription(MatchRules rules) {
    final rule = ruleTypeLabel(rules.ruleType);
    return isKo
        ? '외부 서버 없이 같은 Wi-Fi 또는 핫스팟에 연결된 두 기기(iOS ↔ Android)가 직접 연결되어 대국합니다. 방장이 설정한 $rule 및 제한시간·무르기 룰이 참가자에게 자동으로 동기화됩니다.'
        : 'Connect two devices directly over the same Wi-Fi or Personal Hotspot (iOS ↔ Android) with no external server. The host\'s $rule, timer, and undo rules sync automatically.';
  }

  String get crossPlatformChip =>
      isKo ? 'iOS ↔ Android 호환' : 'iOS ↔ Android';
  String get serverlessP2pChip =>
      isKo ? '서버 없음 · 로컬 P2P' : 'Serverless P2P';
  String get createRoomButton => isKo ? '방 만들기 (호스트)' : 'Create Room (Host)';
  String get joinRoomButton =>
      isKo ? '주변 방 참가하기 (게스트)' : 'Join Nearby Room (Guest)';

  // ── Rule Settings Sheet ───────────────────────────────────────────────────
  String get ruleSheetTitle => isKo ? '대국 룰 설정' : 'Match Rules';
  String get ruleSheetSubtitle =>
      isKo ? '새 대국을 시작할 때 적용되는 규칙입니다.' : 'Applied when starting a new match.';
  String get ruleTypeSectionTitle => isKo ? '오목 규칙' : 'Rule Set';
  String get turnTimerSwitchTitle =>
      isKo ? '턴 제한시간 (유저 · AI 공통)' : 'Turn Time Limit (All Players)';
  String get turnTimerSwitchSubtitle => isKo
      ? '0초가 되면 즉시 시간패로 대국이 종료됩니다'
      : 'Running out of time results in an immediate timeout loss';
  String get secondsPerMoveLabel => isKo ? '수당 제한시간' : 'Time per move';
  String get decreaseOneSecTooltip => isKo ? '1초 감소' : 'Decrease 1s';
  String get increaseOneSecTooltip => isKo ? '1초 증가' : 'Increase 1s';
  String get undoLimitSectionTitle => isKo ? '무르기 횟수 제한' : 'Undo Limit';

  // ── Settings Sheet ────────────────────────────────────────────────────────
  String get settingsSheetTitle => isKo ? '게임 설정' : 'Settings';
  String get confirmBeforePlaceTitle =>
      isKo ? '착수 확인 모드 (오터치 방지)' : '2-Step Move Confirmation';
  String get confirmBeforePlaceSubtitle => isKo
      ? '위치 미리보기 후 확정 버튼 또는 재탭으로 착수'
      : 'Preview before placing; tap Confirm or tap again to place';
  String get showForbiddenTitle =>
      isKo ? '렌주룰 금수 표시 (✕)' : 'Show Renju Forbidden Moves (✕)';
  String get showForbiddenSubtitle => isKo
      ? '흑 차례일 때 3-3 · 4-4 · 장목 금지 위치 표시'
      : 'Highlight 3-3, 4-4, and overline points on Black\'s turn';
  String get showMoveNumbersTitle => isKo ? '수순 번호 표시' : 'Show Move Numbers';
  String get showMoveNumbersSubtitle => isKo
      ? '바둑돌 위에 1, 2, 3... 착수 순서 표시'
      : 'Display 1, 2, 3... sequence numbers on stones';
  String get showCoordinatesTitle =>
      isKo ? '바둑판 좌표 표시' : 'Show Board Coordinates';
  String get showCoordinatesSubtitle => isKo
      ? '테두리에 A~O, 1~15 좌표 표시'
      : 'Display A–O and 1–15 grid labels along edges';
  String get soundEffectsTitle => isKo ? '효과음' : 'Sound Effects';
  String get soundEffectsSubtitle =>
      isKo ? '바둑돌 착수음 및 승패 효과음 재생' : 'Play stone placement and result audio';
  String get hapticFeedbackTitle => isKo ? '진동 피드백' : 'Haptic Feedback';
  String get hapticFeedbackSubtitle =>
      isKo ? '돌 착수 및 금수 알림 시 진동' : 'Vibrate on stone placement and alerts';
  String get resetStatsButton => isKo ? '전적 초기화' : 'Reset Stats';
  String get resetStatsDialogTitle => isKo ? '전적 초기화' : 'Reset Statistics';
  String get resetStatsDialogContent => isKo
      ? '모든 난이도의 승패 기록을 초기화할까요?'
      : 'Reset win/loss records across all AI difficulties?';
  String get resetAction => isKo ? '초기화' : 'Reset';
  String get resetStatsDone =>
      isKo ? '전적이 초기화되었습니다.' : 'Statistics have been reset.';

  // ── Game Screen & HUD ─────────────────────────────────────────────────────
  String gameAppBarTitle(GameState state) => switch (state.mode) {
        GameMode.vsAi =>
          isKo ? 'AI 대전 · ${difficultyLabel(state.difficulty)}' : 'vs AI · ${difficultyLabel(state.difficulty)}',
        GameMode.localTwoPlayer => isKo ? '로컬 2인 대전' : 'Local 2P Match',
        GameMode.nearbyP2p => isKo ? '근거리 2인 대전' : 'Nearby 2P Match',
      };

  String moveCountLabel(int count) => isKo ? '$count수' : 'Move $count';
  String get replayLabel => isKo ? '기보 복기' : 'Replay';
  String replayProgressLabel(int step, int total) =>
      isKo ? '기보 복기 · $step / $total수' : 'Replay · $step / $total';
  String get exitReplay => isKo ? '복기 종료' : 'Exit Replay';
  String get replayFirstTooltip => isKo ? '처음으로' : 'First move';
  String get replayPrevTooltip => isKo ? '이전 수' : 'Previous move';
  String get replayNextTooltip => isKo ? '다음 수' : 'Next move';
  String get replayLastTooltip => isKo ? '마지막 수' : 'Last move';

  String playerBlackTitle(GameState state, {required bool blackIsHuman}) {
    if (state.isLocalTwoPlayer) return isKo ? '흑 (선공)' : 'Black (1st)';
    if (state.isNearbyP2p) {
      return blackIsHuman
          ? (isKo
              ? '${state.localPlayerName} (나 · 흑)'
              : '${state.localPlayerName} (You · B)')
          : (isKo ? '${state.opponentName} (흑)' : '${state.opponentName} (B)');
    }
    return blackIsHuman
        ? (isKo ? '나 (흑 · 선공)' : 'You')
        : 'AI · ${difficultyLabel(state.difficulty)}';
  }

  String playerBlackSubtitle(
    GameState state, {
    required bool blackIsHuman,
    required bool blackActive,
    required bool isRenju,
  }) {
    if (state.isLocalTwoPlayer) {
      if (!blackActive) return isKo ? '대기 중' : 'Waiting';
      return isRenju
          ? (isKo ? '차례 · 금수 적용' : 'Turn · Renju')
          : (isKo ? '차례 · 자유룰' : 'Turn · Freestyle');
    }
    if (state.isNearbyP2p) {
      if (!blackActive) return isKo ? '대기 중' : 'Waiting';
      return blackIsHuman
          ? (isKo ? '내 차례' : 'Your turn')
          : (isKo ? '상대방 고민 중...' : 'Opponent thinking...');
    }
    if (blackIsHuman) {
      return isRenju
          ? (isKo ? '렌주 금수 적용' : 'Black · Renju')
          : (isKo ? '자유룰 · 선공' : 'Black · 1st');
    }
    return state.isAiThinking
        ? (isKo ? '수읽기 중...' : 'Thinking...')
        : (isKo ? '흑 · 선공' : 'Black · 1st');
  }

  String playerWhiteTitle(GameState state, {required bool blackIsHuman}) {
    if (state.isLocalTwoPlayer) return isKo ? '백 (후공)' : 'White (2nd)';
    if (state.isNearbyP2p) {
      return !blackIsHuman
          ? (isKo
              ? '${state.localPlayerName} (나 · 백)'
              : '${state.localPlayerName} (You · W)')
          : (isKo ? '${state.opponentName} (백)' : '${state.opponentName} (W)');
    }
    return !blackIsHuman
        ? (isKo ? '나 (백 · 후공)' : 'You')
        : 'AI · ${difficultyLabel(state.difficulty)}';
  }

  String playerWhiteSubtitle(
    GameState state, {
    required bool blackIsHuman,
    required bool whiteActive,
  }) {
    if (state.isLocalTwoPlayer) {
      return whiteActive
          ? (isKo ? '차례 · 금수 없음' : 'Turn · Free')
          : (isKo ? '대기 중' : 'Waiting');
    }
    if (state.isNearbyP2p) {
      if (!whiteActive) return isKo ? '대기 중' : 'Waiting';
      return !blackIsHuman
          ? (isKo ? '내 차례' : 'Your turn')
          : (isKo ? '상대방 고민 중...' : 'Opponent thinking...');
    }
    if (!blackIsHuman) {
      return isKo ? '금수 없음' : 'White · 2nd';
    }
    return state.isAiThinking
        ? (isKo ? '수읽기 중...' : 'Thinking...')
        : (isKo ? '백 · 후공' : 'White · 2nd');
  }

  String undoActionLabel(GameState state) {
    final undoMax = state.rules.undoLimit.maxCount;
    final remaining = state.remainingUndos;
    if (undoMax == 0) return isKo ? '무르기 금지' : 'No Undo';
    if (remaining != null) {
      return isKo ? '무르기 ($remaining)' : 'Undo ($remaining)';
    }
    return isKo ? '무르기' : 'Undo';
  }

  String confirmMoveCtaLabel(GameState state) {
    final pending = state.pendingMove;
    if (pending != null) {
      return isKo ? '${pending.notation} 착수 확정' : 'Confirm ${pending.notation}';
    }
    if (state.isOpponentDisconnected) {
      return isKo ? '상대방과 연결이 끊어졌습니다' : 'Opponent disconnected';
    }
    if (state.isAiThinking) {
      return isKo ? 'AI가 수읽기 중입니다...' : 'AI is thinking...';
    }
    if (state.isNearbyP2p && !state.isHumanTurn) {
      return isKo ? '상대방의 착수를 기다리는 중...' : 'Waiting for opponent...';
    }
    return isKo ? '착수할 위치를 선택하세요' : 'Tap a point to place your stone';
  }

  String get hintButton => isKo ? '힌트' : 'Hint';
  String get resetZoomTooltip => isKo ? '배율 초기화' : 'Reset zoom';
  String get newGameButton => isKo ? '새 대국' : 'Restart';

  String get restartDialogTitle => isKo ? '새 대국 시작' : 'Start New Match';
  String get restartDialogContent => isKo
      ? '현재 진행 중인 대국을 초기화하고 다시 시작할까요?'
      : 'Reset the current board and start a new match?';
  String get restartAction => isKo ? '다시 시작' : 'Restart';

  String p2pUndoRequestBanner(String opponentName) => isKo
      ? '$opponentName님이 무르기를 요청했습니다.'
      : '$opponentName requested an undo.';
  String p2pRematchRequestBanner(String opponentName) => isKo
      ? '$opponentName님이 다시 대국을 요청했습니다.'
      : '$opponentName requested a rematch.';
  String get disconnectedBannerText =>
      isKo ? '상대방과 연결이 끊어졌습니다.' : 'Disconnected from opponent.';

  // Result Banner
  String get resultDrawHeadline => isKo ? '무승부!' : 'Draw!';
  String get resultDrawDetail =>
      isKo ? '225수 접전 끝에 비겼습니다.' : 'The board is full after 225 moves.';

  String resultLocal2pHeadline({required bool blackWon, required bool isTimeout}) {
    final winner = stoneFullLabel(blackWon ? Stone.black : Stone.white);
    if (isTimeout) return isKo ? '$winner 시간 초과 승리!' : '$winner Wins on Time!';
    return isKo ? '$winner 승리!' : '$winner Wins!';
  }

  String resultLocal2pDetail({
    required bool blackWon,
    required bool isTimeout,
    required int turnLimitSec,
    required int moveCount,
  }) {
    final winner = stoneFullLabel(blackWon ? Stone.black : Stone.white);
    final loser = stoneFullLabel(blackWon ? Stone.white : Stone.black);
    if (isTimeout) {
      return isKo
          ? '$loser이 제한시간($turnLimitSec초)을 초과했습니다.'
          : '$loser ran out of time (${turnLimitSec}s).';
    }
    return isKo
        ? '$winner이 $moveCount수 만에 5목을 완성했습니다.'
        : '$winner made five in a row in $moveCount moves.';
  }

  String resultP2pHeadline({
    required bool iWon,
    required bool isTimeout,
    required String opponentName,
  }) {
    if (iWon) {
      return isTimeout
          ? (isKo ? '시간 초과 승리!' : 'Victory on Time!')
          : (isKo ? '승리했습니다!' : 'You Win!');
    }
    return isTimeout
        ? (isKo ? '시간 초과 패배' : 'Time Out Loss')
        : (isKo ? '$opponentName 승리' : '$opponentName Wins');
  }

  String resultP2pDetail({
    required bool iWon,
    required bool isTimeout,
    required String opponentName,
    required int turnLimitSec,
    required int moveCount,
  }) {
    if (isTimeout) {
      return iWon
          ? (isKo
              ? '$opponentName님이 제한시간을 초과했습니다.'
              : '$opponentName ran out of time.')
          : (isKo
              ? '턴 제한시간($turnLimitSec초)을 초과했습니다.'
              : 'You exceeded the ${turnLimitSec}s turn limit.');
    }
    return iWon
        ? (isKo
            ? '$opponentName님을 $moveCount수 만에 이겼습니다.'
            : 'You defeated $opponentName in $moveCount moves.')
        : (isKo
            ? '$opponentName님이 $moveCount수 만에 승리했습니다.'
            : '$opponentName won in $moveCount moves.');
  }

  String resultAiWinHeadline({required bool isTimeout}) => isTimeout
      ? (isKo ? '시간 초과 승리!' : 'Victory on Time!')
      : (isKo ? '승리했습니다!' : 'You Win!');

  String resultAiWinDetail({
    required bool isTimeout,
    required AiDifficulty difficulty,
    required int moveCount,
  }) {
    final diff = difficultyLabel(difficulty);
    if (isTimeout) {
      return isKo ? '$diff AI가 제한시간을 초과했습니다.' : '$diff AI ran out of time.';
    }
    return isKo
        ? '$diff AI를 $moveCount수 만에 이겼습니다.'
        : 'Defeated $diff AI in $moveCount moves.';
  }

  String resultAiLossHeadline({required bool isTimeout}) => isTimeout
      ? (isKo ? '시간 초과 패배' : 'Time Out Loss')
      : (isKo ? 'AI 승리' : 'AI Wins');

  String resultAiLossDetail({
    required bool isTimeout,
    required AiDifficulty difficulty,
    required int turnLimitSec,
    required int moveCount,
  }) {
    if (isTimeout) {
      return isKo
          ? '턴 제한시간($turnLimitSec초)을 초과했습니다.'
          : 'You exceeded the ${turnLimitSec}s turn limit.';
    }
    final diff = difficultyLabel(difficulty);
    return isKo
        ? '$diff AI가 $moveCount수 만에 승리했습니다.'
        : '$diff AI won in $moveCount moves.';
  }

  String get replayButton => isKo ? '복기' : 'Replay';
  String get waitingRematchLabel =>
      isKo ? '상대 응답 대기 중...' : 'Waiting for opponent...';
  String get rematchButton => isKo ? '다시 대국' : 'Rematch';

  // ── Game Notices ──────────────────────────────────────────────────────────
  String formatGameNotice(GameNotice notice) => switch (notice) {
        RandomStoneAssignedNotice(:final isBlack) => isBlack
            ? (isKo
                ? '무작위 배정: 흑돌(선공)으로 시작합니다'
                : 'Random draw: You play Black (1st)')
            : (isKo
                ? '무작위 배정: 백돌(후공)으로 시작합니다'
                : 'Random draw: You play White (2nd)'),
        P2pConnectedNotice(:final isBlack) => isBlack
            ? (isKo
                ? '연결 완료! 흑돌(선공)으로 시작합니다'
                : 'Connected! You play Black (1st)')
            : (isKo
                ? '연결 완료! 백돌(후공)으로 시작합니다'
                : 'Connected! You play White (2nd)'),
        P2pRematchStartedNotice(:final isBlack) => isBlack
            ? (isKo
                ? '새 대국! 흑돌(선공)으로 시작합니다'
                : 'New match! You play Black (1st)')
            : (isKo
                ? '새 대국! 백돌(후공)으로 시작합니다'
                : 'New match! You play White (2nd)'),
        ForbiddenMoveNotice(:final reason) => switch (reason) {
            ForbiddenReason.overline => isKo
                ? '금수입니다: 장목 (흑 6목 이상 불가)'
                : 'Forbidden: Overline (6+ stones)',
            ForbiddenReason.doubleFour =>
              isKo ? '금수입니다: 4-4 (사사 금지)' : 'Forbidden: Double Four (4-4)',
            ForbiddenReason.doubleThree =>
              isKo ? '금수입니다: 3-3 (쌍삼 금지)' : 'Forbidden: Double Three (3-3)',
            ForbiddenReason.none => '',
          },
        HintSuggestedNotice(:final notation) =>
          isKo ? '추천 수: $notation' : 'Hint: $notation',
        SimpleGameNotice(:final type) => switch (type) {
            SimpleNoticeType.undoRequested =>
              isKo ? '상대방에게 무르기를 요청했습니다' : 'Undo request sent',
            SimpleNoticeType.undoDeclinedBySelf =>
              isKo ? '무르기 요청을 거절했습니다' : 'Undo request declined',
            SimpleNoticeType.undoDeclinedByPeer =>
              isKo ? '상대방이 무르기를 거절했습니다' : 'Opponent declined undo',
            SimpleNoticeType.undoApplied =>
              isKo ? '무르기가 적용되었습니다' : 'Move undone',
            SimpleNoticeType.rematchRequested =>
              isKo ? '상대방에게 다시 대국을 요청했습니다' : 'Rematch request sent',
            SimpleNoticeType.rematchDeclinedBySelf =>
              isKo ? '다시 대국 요청을 거절했습니다' : 'Rematch request declined',
            SimpleNoticeType.rematchDeclinedByPeer =>
              isKo ? '상대방이 다시 대국을 거절했습니다' : 'Opponent declined rematch',
            SimpleNoticeType.peerLeft =>
              isKo ? '상대방이 대국에서 나갔습니다' : 'Opponent left the match',
            SimpleNoticeType.peerDisconnected =>
              isKo ? '상대방과 연결이 끊어졌습니다' : 'Connection lost',
          },
      };

  // ── Nearby Lobby Screen ───────────────────────────────────────────────────
  String get defaultHostName => isKo ? '방장' : 'Host';
  String get defaultGuestName => isKo ? '참가자' : 'Guest';
  String roomBroadcastName(String hostName) =>
      isKo ? '$hostName의 오목방' : "$hostName's Omok";

  String get nearbyHostAppBar => isKo ? '근거리 방 만들기' : 'Create Nearby Room';
  String get nearbyGuestAppBar => isKo ? '주변 방 참가하기' : 'Join Nearby Room';
  String get nicknameLabel => isKo ? '내 닉네임' : 'Your Nickname';

  String get openingRoomStatus => isKo ? '로컬 방을 여는 중...' : 'Opening local room...';
  String get waitingGuestStatus =>
      isKo ? '상대방 참가를 기다리는 중...' : 'Waiting for opponent to join...';
  String hostOpenFailedError(Object error) => isKo
      ? '방을 열지 못했습니다. Wi-Fi 또는 핫스팟 연결을 확인해 주세요. ($error)'
      : 'Could not open room. Check your Wi-Fi or hotspot connection. ($error)';
  String get autoScanFailedError => isKo
      ? '자동 탐색을 시작하지 못했습니다. 아래 IP 직접 연결을 이용해 주세요.'
      : 'Could not start auto-discovery. Use Direct IP connection below.';
  String connectingToStatus(String target) =>
      isKo ? '$target에 연결 중...' : 'Connecting to $target...';
  String joinFailedError(List<String> hosts, int port) => isKo
      ? '방에 연결하지 못했습니다. 같은 Wi-Fi/핫스팟인지와 IP·포트를 확인해 주세요.\n(시도: ${hosts.take(3).join(', ')}:$port)'
      : 'Could not connect to room. Check that both devices share the same Wi-Fi/hotspot and verify IP & Port.\n(Tried: ${hosts.take(3).join(', ')}:$port)';

  String portOnlyLabel(int port) => isKo ? '포트 $port' : 'Port $port';
  String hostRulesSummary(MatchRules rules) =>
      '${ruleTypeLabel(rules.ruleType)} · ${timeLimitPill(rules)} · ${undoPill(rules.undoLimit)}';
  String get directAddressCaption => isKo
      ? '직접 연결 주소 (자동 탐색이 안 될 때)'
      : 'Direct Address (if auto-discovery fails)';
  String get copyAddressTooltip => isKo ? '주소 복사' : 'Copy address';
  String get addressCopiedSnackbar =>
      isKo ? '연결 주소를 복사했습니다.' : 'Address copied to clipboard.';
  String get closeRoomButton => isKo ? '방 닫기' : 'Close Room';
  String get hostStoneSectionTitle => isKo ? '방장 돌 선택' : 'Host Stone';
  String get openingRoomButton => isKo ? '방 여는 중...' : 'Opening...';
  String get openRoomAndWaitButton =>
      isKo ? '방 열고 상대 기다리기' : 'Open Room & Wait';

  String get discoveredRoomsTitle => isKo ? '발견된 주변 방' : 'Nearby Rooms';
  String get scanningRoomsHint => isKo
      ? '같은 Wi-Fi 또는 핫스팟에서 열린 오목방을 찾는 중입니다...'
      : 'Searching for Omok rooms on the same Wi-Fi or hotspot...';
  String roomTileSubtitle({
    required RuleType ruleType,
    required int? turnTimeLimitSeconds,
    required String endpoint,
  }) {
    final timer = turnTimeLimitSeconds != null
        ? (isKo ? '제한시간 $turnTimeLimitSeconds초' : 'Timer ${turnTimeLimitSeconds}s')
        : (isKo ? '제한시간 없음' : 'No Timer');
    return '${ruleTypeLabel(ruleType)} · $timer · $endpoint';
  }

  String get manualConnectTitle =>
      isKo ? 'IP 주소로 직접 연결 (핫스팟/수동 백업)' : 'Direct IP Connection (Manual)';
  String get hostIpFieldLabel =>
      isKo ? '방장 IP (예: 192.168.0.12)' : 'Host IP (e.g. 192.168.0.12)';
  String get portFieldLabel => isKo ? '포트' : 'Port';
  String get connectingButton => isKo ? '연결 중...' : 'Connecting...';
  String get directConnectButton => isKo ? '직접 연결하기' : 'Connect Directly';
  String get invalidIpPortError => isKo
      ? '올바른 IP 주소와 포트 번호(1~65535)를 입력해 주세요.'
      : 'Please enter a valid IP address and port (1–65535).';

  String get networkTipText => isKo
      ? '두 기기(iOS · Android 모두 가능)가 같은 Wi-Fi에 연결되어 있거나, 한쪽 기기의 개인용 핫스팟에 연결되어 있으면 인터넷/서버 없이 대국할 수 있습니다.'
      : 'Two devices (iOS or Android) on the same Wi-Fi or Personal Hotspot can play directly with no internet or server.';
}

class _AppStringsDelegate extends LocalizationsDelegate<AppStrings> {
  const _AppStringsDelegate();

  @override
  bool isSupported(Locale locale) =>
      locale.languageCode == 'en' || locale.languageCode == 'ko';

  @override
  Future<AppStrings> load(Locale locale) =>
      SynchronousFuture<AppStrings>(AppStrings(locale));

  @override
  bool shouldReload(covariant LocalizationsDelegate<AppStrings> old) => false;
}
