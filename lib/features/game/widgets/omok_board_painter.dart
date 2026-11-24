import 'package:material_ui/material_ui.dart';

import '../../../engine/engine.dart';
import '../../../shared/theme/app_theme.dart';

/// Custom 2D canvas painter for a classic 15x15 kaya-wood Omok board with
/// stone placement animation, move numbers, hint highlight, and Renju markers.
class OmokBoardPainter extends CustomPainter {
  const OmokBoardPainter({
    required this.board,
    required this.humanStone,
    required this.showCoordinates,
    required this.showForbiddenMarkers,
    required this.showMoveNumbers,
    required this.forbiddenMoves,
    this.pendingMove,
    this.hintMove,
    this.winningLine = const [],
    this.lastMoveProgress = 1.0,
  });

  final BoardState board;
  final Stone humanStone;
  final bool showCoordinates;
  final bool showForbiddenMarkers;
  final bool showMoveNumbers;
  final Map<Coordinate, ForbiddenReason> forbiddenMoves;
  final Coordinate? pendingMove;
  final Coordinate? hintMove;
  final List<Coordinate> winningLine;

  /// Animation progress `[0.0, 1.0]` for the most recently placed stone.
  final double lastMoveProgress;

  static const Color _hintTeal = Color(0xFF00897B);

  static const List<(int, int)> _starPoints = [
    (3, 3),
    (3, 11),
    (7, 7),
    (11, 3),
    (11, 11),
  ];

  /// Computes grid geometry shared between painting and touch hit-testing.
  static BoardMetrics computeMetrics(Size size, {required bool showCoordinates}) {
    final side = size.shortestSide;
    final padding = showCoordinates ? side * 0.068 : side * 0.042;
    final gridSpan = side - (padding * 2);
    final cellSize = gridSpan / (kBoardSize - 1);
    final origin = Offset(
      (size.width - gridSpan) / 2,
      (size.height - gridSpan) / 2,
    );
    return BoardMetrics(
      origin: origin,
      gridSpan: gridSpan,
      cellSize: cellSize,
      padding: padding,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final metrics = computeMetrics(size, showCoordinates: showCoordinates);
    final boardRect = Rect.fromLTWH(0, 0, size.width, size.height);
    final rrect = RRect.fromRectAndRadius(boardRect, const Radius.circular(14));

    // 1. Wood surface gradient, grain, and inner bevel.
    final bgPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          AppTheme.boardWoodLight,
          AppTheme.boardWoodDark,
        ],
      ).createShader(boardRect);
    canvas.drawRRect(rrect, bgPaint);

    final grainPaint = Paint()
      ..color = AppTheme.boardBorder.withValues(alpha: 0.055)
      ..strokeWidth = 1.0;
    for (var y = 10.0; y < size.height; y += 13.0) {
      canvas.drawLine(Offset(6, y), Offset(size.width - 6, y), grainPaint);
    }

    // Top-left inner highlight for physical wooden slab feel.
    final highlightPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRRect(rrect.deflate(2.5), highlightPaint);

    final borderPaint = Paint()
      ..color = AppTheme.boardBorder.withValues(alpha: 0.65)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;
    canvas.drawRRect(rrect.deflate(1), borderPaint);

    // 2. Grid lines.
    final linePaint = Paint()
      ..color = AppTheme.boardGrid.withValues(alpha: 0.78)
      ..strokeWidth = 1.0;
    final outerLinePaint = Paint()
      ..color = AppTheme.boardGrid
      ..strokeWidth = 1.65;

    for (var i = 0; i < kBoardSize; i++) {
      final isEdge = i == 0 || i == kBoardSize - 1;
      final paint = isEdge ? outerLinePaint : linePaint;
      final offset = i * metrics.cellSize;

      canvas.drawLine(
        Offset(metrics.origin.dx, metrics.origin.dy + offset),
        Offset(metrics.origin.dx + metrics.gridSpan, metrics.origin.dy + offset),
        paint,
      );
      canvas.drawLine(
        Offset(metrics.origin.dx + offset, metrics.origin.dy),
        Offset(metrics.origin.dx + offset, metrics.origin.dy + metrics.gridSpan),
        paint,
      );
    }

    // 3. Five star points (화점).
    final starPaint = Paint()..color = AppTheme.boardGrid;
    final starRadius = (metrics.cellSize * 0.145).clamp(2.4, 4.2);
    for (final (r, c) in _starPoints) {
      canvas.drawCircle(metrics.centerOf(r, c), starRadius, starPaint);
    }

    // 4. Optional algebraic coordinates (A–O, 1–15).
    if (showCoordinates) {
      _paintCoordinates(canvas, metrics);
    }

    // 5. Pending move crosshair guide lines.
    if (pendingMove != null) {
      final center = metrics.centerOf(pendingMove!.row, pendingMove!.col);
      final guidePaint = Paint()
        ..color = AppTheme.accentWood.withValues(alpha: 0.45)
        ..strokeWidth = 1.4;
      canvas.drawLine(
        Offset(metrics.origin.dx, center.dy),
        Offset(metrics.origin.dx + metrics.gridSpan, center.dy),
        guidePaint,
      );
      canvas.drawLine(
        Offset(center.dx, metrics.origin.dy),
        Offset(center.dx, metrics.origin.dy + metrics.gridSpan),
        guidePaint,
      );
    }

    // 6. Renju forbidden markers (✕) on Black's turn.
    if (showForbiddenMarkers &&
        board.nextTurn == Stone.black &&
        forbiddenMoves.isNotEmpty) {
      _paintForbiddenMarkers(canvas, metrics);
    }

    // 7. AI Hint target highlight (drawn underneath preview if overlapping).
    final stoneRadius = metrics.cellSize * 0.44;
    if (hintMove != null && !board.isOccupied(hintMove!)) {
      _paintHintMarker(
        canvas,
        metrics.centerOf(hintMove!.row, hintMove!.col),
        stoneRadius,
      );
    }

    // 7b. Winning line connector underneath stones so move numbers stay clear.
    if (winningLine.length >= 5) {
      _paintWinningLineConnector(canvas, metrics);
    }

    // 8. Placed stones (with smooth drop-in & ripple on latest move).
    final last = board.lastMove;
    final moveNumberByIndex = showMoveNumbers
        ? {for (final m in board.history) m.coordinate.index: m.moveNumber}
        : const <int, int>{};

    for (var r = 0; r < kBoardSize; r++) {
      for (var c = 0; c < kBoardSize; c++) {
        final stone = board.stoneAtRowCol(r, c);
        if (stone == Stone.empty) continue;

        final center = metrics.centerOf(r, c);
        final isLast = last != null &&
            last.coordinate.row == r &&
            last.coordinate.col == c;

        if (isLast && lastMoveProgress < 1.0) {
          final t = Curves.easeOutCubic.transform(lastMoveProgress);
          final rippleAlpha = (1.0 - t) * 0.45;
          if (rippleAlpha > 0.01) {
            final ripplePaint = Paint()
              ..color = AppTheme.winGold.withValues(alpha: rippleAlpha)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.0 * (1.0 - t * 0.5);
            canvas.drawCircle(
              center,
              stoneRadius * (0.95 + t * 0.72),
              ripplePaint,
            );
          }

          final scale = 1.24 - (0.24 * t);
          _paintStone(
            canvas,
            center,
            stoneRadius * scale,
            stone,
            opacity: 0.65 + (0.35 * t),
          );
        } else {
          _paintStone(canvas, center, stoneRadius, stone);
        }

        if (showMoveNumbers) {
          final number = moveNumberByIndex[r * kBoardSize + c];
          if (number != null) {
            _paintMoveNumber(
              canvas,
              center,
              stoneRadius,
              number,
              stone,
              isLatest: isLast,
            );
          }
        }
      }
    }

    // 9. Last move ring (when move numbers are hidden and no winning line).
    if (last != null && winningLine.isEmpty && !showMoveNumbers) {
      final center = metrics.centerOf(last.coordinate.row, last.coordinate.col);
      final markerPaint = Paint()
        ..color = last.stone == Stone.black
            ? const Color(0xFFFFD54F)
            : const Color(0xFFD84315)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.1;
      canvas.drawCircle(center, stoneRadius * 0.42, markerPaint);
    }

    // 10. Ghost preview stone in 2-step confirmation mode.
    if (pendingMove != null) {
      final center = metrics.centerOf(pendingMove!.row, pendingMove!.col);
      _paintPreviewStone(canvas, center, stoneRadius, humanStone);
    }

    // 11. Winning stone halo highlights.
    if (winningLine.length >= 5) {
      _paintWinningStoneHalos(canvas, metrics, stoneRadius);
    }
  }

  void _paintCoordinates(Canvas canvas, BoardMetrics metrics) {
    final fontSize = (metrics.cellSize * 0.42).clamp(8.0, 11.5);
    final style = TextStyle(
      color: AppTheme.boardGrid.withValues(alpha: 0.72),
      fontSize: fontSize,
      fontWeight: FontWeight.w600,
    );

    final labelOffset = metrics.padding * 0.56;
    for (var i = 0; i < kBoardSize; i++) {
      final colChar = String.fromCharCode('A'.codeUnitAt(0) + i);
      final colTp = TextPainter(
        text: TextSpan(text: colChar, style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      final x = metrics.origin.dx + i * metrics.cellSize - colTp.width / 2;
      colTp.paint(
        canvas,
        Offset(
          x,
          metrics.origin.dy + metrics.gridSpan + labelOffset - colTp.height / 2,
        ),
      );

      final rowText = '${kBoardSize - i}';
      final rowTp = TextPainter(
        text: TextSpan(text: rowText, style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      final y = metrics.origin.dy + i * metrics.cellSize - rowTp.height / 2;
      rowTp.paint(
        canvas,
        Offset(metrics.origin.dx - labelOffset - rowTp.width / 2, y),
      );
    }
  }

  void _paintForbiddenMarkers(Canvas canvas, BoardMetrics metrics) {
    final crossHalf = metrics.cellSize * 0.22;
    final paint = Paint()
      ..color = AppTheme.forbiddenCrimson.withValues(alpha: 0.8)
      ..strokeWidth = 1.85
      ..strokeCap = StrokeCap.round;

    for (final coord in forbiddenMoves.keys) {
      final center = metrics.centerOf(coord.row, coord.col);
      canvas.drawLine(
        Offset(center.dx - crossHalf, center.dy - crossHalf),
        Offset(center.dx + crossHalf, center.dy + crossHalf),
        paint,
      );
      canvas.drawLine(
        Offset(center.dx + crossHalf, center.dy - crossHalf),
        Offset(center.dx - crossHalf, center.dy + crossHalf),
        paint,
      );
    }
  }

  void _paintHintMarker(Canvas canvas, Offset center, double radius) {
    final fillPaint = Paint()..color = _hintTeal.withValues(alpha: 0.22);
    canvas.drawCircle(center, radius * 0.92, fillPaint);

    final ringPaint = Paint()
      ..color = _hintTeal
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4;
    canvas.drawCircle(center, radius * 0.92, ringPaint);

    final dotPaint = Paint()..color = _hintTeal;
    canvas.drawCircle(center, radius * 0.24, dotPaint);
  }

  void _paintStone(
    Canvas canvas,
    Offset center,
    double radius,
    Stone stone, {
    double opacity = 1.0,
  }) {
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.28 * opacity)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.2);
    canvas.drawCircle(
      center + Offset(radius * 0.1, radius * 0.14),
      radius * 0.96,
      shadowPaint,
    );

    final rect = Rect.fromCircle(center: center, radius: radius);
    if (stone == Stone.black) {
      final paint = Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.35),
          radius: 0.85,
          colors: [
            const Color(0xFF575757).withValues(alpha: opacity),
            const Color(0xFF1A1A1A).withValues(alpha: opacity),
            const Color(0xFF070707).withValues(alpha: opacity),
          ],
          stops: const [0.0, 0.45, 1.0],
        ).createShader(rect);
      canvas.drawCircle(center, radius, paint);
    } else {
      final paint = Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.35),
          radius: 0.9,
          colors: [
            const Color(0xFFFFFFFF).withValues(alpha: opacity),
            const Color(0xFFF3EFE6).withValues(alpha: opacity),
            const Color(0xFFD2CCC0).withValues(alpha: opacity),
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(rect);
      canvas.drawCircle(center, radius, paint);

      final rimPaint = Paint()
        ..color = Colors.black.withValues(alpha: 0.18 * opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.85;
      canvas.drawCircle(center, radius, rimPaint);
    }
  }

  void _paintMoveNumber(
    Canvas canvas,
    Offset center,
    double stoneRadius,
    int number,
    Stone stone, {
    required bool isLatest,
  }) {
    final fontSize = number >= 100
        ? (stoneRadius * 0.72).clamp(7.0, 10.5)
        : (stoneRadius * 0.88).clamp(8.0, 12.0);
    final Color textColor;
    if (isLatest) {
      textColor = stone == Stone.black
          ? const Color(0xFFFFD54F)
          : const Color(0xFFD84315);
    } else {
      textColor = stone == Stone.black
          ? Colors.white.withValues(alpha: 0.92)
          : AppTheme.inkPrimary;
    }

    final tp = TextPainter(
      text: TextSpan(
        text: '$number',
        style: TextStyle(
          color: textColor,
          fontSize: fontSize,
          fontWeight: isLatest ? FontWeight.w900 : FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));
  }

  void _paintPreviewStone(
    Canvas canvas,
    Offset center,
    double radius,
    Stone stone,
  ) {
    final fillColor = stone == Stone.black
        ? Colors.black.withValues(alpha: 0.48)
        : Colors.white.withValues(alpha: 0.72);
    canvas.drawCircle(center, radius, Paint()..color = fillColor);

    final ringPaint = Paint()
      ..color = AppTheme.winGold
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;
    canvas.drawCircle(center, radius + 1.5, ringPaint);
  }

  void _paintWinningLineConnector(Canvas canvas, BoardMetrics metrics) {
    final first = metrics.centerOf(winningLine.first.row, winningLine.first.col);
    final last = metrics.centerOf(winningLine.last.row, winningLine.last.col);

    final linePaint = Paint()
      ..color = AppTheme.winGold.withValues(alpha: 0.92)
      ..strokeWidth = 4.6
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(first, last, linePaint);
  }

  void _paintWinningStoneHalos(
    Canvas canvas,
    BoardMetrics metrics,
    double stoneRadius,
  ) {
    final haloPaint = Paint()
      ..color = AppTheme.winGold
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6;
    for (final coord in winningLine) {
      canvas.drawCircle(
        metrics.centerOf(coord.row, coord.col),
        stoneRadius * 1.06,
        haloPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant OmokBoardPainter oldDelegate) =>
      oldDelegate.board != board ||
      oldDelegate.humanStone != humanStone ||
      oldDelegate.showCoordinates != showCoordinates ||
      oldDelegate.showForbiddenMarkers != showForbiddenMarkers ||
      oldDelegate.showMoveNumbers != showMoveNumbers ||
      oldDelegate.forbiddenMoves != forbiddenMoves ||
      oldDelegate.pendingMove != pendingMove ||
      oldDelegate.hintMove != hintMove ||
      oldDelegate.winningLine != winningLine ||
      oldDelegate.lastMoveProgress != lastMoveProgress;
}

class BoardMetrics {
  const BoardMetrics({
    required this.origin,
    required this.gridSpan,
    required this.cellSize,
    required this.padding,
  });

  final Offset origin;
  final double gridSpan;
  final double cellSize;
  final double padding;

  Offset centerOf(int row, int col) => Offset(
        origin.dx + col * cellSize,
        origin.dy + row * cellSize,
      );

  /// Maps a local tap position on the board canvas to the nearest valid
  /// intersection, or `null` if the tap was far outside the grid.
  Coordinate? hitTest(Offset localPos) {
    final col = ((localPos.dx - origin.dx) / cellSize).round();
    final row = ((localPos.dy - origin.dy) / cellSize).round();
    if (row < 0 || row >= kBoardSize || col < 0 || col >= kBoardSize) {
      return null;
    }

    final center = centerOf(row, col);
    final dist = (localPos - center).distance;
    if (dist > cellSize * 0.52) {
      return null;
    }
    return Coordinate(row, col);
  }
}
