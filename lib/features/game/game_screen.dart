import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/engine.dart';
import '../../l10n/app_strings.dart';
import '../../shared/layout/responsive_layout.dart';
import '../../shared/providers/app_providers.dart';
import '../../shared/theme/app_theme.dart';
import '../settings/settings_sheet.dart';
import 'controller/game_controller.dart';
import 'controller/game_state.dart';
import 'widgets/game_hud.dart';
import 'widgets/omok_board_view.dart';

/// Main interactive 2D Omok match screen supporting AI, Local 2P, and Nearby P2P.
class GameScreen extends ConsumerStatefulWidget {
  const GameScreen({super.key});

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen> {
  final TransformationController _transformController =
      TransformationController();
  bool _isZoomed = false;
  GameNotice? _bannerNotice;
  Timer? _noticeTimer;

  @override
  void initState() {
    super.initState();
    _transformController.addListener(_onTransformChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final initialNotice = ref.read(gameControllerProvider).notice;
      if (initialNotice != null) {
        _showNotice(initialNotice);
      }
    });
  }

  @override
  void dispose() {
    _noticeTimer?.cancel();
    _transformController.removeListener(_onTransformChanged);
    _transformController.dispose();
    super.dispose();
  }

  void _onTransformChanged() {
    final scale = _transformController.value.getMaxScaleOnAxis();
    final zoomed = scale > 1.05;
    if (zoomed != _isZoomed) {
      setState(() => _isZoomed = zoomed);
    }
  }

  void _resetZoom() {
    _transformController.value = Matrix4.identity();
  }

  void _showNotice(GameNotice notice) {
    _noticeTimer?.cancel();
    setState(() => _bannerNotice = notice);
    _noticeTimer = Timer(const Duration(milliseconds: 2200), () {
      if (mounted) {
        setState(() => _bannerNotice = null);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final state = ref.watch(gameControllerProvider);
    final settings = ref.watch(settingsProvider);
    final controller = ref.read(gameControllerProvider.notifier);

    ref.listen<int>(
      gameControllerProvider.select((st) => st.noticeToken),
      (prev, next) {
        final notice = ref.read(gameControllerProvider).notice;
        if (notice != null) {
          _showNotice(notice);
        }
      },
    );

    final showForbidden = settings.showForbiddenMarkers &&
        state.rules.ruleType == RuleType.renju &&
        !state.isReplaying;

    final noticeText =
        _bannerNotice != null ? s.formatGameNotice(_bannerNotice!) : null;

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          controller.pauseAndLeave();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            s.gameAppBarTitle(state),
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
          ),
          actions: [
            IconButton(
              tooltip: s.settingsTooltip,
              icon: const Icon(Icons.tune_rounded),
              onPressed: () => SettingsSheet.show(context),
            ),
          ],
        ),
        body: SafeArea(
          child: Builder(
            builder: (context) {
              final isTablet = ResponsiveLayout.isTablet(context);
              final isSideBySide =
                  ResponsiveLayout.useSideBySideLayout(context);

              final consentBanner = state.hasIncomingUndoRequest
                  ? _P2pConsentBanner(
                      icon: Icons.undo_rounded,
                      message: s.p2pUndoRequestBanner(state.opponentName),
                      onDecline: () => controller.respondToUndoRequest(false),
                      onAccept: () => controller.respondToUndoRequest(true),
                    )
                  : state.hasIncomingRematchRequest
                      ? _P2pConsentBanner(
                          icon: Icons.replay_rounded,
                          message:
                              s.p2pRematchRequestBanner(state.opponentName),
                          onDecline: () =>
                              controller.respondToRematchRequest(false),
                          onAccept: () =>
                              controller.respondToRematchRequest(true),
                        )
                      : null;

              final bottomControls = state.isReplaying
                  ? ReplayControlBar(
                      currentStep: state.replayMoveCount ?? 0,
                      totalMoves: state.board.moveCount,
                      onSeek: controller.setReplayStep,
                      onStepDelta: controller.stepReplay,
                      onExitReplay: controller.exitReplay,
                    )
                  : state.isGameOver
                      ? _GameResultBanner(
                          state: state,
                          onReplay: controller.enterReplay,
                          onRematch: () {
                            _resetZoom();
                            controller.restart();
                          },
                          onHome: () => Navigator.of(context).pop(),
                        )
                      : (state.isNearbyP2p && state.isOpponentDisconnected)
                          ? _DisconnectedBanner(
                              onHome: () => Navigator.of(context).pop(),
                            )
                          : GameActionBar(
                              state: state,
                              confirmBeforePlace: settings.confirmBeforePlace,
                              isZoomed: _isZoomed,
                              onConfirmMove: controller.confirmPendingMove,
                              onUndo: controller.undo,
                              onHint: controller.requestHint,
                              onResetZoom: _resetZoom,
                              onRestart: () =>
                                  _confirmRestart(context, controller),
                            );

              Widget buildBoardStage() {
                return LayoutBuilder(
                  builder: (context, constraints) {
                    final extent = ResponsiveLayout.computeBoardExtent(
                      maxWidth: constraints.maxWidth,
                      maxHeight: constraints.maxHeight,
                      isTablet: isTablet,
                      isSideBySide: isSideBySide,
                    );
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox.square(
                          dimension: extent,
                          child: OmokBoardView(
                            board: state.displayBoard,
                            humanStone: state.activeControlStone,
                            showCoordinates: settings.showCoordinates,
                            showForbiddenMarkers: showForbidden,
                            showMoveNumbers:
                                settings.showMoveNumbers || state.isReplaying,
                            forbiddenMoves: state.forbiddenMoves,
                            transformationController: _transformController,
                            pendingMove: state.pendingMove,
                            hintMove: state.hintMove,
                            winningLine: state.displayWinningLine,
                            onIntersectionTap: controller.onIntersectionTapped,
                          ),
                        ),
                        Positioned(
                          top: 8,
                          child: IgnorePointer(
                            child: AnimatedOpacity(
                              opacity:
                                  noticeText != null && noticeText.isNotEmpty
                                      ? 1.0
                                      : 0.0,
                              duration: const Duration(milliseconds: 180),
                              child: noticeText == null || noticeText.isEmpty
                                  ? const SizedBox.shrink()
                                  : Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppTheme.inkPrimary
                                            .withValues(alpha: 0.9),
                                        borderRadius: BorderRadius.circular(20),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black
                                                .withValues(alpha: 0.2),
                                            blurRadius: 8,
                                            offset: const Offset(0, 3),
                                          ),
                                        ],
                                      ),
                                      child: Text(
                                        noticeText,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                );
              }

              // Tablet landscape: 2-column side-by-side layout.
              if (isSideBySide) {
                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1100),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                      child: Row(
                        children: [
                          Expanded(child: buildBoardStage()),
                          const SizedBox(width: 24),
                          SizedBox(
                            width: 340,
                            child: LayoutBuilder(
                              builder: (context, sideConstraints) {
                                return SingleChildScrollView(
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      minHeight: sideConstraints.maxHeight,
                                    ),
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            GameStatusHeader(
                                              state: state,
                                              vertical: true,
                                            ),
                                            if (consentBanner != null) ...[
                                              const SizedBox(height: 12),
                                              consentBanner,
                                            ],
                                          ],
                                        ),
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 16),
                                          child: bottomControls,
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }

              // Phone portrait & Tablet portrait: centered vertical stack.
              return Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: isTablet ? 600 : double.infinity,
                  ),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      isTablet ? 24 : 16,
                      4,
                      isTablet ? 24 : 16,
                      isTablet ? 22 : 16,
                    ),
                    child: Column(
                      children: [
                        GameStatusHeader(state: state),
                        if (consentBanner != null) ...[
                          const SizedBox(height: 10),
                          consentBanner,
                        ],
                        const SizedBox(height: 12),
                        Expanded(child: buildBoardStage()),
                        const SizedBox(height: 14),
                        bottomControls,
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _confirmRestart(
    BuildContext context,
    GameController controller,
  ) async {
    if (ref.read(gameControllerProvider).board.isEmpty) {
      controller.restart();
      return;
    }
    final s = AppStrings.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.restartDialogTitle),
        content: Text(s.restartDialogContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.restartAction),
          ),
        ],
      ),
    );
    if (ok == true) {
      _resetZoom();
      controller.restart();
    }
  }
}

class _P2pConsentBanner extends StatelessWidget {
  const _P2pConsentBanner({
    required this.icon,
    required this.message,
    required this.onDecline,
    required this.onAccept,
  });

  final IconData icon;
  final String message;
  final VoidCallback onDecline;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.warmCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.accentWood, width: 1.5),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.accentWood, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppTheme.inkPrimary,
              ),
            ),
          ),
          TextButton(
            onPressed: onDecline,
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            child: Text(s.decline),
          ),
          const SizedBox(width: 4),
          FilledButton(
            onPressed: onAccept,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              textStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            child: Text(s.accept),
          ),
        ],
      ),
    );
  }
}

class _DisconnectedBanner extends StatelessWidget {
  const _DisconnectedBanner({required this.onHome});

  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.warmCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.forbiddenCrimson.withValues(alpha: 0.45),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.wifi_off_rounded,
            color: AppTheme.forbiddenCrimson,
            size: 24,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              s.disconnectedBannerText,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: AppTheme.inkPrimary,
              ),
            ),
          ),
          FilledButton(
            onPressed: onHome,
            child: Text(s.leave),
          ),
        ],
      ),
    );
  }
}

class _GameResultBanner extends StatelessWidget {
  const _GameResultBanner({
    required this.state,
    required this.onReplay,
    required this.onRematch,
    required this.onHome,
  });

  final GameState state;
  final VoidCallback onReplay;
  final VoidCallback onRematch;
  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final status = state.result.status;
    final isTimeout = state.result.isTimeout;
    final String headline;
    final String detail;
    final IconData icon;
    final Color accent;

    if (status == GameStatus.draw) {
      headline = s.resultDrawHeadline;
      detail = s.resultDrawDetail;
      icon = Icons.handshake_rounded;
      accent = AppTheme.accentWood;
    } else if (state.isLocalTwoPlayer) {
      final blackWon = status == GameStatus.blackWin;
      headline = s.resultLocal2pHeadline(
        blackWon: blackWon,
        isTimeout: isTimeout,
      );
      detail = s.resultLocal2pDetail(
        blackWon: blackWon,
        isTimeout: isTimeout,
        turnLimitSec: state.rules.turnTimeLimitSeconds,
        moveCount: state.board.moveCount,
      );
      icon = isTimeout ? Icons.timer_off_rounded : Icons.emoji_events_rounded;
      accent = const Color(0xFF2E7D32);
    } else if (state.isNearbyP2p) {
      final iWon = status.winner == state.humanStone;
      headline = s.resultP2pHeadline(
        iWon: iWon,
        isTimeout: isTimeout,
        opponentName: state.opponentName,
      );
      detail = s.resultP2pDetail(
        iWon: iWon,
        isTimeout: isTimeout,
        opponentName: state.opponentName,
        turnLimitSec: state.rules.turnTimeLimitSeconds,
        moveCount: state.board.moveCount,
      );
      icon = isTimeout
          ? Icons.timer_off_rounded
          : (iWon ? Icons.emoji_events_rounded : Icons.people_alt_rounded);
      accent = iWon ? const Color(0xFF2E7D32) : AppTheme.forbiddenCrimson;
    } else if (status.winner == state.humanStone) {
      headline = s.resultAiWinHeadline(isTimeout: isTimeout);
      detail = s.resultAiWinDetail(
        isTimeout: isTimeout,
        difficulty: state.difficulty,
        moveCount: state.board.moveCount,
      );
      icon = isTimeout ? Icons.timer_off_rounded : Icons.emoji_events_rounded;
      accent = const Color(0xFF2E7D32);
    } else {
      headline = s.resultAiLossHeadline(isTimeout: isTimeout);
      detail = s.resultAiLossDetail(
        isTimeout: isTimeout,
        difficulty: state.difficulty,
        turnLimitSec: state.rules.turnTimeLimitSeconds,
        moveCount: state.board.moveCount,
      );
      icon = isTimeout ? Icons.timer_off_rounded : Icons.psychology_rounded;
      accent = AppTheme.forbiddenCrimson;
    }

    final rematchDisabled = state.isNearbyP2p &&
        (state.isOpponentDisconnected || state.isWaitingRematchResponse);
    final rematchLabel = state.isNearbyP2p && state.isWaitingRematchResponse
        ? s.waitingRematchLabel
        : s.rematchButton;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.warmCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.45), width: 1.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, color: accent, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      headline,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: accent,
                      ),
                    ),
                    Text(
                      detail,
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.inkPrimary.withValues(alpha: 0.72),
                      ),
                    ),
                  ],
                ),
              ),
              if (state.board.isNotEmpty)
                TextButton.icon(
                  onPressed: onReplay,
                  icon: const Icon(Icons.history_edu_rounded, size: 18),
                  label: Text(s.replayButton),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onHome,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.inkPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(s.home),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: rematchDisabled ? null : onRematch,
                  icon: const Icon(Icons.replay_rounded, size: 18),
                  label: Text(rematchLabel),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
