import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// Breakpoints and layout sizing helpers for phone vs tablet portrait/landscape.
class ResponsiveLayout {
  const ResponsiveLayout._();

  /// Standard Material breakpoint separating phones from tablets.
  static const double tabletShortestSide = 600;

  /// Width threshold for side-by-side landscape layouts on tablets.
  static const double sideBySideMinWidth = 760;

  /// Hard visual caps so the 15x15 Omok board stays crisp and comfortable to
  /// reach even on 12.9-inch iPads or large Android tablets.
  static const double maxBoardPortraitPhone = 480;
  static const double maxBoardPortraitTablet = 560;
  static const double maxBoardLandscapeTablet = 600;

  static const double modalSheetMaxWidth = 520;

  static bool isTablet(BuildContext context) =>
      MediaQuery.sizeOf(context).shortestSide >= tabletShortestSide;

  static bool isLandscape(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return size.width > size.height;
  }

  /// True when the screen is wide landscape (e.g., tablet landscape) and
  /// should place the board and controls side-by-side.
  static bool useSideBySideLayout(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return size.width >= sideBySideMinWidth && size.width > size.height;
  }

  /// Computes a well-proportioned square board dimension for the given viewport
  /// constraints so the board never feels cramped on phones or oversized on tablets.
  static double computeBoardExtent({
    required double maxWidth,
    required double maxHeight,
    required bool isTablet,
    required bool isSideBySide,
  }) {
    final rawFit = math.min(maxWidth, maxHeight);
    if (isSideBySide) {
      return math.min(rawFit * 0.96, maxBoardLandscapeTablet);
    }
    if (isTablet) {
      return math.min(
        math.min(maxWidth * 0.88, maxHeight * 0.96),
        maxBoardPortraitTablet,
      );
    }
    return math.min(rawFit, maxBoardPortraitPhone);
  }

  /// Applies platform orientation rules at app startup:
  /// - Phones (`shortestSide < 600dp`): Portrait-only.
  /// - Tablets (`shortestSide >= 600dp`): Portrait & Landscape (all 4).
  static Future<void> applyDeviceOrientationPolicy() async {
    final view = ui.PlatformDispatcher.instance.implicitView;
    if (view == null) return;

    final logicalSize = view.physicalSize / view.devicePixelRatio;
    final isTabletDevice = logicalSize.shortestSide >= tabletShortestSide;

    if (isTabletDevice) {
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
      ]);
    }
  }
}
