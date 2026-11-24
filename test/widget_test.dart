import 'dart:async';
import 'dart:math';

import 'dart:ui' show Locale, Size;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omok/app.dart';
import 'package:omok/data/models/match_rules.dart';
import 'package:omok/data/models/saved_match.dart';
import 'package:omok/data/repositories/local_storage_repository.dart';
import 'package:omok/engine/engine.dart';
import 'package:omok/features/game/controller/game_controller.dart';
import 'package:omok/features/game/widgets/omok_board_view.dart';
import 'package:omok/shared/providers/app_providers.dart';
import 'package:omok/shared/services/sound_service.dart';

/// Deterministic, synchronous MoveSource for fast widget tests.
class _SyncTestMoveSource implements MoveSource {
  _SyncTestMoveSource(this.aiStone, this.difficulty, this.ruleType);

  final Stone aiStone;
  final AiDifficulty difficulty;
  final RuleType ruleType;
  bool _cancelled = false;

  @override
  Future<Coordinate?> nextMove(BoardState board) async {
    if (_cancelled) return null;
    final engine = DartAiEngine(random: Random(0));
    final RuleEngine rules = ruleType == RuleType.freestyle
        ? const FreestyleRuleEngine()
        : const RenjuRuleEngine();
    return engine.findBestMoveSync(
      board: board,
      aiStone: aiStone,
      difficulty: difficulty,
      ruleEngine: rules,
    );
  }

  @override
  void cancel() {
    _cancelled = true;
  }
}

/// MoveSource that never completes until cancelled (tests AI timeout).
class _HangingMoveSource implements MoveSource {
  final Completer<Coordinate?> _completer = Completer<Coordinate?>();

  @override
  Future<Coordinate?> nextMove(BoardState board) => _completer.future;

  @override
  void cancel() {
    if (!_completer.isCompleted) {
      _completer.complete(null);
    }
  }
}

/// Deterministic Random whose `nextBool()` returns a fixed value.
class _FixedBoolRandom implements Random {
  _FixedBoolRandom(this.value);

  final bool value;

  @override
  bool nextBool() => value;

  @override
  double nextDouble() => 0.0;

  @override
  int nextInt(int max) => 0;
}

MoveSource _syncFactory({
  required Stone aiStone,
  required AiDifficulty difficulty,
  required RuleType ruleType,
  int? turnTimeLimitSeconds,
}) =>
    _SyncTestMoveSource(aiStone, difficulty, ruleType);

void main() {
  testWidgets('HomeScreen displays 4 difficulties, 3 stone options, hint & undo',
      (tester) async {
    final storage = InMemoryStorageRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageRepositoryProvider.overrideWithValue(storage),
          soundServiceProvider.overrideWithValue(const SilentSoundService()),
          aiMoveSourceFactoryProvider.overrideWithValue(_syncFactory),
        ],
        child: const OmokApp(locale: Locale('ko')),
      ),
    );

    expect(find.text('초급'), findsOneWidget);
    expect(find.text('중급'), findsOneWidget);
    expect(find.text('고급'), findsOneWidget);
    expect(find.text('전문가'), findsOneWidget);
    expect(find.text('흑돌'), findsOneWidget);
    expect(find.text('백돌'), findsOneWidget);
    expect(find.text('무작위'), findsOneWidget);
    expect(find.text('룰 설정'), findsOneWidget);

    await tester.tap(find.text('초급'));
    await tester.pumpAndSettle();

    final startButton = find.text('초급 AI와 대국 시작');
    await tester.ensureVisible(startButton);
    await tester.tap(startButton);
    await tester.pumpAndSettle();

    expect(find.byType(OmokBoardView), findsOneWidget);
    expect(find.text('0수'), findsOneWidget);

    await tester.tap(find.text('힌트'));
    await tester.pumpAndSettle();
    expect(find.text('H8 착수 확정'), findsOneWidget);

    await tester.tap(find.text('H8 착수 확정'));
    await tester.pumpAndSettle();
    expect(find.text('2수'), findsOneWidget);
    expect(storage.loadSavedMatch()?.moveCount, 2);

    await tester.tap(find.text('무르기'));
    await tester.pumpAndSettle();
    expect(find.text('0수'), findsOneWidget);
  });

  testWidgets('RuleSettingsSheet updates Freestyle, time limit, and undo limit',
      (tester) async {
    final storage = InMemoryStorageRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageRepositoryProvider.overrideWithValue(storage),
          soundServiceProvider.overrideWithValue(const SilentSoundService()),
          aiMoveSourceFactoryProvider.overrideWithValue(_syncFactory),
        ],
        child: const OmokApp(locale: Locale('ko')),
      ),
    );

    // Open rule settings sheet from Home screen card.
    await tester.tap(find.text('룰 설정'));
    await tester.pumpAndSettle();
    expect(find.text('대국 룰 설정'), findsOneWidget);

    // Switch to Freestyle rule.
    await tester.tap(find.text('자유룰'));
    await tester.pumpAndSettle();

    // Enable turn time limit & select 60초 preset.
    await tester.tap(find.text('턴 제한시간 (유저 · AI 공통)'));
    await tester.pumpAndSettle();
    final preset60 = find.text('60초');
    await tester.ensureVisible(preset60);
    await tester.tap(preset60);
    await tester.pumpAndSettle();

    // Select UndoLimit = 1회.
    final undoOne = find.text('1회');
    await tester.ensureVisible(undoOne);
    await tester.tap(undoOne);
    await tester.pumpAndSettle();

    // Confirm sheet.
    final okBtn = find.text('확인');
    await tester.ensureVisible(okBtn);
    await tester.tap(okBtn);
    await tester.pumpAndSettle();

    // Summary pills on Home screen reflect updated rules.
    expect(find.text('자유룰'), findsOneWidget);
    expect(find.text('제한시간 60초'), findsOneWidget);
    expect(find.text('무르기 1회'), findsOneWidget);

    // Persisted in storage repository.
    final savedRules = storage.loadMatchRules();
    expect(savedRules.ruleType, RuleType.freestyle);
    expect(savedRules.useTimeLimit, isTrue);
    expect(savedRules.turnTimeLimitSeconds, 60);
    expect(savedRules.undoLimit, UndoLimit.one);
  });

  testWidgets('Turn time limit triggers immediate timeout loss & win',
      (tester) async {
    final storage = InMemoryStorageRepository();

    // 1. Human timeout (2s timer, human does not move -> AI wins on time).
    final humanContainer = ProviderContainer(
      overrides: [
        storageRepositoryProvider.overrideWithValue(storage),
        soundServiceProvider.overrideWithValue(const SilentSoundService()),
        aiMoveSourceFactoryProvider.overrideWithValue(_syncFactory),
      ],
    );
    addTearDown(humanContainer.dispose);

    humanContainer.read(gameControllerProvider.notifier).startNewGame(
          difficulty: AiDifficulty.beginner,
          stonePreference: StonePreference.black,
          rules: const MatchRules(
            useTimeLimit: true,
            turnTimeLimitSeconds: 2,
          ),
        );

    expect(
      humanContainer.read(gameControllerProvider).remainingTurnSeconds,
      2,
    );
    await tester.pump(const Duration(seconds: 2));
    final afterHumanTimeout = humanContainer.read(gameControllerProvider);
    expect(afterHumanTimeout.isGameOver, isTrue);
    expect(afterHumanTimeout.result.isTimeout, isTrue);
    expect(afterHumanTimeout.result.status, GameStatus.whiteWin);

    // 2. AI timeout (2s timer, hanging AI -> human wins on time!).
    final aiContainer = ProviderContainer(
      overrides: [
        storageRepositoryProvider.overrideWithValue(storage),
        soundServiceProvider.overrideWithValue(const SilentSoundService()),
        aiMoveSourceFactoryProvider.overrideWithValue(
          ({
            required aiStone,
            required difficulty,
            required ruleType,
            turnTimeLimitSeconds,
          }) =>
              _HangingMoveSource(),
        ),
      ],
    );
    addTearDown(aiContainer.dispose);

    aiContainer.read(gameControllerProvider.notifier).startNewGame(
          difficulty: AiDifficulty.expert,
          stonePreference: StonePreference.white, // AI Black moves first
          rules: const MatchRules(
            useTimeLimit: true,
            turnTimeLimitSeconds: 2,
          ),
        );

    await tester.pump(const Duration(seconds: 2));
    final afterAiTimeout = aiContainer.read(gameControllerProvider);
    expect(afterAiTimeout.isGameOver, isTrue);
    expect(afterAiTimeout.result.isTimeout, isTrue);
    expect(afterAiTimeout.result.status, GameStatus.whiteWin);
  });

  testWidgets('Undo limit enforces exact per-match undo count', (tester) async {
    final storage = InMemoryStorageRepository();
    await storage.saveSettings(
      storage.loadSettings().copyWith(confirmBeforePlace: false),
    );
    final container = ProviderContainer(
      overrides: [
        storageRepositoryProvider.overrideWithValue(storage),
        soundServiceProvider.overrideWithValue(const SilentSoundService()),
        aiMoveSourceFactoryProvider.overrideWithValue(_syncFactory),
      ],
    );
    addTearDown(container.dispose);

    final ctrl = container.read(gameControllerProvider.notifier);
    ctrl.startNewGame(
      difficulty: AiDifficulty.beginner,
      stonePreference: StonePreference.black,
      rules: const MatchRules(undoLimit: UndoLimit.one),
    );

    ctrl.onIntersectionTapped(const Coordinate(7, 7));
    await tester.pump();
    expect(container.read(gameControllerProvider).remainingUndos, 1);
    expect(container.read(gameControllerProvider).canUndo, isTrue);

    ctrl.undo();
    expect(container.read(gameControllerProvider).remainingUndos, 0);
    expect(container.read(gameControllerProvider).canUndo, isFalse);

    // Place again -> still cannot undo because 1-undo quota is exhausted.
    ctrl.onIntersectionTapped(const Coordinate(7, 7));
    await tester.pump();
    expect(container.read(gameControllerProvider).canUndo, isFalse);
  });

  testWidgets('Random stone option assigns White and lets AI Black open first',
      (tester) async {
    final storage = InMemoryStorageRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageRepositoryProvider.overrideWithValue(storage),
          soundServiceProvider.overrideWithValue(const SilentSoundService()),
          randomProvider.overrideWithValue(_FixedBoolRandom(false)),
          aiMoveSourceFactoryProvider.overrideWithValue(_syncFactory),
        ],
        child: const OmokApp(locale: Locale('ko')),
      ),
    );

    final randomCard = find.text('무작위');
    await tester.ensureVisible(randomCard);
    await tester.tap(randomCard);
    await tester.pumpAndSettle();

    final startButton = find.text('중급 AI와 대국 시작');
    await tester.ensureVisible(startButton);
    await tester.tap(startButton);
    await tester.pumpAndSettle();

    expect(find.text('나 (백 · 후공)'), findsOneWidget);
    expect(find.text('1수'), findsOneWidget);
  });

  testWidgets('Post-game replay scrubs through completed match moves cleanly',
      (tester) async {
    final storage = InMemoryStorageRepository();
    final container = ProviderContainer(
      overrides: [
        storageRepositoryProvider.overrideWithValue(storage),
        soundServiceProvider.overrideWithValue(const SilentSoundService()),
        aiMoveSourceFactoryProvider.overrideWithValue(_syncFactory),
      ],
    );
    addTearDown(container.dispose);

    final winningMoves = [
      const Coordinate(7, 5).index,
      const Coordinate(6, 5).index,
      const Coordinate(7, 6).index,
      const Coordinate(6, 6).index,
      const Coordinate(7, 7).index,
      const Coordinate(6, 7).index,
      const Coordinate(7, 8).index,
      const Coordinate(6, 8).index,
      const Coordinate(7, 9).index,
    ];

    container.read(gameControllerProvider.notifier).resumeMatch(
          SavedMatch(
            difficulty: AiDifficulty.beginner,
            humanStone: Stone.black,
            moveIndices: winningMoves,
            updatedAtIso: DateTime(2026, 11, 24).toIso8601String(),
          ),
        );

    final controller = container.read(gameControllerProvider.notifier);
    expect(container.read(gameControllerProvider).isGameOver, isTrue);

    controller.enterReplay();
    expect(container.read(gameControllerProvider).isReplaying, isTrue);
    expect(container.read(gameControllerProvider).displayBoard.moveCount, 1);
    expect(container.read(gameControllerProvider).displayWinningLine, isEmpty);

    controller.setReplayStep(9);
    expect(container.read(gameControllerProvider).displayBoard.moveCount, 9);
    expect(
      container.read(gameControllerProvider).displayWinningLine.length,
      5,
    );

    controller.exitReplay();
    expect(container.read(gameControllerProvider).isReplaying, isFalse);
  });

  testWidgets('HomeScreen shows Resume card when an offline match is saved',
      (tester) async {
    final storage = InMemoryStorageRepository();
    await storage.saveMatch(
      SavedMatch(
        difficulty: AiDifficulty.expert,
        humanStone: Stone.black,
        moveIndices: [
          const Coordinate(7, 7).index,
          const Coordinate(6, 6).index,
        ],
        updatedAtIso: DateTime(2026, 11, 24).toIso8601String(),
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageRepositoryProvider.overrideWithValue(storage),
          soundServiceProvider.overrideWithValue(const SilentSoundService()),
          aiMoveSourceFactoryProvider.overrideWithValue(_syncFactory),
        ],
        child: const OmokApp(locale: Locale('ko')),
      ),
    );

    expect(find.text('진행 중인 대국'), findsOneWidget);
    expect(find.text('이어하기'), findsOneWidget);

    await tester.tap(find.text('이어하기'));
    await tester.pumpAndSettle();

    expect(find.byType(OmokBoardView), findsOneWidget);
    expect(find.text('2수'), findsOneWidget);
  });

  testWidgets('Local 2-player mode alternates Black/White turns, hides Hint, undoes 1 ply',
      (tester) async {
    final storage = InMemoryStorageRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageRepositoryProvider.overrideWithValue(storage),
          soundServiceProvider.overrideWithValue(const SilentSoundService()),
          aiMoveSourceFactoryProvider.overrideWithValue(_syncFactory),
        ],
        child: const OmokApp(locale: Locale('ko')),
      ),
    );

    // Switch to Local 2-player tab and start match.
    await tester.tap(find.text('로컬 2인'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('로컬 2인 대국 시작'));
    await tester.pumpAndSettle();

    expect(find.text('로컬 2인 대전'), findsOneWidget);
    expect(find.text('힌트'), findsNothing);
    expect(find.text('0수'), findsOneWidget);

    // Black plays H8 (center) via 2-step preview + confirm.
    final boardCenter = tester.getCenter(find.byType(OmokBoardView));
    await tester.tapAt(boardCenter);
    await tester.pumpAndSettle();
    await tester.tap(find.text('H8 착수 확정'));
    await tester.pumpAndSettle();

    // Only 1 stone placed (no AI reply!), now White's turn.
    expect(find.text('1수'), findsOneWidget);
    expect(find.text('차례 · 금수 없음'), findsOneWidget);

    // Undo in local 2-player reverts exactly 1 move back to 0수.
    await tester.tap(find.text('무르기'));
    await tester.pumpAndSettle();
    expect(find.text('0수'), findsOneWidget);
  });

  testWidgets('Tablet landscape uses side-by-side layout and caps board size',
      (tester) async {
    // iPad Air landscape logical size: 1180 x 820
    tester.view.physicalSize = const Size(1180, 820);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final storage = InMemoryStorageRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageRepositoryProvider.overrideWithValue(storage),
          soundServiceProvider.overrideWithValue(const SilentSoundService()),
          aiMoveSourceFactoryProvider.overrideWithValue(_syncFactory),
        ],
        child: const OmokApp(locale: Locale('ko')),
      ),
    );

    // Home renders cleanly in 2-column landscape without overflow.
    expect(find.text('중급 AI와 대국 시작'), findsOneWidget);
    await tester.tap(find.text('중급 AI와 대국 시작'));
    await tester.pumpAndSettle();

    // GameScreen renders side-by-side: board on left, action bar on right.
    final boardRect = tester.getRect(find.byType(OmokBoardView));
    final undoRect = tester.getRect(find.text('무르기'));

    expect(boardRect.width, closeTo(boardRect.height, 1.0));
    expect(boardRect.width, lessThanOrEqualTo(600.0));
    expect(boardRect.right, lessThan(undoRect.left));
  });

  testWidgets('Tablet portrait caps board size cleanly without stretching',
      (tester) async {
    // iPad Air portrait logical size: 820 x 1180
    tester.view.physicalSize = const Size(820, 1180);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final storage = InMemoryStorageRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageRepositoryProvider.overrideWithValue(storage),
          soundServiceProvider.overrideWithValue(const SilentSoundService()),
          aiMoveSourceFactoryProvider.overrideWithValue(_syncFactory),
        ],
        child: const OmokApp(locale: Locale('ko')),
      ),
    );

    await tester.tap(find.text('중급 AI와 대국 시작'));
    await tester.pumpAndSettle();

    final boardRect = tester.getRect(find.byType(OmokBoardView));
    expect(boardRect.width, closeTo(boardRect.height, 1.0));
    expect(boardRect.width, lessThanOrEqualTo(560.0));
  });

  testWidgets('English locale renders full English UI and non-Korean locales fall back to English',
      (tester) async {
    final storage = InMemoryStorageRepository();

    // Default test locale is en_US (auto-detected without override).
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageRepositoryProvider.overrideWithValue(storage),
          soundServiceProvider.overrideWithValue(const SilentSoundService()),
          aiMoveSourceFactoryProvider.overrideWithValue(_syncFactory),
        ],
        child: const OmokApp(),
      ),
    );

    expect(find.text('Omok'), findsOneWidget);
    expect(find.text('Renju Omok'), findsOneWidget);
    expect(find.text('vs AI'), findsOneWidget);
    expect(find.text('Local 2P'), findsOneWidget);
    expect(find.text('Nearby 2P'), findsOneWidget);
    expect(find.text('Beginner'), findsOneWidget);
    expect(find.text('Intermediate'), findsOneWidget);
    expect(find.text('Advanced'), findsOneWidget);
    expect(find.text('Expert'), findsOneWidget);
    expect(find.text('Match Rules'), findsOneWidget);

    await tester.tap(find.text('Beginner'));
    await tester.pumpAndSettle();

    final startButton = find.text('Play vs Beginner AI');
    await tester.ensureVisible(startButton);
    await tester.tap(startButton);
    await tester.pumpAndSettle();

    expect(find.text('vs AI · Beginner'), findsOneWidget);
    expect(find.text('Move 0'), findsOneWidget);
    expect(find.text('Hint'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);

    await tester.tap(find.text('Hint'));
    await tester.pumpAndSettle();
    expect(find.text('Confirm H8'), findsOneWidget);

    await tester.tap(find.text('Confirm H8'));
    await tester.pumpAndSettle();
    expect(find.text('Move 2'), findsOneWidget);
  });

  testWidgets('Non-Korean system locales fall back cleanly to English',
      (tester) async {
    final storage = InMemoryStorageRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageRepositoryProvider.overrideWithValue(storage),
          soundServiceProvider.overrideWithValue(const SilentSoundService()),
          aiMoveSourceFactoryProvider.overrideWithValue(_syncFactory),
        ],
        child: const OmokApp(locale: Locale('ja')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Omok'), findsOneWidget);
    expect(find.text('Match Rules'), findsOneWidget);
  });
}
