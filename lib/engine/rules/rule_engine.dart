import '../model/board_state.dart';
import '../model/coordinate.dart';
import '../model/game_result.dart';
import '../model/move.dart';
import '../model/stone.dart';

/// Supported Omok rule variants.
enum RuleType {
  renju(
    label: '렌주룰',
    shortDescription: '흑 금수(3-3 · 4-4 · 장목) 적용, 흑은 정확히 5목만 승리',
  ),
  freestyle(
    label: '자유룰',
    shortDescription: '흑·백 모두 금수 없음, 5목 이상(6목 포함) 모두 승리',
  );

  const RuleType({
    required this.label,
    required this.shortDescription,
  });

  final String label;
  final String shortDescription;
}

/// Reason why a candidate move is forbidden under a rule set.
enum ForbiddenReason {
  none,
  overline,
  doubleFour,
  doubleThree;

  bool get isForbidden => this != ForbiddenReason.none;
}

/// Abstract contract for Omok rule sets (e.g., Renju, Freestyle).
abstract class RuleEngine {
  const RuleEngine();

  RuleType get ruleType;

  /// Evaluates whether placing [player]'s stone at [pos] on [board] is
  /// forbidden. Assumes [pos] is valid; returns [ForbiddenReason.none] if
  /// occupied or legal.
  ForbiddenReason getForbiddenReason(
    BoardState board,
    Coordinate pos,
    Stone player,
  );

  bool isForbiddenMove(BoardState board, Coordinate pos, Stone player) =>
      getForbiddenReason(board, pos, player).isForbidden;

  /// Computes all currently forbidden intersections for [player] (useful for
  /// rendering forbidden markers on Black's turn in Renju).
  Map<Coordinate, ForbiddenReason> getForbiddenMoves(
    BoardState board,
    Stone player,
  );

  /// Evaluates win/draw status immediately after [lastMove] was placed on
  /// [board].
  GameResult checkResult(BoardState board, Move lastMove);
}
