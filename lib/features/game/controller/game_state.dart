import '../../../data/models/match_rules.dart';
import '../../../data/models/saved_match.dart';
import '../../../engine/engine.dart';

/// Active play mode for a match.
enum GameMode {
  vsAi(label: 'AI 대전'),
  localTwoPlayer(label: '로컬 2인'),
  nearbyP2p(label: '근거리 2인');

  const GameMode({required this.label});

  final String label;
}

/// Simple parameterless in-game toast notice categories.
enum SimpleNoticeType {
  undoRequested,
  undoDeclinedBySelf,
  undoDeclinedByPeer,
  undoApplied,
  rematchRequested,
  rematchDeclinedBySelf,
  rematchDeclinedByPeer,
  peerLeft,
  peerDisconnected,
}

/// Locale-agnostic structured notice rendered by the UI via `AppStrings`.
sealed class GameNotice {
  const GameNotice();
}

final class RandomStoneAssignedNotice extends GameNotice {
  const RandomStoneAssignedNotice({required this.isBlack});
  final bool isBlack;
}

final class P2pConnectedNotice extends GameNotice {
  const P2pConnectedNotice({required this.isBlack});
  final bool isBlack;
}

final class P2pRematchStartedNotice extends GameNotice {
  const P2pRematchStartedNotice({required this.isBlack});
  final bool isBlack;
}

final class ForbiddenMoveNotice extends GameNotice {
  const ForbiddenMoveNotice(this.reason);
  final ForbiddenReason reason;
}

final class HintSuggestedNotice extends GameNotice {
  const HintSuggestedNotice(this.notation);
  final String notation;
}

final class SimpleGameNotice extends GameNotice {
  const SimpleGameNotice(this.type);
  final SimpleNoticeType type;
}

/// Immutable UI state for an active or finished Omok match.
class GameState {
  const GameState({
    required this.board,
    required this.difficulty,
    required this.humanStone,
    this.mode = GameMode.vsAi,
    this.stonePreference = StonePreference.black,
    this.rules = const MatchRules(),
    this.undosUsed = 0,
    this.remainingTurnSeconds,
    this.result = GameResult.ongoing,
    this.isAiThinking = false,
    this.isHintLoading = false,
    this.pendingMove,
    this.hintMove,
    this.replayMoveCount,
    this.forbiddenMoves = const {},
    this.notice,
    this.noticeToken = 0,
    // Nearby P2P fields
    this.isHost = false,
    this.localPlayerName = 'Host',
    this.opponentName = 'Guest',
    this.isOpponentDisconnected = false,
    this.hasIncomingUndoRequest = false,
    this.isWaitingUndoResponse = false,
    this.hasIncomingRematchRequest = false,
    this.isWaitingRematchResponse = false,
  });

  factory GameState.initial({
    GameMode mode = GameMode.vsAi,
    AiDifficulty difficulty = AiDifficulty.intermediate,
    Stone humanStone = Stone.black,
    StonePreference stonePreference = StonePreference.black,
    MatchRules rules = const MatchRules(),
  }) =>
      GameState(
        board: BoardState.empty(),
        mode: mode,
        difficulty: difficulty,
        humanStone: humanStone,
        stonePreference: stonePreference,
        rules: rules,
        remainingTurnSeconds:
            rules.useTimeLimit ? rules.turnTimeLimitSeconds : null,
      );

  final BoardState board;
  final GameMode mode;
  final AiDifficulty difficulty;
  final Stone humanStone;
  final StonePreference stonePreference;
  final MatchRules rules;
  final int undosUsed;

  /// Remaining seconds for the active player's current turn (null if no limit).
  final int? remainingTurnSeconds;

  final GameResult result;
  final bool isAiThinking;
  final bool isHintLoading;

  /// Selected preview coordinate waiting for confirmation in 2-step mode.
  final Coordinate? pendingMove;

  /// AI-suggested hint coordinate for the human player (AI mode only).
  final Coordinate? hintMove;

  /// Non-null while scrubbing post-game replay (`0..board.moveCount`).
  final int? replayMoveCount;

  /// Currently forbidden intersections when Black is to move (Renju only).
  final Map<Coordinate, ForbiddenReason> forbiddenMoves;

  /// One-shot user feedback notice (localized in the UI layer).
  final GameNotice? notice;
  final int noticeToken;

  // Nearby P2P state
  final bool isHost;
  final String localPlayerName;
  final String opponentName;
  final bool isOpponentDisconnected;
  final bool hasIncomingUndoRequest;
  final bool isWaitingUndoResponse;
  final bool hasIncomingRematchRequest;
  final bool isWaitingRematchResponse;

  Stone get aiStone => humanStone.opponent;
  Stone get currentTurn => board.nextTurn;
  bool get isGameOver => result.status.isFinished;
  bool get isReplaying => replayMoveCount != null;
  bool get isLocalTwoPlayer => mode == GameMode.localTwoPlayer;
  bool get isNearbyP2p => mode == GameMode.nearbyP2p;

  /// Stone color currently controlled by local touch input.
  Stone get activeControlStone => isLocalTwoPlayer ? currentTurn : humanStone;

  bool get isHumanTurn {
    if (isGameOver || isReplaying) return false;
    if (isLocalTwoPlayer) return true;
    if (isNearbyP2p) {
      return !isOpponentDisconnected && currentTurn == humanStone;
    }
    return !isAiThinking && currentTurn == humanStone;
  }

  /// Remaining undos (`null` means unlimited).
  int? get remainingUndos {
    final max = rules.undoLimit.maxCount;
    if (max == null) return null;
    return (max - undosUsed).clamp(0, max);
  }

  /// Board snapshot currently displayed on screen (supports post-game replay).
  BoardState get displayBoard {
    final step = replayMoveCount;
    if (step == null || step >= board.moveCount) {
      return board;
    }
    return board.undo(steps: board.moveCount - step);
  }

  /// Winning line shown when game ends (or when replay reaches the final move).
  List<Coordinate> get displayWinningLine {
    if (!isReplaying) return result.winningLine;
    return replayMoveCount == board.moveCount ? result.winningLine : const [];
  }

  bool get canUndo {
    if (board.isEmpty || isReplaying || isGameOver) return false;
    final left = remainingUndos;
    if (left != null && left <= 0) return false;
    if (isNearbyP2p) {
      return !isOpponentDisconnected &&
          !isWaitingUndoResponse &&
          !hasIncomingUndoRequest;
    }
    if (!isLocalTwoPlayer && humanStone == Stone.white && board.moveCount <= 1) {
      return false;
    }
    return true;
  }

  GameState copyWith({
    BoardState? board,
    GameMode? mode,
    AiDifficulty? difficulty,
    Stone? humanStone,
    StonePreference? stonePreference,
    MatchRules? rules,
    int? undosUsed,
    int? remainingTurnSeconds,
    bool clearTurnSeconds = false,
    GameResult? result,
    bool? isAiThinking,
    bool? isHintLoading,
    Coordinate? pendingMove,
    bool clearPendingMove = false,
    Coordinate? hintMove,
    bool clearHintMove = false,
    int? replayMoveCount,
    bool clearReplay = false,
    Map<Coordinate, ForbiddenReason>? forbiddenMoves,
    GameNotice? notice,
    int? noticeToken,
    bool? isHost,
    String? localPlayerName,
    String? opponentName,
    bool? isOpponentDisconnected,
    bool? hasIncomingUndoRequest,
    bool? isWaitingUndoResponse,
    bool? hasIncomingRematchRequest,
    bool? isWaitingRematchResponse,
  }) =>
      GameState(
        board: board ?? this.board,
        mode: mode ?? this.mode,
        difficulty: difficulty ?? this.difficulty,
        humanStone: humanStone ?? this.humanStone,
        stonePreference: stonePreference ?? this.stonePreference,
        rules: rules ?? this.rules,
        undosUsed: undosUsed ?? this.undosUsed,
        remainingTurnSeconds: clearTurnSeconds
            ? null
            : (remainingTurnSeconds ?? this.remainingTurnSeconds),
        result: result ?? this.result,
        isAiThinking: isAiThinking ?? this.isAiThinking,
        isHintLoading: isHintLoading ?? this.isHintLoading,
        pendingMove:
            clearPendingMove ? null : (pendingMove ?? this.pendingMove),
        hintMove: clearHintMove ? null : (hintMove ?? this.hintMove),
        replayMoveCount:
            clearReplay ? null : (replayMoveCount ?? this.replayMoveCount),
        forbiddenMoves: forbiddenMoves ?? this.forbiddenMoves,
        notice: notice ?? this.notice,
        noticeToken: noticeToken ?? this.noticeToken,
        isHost: isHost ?? this.isHost,
        localPlayerName: localPlayerName ?? this.localPlayerName,
        opponentName: opponentName ?? this.opponentName,
        isOpponentDisconnected:
            isOpponentDisconnected ?? this.isOpponentDisconnected,
        hasIncomingUndoRequest:
            hasIncomingUndoRequest ?? this.hasIncomingUndoRequest,
        isWaitingUndoResponse:
            isWaitingUndoResponse ?? this.isWaitingUndoResponse,
        hasIncomingRematchRequest:
            hasIncomingRematchRequest ?? this.hasIncomingRematchRequest,
        isWaitingRematchResponse:
            isWaitingRematchResponse ?? this.isWaitingRematchResponse,
      );
}
