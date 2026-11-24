/// User-configurable gameplay and board display preferences (stored offline).
class AppSettings {
  const AppSettings({
    this.confirmBeforePlace = true,
    this.showForbiddenMarkers = true,
    this.showCoordinates = true,
    this.showMoveNumbers = false,
    this.soundEnabled = true,
    this.hapticEnabled = true,
  });

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        confirmBeforePlace: json['confirmBeforePlace'] as bool? ?? true,
        showForbiddenMarkers: json['showForbiddenMarkers'] as bool? ?? true,
        showCoordinates: json['showCoordinates'] as bool? ?? true,
        showMoveNumbers: json['showMoveNumbers'] as bool? ?? false,
        soundEnabled: json['soundEnabled'] as bool? ?? true,
        hapticEnabled: json['hapticEnabled'] as bool? ?? true,
      );

  /// When true, tapping an intersection shows a preview stone first; tapping
  /// "착수 확정" (or tapping the same intersection again) commits the move.
  final bool confirmBeforePlace;

  /// Displays subtle `✕` markers on Renju forbidden spots during Black's turn.
  final bool showForbiddenMarkers;

  /// Displays A–O and 1–15 coordinate labels around the board perimeter.
  final bool showCoordinates;

  /// Displays move numbers (1, 2, 3...) inside stones during active play.
  final bool showMoveNumbers;

  /// Plays offline synthesized wood-click and match result sound effects.
  final bool soundEnabled;

  /// Triggers subtle haptic feedback when placing stones or finishing a game.
  final bool hapticEnabled;

  AppSettings copyWith({
    bool? confirmBeforePlace,
    bool? showForbiddenMarkers,
    bool? showCoordinates,
    bool? showMoveNumbers,
    bool? soundEnabled,
    bool? hapticEnabled,
  }) =>
      AppSettings(
        confirmBeforePlace: confirmBeforePlace ?? this.confirmBeforePlace,
        showForbiddenMarkers: showForbiddenMarkers ?? this.showForbiddenMarkers,
        showCoordinates: showCoordinates ?? this.showCoordinates,
        showMoveNumbers: showMoveNumbers ?? this.showMoveNumbers,
        soundEnabled: soundEnabled ?? this.soundEnabled,
        hapticEnabled: hapticEnabled ?? this.hapticEnabled,
      );

  Map<String, dynamic> toJson() => {
        'confirmBeforePlace': confirmBeforePlace,
        'showForbiddenMarkers': showForbiddenMarkers,
        'showCoordinates': showCoordinates,
        'showMoveNumbers': showMoveNumbers,
        'soundEnabled': soundEnabled,
        'hapticEnabled': hapticEnabled,
      };
}
