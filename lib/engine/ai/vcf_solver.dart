import 'dart:typed_data';

import '../model/coordinate.dart';
import '../model/stone.dart';
import '../rules/renju_rule_engine.dart';
import 'pattern_evaluator.dart';

/// Victory by Continuous Four (VCF) solver for Expert AI.
///
/// Explores forcing sequences where the attacker repeatedly creates 4-in-a-row
/// threats (forcing a unique defensive reply each ply) until achieving an
/// unstoppable 5, open four, or forbidden-defense trap.
class VcfSolver {
  VcfSolver({
    required this.evaluator,
    this.renjuRules = const RenjuRuleEngine(),
  });

  final PatternEvaluator evaluator;
  final RenjuRuleEngine? renjuRules;

  int _nodesVisited = 0;
  int _maxNodes = 6000;
  late Stopwatch _stopwatch;
  int _deadlineMs = 300;
  bool _timedOut = false;

  bool get timedOut => _timedOut;

  /// Searches for a forced VCF winning move for [attackerCode] up to
  /// [maxDepth] plies within [timeBudgetMs].
  ///
  /// Returns the winning flat board index (`0..224`), or `-1` if none found.
  int findWinningMove(
    Uint8List cells,
    int attackerCode, {
    int maxDepth = 14,
    int timeBudgetMs = 300,
    int maxNodes = 6000,
  }) {
    _nodesVisited = 0;
    _maxNodes = maxNodes;
    _deadlineMs = timeBudgetMs;
    _timedOut = false;
    _stopwatch = Stopwatch()..start();

    final work = Uint8List.fromList(cells);
    return _search(work, attackerCode, maxDepth);
  }

  int _search(Uint8List cells, int attackerCode, int depth) {
    if (depth <= 0 || _timedOut) return -1;
    _nodesVisited++;
    if (_nodesVisited >= _maxNodes ||
        (_nodesVisited & 63) == 0 &&
            _stopwatch.elapsedMilliseconds >= _deadlineMs) {
      _timedOut = true;
      return -1;
    }

    final defenderCode = attackerCode == Stone.black.code
        ? Stone.white.code
        : Stone.black.code;

    final candidates = _collectNeighborEmpties(cells);

    // 1. Check if attacker can win immediately on this move.
    for (final idx in candidates) {
      final r = idx ~/ kBoardSize;
      final c = idx % kBoardSize;
      if (evaluator.isImmediateWin(cells, r, c, attackerCode)) {
        return idx;
      }
    }

    if (depth < 2) return -1;

    // 2. Check if defender already threatens an immediate 5-in-a-row.
    final defenderWins = <int>[];
    for (final idx in candidates) {
      final r = idx ~/ kBoardSize;
      final c = idx % kBoardSize;
      if (defenderCode == Stone.black.code &&
          renjuRules != null &&
          renjuRules!.checkForbiddenOnBuffer(cells, r, c).isForbidden) {
        continue;
      }
      if (evaluator.isImmediateWin(cells, r, c, defenderCode)) {
        defenderWins.add(idx);
        if (defenderWins.length >= 2) {
          // Defender has 2+ immediate wins and attacker has no immediate win.
          return -1;
        }
      }
    }

    // If defender has exactly 1 immediate win, attacker's forcing move MUST
    // occupy that exact cell to survive.
    final forcingCandidates =
        defenderWins.length == 1 ? defenderWins : candidates;

    // 3. Generate and sort all legal 4-making moves for attacker.
    final fourMoves = <(int, List<int>)>[];
    for (final idx in forcingCandidates) {
      final r = idx ~/ kBoardSize;
      final c = idx % kBoardSize;

      // Skip forbidden moves when attacker is Black under Renju.
      if (attackerCode == Stone.black.code &&
          renjuRules != null &&
          renjuRules!.checkForbiddenOnBuffer(cells, r, c).isForbidden) {
        continue;
      }

      cells[idx] = attackerCode;
      final winningFollowUps = _findImmediateWinsAround(
        cells,
        r,
        c,
        attackerCode,
      );
      cells[idx] = 0;

      if (winningFollowUps.isEmpty) continue;

      // Open four or double-four (2+ distinct winning replies): unstoppable!
      if (winningFollowUps.length >= 2) {
        return idx;
      }

      fourMoves.add((idx, winningFollowUps));
    }

    // 4. Explore closed/broken fours with forced single defensive reply.
    for (final (moveIdx, followUps) in fourMoves) {
      if (_timedOut) return -1;
      final defIdx = followUps[0];
      final defR = defIdx ~/ kBoardSize;
      final defC = defIdx % kBoardSize;

      cells[moveIdx] = attackerCode;

      // If defender is Black and the ONLY blocking cell is forbidden, attacker wins!
      if (defenderCode == Stone.black.code &&
          renjuRules != null &&
          renjuRules!.checkForbiddenOnBuffer(cells, defR, defC).isForbidden) {
        cells[moveIdx] = 0;
        return moveIdx;
      }

      // Place defender's forced block.
      cells[defIdx] = defenderCode;
      final defenderCounterWon =
          evaluator.isImmediateWin(cells, defR, defC, defenderCode);

      var won = false;
      if (!defenderCounterWon) {
        won = _search(cells, attackerCode, depth - 2) != -1;
      }

      cells[defIdx] = 0;
      cells[moveIdx] = 0;

      if (won) {
        return moveIdx;
      }
    }

    return -1;
  }

  /// Finds distinct empty cells within 4 steps of [(row, col)] along any axis
  /// where [stoneCode] would immediately win on the next move.
  List<int> _findImmediateWinsAround(
    Uint8List cells,
    int row,
    int col,
    int stoneCode,
  ) {
    final wins = <int>[];
    for (final (dr, dc) in PatternEvaluator.axes) {
      for (var k = -4; k <= 4; k++) {
        if (k == 0) continue;
        final r = row + k * dr;
        final c = col + k * dc;
        if (r < 0 || r >= kBoardSize || c < 0 || c >= kBoardSize) continue;
        final idx = r * kBoardSize + c;
        if (cells[idx] != 0) continue;

        if (evaluator.isImmediateWin(cells, r, c, stoneCode)) {
          if (!wins.contains(idx)) {
            wins.add(idx);
            if (wins.length >= 2) {
              return wins;
            }
          }
        }
      }
    }
    return wins;
  }

  /// Collects empty cells within Chebyshev distance 2 of any stone.
  List<int> _collectNeighborEmpties(Uint8List cells) {
    final marked = Uint8List(kBoardCellCount);
    final result = <int>[];

    for (var i = 0; i < kBoardCellCount; i++) {
      if (cells[i] == 0) continue;
      final r = i ~/ kBoardSize;
      final c = i % kBoardSize;
      final rMin = r > 1 ? r - 2 : 0;
      final rMax = r < kBoardSize - 2 ? r + 2 : kBoardSize - 1;
      final cMin = c > 1 ? c - 2 : 0;
      final cMax = c < kBoardSize - 2 ? c + 2 : kBoardSize - 1;

      for (var nr = rMin; nr <= rMax; nr++) {
        final rowOffset = nr * kBoardSize;
        for (var nc = cMin; nc <= cMax; nc++) {
          final nIdx = rowOffset + nc;
          if (cells[nIdx] == 0 && marked[nIdx] == 0) {
            marked[nIdx] = 1;
            result.add(nIdx);
          }
        }
      }
    }
    return result;
  }
}
