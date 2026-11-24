import 'dart:math';

import '../model/board_state.dart';
import '../model/coordinate.dart';

/// Built-in offline Renju opening book for moves 1 to 3.
///
/// Prevents deterministic AI games from repeating the exact same opening
/// sequence while staying true to classic Renju shapes (직지형 / 사지형).
class OpeningBook {
  const OpeningBook();

  static const Coordinate center = Coordinate(7, 7);

  /// Standard White responses to Black's opening at H8 (7,7).
  static const List<Coordinate> _secondMoves = [
    Coordinate(6, 6), // Diagonal (간접/사지형)
    Coordinate(6, 8),
    Coordinate(8, 6),
    Coordinate(8, 8),
    Coordinate(6, 7), // Orthogonal (직접/직지형)
    Coordinate(7, 6),
    Coordinate(7, 8),
    Coordinate(8, 7),
  ];

  /// Classic 3rd-move offsets for Black relative to center (7,7) when White
  /// played orthogonally at (6,7) — rotated dynamically to match White's actual
  /// 2nd move.
  static const List<(int, int)> _orthogonalThirdOffsets = [
    (-1, 1), // 화월 / 포월 계열 (Diagonal adjacent)
    (-1, -1),
    (0, 1), // 한성 계열
    (0, -1),
    (1, 1), // 운월 / 우월 계열
    (1, -1),
    (-2, 1), // 서성 / 계월 계열
    (-2, -1),
  ];

  /// Classic 3rd-move offsets for Black relative to center (7,7) when White
  /// played diagonally at (6,6).
  static const List<(int, int)> _diagonalThirdOffsets = [
    (-1, 1), // 화월 (Flower Moon)
    (1, -1),
    (0, 1), // 포월 (Puget)
    (1, 0),
    (1, 1), // 명월 / 은월 계열
    (-2, 0),
    (0, -2),
  ];

  /// Returns a book move for early plies, or `null` if outside book coverage.
  Coordinate? lookup(BoardState board, Random random) {
    if (board.isEmpty) {
      return center;
    }

    if (board.moveCount == 1) {
      final first = board.history.first.coordinate;
      if (first == center) {
        return _secondMoves[random.nextInt(_secondMoves.length)];
      }
      // If Black didn't open on center, play adjacent toward center.
      final dr = (center.row - first.row).sign;
      final dc = (center.col - first.col).sign;
      final candidate = Coordinate(first.row + dr, first.col + dc);
      if (candidate.isValid && !board.isOccupied(candidate)) {
        return candidate;
      }
      return null;
    }

    if (board.moveCount == 2) {
      final first = board.history[0].coordinate;
      final second = board.history[1].coordinate;
      if (first != center) return null;

      final dr = second.row - center.row;
      final dc = second.col - center.col;
      if (dr.abs() > 1 || dc.abs() > 1) return null;

      final isDiagonal = dr != 0 && dc != 0;
      final candidates = <Coordinate>[];

      if (isDiagonal) {
        for (final (or, oc) in _diagonalThirdOffsets) {
          // Align relative to White's quadrant (dr, dc) vs (-1, -1).
          final r = center.row + or * (-dr);
          final c = center.col + oc * (-dc);
          final coord = Coordinate(r, c);
          if (coord.isValid && !board.isOccupied(coord)) {
            candidates.add(coord);
          }
        }
      } else {
        // Align orthogonal White move (dr, dc) relative to (-1, 0).
        for (final (or, oc) in _orthogonalThirdOffsets) {
          final int r;
          final int c;
          if (dr == -1 && dc == 0) {
            r = center.row + or;
            c = center.col + oc;
          } else if (dr == 1 && dc == 0) {
            r = center.row - or;
            c = center.col - oc;
          } else if (dr == 0 && dc == 1) {
            r = center.row + oc;
            c = center.col - or;
          } else {
            // dr == 0 && dc == -1
            r = center.row - oc;
            c = center.col + or;
          }
          final coord = Coordinate(r, c);
          if (coord.isValid && !board.isOccupied(coord)) {
            candidates.add(coord);
          }
        }
      }

      if (candidates.isNotEmpty) {
        return candidates[random.nextInt(candidates.length)];
      }
    }

    return null;
  }
}
