import 'dart:typed_data';

import '../model/coordinate.dart';
import '../model/stone.dart';

/// Threat classification for a single candidate stone placement.
class PointThreatSummary {
  const PointThreatSummary({
    required this.makesWin,
    required this.openFours,
    required this.closedFours,
    required this.openThrees,
    required this.closedThrees,
    required this.openTwos,
    required this.closedTwos,
    required this.score,
  });

  final bool makesWin;
  final int openFours;
  final int closedFours;
  final int openThrees;
  final int closedThrees;
  final int openTwos;
  final int closedTwos;
  final int score;

  int get totalFours => openFours + closedFours;
  bool get isWinningThreat =>
      makesWin ||
      openFours > 0 ||
      totalFours >= 2 ||
      (totalFours >= 1 && openThrees >= 1);
}

/// Fast, zero-allocation pattern evaluator for 15x15 Omok/Renju boards.
///
/// Recognizes consecutive and 1-gap broken patterns (e.g. `●●_●`, `●●_●●`)
/// across all 4 axes and handles Renju exact-5 vs overline rules for Black.
class PatternEvaluator {
  const PatternEvaluator({this.isRenju = true});

  /// When true, Black is restricted to exact-5 wins (no overline/3-3/4-4).
  /// When false (Freestyle), both colors win on 5+ and allow 3-3/4-4 combos.
  final bool isRenju;

  static const int winScore = 10000000;
  static const int openFourScore = 120000;
  static const int fourThreeBonus = 90000;
  static const int closedFourScore = 12000;
  static const int openThreeScore = 10500;
  static const int doubleThreeBonus = 45000;
  static const int closedThreeScore = 1200;
  static const int openTwoScore = 450;
  static const int closedTwoScore = 70;

  static const List<(int, int)> axes = [
    (0, 1),
    (1, 0),
    (1, 1),
    (1, -1),
  ];

  /// Precomputed line definitions (startRow, startCol, dr, dc, length) for all
  /// 72 lines on the 15x15 board that have length >= 5.
  static final List<(int, int, int, int, int)> _allLines = _buildLines();

  static List<(int, int, int, int, int)> _buildLines() {
    final lines = <(int, int, int, int, int)>[];
    // 15 rows
    for (var r = 0; r < kBoardSize; r++) {
      lines.add((r, 0, 0, 1, kBoardSize));
    }
    // 15 columns
    for (var c = 0; c < kBoardSize; c++) {
      lines.add((0, c, 1, 0, kBoardSize));
    }
    // Main diagonals (\) of length >= 5
    for (var startRow = 0; startRow <= kBoardSize - 5; startRow++) {
      lines.add((startRow, 0, 1, 1, kBoardSize - startRow));
    }
    for (var startCol = 1; startCol <= kBoardSize - 5; startCol++) {
      lines.add((0, startCol, 1, 1, kBoardSize - startCol));
    }
    // Anti-diagonals (/) of length >= 5
    for (var startCol = 4; startCol < kBoardSize; startCol++) {
      lines.add((0, startCol, 1, -1, startCol + 1));
    }
    for (var startRow = 1; startRow <= kBoardSize - 5; startRow++) {
      lines.add((startRow, kBoardSize - 1, 1, -1, kBoardSize - startRow));
    }
    return List.unmodifiable(lines);
  }

  /// Checks whether placing [stoneCode] at [(row, col)] immediately wins.
  /// Assumes `cells[row * 15 + col] == 0` (or already set to [stoneCode]).
  bool isImmediateWin(Uint8List cells, int row, int col, int stoneCode) {
    final idx = row * kBoardSize + col;
    final prev = cells[idx];
    cells[idx] = stoneCode;
    try {
      final restrictBlack = isRenju && stoneCode == Stone.black.code;
      for (final (dr, dc) in axes) {
        final len = _contiguousLen(cells, row, col, dr, dc, stoneCode);
        if (restrictBlack ? len == 5 : len >= 5) {
          return true;
        }
      }
      return false;
    } finally {
      cells[idx] = prev;
    }
  }

  /// Evaluates the immediate tactical impact of placing [stoneCode] at an empty
  /// cell [(row, col)]. Used for move ordering, Beginner AI, and threat detection.
  PointThreatSummary evaluatePoint(
    Uint8List cells,
    int row,
    int col,
    int stoneCode,
  ) {
    final idx = row * kBoardSize + col;
    final prev = cells[idx];
    cells[idx] = stoneCode;

    var makesWin = false;
    var openFours = 0;
    var closedFours = 0;
    var openThrees = 0;
    var closedThrees = 0;
    var openTwos = 0;
    var closedTwos = 0;

    final restrictBlack = isRenju && stoneCode == Stone.black.code;

    try {
      for (final (dr, dc) in axes) {
        final len = _contiguousLen(cells, row, col, dr, dc, stoneCode);
        if (restrictBlack ? len == 5 : len >= 5) {
          makesWin = true;
          break;
        }
        if (restrictBlack && len > 5) {
          // Overline on this axis is useless for Black under Renju.
          continue;
        }

        // Check fours (including broken fours) by counting distinct empty
        // cells along this axis within [-4, +4] that complete a win containing
        // (row, col).
        final fivePoints = _countWinningCompletionsOnAxis(
          cells,
          row,
          col,
          dr,
          dc,
          stoneCode,
        );

        if (fivePoints >= 2) {
          // Distinguish straight open four (`_SSSS_`) vs single-line double-four.
          if (len == 4 && fivePoints == 2) {
            openFours++;
          } else {
            closedFours += 2;
          }
          continue;
        } else if (fivePoints == 1) {
          closedFours++;
          continue;
        }

        // Check open/closed threes & twos (including 1-gap broken shapes).
        final pattern = _classifySubFourAxis(cells, row, col, dr, dc, stoneCode);
        switch (pattern) {
          case _AxisPattern.openThree:
            openThrees++;
          case _AxisPattern.closedThree:
            closedThrees++;
          case _AxisPattern.openTwo:
            openTwos++;
          case _AxisPattern.closedTwo:
            closedTwos++;
          case _AxisPattern.none:
            break;
        }
      }
    } finally {
      cells[idx] = prev;
    }

    var score = 0;
    if (makesWin) {
      score = winScore;
    } else {
      score += openFours * openFourScore;
      score += closedFours * closedFourScore;
      score += openThrees * openThreeScore;
      score += closedThrees * closedThreeScore;
      score += openTwos * openTwoScore;
      score += closedTwos * closedTwoScore;

      final totalFours = openFours + closedFours;
      if (!restrictBlack && totalFours >= 2) {
        score += openFourScore;
      }
      if (totalFours >= 1 && openThrees >= 1) {
        score += fourThreeBonus;
      }
      if (!restrictBlack && openThrees >= 2) {
        score += doubleThreeBonus;
      }

      // Mild center-proximity bias for opening/quiet positions.
      final centerDist = (row - 7).abs() + (col - 7).abs();
      score += (14 - centerDist) * 4;
    }

    return PointThreatSummary(
      makesWin: makesWin,
      openFours: openFours,
      closedFours: closedFours,
      openThrees: openThrees,
      closedThrees: closedThrees,
      openTwos: openTwos,
      closedTwos: closedTwos,
      score: score,
    );
  }

  /// Static full-board evaluation from the perspective of [aiCode], given that
  /// [turnCode] is about to move.
  int evaluateBoard(Uint8List cells, int aiCode, int turnCode) {
    final oppCode = aiCode == Stone.black.code
        ? Stone.white.code
        : Stone.black.code;

    var aiTotal = 0;
    var oppTotal = 0;

    for (final (sr, sc, dr, dc, len) in _allLines) {
      aiTotal += _scoreLineForColor(cells, sr, sc, dr, dc, len, aiCode);
      oppTotal += _scoreLineForColor(cells, sr, sc, dr, dc, len, oppCode);
    }

    // Active player gets a tempo bonus because their existing threats are 1 ply
    // closer to conversion.
    if (turnCode == aiCode) {
      return (aiTotal * 11 ~/ 10) - oppTotal;
    } else {
      return aiTotal - (oppTotal * 11 ~/ 10);
    }
  }

  /// Scores all runs and 1-gap broken shapes of [color] along a single line.
  int _scoreLineForColor(
    Uint8List cells,
    int sr,
    int sc,
    int dr,
    int dc,
    int length,
    int color,
  ) {
    var score = 0;
    var i = 0;

    while (i < length) {
      final r = sr + i * dr;
      final c = sc + i * dc;
      if (cells[r * kBoardSize + c] != color) {
        i++;
        continue;
      }

      // Measure contiguous run starting at i.
      final runStart = i;
      while (i < length &&
          cells[(sr + i * dr) * kBoardSize + (sc + i * dc)] == color) {
        i++;
      }
      final runLen = i - runStart;

      final leftOpen = runStart > 0 &&
          cells[(sr + (runStart - 1) * dr) * kBoardSize +
                  (sc + (runStart - 1) * dc)] ==
              0;
      final rightOpen = i < length &&
          cells[(sr + i * dr) * kBoardSize + (sc + i * dc)] == 0;

      // Check for a 1-gap continuation to the right: `run _ nextRun`.
      var bridgedLen = 0;
      var bridgeRightOpen = false;
      if (rightOpen && i + 1 < length) {
        final nextCell =
            cells[(sr + (i + 1) * dr) * kBoardSize + (sc + (i + 1) * dc)];
        if (nextCell == color) {
          var j = i + 1;
          while (j < length &&
              cells[(sr + j * dr) * kBoardSize + (sc + j * dc)] == color) {
            j++;
          }
          bridgedLen = runLen + (j - (i + 1));
          bridgeRightOpen = j < length &&
              cells[(sr + j * dr) * kBoardSize + (sc + j * dc)] == 0;
        }
      }

      final openEnds = (leftOpen ? 1 : 0) + (rightOpen ? 1 : 0);

      if (runLen >= 5) {
        if (!isRenju || color == Stone.white.code || runLen == 5) {
          score += winScore;
        }
      } else if (runLen == 4) {
        if (openEnds == 2) {
          score += openFourScore;
        } else if (openEnds == 1) {
          score += closedFourScore;
        }
      } else if (runLen == 3) {
        if (openEnds == 2) {
          // Verify at least 5 total spaces exist around the open three.
          final hasExtraSpace = (runStart >= 2 &&
                  cells[(sr + (runStart - 2) * dr) * kBoardSize +
                          (sc + (runStart - 2) * dc)] ==
                      0) ||
              (i + 1 < length &&
                  cells[(sr + (i + 1) * dr) * kBoardSize +
                          (sc + (i + 1) * dc)] ==
                      0);
          score += hasExtraSpace ? openThreeScore : closedThreeScore;
        } else if (openEnds == 1) {
          score += closedThreeScore;
        }
      } else if (runLen == 2) {
        if (openEnds == 2) {
          score += openTwoScore;
        } else if (openEnds == 1) {
          score += closedTwoScore;
        }
      }

      // Score 1-gap broken threats (e.g., `●●_●●`, `●●●_●`, `●●_●`).
      if (bridgedLen >= 4) {
        // Broken 4 (filling the gap makes 5!).
        if (!isRenju || color == Stone.white.code || bridgedLen == 4) {
          score += closedFourScore;
        }
      } else if (bridgedLen == 3) {
        // Broken 3 (`●●_●` or `●_●●`): open if both outer ends are empty.
        if (leftOpen && bridgeRightOpen) {
          score += openThreeScore * 9 ~/ 10;
        } else if (leftOpen || bridgeRightOpen) {
          score += closedThreeScore;
        }
      }
    }

    return score;
  }

  /// Counts empty cells on [(dr, dc)] within [-4, 4] of [(row, col)] that
  /// would complete a winning 5-line including [(row, col)].
  int _countWinningCompletionsOnAxis(
    Uint8List cells,
    int row,
    int col,
    int dr,
    int dc,
    int stoneCode,
  ) {
    final restrictBlack = isRenju && stoneCode == Stone.black.code;
    var count = 0;

    for (var k = -4; k <= 4; k++) {
      if (k == 0) continue;
      final r = row + k * dr;
      final c = col + k * dc;
      if (!_inBounds(r, c)) continue;
      final idx = r * kBoardSize + c;
      if (cells[idx] != 0) continue;

      cells[idx] = stoneCode;
      final (neg, pos) = _contiguousExtent(cells, r, c, dr, dc, stoneCode);
      cells[idx] = 0;

      final total = neg + pos + 1;
      final originOffset = -k;
      final includesOrigin = originOffset >= -neg && originOffset <= pos;
      if (includesOrigin && (restrictBlack ? total == 5 : total >= 5)) {
        count++;
      }
    }

    return count;
  }

  _AxisPattern _classifySubFourAxis(
    Uint8List cells,
    int row,
    int col,
    int dr,
    int dc,
    int stoneCode,
  ) {
    final (neg, pos) = _contiguousExtent(cells, row, col, dr, dc, stoneCode);
    final runLen = neg + pos + 1;

    final leftR = row - (neg + 1) * dr;
    final leftC = col - (neg + 1) * dc;
    final rightR = row + (pos + 1) * dr;
    final rightC = col + (pos + 1) * dc;

    final leftOpen = _inBounds(leftR, leftC) &&
        cells[leftR * kBoardSize + leftC] == 0;
    final rightOpen = _inBounds(rightR, rightC) &&
        cells[rightR * kBoardSize + rightC] == 0;

    // Count broken-3 extension across a single empty gap on left or right.
    var leftGapStones = 0;
    var leftGapOuterOpen = false;
    if (leftOpen) {
      var r = leftR - dr;
      var c = leftC - dc;
      while (_inBounds(r, c) && cells[r * kBoardSize + c] == stoneCode) {
        leftGapStones++;
        r -= dr;
        c -= dc;
      }
      leftGapOuterOpen = _inBounds(r, c) && cells[r * kBoardSize + c] == 0;
    }

    var rightGapStones = 0;
    var rightGapOuterOpen = false;
    if (rightOpen) {
      var r = rightR + dr;
      var c = rightC + dc;
      while (_inBounds(r, c) && cells[r * kBoardSize + c] == stoneCode) {
        rightGapStones++;
        r += dr;
        c += dc;
      }
      rightGapOuterOpen = _inBounds(r, c) && cells[r * kBoardSize + c] == 0;
    }

    // Check contiguous 3 first.
    if (runLen == 3) {
      if (leftOpen && rightOpen) {
        final leftExtra = _inBounds(leftR - dr, leftC - dc) &&
            cells[(leftR - dr) * kBoardSize + (leftC - dc)] == 0;
        final rightExtra = _inBounds(rightR + dr, rightC + dc) &&
            cells[(rightR + dr) * kBoardSize + (rightC + dc)] == 0;
        if (leftExtra || rightExtra) {
          return _AxisPattern.openThree;
        }
        return _AxisPattern.closedThree;
      }
      if (leftOpen || rightOpen) {
        return _AxisPattern.closedThree;
      }
      return _AxisPattern.none;
    }

    // Check broken 3 (`●●_●` or `●_●●`).
    if (runLen + leftGapStones == 3 && leftGapStones > 0) {
      return (rightOpen && leftGapOuterOpen)
          ? _AxisPattern.openThree
          : _AxisPattern.closedThree;
    }
    if (runLen + rightGapStones == 3 && rightGapStones > 0) {
      return (leftOpen && rightGapOuterOpen)
          ? _AxisPattern.openThree
          : _AxisPattern.closedThree;
    }

    // Contiguous or broken 2.
    if (runLen == 2) {
      if (leftOpen && rightOpen) return _AxisPattern.openTwo;
      if (leftOpen || rightOpen) return _AxisPattern.closedTwo;
    }
    if (runLen == 1 && (leftGapStones == 1 || rightGapStones == 1)) {
      if ((leftGapStones == 1 && rightOpen && leftGapOuterOpen) ||
          (rightGapStones == 1 && leftOpen && rightGapOuterOpen)) {
        return _AxisPattern.openTwo;
      }
      return _AxisPattern.closedTwo;
    }

    return _AxisPattern.none;
  }

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

  int _contiguousLen(
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

  bool _inBounds(int row, int col) =>
      row >= 0 && row < kBoardSize && col >= 0 && col < kBoardSize;
}

enum _AxisPattern {
  none,
  closedTwo,
  openTwo,
  closedThree,
  openThree,
}
