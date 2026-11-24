import 'dart:typed_data';

import '../model/board_state.dart';
import '../model/coordinate.dart';
import '../model/game_result.dart';
import '../model/move.dart';
import '../model/stone.dart';
import 'rule_engine.dart';

/// Official RIF Renju Rule implementation for 15x15 Omok.
///
/// - **White**: No forbidden moves; 5 or more in a row wins.
/// - **Black**: Exact 5 in a row wins (even if another axis has 6+, 4-4, or
///   3-3). Otherwise overline (6+), double-four (4-4, including single-line
///   4-4), and double-three (3-3, with recursive false-3-3 verification) are
///   forbidden.
class RenjuRuleEngine extends RuleEngine {
  const RenjuRuleEngine();

  @override
  RuleType get ruleType => RuleType.renju;

  static const List<(int, int)> _axes = [
    (0, 1), // Horizontal
    (1, 0), // Vertical
    (1, 1), // Main diagonal (\)
    (1, -1), // Anti-diagonal (/)
  ];

  @override
  ForbiddenReason getForbiddenReason(
    BoardState board,
    Coordinate pos,
    Stone player,
  ) {
    if (player != Stone.black || !pos.isValid || board.isOccupied(pos)) {
      return ForbiddenReason.none;
    }
    final cells = board.copyRawCells();
    return checkForbiddenOnBuffer(cells, pos.row, pos.col);
  }

  /// Fast buffer-level forbidden check for Black, also reusable by AI search.
  ForbiddenReason checkForbiddenOnBuffer(Uint8List cells, int row, int col) {
    final idx = row * kBoardSize + col;
    if (!_inBounds(row, col) || cells[idx] != Stone.empty.code) {
      return ForbiddenReason.none;
    }

    cells[idx] = Stone.black.code;
    try {
      // 1. Exact 5 always wins immediately and overrides all forbidden moves.
      var hasOverline = false;
      for (final (dr, dc) in _axes) {
        final runLength = _countContiguous(cells, row, col, dr, dc, Stone.black.code);
        if (runLength == 5) {
          return ForbiddenReason.none;
        }
        if (runLength > 5) {
          hasOverline = true;
        }
      }

      // 2. Overline (6+ in a row).
      if (hasOverline) {
        return ForbiddenReason.overline;
      }

      // 3. Double-four (4-4) & Double-three (3-3).
      var totalFours = 0;
      var totalOpenThrees = 0;

      for (final (dr, dc) in _axes) {
        final foursOnAxis = _countFoursOnAxis(cells, row, col, dr, dc);
        totalFours += foursOnAxis;
        if (totalFours >= 2) {
          return ForbiddenReason.doubleFour;
        }

        // An axis already forming a 4 is not counted as an open 3.
        if (foursOnAxis == 0 && _hasOpenThreeOnAxis(cells, row, col, dr, dc)) {
          totalOpenThrees++;
        }
      }

      if (totalOpenThrees >= 2) {
        return ForbiddenReason.doubleThree;
      }

      return ForbiddenReason.none;
    } finally {
      cells[idx] = Stone.empty.code;
    }
  }

  @override
  Map<Coordinate, ForbiddenReason> getForbiddenMoves(
    BoardState board,
    Stone player,
  ) {
    if (player != Stone.black) {
      return const {};
    }

    final cells = board.copyRawCells();
    final forbidden = <Coordinate, ForbiddenReason>{};
    for (var row = 0; row < kBoardSize; row++) {
      for (var col = 0; col < kBoardSize; col++) {
        if (cells[row * kBoardSize + col] != Stone.empty.code) {
          continue;
        }
        final reason = checkForbiddenOnBuffer(cells, row, col);
        if (reason.isForbidden) {
          forbidden[Coordinate(row, col)] = reason;
        }
      }
    }
    return forbidden;
  }

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
      final isWin = stone == Stone.black ? line.length == 5 : line.length >= 5;
      if (isWin) {
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

  /// Counts how many distinct fours are created along [(dr, dc)] passing
  /// through [(row, col)] (where [cells] already has Black at [(row, col)]).
  ///
  /// Distinguishes a single open four (`_BBBB_`, which has 2 exact-5 points
  /// separated by 5 steps around 4 contiguous Black stones) from a single-line
  /// double-four (`B_BBB_B`, `BB_B_BB`, etc., which yields 2 fours).
  int _countFoursOnAxis(Uint8List cells, int row, int col, int dr, int dc) {
    final fiveOffsets = <int>[];

    for (var k = -4; k <= 4; k++) {
      if (k == 0) continue;
      final r = row + k * dr;
      final c = col + k * dc;
      if (!_inBounds(r, c)) continue;
      final idx = r * kBoardSize + c;
      if (cells[idx] != Stone.empty.code) continue;

      cells[idx] = Stone.black.code;
      final (neg, pos) = _contiguousExtent(cells, r, c, dr, dc, Stone.black.code);
      cells[idx] = Stone.empty.code;

      final totalLen = neg + pos + 1;
      // The resulting exact-5 segment must include the origin (row, col),
      // which lies at offset (-k) from (r, c).
      final originOffsetFromR = -k;
      final includesOrigin =
          originOffsetFromR >= -neg && originOffsetFromR <= pos;

      if (totalLen == 5 && includesOrigin) {
        fiveOffsets.add(k);
      }
    }

    if (fiveOffsets.isEmpty) return 0;
    if (fiveOffsets.length == 1) return 1;

    // Exactly two 5-making points: check whether they are the two open ends
    // of a single contiguous 4-stone run (`_BBBB_`).
    if (fiveOffsets.length == 2 && (fiveOffsets[1] - fiveOffsets[0]) == 5) {
      var allBlackBetween = true;
      for (var step = fiveOffsets[0] + 1; step < fiveOffsets[1]; step++) {
        final r = row + step * dr;
        final c = col + step * dc;
        if (cells[r * kBoardSize + c] != Stone.black.code) {
          allBlackBetween = false;
          break;
        }
      }
      if (allBlackBetween) {
        return 1; // One open four.
      }
    }

    // Multiple distinct fours on the same line (single-line 4-4).
    return 2;
  }

  /// Checks whether placing Black at [(row, col)] creates a true Renju open
  /// three along [(dr, dc)].
  ///
  /// A true open three exists iff there is an empty point `e` along the axis
  /// such that:
  /// 1. Temporarily placing Black at `e` forms a straight open four (`_BBBB_`)
  ///    containing [(row, col)], whose both open endpoints independently form
  ///    exact-5 (not overline); AND
  /// 2. `e` itself is not a forbidden move for Black (recursive false-3-3
  ///    check).
  bool _hasOpenThreeOnAxis(Uint8List cells, int row, int col, int dr, int dc) {
    for (var k = -3; k <= 3; k++) {
      if (k == 0) continue;
      final er = row + k * dr;
      final ec = col + k * dc;
      if (!_inBounds(er, ec)) continue;
      final eIdx = er * kBoardSize + ec;
      if (cells[eIdx] != Stone.empty.code) continue;

      cells[eIdx] = Stone.black.code;
      final formsStraightOpenFour = _isStraightOpenFourContaining(
        cells,
        er,
        ec,
        row,
        col,
        dr,
        dc,
      );
      cells[eIdx] = Stone.empty.code;

      if (!formsStraightOpenFour) continue;

      // Verify `e` is a legal move for Black (handles recursive false 3-3).
      if (checkForbiddenOnBuffer(cells, er, ec) == ForbiddenReason.none) {
        return true;
      }
    }
    return false;
  }

  /// Checks whether [(er, ec)] (already set to Black in [cells]) is part of a
  /// straight open four (`_BBBB_`) along [(dr, dc)] that contains
  /// [(originRow, originCol)], with both ends forming exact-5.
  bool _isStraightOpenFourContaining(
    Uint8List cells,
    int er,
    int ec,
    int originRow,
    int originCol,
    int dr,
    int dc,
  ) {
    final (neg, pos) = _contiguousExtent(cells, er, ec, dr, dc, Stone.black.code);
    if (neg + pos + 1 != 4) {
      return false;
    }

    // Verify (originRow, originCol) lies within the 4 contiguous stones.
    final startR = er - neg * dr;
    final startC = ec - neg * dc;
    var containsOrigin = false;
    for (var i = 0; i < 4; i++) {
      if (startR + i * dr == originRow && startC + i * dc == originCol) {
        containsOrigin = true;
        break;
      }
    }
    if (!containsOrigin) {
      return false;
    }

    // Both endpoints directly flanking the 4 stones must be empty and yield
    // exact-5 (not overline).
    final leftR = startR - dr;
    final leftC = startC - dc;
    final rightR = startR + 4 * dr;
    final rightC = startC + 4 * dc;

    if (!_makesExactFiveAt(cells, leftR, leftC, dr, dc)) return false;
    if (!_makesExactFiveAt(cells, rightR, rightC, dr, dc)) return false;

    return true;
  }

  bool _makesExactFiveAt(Uint8List cells, int r, int c, int dr, int dc) {
    if (!_inBounds(r, c)) return false;
    final idx = r * kBoardSize + c;
    if (cells[idx] != Stone.empty.code) return false;

    cells[idx] = Stone.black.code;
    final len = _countContiguous(cells, r, c, dr, dc, Stone.black.code);
    cells[idx] = Stone.empty.code;
    return len == 5;
  }

  /// Returns `(negSteps, posSteps)` counting contiguous matching stones in the
  /// `(-dr, -dc)` and `(+dr, +dc)` directions from [(row, col)] (excluding
  /// [(row, col)] itself).
  (int, int) _contiguousExtent(
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

    return (neg, pos);
  }

  int _countContiguous(
    Uint8List cells,
    int row,
    int col,
    int dr,
    int dc,
    int code,
  ) {
    final (neg, pos) = _contiguousExtent(cells, row, col, dr, dc, code);
    return neg + pos + 1;
  }

  List<Coordinate> _collectContiguous(
    Uint8List cells,
    int row,
    int col,
    int dr,
    int dc,
    int code,
  ) {
    final (neg, pos) = _contiguousExtent(cells, row, col, dr, dc, code);
    final startR = row - neg * dr;
    final startC = col - neg * dc;
    final count = neg + pos + 1;
    return List<Coordinate>.generate(
      count,
      (i) => Coordinate(startR + i * dr, startC + i * dc),
      growable: false,
    );
  }

  bool _inBounds(int row, int col) =>
      row >= 0 && row < kBoardSize && col >= 0 && col < kBoardSize;
}
