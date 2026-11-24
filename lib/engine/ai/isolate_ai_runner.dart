import 'dart:async';
import 'dart:isolate';

import '../model/board_state.dart';
import '../model/coordinate.dart';
import '../model/stone.dart';
import '../rules/freestyle_rule_engine.dart';
import '../rules/renju_rule_engine.dart';
import '../rules/rule_engine.dart';
import 'ai_difficulty.dart';
import 'dart_ai_engine.dart';
import 'move_source.dart';

/// Runs [DartAiEngine] in a dedicated background [Isolate] so the Flutter UI
/// thread stays at 60/120fps even during deep Expert VCF/Alpha-Beta searches.
///
/// Supports immediate cancellation via [cancel] and respects both [ruleType]
/// (Renju vs Freestyle) and optional [turnTimeLimitSeconds].
class IsolateAiRunner implements MoveSource {
  IsolateAiRunner({
    required this.aiStone,
    required this.difficulty,
    this.ruleType = RuleType.renju,
    this.turnTimeLimitSeconds,
    this.enforceMinDelay = true,
  });

  final Stone aiStone;
  final AiDifficulty difficulty;
  final RuleType ruleType;

  /// Optional per-turn time limit (in seconds). When set, AI search budget and
  /// minimum display delay adapt safely to avoid unintentional AI timeouts.
  final int? turnTimeLimitSeconds;

  /// When true, ensures moves take at least [AiDifficulty.minDisplayDelayMs]
  /// (capped if a tight turn timer is active).
  final bool enforceMinDelay;

  Isolate? _activeIsolate;
  ReceivePort? _receivePort;
  Completer<Coordinate?>? _pendingCompleter;
  bool _cancelled = false;

  @override
  Future<Coordinate?> nextMove(BoardState board) async {
    cancel();
    _cancelled = false;

    final stopwatch = Stopwatch()..start();
    final receivePort = ReceivePort();
    final completer = Completer<Coordinate?>();

    _receivePort = receivePort;
    _pendingCompleter = completer;

    final int? budgetOverrideMs = turnTimeLimitSeconds == null
        ? null
        : (turnTimeLimitSeconds! * 1000 * 0.65).round().clamp(150, 2500);

    final request = _IsolateAiRequest(
      sendPort: receivePort.sendPort,
      moveIndices: [
        for (final m in board.history) (m.coordinate.index, m.stone.code),
      ],
      aiStoneCode: aiStone.code,
      difficultyIndex: difficulty.index,
      ruleTypeIndex: ruleType.index,
      maxThinkMsOverride: budgetOverrideMs,
    );

    receivePort.listen((message) {
      if (!completer.isCompleted) {
        if (message is int && message >= 0) {
          completer.complete(Coordinate.fromIndex(message));
        } else {
          completer.complete(null);
        }
      }
      _cleanupWorker();
    });

    try {
      final isolate = await Isolate.spawn(_aiWorkerEntryPoint, request);
      if (_cancelled) {
        isolate.kill(priority: Isolate.immediate);
        _cleanupWorker();
        return null;
      }
      _activeIsolate = isolate;
    } catch (_) {
      _cleanupWorker();
      if (!completer.isCompleted) {
        completer.complete(null);
      }
      rethrow;
    }

    final result = await completer.future;
    if (_cancelled || result == null) {
      return null;
    }

    if (enforceMinDelay) {
      final targetDelayMs = turnTimeLimitSeconds == null
          ? difficulty.minDisplayDelayMs
          : difficulty.minDisplayDelayMs
              .clamp(0, turnTimeLimitSeconds! * 250);
      final elapsed = stopwatch.elapsedMilliseconds;
      final remaining = targetDelayMs - elapsed;
      if (remaining > 0) {
        await Future<void>.delayed(Duration(milliseconds: remaining));
        if (_cancelled) {
          return null;
        }
      }
    }

    return result;
  }

  @override
  void cancel() {
    _cancelled = true;
    _cleanupWorker();
    final pending = _pendingCompleter;
    _pendingCompleter = null;
    if (pending != null && !pending.isCompleted) {
      pending.complete(null);
    }
  }

  void _cleanupWorker() {
    _activeIsolate?.kill(priority: Isolate.immediate);
    _activeIsolate = null;
    _receivePort?.close();
    _receivePort = null;
  }
}

class _IsolateAiRequest {
  const _IsolateAiRequest({
    required this.sendPort,
    required this.moveIndices,
    required this.aiStoneCode,
    required this.difficultyIndex,
    required this.ruleTypeIndex,
    this.maxThinkMsOverride,
  });

  final SendPort sendPort;
  final List<(int, int)> moveIndices;
  final int aiStoneCode;
  final int difficultyIndex;
  final int ruleTypeIndex;
  final int? maxThinkMsOverride;
}

void _aiWorkerEntryPoint(_IsolateAiRequest req) {
  var board = BoardState.empty();
  for (final (idx, stoneCode) in req.moveIndices) {
    board = board.placeStone(
      Coordinate.fromIndex(idx),
      stone: Stone.fromCode(stoneCode),
    );
  }

  final ruleType = RuleType.values[req.ruleTypeIndex];
  final RuleEngine ruleEngine = ruleType == RuleType.freestyle
      ? const FreestyleRuleEngine()
      : const RenjuRuleEngine();

  final engine = DartAiEngine();
  final best = engine.findBestMoveSync(
    board: board,
    aiStone: Stone.fromCode(req.aiStoneCode),
    difficulty: AiDifficulty.values[req.difficultyIndex],
    ruleEngine: ruleEngine,
    maxThinkMsOverride: req.maxThinkMsOverride,
  );

  req.sendPort.send(best.index);
}
