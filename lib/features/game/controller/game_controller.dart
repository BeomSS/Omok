import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/match_rules.dart';
import '../../../data/models/saved_match.dart';
import '../../../engine/engine.dart';
import '../../../multiplayer/multiplayer.dart';
import '../../../shared/providers/app_providers.dart';
import '../../../shared/services/sound_service.dart';
import 'game_state.dart';

final gameControllerProvider =
    NotifierProvider<GameController, GameState>(GameController.new);

class GameController extends Notifier<GameState> {
  MoveSource? _activeAiSource;
  MoveSource? _activeHintSource;
  Timer? _turnTimer;
  int _sessionGeneration = 0;

  // Nearby P2P active transport & subscriptions
  MatchTransport? _p2pTransport;
  StreamSubscription<MatchPacket>? _p2pPacketSub;
  StreamSubscription<TransportConnectionState>? _p2pStateSub;

  @override
  GameState build() {
    ref.onDispose(() {
      _stopTurnTimer();
      _cancelAllWorkers();
      _detachP2pTransport(closeTransport: true);
    });
    return GameState.initial();
  }

  /// Starts a fresh AI match with [difficulty], [stonePreference], and [rules].
  void startNewGame({
    required AiDifficulty difficulty,
    required StonePreference stonePreference,
    required MatchRules rules,
  }) {
    _stopTurnTimer();
    _cancelAllWorkers();
    _detachP2pTransport(closeTransport: true);
    _sessionGeneration++;

    final Stone resolvedStone;
    GameNotice? notice;
    if (stonePreference == StonePreference.random) {
      final pickBlack = ref.read(randomProvider).nextBool();
      resolvedStone = pickBlack ? Stone.black : Stone.white;
      notice = RandomStoneAssignedNotice(isBlack: pickBlack);
    } else {
      resolvedStone = stonePreference == StonePreference.white
          ? Stone.white
          : Stone.black;
    }

    state = GameState(
      board: BoardState.empty(),
      mode: GameMode.vsAi,
      difficulty: difficulty,
      humanStone: resolvedStone,
      stonePreference: stonePreference,
      rules: rules,
      undosUsed: 0,
      remainingTurnSeconds:
          rules.useTimeLimit ? rules.turnTimeLimitSeconds : null,
      result: GameResult.ongoing,
      isAiThinking: false,
      isHintLoading: false,
      forbiddenMoves: const {},
      notice: notice,
      noticeToken: notice != null ? state.noticeToken + 1 : state.noticeToken,
    );

    ref.read(savedMatchProvider.notifier).clear();
    _startTurnTimer();

    if (resolvedStone == Stone.white) {
      _triggerAiTurn();
    }
  }

  /// Starts a local pass-and-play 2-player match on one device.
  void startLocalTwoPlayerGame({required MatchRules rules}) {
    _stopTurnTimer();
    _cancelAllWorkers();
    _detachP2pTransport(closeTransport: true);
    _sessionGeneration++;

    state = GameState(
      board: BoardState.empty(),
      mode: GameMode.localTwoPlayer,
      difficulty: state.difficulty,
      humanStone: Stone.black,
      stonePreference: StonePreference.black,
      rules: rules,
      undosUsed: 0,
      remainingTurnSeconds:
          rules.useTimeLimit ? rules.turnTimeLimitSeconds : null,
      result: GameResult.ongoing,
      isAiThinking: false,
      isHintLoading: false,
      forbiddenMoves: const {},
    );

    _startTurnTimer();
  }

  /// Starts a serverless nearby Wi-Fi / Hotspot P2P match over [transport].
  void startNearbyP2pGame({
    required MatchTransport transport,
    required bool isHost,
    required Stone localStone,
    required StonePreference hostStonePreference,
    required MatchRules rules,
    required String localName,
    required String opponentName,
  }) {
    _stopTurnTimer();
    _cancelAllWorkers();
    _detachP2pTransport(closeTransport: false);
    _sessionGeneration++;

    _p2pTransport = transport;
    _p2pPacketSub = transport.incomingPackets.listen(_handlePeerPacket);
    _p2pStateSub = transport.connectionState.listen(_handleTransportState);

    final colorNotice = P2pConnectedNotice(isBlack: localStone == Stone.black);

    state = GameState(
      board: BoardState.empty(),
      mode: GameMode.nearbyP2p,
      difficulty: state.difficulty,
      humanStone: localStone,
      stonePreference: hostStonePreference,
      rules: rules,
      undosUsed: 0,
      remainingTurnSeconds:
          rules.useTimeLimit ? rules.turnTimeLimitSeconds : null,
      result: GameResult.ongoing,
      isAiThinking: false,
      isHintLoading: false,
      forbiddenMoves: const {},
      isHost: isHost,
      localPlayerName: localName,
      opponentName: opponentName,
      isOpponentDisconnected: false,
      notice: colorNotice,
      noticeToken: state.noticeToken + 1,
    );

    _startTurnTimer();
  }

  /// Restores an auto-saved offline AI match from [SavedMatch].
  void resumeMatch(SavedMatch saved) {
    _stopTurnTimer();
    _cancelAllWorkers();
    _detachP2pTransport(closeTransport: true);
    _sessionGeneration++;

    final ruleEngine = saved.rules.createRuleEngine();
    final board = saved.toBoardState();
    final last = board.lastMove;
    final result = last == null
        ? GameResult.ongoing
        : ruleEngine.checkResult(board, last);
    final forbidden = !result.status.isFinished && board.nextTurn == Stone.black
        ? ruleEngine.getForbiddenMoves(board, Stone.black)
        : const <Coordinate, ForbiddenReason>{};

    state = GameState(
      board: board,
      mode: GameMode.vsAi,
      difficulty: saved.difficulty,
      humanStone: saved.humanStone,
      stonePreference: saved.stonePreference,
      rules: saved.rules,
      undosUsed: saved.undosUsed,
      remainingTurnSeconds: !result.status.isFinished && saved.rules.useTimeLimit
          ? saved.rules.turnTimeLimitSeconds
          : null,
      result: result,
      isAiThinking: false,
      isHintLoading: false,
      forbiddenMoves: forbidden,
    );

    if (!result.status.isFinished) {
      _startTurnTimer();
      if (board.nextTurn == state.aiStone) {
        _triggerAiTurn();
      }
    }
  }

  /// Restarts the current match (or requests rematch in P2P mode).
  void restart() {
    if (state.isNearbyP2p) {
      requestP2pRematch();
    } else if (state.isLocalTwoPlayer) {
      startLocalTwoPlayerGame(rules: state.rules);
    } else {
      startNewGame(
        difficulty: state.difficulty,
        stonePreference: state.stonePreference,
        rules: state.rules,
      );
    }
  }

  /// Stops timers, cancels AI workers, and notifies peer when leaving screen.
  void pauseAndLeave() {
    _stopTurnTimer();
    _cancelAllWorkers();
    if (state.isNearbyP2p) {
      _sendPacketBestEffort(const LeavePacket());
      _detachP2pTransport(closeTransport: true);
      return;
    }
    if (!state.isLocalTwoPlayer && !state.isGameOver && state.board.isNotEmpty) {
      _persistProgress(state.board, undosUsed: state.undosUsed);
    }
  }

  /// Handles a tap on board intersection [coord].
  void onIntersectionTapped(Coordinate coord) {
    if (!state.isHumanTurn || !coord.isValid || state.board.isOccupied(coord)) {
      return;
    }

    final activeStone = state.activeControlStone;
    final ruleEngine = state.rules.createRuleEngine();
    final forbiddenReason =
        ruleEngine.getForbiddenReason(state.board, coord, activeStone);
    if (forbiddenReason.isForbidden) {
      _triggerHaptic(heavy: true);
      _playSound((s) => s.playForbidden());
      state = state.copyWith(
        clearPendingMove: true,
        notice: ForbiddenMoveNotice(forbiddenReason),
        noticeToken: state.noticeToken + 1,
      );
      return;
    }

    final settings = ref.read(settingsProvider);
    if (settings.confirmBeforePlace) {
      if (state.pendingMove == coord) {
        _commitHumanMove(coord, activeStone);
      } else {
        _triggerHaptic(selection: true);
        state = state.copyWith(pendingMove: coord);
      }
    } else {
      _commitHumanMove(coord, activeStone);
    }
  }

  void confirmPendingMove() {
    final pending = state.pendingMove;
    if (pending == null || !state.isHumanTurn) return;
    _commitHumanMove(pending, state.activeControlStone);
  }

  void clearPendingMove() {
    if (state.pendingMove != null) {
      state = state.copyWith(clearPendingMove: true);
    }
  }

  /// Computes a recommended move for the human player in AI mode.
  Future<void> requestHint() async {
    if (state.isLocalTwoPlayer ||
        state.isNearbyP2p ||
        !state.isHumanTurn ||
        state.isHintLoading) {
      return;
    }

    _cancelHint();
    final generation = _sessionGeneration;
    final boardSnapshot = state.board;
    final humanStone = state.humanStone;

    final factory = ref.read(aiMoveSourceFactoryProvider);
    final source = factory(
      aiStone: humanStone,
      difficulty: AiDifficulty.advanced,
      ruleType: state.rules.ruleType,
      turnTimeLimitSeconds:
          state.rules.useTimeLimit ? state.remainingTurnSeconds : null,
    );
    _activeHintSource = source;

    state = state.copyWith(isHintLoading: true, clearHintMove: true);

    final suggested = await source.nextMove(boardSnapshot);
    if (generation != _sessionGeneration || !state.isHumanTurn) {
      return;
    }
    _activeHintSource = null;

    if (suggested == null || state.board.isOccupied(suggested)) {
      state = state.copyWith(isHintLoading: false);
      return;
    }

    _triggerHaptic(selection: true);
    final confirmMode = ref.read(settingsProvider).confirmBeforePlace;
    state = state.copyWith(
      isHintLoading: false,
      hintMove: suggested,
      pendingMove: confirmMode ? suggested : state.pendingMove,
      notice: HintSuggestedNotice(suggested.notation),
      noticeToken: state.noticeToken + 1,
    );
  }

  /// Enters post-game move-by-move replay starting from move 1.
  void enterReplay() {
    if (!state.isGameOver || state.board.isEmpty) return;
    state = state.copyWith(
      replayMoveCount: 1,
      clearPendingMove: true,
      clearHintMove: true,
    );
  }

  void exitReplay() {
    if (!state.isReplaying) return;
    state = state.copyWith(clearReplay: true);
  }

  void setReplayStep(int moveCount) {
    if (!state.isReplaying) return;
    final clamped = moveCount.clamp(0, state.board.moveCount);
    if (clamped != state.replayMoveCount) {
      _triggerHaptic(selection: true);
      state = state.copyWith(replayMoveCount: clamped);
    }
  }

  void stepReplay(int delta) {
    final current = state.replayMoveCount;
    if (current == null) return;
    setReplayStep(current + delta);
  }

  /// Undoes locally, or sends an Undo consent request in Nearby P2P mode.
  void undo() {
    if (!state.canUndo) return;

    if (state.isNearbyP2p) {
      _sendPacketBestEffort(
        UndoRequestPacket(
          requesterStone: state.humanStone,
          currentMoveCount: state.board.moveCount,
        ),
      );
      state = state.copyWith(
        isWaitingUndoResponse: true,
        notice: const SimpleGameNotice(SimpleNoticeType.undoRequested),
        noticeToken: state.noticeToken + 1,
      );
      return;
    }

    final wasAiThinking = state.isAiThinking;
    _stopTurnTimer();
    _cancelAllWorkers();
    _sessionGeneration++;

    final board = state.board;
    final int stepsToUndo;
    if (state.isLocalTwoPlayer) {
      stepsToUndo = 1;
    } else if (wasAiThinking || board.nextTurn == state.aiStone) {
      stepsToUndo = 1;
    } else {
      final maxSteps =
          state.humanStone == Stone.white ? board.moveCount - 1 : board.moveCount;
      stepsToUndo = maxSteps >= 2 ? 2 : maxSteps;
    }

    if (stepsToUndo <= 0) return;

    final prevBoard = board.undo(steps: stepsToUndo);
    final nextUndosUsed = state.undosUsed + 1;
    final ruleEngine = state.rules.createRuleEngine();
    final forbidden = prevBoard.nextTurn == Stone.black
        ? ruleEngine.getForbiddenMoves(prevBoard, Stone.black)
        : const <Coordinate, ForbiddenReason>{};

    _triggerHaptic(selection: true);
    state = state.copyWith(
      board: prevBoard,
      undosUsed: nextUndosUsed,
      remainingTurnSeconds:
          state.rules.useTimeLimit ? state.rules.turnTimeLimitSeconds : null,
      result: GameResult.ongoing,
      isAiThinking: false,
      isHintLoading: false,
      clearPendingMove: true,
      clearHintMove: true,
      clearReplay: true,
      forbiddenMoves: forbidden,
    );

    _startTurnTimer();

    if (!state.isLocalTwoPlayer) {
      if (prevBoard.isEmpty) {
        ref.read(savedMatchProvider.notifier).clear();
      } else {
        _persistProgress(prevBoard, undosUsed: nextUndosUsed);
      }
    }
  }

  /// Accepts or declines an opponent's P2P undo request.
  void respondToUndoRequest(bool accepted) {
    if (!state.isNearbyP2p || !state.hasIncomingUndoRequest) return;
    _sendPacketBestEffort(UndoResponsePacket(accepted: accepted));

    if (accepted) {
      _applyAgreedP2pUndo();
    } else {
      state = state.copyWith(
        hasIncomingUndoRequest: false,
        notice: const SimpleGameNotice(SimpleNoticeType.undoDeclinedBySelf),
        noticeToken: state.noticeToken + 1,
      );
    }
  }

  /// Sends a rematch request in P2P mode.
  void requestP2pRematch() {
    if (!state.isNearbyP2p ||
        state.isOpponentDisconnected ||
        state.isWaitingRematchResponse) {
      return;
    }
    _sendPacketBestEffort(const RematchRequestPacket());
    state = state.copyWith(
      isWaitingRematchResponse: true,
      notice: const SimpleGameNotice(SimpleNoticeType.rematchRequested),
      noticeToken: state.noticeToken + 1,
    );
  }

  /// Accepts or declines an opponent's P2P rematch request.
  void respondToRematchRequest(bool accepted) {
    if (!state.isNearbyP2p || !state.hasIncomingRematchRequest) return;
    _sendPacketBestEffort(RematchResponsePacket(accepted: accepted));

    if (!accepted) {
      state = state.copyWith(
        hasIncomingRematchRequest: false,
        notice: const SimpleGameNotice(SimpleNoticeType.rematchDeclinedBySelf),
        noticeToken: state.noticeToken + 1,
      );
      return;
    }

    state = state.copyWith(hasIncomingRematchRequest: false);
    if (state.isHost) {
      _hostStartP2pRematch();
    }
  }

  void _hostStartP2pRematch() {
    final Stone nextHostStone;
    if (state.stonePreference == StonePreference.random) {
      nextHostStone =
          ref.read(randomProvider).nextBool() ? Stone.black : Stone.white;
    } else {
      // Alternate colors or respect host preference: swap colors on rematch
      // when fixed preference isn't random? Keep preference predictable:
      nextHostStone = state.stonePreference == StonePreference.white
          ? Stone.white
          : Stone.black;
    }

    final startPacket = MatchStartPacket(
      matchId: DateTime.now().millisecondsSinceEpoch.toString(),
      rules: state.rules,
      hostStone: nextHostStone,
      hostName: state.localPlayerName,
      guestName: state.opponentName,
    );
    _sendPacketBestEffort(startPacket);
    _resetP2pBoardForRematch(
      localStone: nextHostStone,
      rules: state.rules,
    );
  }

  void _resetP2pBoardForRematch({
    required Stone localStone,
    required MatchRules rules,
  }) {
    _stopTurnTimer();
    final notice = P2pRematchStartedNotice(isBlack: localStone == Stone.black);

    state = state.copyWith(
      board: BoardState.empty(),
      humanStone: localStone,
      rules: rules,
      undosUsed: 0,
      remainingTurnSeconds:
          rules.useTimeLimit ? rules.turnTimeLimitSeconds : null,
      result: GameResult.ongoing,
      clearPendingMove: true,
      clearHintMove: true,
      clearReplay: true,
      forbiddenMoves: const {},
      hasIncomingUndoRequest: false,
      isWaitingUndoResponse: false,
      hasIncomingRematchRequest: false,
      isWaitingRematchResponse: false,
      notice: notice,
      noticeToken: state.noticeToken + 1,
    );

    _startTurnTimer();
  }

  void _applyAgreedP2pUndo() {
    if (state.board.isEmpty) {
      state = state.copyWith(
        hasIncomingUndoRequest: false,
        isWaitingUndoResponse: false,
      );
      return;
    }
    _stopTurnTimer();
    final prevBoard = state.board.undo(steps: 1);
    final ruleEngine = state.rules.createRuleEngine();
    final forbidden = prevBoard.nextTurn == Stone.black
        ? ruleEngine.getForbiddenMoves(prevBoard, Stone.black)
        : const <Coordinate, ForbiddenReason>{};

    _triggerHaptic(selection: true);
    state = state.copyWith(
      board: prevBoard,
      undosUsed: state.undosUsed + 1,
      remainingTurnSeconds:
          state.rules.useTimeLimit ? state.rules.turnTimeLimitSeconds : null,
      result: GameResult.ongoing,
      clearPendingMove: true,
      clearHintMove: true,
      forbiddenMoves: forbidden,
      hasIncomingUndoRequest: false,
      isWaitingUndoResponse: false,
      notice: const SimpleGameNotice(SimpleNoticeType.undoApplied),
      noticeToken: state.noticeToken + 1,
    );
    _startTurnTimer();
  }

  void _handlePeerPacket(MatchPacket packet) {
    if (!state.isNearbyP2p) return;

    switch (packet) {
      case MovePacket():
        _handleRemoteMove(packet);
      case UndoRequestPacket():
        if (!state.isGameOver && state.board.isNotEmpty) {
          _triggerHaptic(selection: true);
          state = state.copyWith(hasIncomingUndoRequest: true);
        }
      case UndoResponsePacket():
        if (packet.accepted) {
          _applyAgreedP2pUndo();
        } else {
          state = state.copyWith(
            isWaitingUndoResponse: false,
            notice: const SimpleGameNotice(SimpleNoticeType.undoDeclinedByPeer),
            noticeToken: state.noticeToken + 1,
          );
        }
      case TimeoutPacket():
        if (!state.isGameOver) {
          _applyTimeout(packet.winner);
        }
      case RematchRequestPacket():
        if (state.isGameOver) {
          _triggerHaptic(selection: true);
          state = state.copyWith(hasIncomingRematchRequest: true);
        }
      case RematchResponsePacket():
        if (packet.accepted) {
          state = state.copyWith(isWaitingRematchResponse: false);
          if (state.isHost) {
            _hostStartP2pRematch();
          }
        } else {
          state = state.copyWith(
            isWaitingRematchResponse: false,
            notice:
                const SimpleGameNotice(SimpleNoticeType.rematchDeclinedByPeer),
            noticeToken: state.noticeToken + 1,
          );
        }
      case MatchStartPacket():
        // Guest receives Host's rematch start packet.
        if (!state.isHost) {
          _resetP2pBoardForRematch(
            localStone: packet.guestStone,
            rules: packet.rules,
          );
        }
      case LeavePacket():
        _onPeerDisconnected(const SimpleGameNotice(SimpleNoticeType.peerLeft));
      case HelloPacket():
      case MoveAckPacket():
      case PingPacket():
      case PongPacket():
        break;
    }
  }

  void _handleTransportState(TransportConnectionState next) {
    if (!state.isNearbyP2p) return;
    if (next == TransportConnectionState.disconnected ||
        next == TransportConnectionState.error) {
      if (!state.isOpponentDisconnected) {
        _onPeerDisconnected(
          const SimpleGameNotice(SimpleNoticeType.peerDisconnected),
        );
      }
    }
  }

  void _onPeerDisconnected(GameNotice notice) {
    _stopTurnTimer();
    state = state.copyWith(
      isOpponentDisconnected: true,
      hasIncomingUndoRequest: false,
      isWaitingUndoResponse: false,
      hasIncomingRematchRequest: false,
      isWaitingRematchResponse: false,
      clearPendingMove: true,
      notice: notice,
      noticeToken: state.noticeToken + 1,
    );
  }

  void _handleRemoteMove(MovePacket packet) {
    if (state.isGameOver) return;
    if (packet.seq != state.board.moveCount + 1) return;
    if (packet.stone != state.currentTurn) return;
    if (!packet.coordinate.isValid || state.board.isOccupied(packet.coordinate)) {
      return;
    }

    final ruleEngine = state.rules.createRuleEngine();
    if (ruleEngine.isForbiddenMove(
      state.board,
      packet.coordinate,
      packet.stone,
    )) {
      return;
    }

    final nextBoard =
        state.board.placeStone(packet.coordinate, stone: packet.stone);
    final result = ruleEngine.checkResult(nextBoard, nextBoard.lastMove!);

    _triggerHaptic();
    _playSound((s) => s.playStonePlace());

    if (result.status.isFinished) {
      _stopTurnTimer();
      state = state.copyWith(
        board: nextBoard,
        result: result,
        clearPendingMove: true,
        forbiddenMoves: const {},
      );
      _onMatchFinished(result.status);
      return;
    }

    final forbidden = nextBoard.nextTurn == Stone.black
        ? ruleEngine.getForbiddenMoves(nextBoard, Stone.black)
        : const <Coordinate, ForbiddenReason>{};

    state = state.copyWith(
      board: nextBoard,
      result: result,
      remainingTurnSeconds:
          state.rules.useTimeLimit ? state.rules.turnTimeLimitSeconds : null,
      clearPendingMove: true,
      forbiddenMoves: forbidden,
    );

    _startTurnTimer();
  }

  void _commitHumanMove(Coordinate coord, Stone stone) {
    _cancelHint();
    final ruleEngine = state.rules.createRuleEngine();
    final nextBoard = state.board.placeStone(coord, stone: stone);
    final result = ruleEngine.checkResult(nextBoard, nextBoard.lastMove!);

    if (state.isNearbyP2p) {
      _sendPacketBestEffort(
        MovePacket(
          seq: nextBoard.moveCount,
          coordinate: coord,
          stone: stone,
        ),
      );
    }

    _triggerHaptic();
    _playSound((s) => s.playStonePlace());

    if (result.status.isFinished) {
      _stopTurnTimer();
      state = state.copyWith(
        board: nextBoard,
        result: result,
        isAiThinking: false,
        isHintLoading: false,
        clearPendingMove: true,
        clearHintMove: true,
        forbiddenMoves: const {},
      );
      _onMatchFinished(result.status);
      return;
    }

    final forbidden = nextBoard.nextTurn == Stone.black
        ? ruleEngine.getForbiddenMoves(nextBoard, Stone.black)
        : const <Coordinate, ForbiddenReason>{};

    state = state.copyWith(
      board: nextBoard,
      result: result,
      remainingTurnSeconds:
          state.rules.useTimeLimit ? state.rules.turnTimeLimitSeconds : null,
      isHintLoading: false,
      clearPendingMove: true,
      clearHintMove: true,
      forbiddenMoves: forbidden,
    );

    _startTurnTimer();

    if (state.mode == GameMode.vsAi) {
      _persistProgress(nextBoard, undosUsed: state.undosUsed);
      _triggerAiTurn();
    }
  }

  Future<void> _triggerAiTurn() async {
    if (state.mode != GameMode.vsAi ||
        state.isGameOver ||
        state.board.nextTurn != state.aiStone) {
      return;
    }

    final generation = _sessionGeneration;
    final boardSnapshot = state.board;
    final aiStone = state.aiStone;
    final difficulty = state.difficulty;
    final rules = state.rules;

    final factory = ref.read(aiMoveSourceFactoryProvider);
    final source = factory(
      aiStone: aiStone,
      difficulty: difficulty,
      ruleType: rules.ruleType,
      turnTimeLimitSeconds:
          rules.useTimeLimit ? rules.turnTimeLimitSeconds : null,
    );
    _activeAiSource = source;

    state = state.copyWith(
      isAiThinking: true,
      isHintLoading: false,
      clearPendingMove: true,
      clearHintMove: true,
    );

    final move = await source.nextMove(boardSnapshot);

    if (generation != _sessionGeneration || move == null) {
      return;
    }
    _activeAiSource = null;

    if (state.isGameOver || state.board.isOccupied(move)) {
      state = state.copyWith(isAiThinking: false);
      return;
    }

    final ruleEngine = rules.createRuleEngine();
    final nextBoard = state.board.placeStone(move, stone: aiStone);
    final result = ruleEngine.checkResult(nextBoard, nextBoard.lastMove!);

    _triggerHaptic();
    _playSound((s) => s.playStonePlace());

    if (result.status.isFinished) {
      _stopTurnTimer();
      state = state.copyWith(
        board: nextBoard,
        result: result,
        isAiThinking: false,
        forbiddenMoves: const {},
      );
      _onMatchFinished(result.status);
      return;
    }

    final forbidden = nextBoard.nextTurn == Stone.black
        ? ruleEngine.getForbiddenMoves(nextBoard, Stone.black)
        : const <Coordinate, ForbiddenReason>{};

    state = state.copyWith(
      board: nextBoard,
      result: result,
      remainingTurnSeconds:
          rules.useTimeLimit ? rules.turnTimeLimitSeconds : null,
      isAiThinking: false,
      forbiddenMoves: forbidden,
    );

    _startTurnTimer();
    _persistProgress(nextBoard, undosUsed: state.undosUsed);
  }

  void _startTurnTimer() {
    _stopTurnTimer();
    if (!state.rules.useTimeLimit || state.isGameOver || state.isReplaying) {
      return;
    }

    _turnTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (state.isGameOver ||
          state.isReplaying ||
          !state.rules.useTimeLimit ||
          state.isOpponentDisconnected) {
        _stopTurnTimer();
        return;
      }

      final current =
          state.remainingTurnSeconds ?? state.rules.turnTimeLimitSeconds;
      final next = current - 1;

      if (next <= 0) {
        // In Nearby P2P, Host is authoritative for timeouts so both devices
        // never diverge on slight clock skew.
        if (state.isNearbyP2p && !state.isHost) {
          state = state.copyWith(remainingTurnSeconds: 0);
          return;
        }
        final winner = state.currentTurn.opponent;
        if (state.isNearbyP2p && state.isHost) {
          _sendPacketBestEffort(TimeoutPacket(winner: winner));
        }
        _applyTimeout(winner);
      } else {
        if (next <= 5 &&
            (state.isLocalTwoPlayer || state.currentTurn == state.humanStone)) {
          _triggerHaptic(selection: true);
        }
        state = state.copyWith(remainingTurnSeconds: next);
      }
    });
  }

  void _applyTimeout(Stone winner) {
    _stopTurnTimer();
    _cancelAllWorkers();
    _sessionGeneration++;

    final timeoutResult = GameResult.timeout(winner: winner);

    state = state.copyWith(
      remainingTurnSeconds: 0,
      result: timeoutResult,
      isAiThinking: false,
      isHintLoading: false,
      clearPendingMove: true,
      clearHintMove: true,
      forbiddenMoves: const {},
      hasIncomingUndoRequest: false,
      isWaitingUndoResponse: false,
    );

    _onMatchFinished(timeoutResult.status);
  }

  void _stopTurnTimer() {
    _turnTimer?.cancel();
    _turnTimer = null;
  }

  void _onMatchFinished(GameStatus status) {
    _triggerHaptic(heavy: true);
    if (state.isLocalTwoPlayer) {
      if (status != GameStatus.draw) {
        _playSound((s) => s.playWin());
      }
      return;
    }

    if (status.winner == state.humanStone) {
      _playSound((s) => s.playWin());
    } else if (status != GameStatus.draw) {
      _playSound((s) => s.playLose());
    }

    if (state.mode == GameMode.vsAi) {
      ref.read(savedMatchProvider.notifier).clear();
      ref.read(statsProvider.notifier).recordResult(
            difficulty: state.difficulty,
            status: status,
            humanStone: state.humanStone,
          );
    }
  }

  void _persistProgress(BoardState board, {required int undosUsed}) {
    if (board.isEmpty) return;
    ref.read(savedMatchProvider.notifier).save(
          SavedMatch(
            difficulty: state.difficulty,
            humanStone: state.humanStone,
            stonePreference: state.stonePreference,
            rules: state.rules,
            undosUsed: undosUsed,
            moveIndices: [for (final m in board.history) m.coordinate.index],
            updatedAtIso: DateTime.now().toIso8601String(),
          ),
        );
  }

  void _sendPacketBestEffort(MatchPacket packet) {
    final transport = _p2pTransport;
    if (transport == null ||
        transport.currentState != TransportConnectionState.connected) {
      return;
    }
    unawaited(
      transport.send(packet).catchError((_) {}),
    );
  }

  void _detachP2pTransport({required bool closeTransport}) {
    _p2pPacketSub?.cancel();
    _p2pPacketSub = null;
    _p2pStateSub?.cancel();
    _p2pStateSub = null;
    final transport = _p2pTransport;
    _p2pTransport = null;
    if (closeTransport && transport != null) {
      unawaited(transport.close().catchError((_) {}));
    }
  }

  void _cancelAllWorkers() {
    _activeAiSource?.cancel();
    _activeAiSource = null;
    _cancelHint();
  }

  void _cancelHint() {
    _activeHintSource?.cancel();
    _activeHintSource = null;
  }

  void _playSound(Future<void> Function(SoundService sound) play) {
    if (!ref.read(settingsProvider).soundEnabled) return;
    play(ref.read(soundServiceProvider));
  }

  void _triggerHaptic({bool selection = false, bool heavy = false}) {
    if (!ref.read(settingsProvider).hapticEnabled) return;
    if (heavy) {
      HapticFeedback.heavyImpact();
    } else if (selection) {
      HapticFeedback.selectionClick();
    } else {
      HapticFeedback.lightImpact();
    }
  }
}
