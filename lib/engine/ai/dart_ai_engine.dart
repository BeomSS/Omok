import 'dart:math';
import 'dart:typed_data';

import '../model/board_state.dart';
import '../model/coordinate.dart';
import '../model/stone.dart';
import '../rules/renju_rule_engine.dart';
import '../rules/rule_engine.dart';
import 'ai_difficulty.dart';
import 'ai_engine.dart';
import 'opening_book.dart';
import 'pattern_evaluator.dart';
import 'vcf_solver.dart';
import 'zobrist_hash.dart';

/// Pure Dart offline Omok AI supporting 4 distinct difficulty tiers:
/// - **Beginner (초급)**: Depth-1 heuristic + weighted randomness among top moves.
/// - **Intermediate (중급)**: Shallow Alpha-Beta (depth 2, beam 7) + mild
///   human-like variety on quiet positional turns while still blocking open 3s/4s.
/// - **Advanced (고급)**: Iterative-deepening Alpha-Beta (depth 4–5) + Zobrist TT.
/// - **Expert (전문가)**: Opening book + VCF attack/defense solver (depth 14) +
///   Iterative-deepening Alpha-Beta (depth 6–8) + Zobrist TT.
class DartAiEngine implements AiEngine {
  DartAiEngine({
    Random? random,
    PatternEvaluator? evaluator,
    this.openingBook = const OpeningBook(),
  })  : _random = random ?? Random(),
        _customEvaluator = evaluator;

  final Random _random;
  final PatternEvaluator? _customEvaluator;
  final OpeningBook openingBook;
  final ZobristTable _tt = ZobristTable();

  PatternEvaluator _activeEvaluator = const PatternEvaluator(isRenju: true);
  PatternEvaluator get evaluator => _activeEvaluator;

  static const int _infinity = 100000000;
  static const int _mateScore = 50000000;

  @override
  Future<Coordinate> findBestMove({
    required BoardState board,
    required Stone aiStone,
    required AiDifficulty difficulty,
    required RuleEngine ruleEngine,
  }) async {
    return findBestMoveSync(
      board: board,
      aiStone: aiStone,
      difficulty: difficulty,
      ruleEngine: ruleEngine,
    );
  }

  /// Synchronous entry point used inside background Isolates and unit tests.
  Coordinate findBestMoveSync({
    required BoardState board,
    required Stone aiStone,
    required AiDifficulty difficulty,
    required RuleEngine ruleEngine,
    int? maxThinkMsOverride,
  }) {
    if (board.isEmpty) {
      return OpeningBook.center;
    }

    final isRenju = ruleEngine.ruleType == RuleType.renju;
    _activeEvaluator = _customEvaluator ?? PatternEvaluator(isRenju: isRenju);
    final renju = ruleEngine is RenjuRuleEngine ? ruleEngine : null;
    final thinkBudgetMs = (maxThinkMsOverride != null &&
            maxThinkMsOverride < difficulty.maxThinkMs)
        ? maxThinkMsOverride.clamp(120, difficulty.maxThinkMs)
        : difficulty.maxThinkMs;
    final cells = board.copyRawCells();
    final aiCode = aiStone.code;
    final oppCode = aiStone.opponent.code;

    // 1. Opening book for early plies (Advanced & Expert, and move 2 for all).
    if (board.moveCount <= 2 ||
        (board.moveCount <= 3 &&
            (difficulty == AiDifficulty.advanced ||
                difficulty == AiDifficulty.expert))) {
      final bookMove = openingBook.lookup(board, _random);
      if (bookMove != null &&
          !board.isOccupied(bookMove) &&
          !ruleEngine.isForbiddenMove(board, bookMove, aiStone)) {
        return bookMove;
      }
    }

    // 2. Collect all legal neighbor candidates sorted by immediate threat score.
    final ranked = _generateRankedCandidates(
      cells,
      aiCode,
      oppCode,
      renju: renju,
      radius: 2,
    );

    if (ranked.isEmpty) {
      return _findFirstLegalFallback(cells, aiCode, renju);
    }

    // 3. Immediate 5-in-a-row win: always play it across all difficulties!
    for (final (idx, _) in ranked) {
      if (evaluator.isImmediateWin(
        cells,
        idx ~/ kBoardSize,
        idx % kBoardSize,
        aiCode,
      )) {
        return Coordinate.fromIndex(idx);
      }
    }

    // 4. Immediate opponent 5-in-a-row defense: always block forced loss!
    final urgentBlocks = <int>[];
    for (final (idx, _) in ranked) {
      final r = idx ~/ kBoardSize;
      final c = idx % kBoardSize;
      // If opponent is Black and this spot is forbidden for Black, no threat!
      if (oppCode == Stone.black.code &&
          renju != null &&
          renju.checkForbiddenOnBuffer(cells, r, c).isForbidden) {
        continue;
      }
      if (evaluator.isImmediateWin(cells, r, c, oppCode)) {
        urgentBlocks.add(idx);
      }
    }
    if (urgentBlocks.length == 1) {
      return Coordinate.fromIndex(urgentBlocks.first);
    }

    // 5. Dispatch by difficulty tier.
    return switch (difficulty) {
      AiDifficulty.beginner => _chooseBeginnerMove(ranked, urgentBlocks),
      AiDifficulty.intermediate => _chooseIntermediateMove(
          cells: cells,
          aiCode: aiCode,
          oppCode: oppCode,
          renju: renju,
          rankedRoot: ranked,
          urgentBlocks: urgentBlocks,
          timeBudgetMs: thinkBudgetMs,
        ),
      AiDifficulty.advanced => _searchIterative(
          cells: cells,
          aiCode: aiCode,
          oppCode: oppCode,
          renju: renju,
          rankedRoot: ranked,
          urgentBlocks: urgentBlocks,
          maxDepth: 5,
          beamWidth: 14,
          timeBudgetMs: thinkBudgetMs,
          useTt: true,
        ),
      AiDifficulty.expert => _chooseExpertMove(
          cells: cells,
          aiCode: aiCode,
          oppCode: oppCode,
          renju: renju,
          rankedRoot: ranked,
          urgentBlocks: urgentBlocks,
          timeBudgetMs: thinkBudgetMs,
        ),
    };
  }

  /// Beginner: shallow tactical awareness with intentional weighted randomness
  /// so newcomers can build attacks and win.
  Coordinate _chooseBeginnerMove(
    List<(int, int)> ranked,
    List<int> urgentBlocks,
  ) {
    if (urgentBlocks.isNotEmpty) {
      return Coordinate.fromIndex(urgentBlocks.first);
    }

    // If AI has an open four or 4-3, take it 70% of the time; otherwise pick
    // weighted-randomly among top 5 moves.
    final poolSize = ranked.length < 5 ? ranked.length : 5;
    final top = ranked.sublist(0, poolSize);

    // Weighted selection favoring higher-ranked moves while allowing mistakes.
    const weights = [45, 25, 15, 10, 5];
    var totalWeight = 0;
    for (var i = 0; i < top.length; i++) {
      totalWeight += weights[i];
    }
    var roll = _random.nextInt(totalWeight);
    for (var i = 0; i < top.length; i++) {
      roll -= weights[i];
      if (roll < 0) {
        return Coordinate.fromIndex(top[i].$1);
      }
    }
    return Coordinate.fromIndex(top.first.$1);
  }

  /// Intermediate: depth-2 Alpha-Beta with narrower beam (7) and occasional
  /// 2nd-best move selection on quiet turns. Always responds accurately to
  /// immediate open 3 / 4 threats so it feels natural yet beatable with setups.
  Coordinate _chooseIntermediateMove({
    required Uint8List cells,
    required int aiCode,
    required int oppCode,
    required RenjuRuleEngine? renju,
    required List<(int, int)> rankedRoot,
    required List<int> urgentBlocks,
    required int timeBudgetMs,
  }) {
    if (urgentBlocks.isNotEmpty) {
      return Coordinate.fromIndex(urgentBlocks.first);
    }

    // Check if there is an active tactical threat (open 3 / closed 4 or higher).
    final hasTacticalThreat =
        rankedRoot.first.$2 >= PatternEvaluator.openThreeScore;

    // On quiet turns (no urgent 3/4 threats), occasionally pick the 2nd-best
    // candidate move (~25%) to give human players realistic tactical openings.
    if (!hasTacticalThreat && rankedRoot.length >= 2 && _random.nextInt(100) < 25) {
      return Coordinate.fromIndex(rankedRoot[1].$1);
    }

    return _searchIterative(
      cells: cells,
      aiCode: aiCode,
      oppCode: oppCode,
      renju: renju,
      rankedRoot: rankedRoot,
      urgentBlocks: urgentBlocks,
      maxDepth: 2,
      beamWidth: 7,
      timeBudgetMs: timeBudgetMs,
      useTt: false,
    );
  }

  /// Expert: VCF winning attack -> VCF defense filtering -> deep Iterative
  /// Deepening Alpha-Beta with Zobrist TT.
  Coordinate _chooseExpertMove({
    required Uint8List cells,
    required int aiCode,
    required int oppCode,
    required RenjuRuleEngine? renju,
    required List<(int, int)> rankedRoot,
    required List<int> urgentBlocks,
    required int timeBudgetMs,
  }) {
    final stopwatch = Stopwatch()..start();
    final vcf = VcfSolver(evaluator: evaluator, renjuRules: renju);

    // A. Check if AI has a forced VCF win (up to 14 plies).
    final vcfWinIdx = vcf.findWinningMove(
      cells,
      aiCode,
      maxDepth: 14,
      timeBudgetMs: 320,
    );
    if (vcfWinIdx != -1) {
      return Coordinate.fromIndex(vcfWinIdx);
    }

    // B. Check if opponent currently threatens a forced VCF win (shallow 10-ply
    // check so we can prioritize moves that refute it).
    var candidateRoot = rankedRoot;
    if (urgentBlocks.isEmpty) {
      final oppVcfIdx = vcf.findWinningMove(
        cells,
        oppCode,
        maxDepth: 10,
        timeBudgetMs: 180,
        maxNodes: 2500,
      );
      if (oppVcfIdx != -1) {
        // Test top candidate moves to find ones that stop opponent's VCF.
        final refutations = <(int, int)>[];
        final testLimit = rankedRoot.length < 12 ? rankedRoot.length : 12;
        for (var i = 0; i < testLimit; i++) {
          final (idx, score) = rankedRoot[i];
          cells[idx] = aiCode;
          final stillHasVcf = vcf.findWinningMove(
                cells,
                oppCode,
                maxDepth: 10,
                timeBudgetMs: 40,
                maxNodes: 1000,
              ) !=
              -1;
          cells[idx] = 0;
          if (!stillHasVcf) {
            refutations.add((idx, score));
          }
          if (stopwatch.elapsedMilliseconds > 700) break;
        }
        if (refutations.isNotEmpty) {
          candidateRoot = refutations;
        }
      }
    }

    final remainingMs =
        (timeBudgetMs - stopwatch.elapsedMilliseconds).clamp(300, timeBudgetMs);

    return _searchIterative(
      cells: cells,
      aiCode: aiCode,
      oppCode: oppCode,
      renju: renju,
      rankedRoot: candidateRoot,
      urgentBlocks: urgentBlocks,
      maxDepth: 6,
      beamWidth: 16,
      timeBudgetMs: remainingMs,
      useTt: true,
    );
  }

  /// Iterative-deepening Negamax Alpha-Beta with optional Zobrist TT.
  Coordinate _searchIterative({
    required Uint8List cells,
    required int aiCode,
    required int oppCode,
    required RenjuRuleEngine? renju,
    required List<(int, int)> rankedRoot,
    required List<int> urgentBlocks,
    required int maxDepth,
    required int beamWidth,
    required int timeBudgetMs,
    required bool useTt,
  }) {
    if (useTt) {
      _tt.clear();
    }

    final stopwatch = Stopwatch()..start();
    final rootCandidates = urgentBlocks.isNotEmpty
        ? urgentBlocks
        : rankedRoot
            .take(beamWidth)
            .map((e) => e.$1)
            .toList(growable: true);

    var bestMoveIdx = rootCandidates.first;
    final rootHash = useTt ? _tt.computeHash(cells, aiCode) : 0;

    final ctx = _SearchContext(
      cells: cells,
      aiCode: aiCode,
      renju: renju,
      beamWidth: beamWidth,
      useTt: useTt,
      stopwatch: stopwatch,
      timeBudgetMs: timeBudgetMs,
    );

    // Search progressively: depth 2, 3, ..., maxDepth.
    for (var depth = 2; depth <= maxDepth; depth++) {
      ctx.timedOut = false;
      var currentBestIdx = rootCandidates.first;
      var bestScore = -_infinity;
      var alpha = -_infinity;
      const beta = _infinity;

      // Put previous iteration's best move first for PV move ordering.
      final pvPos = rootCandidates.indexOf(bestMoveIdx);
      if (pvPos > 0) {
        rootCandidates.removeAt(pvPos);
        rootCandidates.insert(0, bestMoveIdx);
      }

      for (final idx in rootCandidates) {
        final r = idx ~/ kBoardSize;
        final c = idx % kBoardSize;

        cells[idx] = aiCode;
        int score;
        if (evaluator.isImmediateWin(cells, r, c, aiCode)) {
          score = _mateScore + depth;
        } else {
          final nextHash = useTt
              ? _tt.toggleTurn(_tt.toggleStone(rootHash, idx, aiCode))
              : 0;
          score = -_negamax(
            ctx: ctx,
            depth: depth - 1,
            alpha: -beta,
            beta: -alpha,
            turnCode: oppCode,
            hash: nextHash,
          );
        }
        cells[idx] = 0;

        if (ctx.timedOut) break;

        if (score > bestScore) {
          bestScore = score;
          currentBestIdx = idx;
        }
        if (score > alpha) {
          alpha = score;
        }
        if (score >= _mateScore) {
          // Proven forced win found at this depth!
          return Coordinate.fromIndex(currentBestIdx);
        }
      }

      if (!ctx.timedOut) {
        bestMoveIdx = currentBestIdx;
      } else {
        break;
      }

      if (stopwatch.elapsedMilliseconds >= timeBudgetMs * 7 ~/ 10) {
        break;
      }
    }

    return Coordinate.fromIndex(bestMoveIdx);
  }

  int _negamax({
    required _SearchContext ctx,
    required int depth,
    required int alpha,
    required int beta,
    required int turnCode,
    required int hash,
  }) {
    ctx.nodes++;
    if ((ctx.nodes & 255) == 0 &&
        ctx.stopwatch.elapsedMilliseconds >= ctx.timeBudgetMs) {
      ctx.timedOut = true;
      return 0;
    }

    final originalAlpha = alpha;
    var ttBestMove = -1;

    if (ctx.useTt) {
      final entry = _tt.probe(hash);
      if (entry != null) {
        ttBestMove = entry.bestMoveIdx;
        if (entry.depth >= depth) {
          if (entry.flag == TtFlag.exact) {
            return entry.score;
          } else if (entry.flag == TtFlag.lowerBound && entry.score > alpha) {
            alpha = entry.score;
          } else if (entry.flag == TtFlag.upperBound && entry.score < beta) {
            beta = entry.score;
          }
          if (alpha >= beta) {
            return entry.score;
          }
        }
      }
    }

    if (depth <= 0) {
      return evaluator.evaluateBoard(ctx.cells, turnCode, turnCode);
    }

    final oppCode =
        turnCode == Stone.black.code ? Stone.white.code : Stone.black.code;

    final ranked = _generateRankedCandidates(
      ctx.cells,
      turnCode,
      oppCode,
      renju: ctx.renju,
      radius: 2,
      pvMoveIdx: ttBestMove,
    );

    if (ranked.isEmpty) {
      return 0; // Draw / no legal moves
    }

    // Immediate tactical win shortcut.
    final firstIdx = ranked.first.$1;
    if (evaluator.isImmediateWin(
      ctx.cells,
      firstIdx ~/ kBoardSize,
      firstIdx % kBoardSize,
      turnCode,
    )) {
      return _mateScore + depth;
    }

    // Narrow beam slightly at deeper plies to keep search crisp.
    final limit = depth >= 3 ? ctx.beamWidth : (ctx.beamWidth * 3 ~/ 4);
    final count = ranked.length < limit ? ranked.length : limit;

    var bestScore = -_infinity;
    var bestMoveIdx = ranked.first.$1;

    for (var i = 0; i < count; i++) {
      final idx = ranked[i].$1;
      final r = idx ~/ kBoardSize;
      final c = idx % kBoardSize;

      ctx.cells[idx] = turnCode;
      int score;
      if (evaluator.isImmediateWin(ctx.cells, r, c, turnCode)) {
        score = _mateScore + depth;
      } else {
        final nextHash = ctx.useTt
            ? _tt.toggleTurn(_tt.toggleStone(hash, idx, turnCode))
            : 0;
        score = -_negamax(
          ctx: ctx,
          depth: depth - 1,
          alpha: -beta,
          beta: -alpha,
          turnCode: oppCode,
          hash: nextHash,
        );
      }
      ctx.cells[idx] = 0;

      if (ctx.timedOut) return 0;

      if (score > bestScore) {
        bestScore = score;
        bestMoveIdx = idx;
      }
      if (score > alpha) {
        alpha = score;
      }
      if (alpha >= beta) {
        break; // Beta cutoff
      }
    }

    if (ctx.useTt) {
      final TtFlag flag;
      if (bestScore <= originalAlpha) {
        flag = TtFlag.upperBound;
      } else if (bestScore >= beta) {
        flag = TtFlag.lowerBound;
      } else {
        flag = TtFlag.exact;
      }
      _tt.store(
        hash: hash,
        depth: depth,
        score: bestScore,
        flag: flag,
        bestMoveIdx: bestMoveIdx,
      );
    }

    return bestScore;
  }

  /// Generates all legal empty intersections within [radius] of existing stones,
  /// scored and sorted descending by combined offensive + defensive priority.
  List<(int, int)> _generateRankedCandidates(
    Uint8List cells,
    int myCode,
    int oppCode, {
    required RenjuRuleEngine? renju,
    required int radius,
    int pvMoveIdx = -1,
  }) {
    final marked = Uint8List(kBoardCellCount);
    final rawCandidates = <int>[];

    for (var i = 0; i < kBoardCellCount; i++) {
      if (cells[i] == 0) continue;
      final r = i ~/ kBoardSize;
      final c = i % kBoardSize;
      final rMin = r > radius ? r - radius : 0;
      final rMax = r < kBoardSize - 1 - radius ? r + radius : kBoardSize - 1;
      final cMin = c > radius ? c - radius : 0;
      final cMax = c < kBoardSize - 1 - radius ? c + radius : kBoardSize - 1;

      for (var nr = rMin; nr <= rMax; nr++) {
        final rowOffset = nr * kBoardSize;
        for (var nc = cMin; nc <= cMax; nc++) {
          final nIdx = rowOffset + nc;
          if (cells[nIdx] == 0 && marked[nIdx] == 0) {
            marked[nIdx] = 1;
            rawCandidates.add(nIdx);
          }
        }
      }
    }

    final scored = <(int, int)>[];
    for (final idx in rawCandidates) {
      final r = idx ~/ kBoardSize;
      final c = idx % kBoardSize;

      // Enforce Renju forbidden moves when current player is Black.
      if (myCode == Stone.black.code &&
          renju != null &&
          renju.checkForbiddenOnBuffer(cells, r, c).isForbidden) {
        continue;
      }

      final attack = evaluator.evaluatePoint(cells, r, c, myCode);
      // Do not count opponent's threat on a spot that is forbidden for Black.
      final oppForbidden = oppCode == Stone.black.code &&
          renju != null &&
          renju.checkForbiddenOnBuffer(cells, r, c).isForbidden;
      final defense = oppForbidden
          ? 0
          : evaluator.evaluatePoint(cells, r, c, oppCode).score;

      var combined = (attack.score * 11 ~/ 10) + defense;
      if (idx == pvMoveIdx) {
        combined += 500000; // Prioritize Transposition Table PV move.
      }
      scored.add((idx, combined));
    }

    scored.sort((a, b) => b.$2.compareTo(a.$2));
    return scored;
  }

  Coordinate _findFirstLegalFallback(
    Uint8List cells,
    int myCode,
    RenjuRuleEngine? renju,
  ) {
    for (var i = 0; i < kBoardCellCount; i++) {
      if (cells[i] != 0) continue;
      final r = i ~/ kBoardSize;
      final c = i % kBoardSize;
      if (myCode == Stone.black.code &&
          renju != null &&
          renju.checkForbiddenOnBuffer(cells, r, c).isForbidden) {
        continue;
      }
      return Coordinate(r, c);
    }
    throw StateError('No legal moves available on the board.');
  }
}

class _SearchContext {
  _SearchContext({
    required this.cells,
    required this.aiCode,
    required this.renju,
    required this.beamWidth,
    required this.useTt,
    required this.stopwatch,
    required this.timeBudgetMs,
  });

  final Uint8List cells;
  final int aiCode;
  final RenjuRuleEngine? renju;
  final int beamWidth;
  final bool useTt;
  final Stopwatch stopwatch;
  final int timeBudgetMs;

  int nodes = 0;
  bool timedOut = false;
}
