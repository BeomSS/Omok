import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:omok/engine/engine.dart';

BoardState buildBoard({
  List<(int, int)> black = const [],
  List<(int, int)> white = const [],
}) {
  var board = BoardState.empty();
  for (final (r, c) in black) {
    board = board.placeStone(Coordinate(r, c), stone: Stone.black);
  }
  for (final (r, c) in white) {
    board = board.placeStone(Coordinate(r, c), stone: Stone.white);
  }
  return board;
}

void main() {
  const rules = RenjuRuleEngine();

  group('DartAiEngine tactical correctness', () {
    test('plays center H8 (7,7) on empty board', () {
      final ai = DartAiEngine(random: Random(42));
      for (final difficulty in AiDifficulty.values) {
        final move = ai.findBestMoveSync(
          board: BoardState.empty(),
          aiStone: Stone.black,
          difficulty: difficulty,
          ruleEngine: rules,
        );
        expect(move, const Coordinate(7, 7));
      }
    });

    test('takes immediate 5-in-a-row win across all difficulties', () {
      final board = buildBoard(
        black: [(7, 4), (7, 5), (7, 6), (7, 7)],
        white: [(6, 4), (6, 5), (6, 6), (7, 3)],
      );

      for (final difficulty in AiDifficulty.values) {
        final ai = DartAiEngine(random: Random(1));
        final move = ai.findBestMoveSync(
          board: board,
          aiStone: Stone.black,
          difficulty: difficulty,
          ruleEngine: rules,
        );
        expect(
          move,
          const Coordinate(7, 8),
          reason: '${difficulty.name} should finish exact 5',
        );
      }
    });

    test('blocks opponent immediate 4-in-a-row threat across all difficulties', () {
      final board = buildBoard(
        black: [(7, 4), (7, 5), (7, 6), (7, 7)],
        white: [(7, 3), (5, 5), (6, 6), (8, 8)],
      );

      for (final difficulty in AiDifficulty.values) {
        final ai = DartAiEngine(random: Random(2));
        final move = ai.findBestMoveSync(
          board: board,
          aiStone: Stone.white,
          difficulty: difficulty,
          ruleEngine: rules,
        );
        expect(
          move,
          const Coordinate(7, 8),
          reason: '${difficulty.name} should block opponent 4-in-a-row',
        );
      }
    });

    test('never plays a Renju forbidden 3-3 or 4-4 move as Black', () {
      // (7, 7) is a tempting 3-3 spot for Black — AI MUST avoid it.
      final board = buildBoard(
        black: [(7, 5), (7, 6), (5, 7), (6, 7)],
        white: [(8, 8), (8, 9), (6, 8), (9, 6)],
      );
      expect(
        rules.isForbiddenMove(board, const Coordinate(7, 7), Stone.black),
        isTrue,
      );

      for (final difficulty in AiDifficulty.values) {
        final ai = DartAiEngine(random: Random(3));
        final move = ai.findBestMoveSync(
          board: board,
          aiStone: Stone.black,
          difficulty: difficulty,
          ruleEngine: rules,
        );
        expect(
          rules.isForbiddenMove(board, move, Stone.black),
          isFalse,
          reason: '${difficulty.name} played forbidden move $move',
        );
      }
    });

    test('Intermediate/Advanced/Expert block opponent open 3', () {
      // Black has an unblocked open 3 on row 7: (7,6), (7,7), (7,8).
      // White must block at (7,5) or (7,9) (or (7,4)/(7,10) to contain).
      final board = buildBoard(
        black: [(7, 6), (7, 7), (7, 8)],
        white: [(5, 5), (9, 9), (6, 5)],
      );

      for (final difficulty in [
        AiDifficulty.intermediate,
        AiDifficulty.advanced,
        AiDifficulty.expert,
      ]) {
        final ai = DartAiEngine(random: Random(4));
        final move = ai.findBestMoveSync(
          board: board,
          aiStone: Stone.white,
          difficulty: difficulty,
          ruleEngine: rules,
        );
        expect(
          move == const Coordinate(7, 5) || move == const Coordinate(7, 9),
          isTrue,
          reason: '${difficulty.name} chose $move instead of blocking open 3',
        );
      }
    });
  });

  group('Expert VCF solver (multi-move forced continuous four)', () {
    test('finds 5-ply forced VCF win (closed 4 -> closed 4 -> open 4)', () {
      // Row 7: W(7,4), B(7,5), B(7,6), B(7,7) -> B(7,8) forces W(7,9)
      // Col 8: W(4,8), B(5,8), B(6,8) + B(7,8) -> B(8,8) forces W(9,8)
      // Row 8: B(8,9), B(8,10) + B(8,8) -> B(8,7) or B(8,11) makes unstoppable open 4!
      final board = buildBoard(
        black: [
          (7, 5), (7, 6), (7, 7),
          (5, 8), (6, 8),
          (8, 9), (8, 10),
        ],
        white: [
          (7, 4),
          (4, 8),
          (2, 2), (2, 3), (3, 2), (12, 12), (12, 11),
        ],
      );

      final solver = VcfSolver(evaluator: const PatternEvaluator());
      final vcfIdx = solver.findWinningMove(
        board.copyRawCells(),
        Stone.black.code,
        maxDepth: 14,
      );
      expect(vcfIdx, isNot(-1));
      expect(Coordinate.fromIndex(vcfIdx), const Coordinate(7, 8));

      final ai = DartAiEngine(random: Random(7));
      final expertMove = ai.findBestMoveSync(
        board: board,
        aiStone: Stone.black,
        difficulty: AiDifficulty.expert,
        ruleEngine: rules,
      );
      expect(expertMove, const Coordinate(7, 8));
    });
  });

  group('IsolateAiRunner & performance budgets', () {
    test('computes legal move in background Isolate', () async {
      final board = buildBoard(
        black: [(7, 7), (7, 8), (6, 7)],
        white: [(6, 6), (8, 8), (6, 8)],
      );

      final runner = IsolateAiRunner(
        aiStone: Stone.black,
        difficulty: AiDifficulty.intermediate,
        enforceMinDelay: false,
      );

      final move = await runner.nextMove(board);
      expect(move, isNotNull);
      expect(board.isOccupied(move!), isFalse);
      expect(rules.isForbiddenMove(board, move, Stone.black), isFalse);
    });

    test('cancel() aborts an in-flight Isolate cleanly and returns null', () async {
      final board = buildBoard(
        black: [(7, 7), (7, 8), (6, 7), (8, 6), (5, 8)],
        white: [(6, 6), (8, 8), (6, 8), (7, 6), (5, 7)],
      );

      final runner = IsolateAiRunner(
        aiStone: Stone.black,
        difficulty: AiDifficulty.expert,
        enforceMinDelay: true,
      );

      final futureMove = runner.nextMove(board);
      runner.cancel();
      final result = await futureMove;
      expect(result, isNull);
    });

    test('all 4 difficulties complete within time budget on mid-game board', () {
      final board = buildBoard(
        black: [(7, 7), (7, 8), (6, 7), (8, 6), (5, 8), (9, 7)],
        white: [(6, 6), (8, 8), (6, 8), (7, 6), (5, 7), (9, 8)],
      );

      for (final difficulty in AiDifficulty.values) {
        final ai = DartAiEngine(random: Random(10));
        final sw = Stopwatch()..start();
        final move = ai.findBestMoveSync(
          board: board,
          aiStone: Stone.black,
          difficulty: difficulty,
          ruleEngine: rules,
        );
        sw.stop();

        expect(board.isOccupied(move), isFalse);
        expect(rules.isForbiddenMove(board, move, Stone.black), isFalse);
        // Allow small slack above maxThinkMs for JIT test VM overhead.
        expect(
          sw.elapsedMilliseconds,
          lessThan(difficulty.maxThinkMs + 1000),
          reason: '${difficulty.name} took ${sw.elapsedMilliseconds}ms',
        );
      }
    });
  });
}
