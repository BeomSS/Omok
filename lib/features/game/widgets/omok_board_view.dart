import 'package:material_ui/material_ui.dart';

import '../../../engine/engine.dart';
import 'omok_board_painter.dart';

/// Interactive 2D Omok board supporting pinch-to-zoom, panning, stone drop
/// animations, and precise intersection tap detection.
class OmokBoardView extends StatefulWidget {
  const OmokBoardView({
    super.key,
    required this.board,
    required this.humanStone,
    required this.showCoordinates,
    required this.showForbiddenMarkers,
    required this.showMoveNumbers,
    required this.forbiddenMoves,
    required this.transformationController,
    required this.onIntersectionTap,
    this.pendingMove,
    this.hintMove,
    this.winningLine = const [],
  });

  final BoardState board;
  final Stone humanStone;
  final bool showCoordinates;
  final bool showForbiddenMarkers;
  final bool showMoveNumbers;
  final Map<Coordinate, ForbiddenReason> forbiddenMoves;
  final TransformationController transformationController;
  final ValueChanged<Coordinate> onIntersectionTap;
  final Coordinate? pendingMove;
  final Coordinate? hintMove;
  final List<Coordinate> winningLine;

  @override
  State<OmokBoardView> createState() => _OmokBoardViewState();
}

class _OmokBoardViewState extends State<OmokBoardView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _dropController;

  @override
  void initState() {
    super.initState();
    _dropController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 165),
      value: 1.0,
    );
  }

  @override
  void didUpdateWidget(covariant OmokBoardView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Trigger smooth drop-in & ripple animation when a new stone is placed.
    if (widget.board.moveCount > oldWidget.board.moveCount) {
      _dropController.forward(from: 0.0);
    } else if (widget.board.moveCount != oldWidget.board.moveCount) {
      _dropController.value = 1.0;
    }
  }

  @override
  void dispose() {
    _dropController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.14),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: InteractiveViewer(
            transformationController: widget.transformationController,
            minScale: 1.0,
            maxScale: 2.4,
            boundaryMargin: const EdgeInsets.all(24),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final boardSize =
                    Size(constraints.maxWidth, constraints.maxHeight);
                final metrics = OmokBoardPainter.computeMetrics(
                  boardSize,
                  showCoordinates: widget.showCoordinates,
                );

                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (details) {
                    final coord = metrics.hitTest(details.localPosition);
                    if (coord != null) {
                      widget.onIntersectionTap(coord);
                    }
                  },
                  child: AnimatedBuilder(
                    animation: _dropController,
                    builder: (context, _) {
                      return CustomPaint(
                        size: boardSize,
                        painter: OmokBoardPainter(
                          board: widget.board,
                          humanStone: widget.humanStone,
                          showCoordinates: widget.showCoordinates,
                          showForbiddenMarkers: widget.showForbiddenMarkers,
                          showMoveNumbers: widget.showMoveNumbers,
                          forbiddenMoves: widget.forbiddenMoves,
                          pendingMove: widget.pendingMove,
                          hintMove: widget.hintMove,
                          winningLine: widget.winningLine,
                          lastMoveProgress: _dropController.value,
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
