import 'dart:typed_data';

import '../model/board_state.dart';
import '../model/coordinate.dart';
import '../model/game_result.dart';
import '../model/move.dart';
import '../model/stone.dart';
import 'rule_engine.dart';

/// Freestyle Omok (Gomoku) rule implementation:
/// - No forbidden moves for either Black or White.
/// - 5 or more contiguous stones in any direction wins for both players.
class FreestyleRuleEngine extends RuleEngine {
  const FreestyleRuleEngine();

  static const List<(int, int)> _axes = [
    (0, 1),
    (1, 0),
    (1, 1),
    (1, -1),
  ];

  @override
  RuleType get ruleType => RuleType.freestyle;

  @override
  ForbiddenReason getForbiddenReason(
    BoardState board,
    Coordinate pos,
    Stone player,
  ) =>
      ForbiddenReason.none;

  @override
  Map<Coordinate, ForbiddenReason> getForbiddenMoves(
    BoardState board,
    Stone player,
  ) =>
      const {};

  @override
  GameResult checkResult(BoardState board, Move lastMove) {
    final cells = board.copyRawCells();
    final row = lastMove.coordinate.row;
    final col = lastMove.coordinate.col;
    final stone = lastMove.stone;
    final code = stone.code;

    if (cells[row * kBoardSize + col] != code) {
      return GameResult.ongoing;
    }

    for (final (dr, dc) in _axes) {
      final line = _collectContiguous(cells, row, col, dr, dc, code);
      if (line.length >= 5) {
        return GameResult(
          status: stone == Stone.black
              ? GameStatus.blackWin
              : GameStatus.whiteWin,
          winningLine: line,
        );
      }
    }

    if (board.isFull) {
      return GameResult.draw;
    }

    return GameResult.ongoing;
  }

  List<Coordinate> _collectContiguous(
    Uint8List cells,
    int row,
    int col,
    int dr,
    int dc,
    int code,
  ) {
    var neg = 0;
    var r = row - dr;
    var c = col - dc;
    while (_inBounds(r, c) && cells[r * kBoardSize + c] == code) {
      neg++;
      r -= dr;
      c -= dc;
    }

    var pos = 0;
    r = row + dr;
    c = col + dc;
    while (_inBounds(r, c) && cells[r * kBoardSize + c] == code) {
      pos++;
      r += dr;
      c += dc;
    }

    final startR = row - neg * dr;
    final startC = col - neg * dc;
    return List<Coordinate>.generate(
      neg + pos + 1,
      (i) => Coordinate(startR + i * dr, startC + i * dc),
      growable: false,
    );
  }

  bool _inBounds(int row, int col) =>
      row >= 0 && row < kBoardSize && col >= 0 && col < kBoardSize;
}
