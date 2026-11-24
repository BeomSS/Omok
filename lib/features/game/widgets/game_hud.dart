import 'package:material_ui/material_ui.dart';

import '../../../engine/engine.dart';
import '../../../l10n/app_strings.dart';
import '../../../shared/theme/app_theme.dart';
import '../controller/game_state.dart';

/// Top or side player status panel showing Black/White roles, active turn,
/// AI thinking indicator, applied rule type, live turn countdown, and move counter.
class GameStatusHeader extends StatelessWidget {
  const GameStatusHeader({
    super.key,
    required this.state,
    this.vertical = false,
  });

  final GameState state;

  /// Stacked sidebar mode used in tablet landscape layout.
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isLocal2P = state.isLocalTwoPlayer;
    final isP2p = state.isNearbyP2p;
    final blackIsHuman = isLocal2P || state.humanStone == Stone.black;
    final shownBoard = state.displayBoard;
    final isRenju = state.rules.ruleType == RuleType.renju;
    final blackActive =
        !state.isGameOver && !state.isReplaying && state.currentTurn == Stone.black;
    final whiteActive =
        !state.isGameOver && !state.isReplaying && state.currentTurn == Stone.white;

    final showTimer = state.rules.useTimeLimit && !state.isReplaying;
    final blackSeconds = showTimer && blackActive
        ? state.remainingTurnSeconds
        : (showTimer && state.isGameOver && state.currentTurn == Stone.black
            ? state.remainingTurnSeconds
            : null);
    final whiteSeconds = showTimer && whiteActive
        ? state.remainingTurnSeconds
        : (showTimer && state.isGameOver && state.currentTurn == Stone.white
            ? state.remainingTurnSeconds
            : null);

    final blackTitle = s.playerBlackTitle(state, blackIsHuman: blackIsHuman);
    final blackSubtitle = s.playerBlackSubtitle(
      state,
      blackIsHuman: blackIsHuman,
      blackActive: blackActive,
      isRenju: isRenju,
    );

    final whiteTitle = s.playerWhiteTitle(state, blackIsHuman: blackIsHuman);
    final whiteSubtitle = s.playerWhiteSubtitle(
      state,
      blackIsHuman: blackIsHuman,
      whiteActive: whiteActive,
    );

    final blackCard = _PlayerCard(
      stone: Stone.black,
      title: blackTitle,
      subtitle: blackSubtitle,
      isActive: blackActive,
      isThinking: !isLocal2P &&
          !blackIsHuman &&
          (state.isAiThinking ||
              (isP2p && blackActive && !state.isOpponentDisconnected)),
      remainingSeconds: blackSeconds,
    );

    final whiteCard = _PlayerCard(
      stone: Stone.white,
      title: whiteTitle,
      subtitle: whiteSubtitle,
      isActive: whiteActive,
      isThinking: !isLocal2P &&
          blackIsHuman &&
          (state.isAiThinking ||
              (isP2p && whiteActive && !state.isOpponentDisconnected)),
      remainingSeconds: whiteSeconds,
    );

    final centerTop = state.isReplaying
        ? '${shownBoard.moveCount}/${state.board.moveCount}'
        : s.moveCountLabel(shownBoard.moveCount);
    final centerBottom = state.isReplaying
        ? s.replayLabel
        : s.ruleTypeLabel(state.rules.ruleType);

    if (vertical) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.warmCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppTheme.accentWood.withValues(alpha: 0.16),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  centerBottom,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.accentWood.withValues(alpha: 0.92),
                  ),
                ),
                Text(
                  centerTop,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14.5,
                    color: AppTheme.inkPrimary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          blackCard,
          const SizedBox(height: 8),
          whiteCard,
        ],
      );
    }

    return Row(
      children: [
        Expanded(child: blackCard),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                centerTop,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14.5,
                  color: AppTheme.inkPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                centerBottom,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.accentWood.withValues(alpha: 0.9),
                ),
              ),
            ],
          ),
        ),
        Expanded(child: whiteCard),
      ],
    );
  }
}

class _PlayerCard extends StatelessWidget {
  const _PlayerCard({
    required this.stone,
    required this.title,
    required this.subtitle,
    required this.isActive,
    required this.isThinking,
    this.remainingSeconds,
  });

  final Stone stone;
  final String title;
  final String subtitle;
  final bool isActive;
  final bool isThinking;
  final int? remainingSeconds;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isUrgent = remainingSeconds != null && remainingSeconds! <= 10;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: isActive
            ? AppTheme.warmCard
            : AppTheme.warmCard.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isUrgent && isActive
              ? AppTheme.forbiddenCrimson
              : (isActive
                  ? AppTheme.accentWood
                  : AppTheme.accentWood.withValues(alpha: 0.16)),
          width: isActive ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          _StoneBadge(stone: stone),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: AppTheme.inkPrimary,
                        ),
                      ),
                    ),
                    if (remainingSeconds != null) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1.5,
                        ),
                        decoration: BoxDecoration(
                          color: isUrgent
                              ? AppTheme.forbiddenCrimson
                              : AppTheme.warmSurface,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          s.secondsShort(remainingSeconds!),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color:
                                isUrgent ? Colors.white : AppTheme.inkPrimary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    if (isThinking) ...[
                      const SizedBox(
                        width: 11,
                        height: 11,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppTheme.accentWood,
                        ),
                      ),
                      const SizedBox(width: 5),
                    ],
                    Expanded(
                      child: Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: isThinking
                              ? AppTheme.accentWood
                              : AppTheme.inkPrimary.withValues(alpha: 0.62),
                          fontWeight:
                              isThinking ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StoneBadge extends StatelessWidget {
  const _StoneBadge({required this.stone});

  final Stone stone;

  @override
  Widget build(BuildContext context) {
    final isBlack = stone == Stone.black;
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: const Alignment(-0.3, -0.3),
          colors: isBlack
              ? const [Color(0xFF555555), Color(0xFF111111)]
              : const [Color(0xFFFFFFFF), Color(0xFFD5CFC3)],
        ),
        border: Border.all(
          color: Colors.black.withValues(alpha: isBlack ? 0.4 : 0.22),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 3,
            offset: const Offset(0.5, 1),
          ),
        ],
      ),
    );
  }
}

/// Bottom action controls (confirm placement, undo with limit, hint, zoom, restart).
class GameActionBar extends StatelessWidget {
  const GameActionBar({
    super.key,
    required this.state,
    required this.confirmBeforePlace,
    required this.isZoomed,
    required this.onConfirmMove,
    required this.onUndo,
    required this.onHint,
    required this.onResetZoom,
    required this.onRestart,
  });

  final GameState state;
  final bool confirmBeforePlace;
  final bool isZoomed;
  final VoidCallback onConfirmMove;
  final VoidCallback onUndo;
  final VoidCallback onHint;
  final VoidCallback onResetZoom;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final pending = state.pendingMove;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (confirmBeforePlace && !state.isGameOver) ...[
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed:
                  (pending != null && state.isHumanTurn) ? onConfirmMove : null,
              icon: const Icon(Icons.check_circle_outline, size: 20),
              label: Text(s.confirmMoveCtaLabel(state)),
            ),
          ),
          const SizedBox(height: 10),
        ],
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: state.canUndo ? onUndo : null,
                icon: const Icon(Icons.undo_rounded, size: 17),
                label: Text(
                  s.undoActionLabel(state),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                style: _secondaryButtonStyle(),
              ),
            ),
            if (!state.isLocalTwoPlayer && !state.isNearbyP2p) ...[
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: (state.isHumanTurn && !state.isHintLoading)
                      ? onHint
                      : null,
                  icon: state.isHintLoading
                      ? const SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppTheme.accentWood,
                          ),
                        )
                      : const Icon(Icons.lightbulb_outline_rounded, size: 18),
                  label: Text(
                    s.hintButton,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  style: _secondaryButtonStyle(),
                ),
              ),
            ],
            const SizedBox(width: 8),
            if (isZoomed) ...[
              IconButton.outlined(
                tooltip: s.resetZoomTooltip,
                onPressed: onResetZoom,
                icon: const Icon(Icons.zoom_out_map_rounded, size: 18),
                style: _iconSecondaryStyle(),
              ),
              const SizedBox(width: 8),
            ],
            if (!state.isNearbyP2p)
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onRestart,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: Text(
                    s.newGameButton,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  style: _secondaryButtonStyle(),
                ),
              ),
          ],
        ),
      ],
    );
  }

  ButtonStyle _secondaryButtonStyle() => OutlinedButton.styleFrom(
        foregroundColor: AppTheme.inkPrimary,
        side: BorderSide(color: AppTheme.accentWood.withValues(alpha: 0.3)),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      );

  ButtonStyle _iconSecondaryStyle() => OutlinedButton.styleFrom(
        foregroundColor: AppTheme.inkPrimary,
        side: BorderSide(color: AppTheme.accentWood.withValues(alpha: 0.3)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      );
}

/// Interactive post-game replay scrubber bar (`|<`, `<`, Slider, `>`, `>|`, Exit).
class ReplayControlBar extends StatelessWidget {
  const ReplayControlBar({
    super.key,
    required this.currentStep,
    required this.totalMoves,
    required this.onSeek,
    required this.onStepDelta,
    required this.onExitReplay,
  });

  final int currentStep;
  final int totalMoves;
  final ValueChanged<int> onSeek;
  final ValueChanged<int> onStepDelta;
  final VoidCallback onExitReplay;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        color: AppTheme.warmCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.accentWood.withValues(alpha: 0.25)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(
                Icons.history_edu_rounded,
                size: 18,
                color: AppTheme.accentWood,
              ),
              const SizedBox(width: 6),
              Text(
                s.replayProgressLabel(currentStep, totalMoves),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13.5,
                  color: AppTheme.inkPrimary,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: onExitReplay,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                child: Text(s.exitReplay),
              ),
            ],
          ),
          Slider(
            value: currentStep.toDouble(),
            min: 0,
            max: totalMoves.toDouble().clamp(1, 225),
            divisions: totalMoves > 0 ? totalMoves : 1,
            activeColor: AppTheme.accentWood,
            onChanged: (v) => onSeek(v.round()),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                tooltip: s.replayFirstTooltip,
                onPressed: currentStep > 0 ? () => onSeek(0) : null,
                icon: const Icon(Icons.first_page_rounded),
              ),
              IconButton(
                tooltip: s.replayPrevTooltip,
                onPressed: currentStep > 0 ? () => onStepDelta(-1) : null,
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              IconButton(
                tooltip: s.replayNextTooltip,
                onPressed:
                    currentStep < totalMoves ? () => onStepDelta(1) : null,
                icon: const Icon(Icons.chevron_right_rounded),
              ),
              IconButton(
                tooltip: s.replayLastTooltip,
                onPressed:
                    currentStep < totalMoves ? () => onSeek(totalMoves) : null,
                icon: const Icon(Icons.last_page_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
