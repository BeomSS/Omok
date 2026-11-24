import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/app_settings.dart';
import '../../data/models/difficulty_stats.dart';
import '../../data/models/match_rules.dart';
import '../../data/models/saved_match.dart';
import '../../data/repositories/local_storage_repository.dart';
import '../../engine/engine.dart';
import '../services/sound_service.dart';

/// Factory signature for creating AI move sources with rule and timer context.
typedef AiMoveSourceFactory = MoveSource Function({
  required Stone aiStone,
  required AiDifficulty difficulty,
  required RuleType ruleType,
  int? turnTimeLimitSeconds,
});

/// Injected at app startup via [ProviderScope.overrides].
final storageRepositoryProvider = Provider<LocalStorageRepository>(
  (ref) => throw UnimplementedError(
    'storageRepositoryProvider must be overridden in ProviderScope.',
  ),
);

/// Random source for stone assignment (overridable in deterministic tests).
final randomProvider = Provider<Random>((ref) => Random());

/// Offline sound service (disposed cleanly with ProviderContainer).
final soundServiceProvider = Provider<SoundService>((ref) {
  final service = AudioPlayerSoundService();
  ref.onDispose(service.dispose);
  return service;
});

/// Factory creating a [MoveSource] for the AI player. Defaults to
/// [IsolateAiRunner] in production; overridable in widget tests.
final aiMoveSourceFactoryProvider = Provider<AiMoveSourceFactory>(
  (ref) => ({
    required aiStone,
    required difficulty,
    required ruleType,
    turnTimeLimitSeconds,
  }) =>
      IsolateAiRunner(
        aiStone: aiStone,
        difficulty: difficulty,
        ruleType: ruleType,
        turnTimeLimitSeconds: turnTimeLimitSeconds,
      ),
);

/// Reactive user convenience/display settings backed by [LocalStorageRepository].
final settingsProvider =
    NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() {
    return ref.watch(storageRepositoryProvider).loadSettings();
  }

  Future<void> update(AppSettings next) async {
    state = next;
    await ref.read(storageRepositoryProvider).saveSettings(next);
  }

  Future<void> toggleConfirmBeforePlace(bool value) =>
      update(state.copyWith(confirmBeforePlace: value));

  Future<void> toggleShowForbiddenMarkers(bool value) =>
      update(state.copyWith(showForbiddenMarkers: value));

  Future<void> toggleShowCoordinates(bool value) =>
      update(state.copyWith(showCoordinates: value));

  Future<void> toggleShowMoveNumbers(bool value) =>
      update(state.copyWith(showMoveNumbers: value));

  Future<void> toggleSoundEnabled(bool value) =>
      update(state.copyWith(soundEnabled: value));

  Future<void> toggleHapticEnabled(bool value) =>
      update(state.copyWith(hapticEnabled: value));
}

/// Reactive match rules (Renju/Freestyle, Turn Time Limit, Undo Limit).
final matchRulesProvider =
    NotifierProvider<MatchRulesNotifier, MatchRules>(MatchRulesNotifier.new);

class MatchRulesNotifier extends Notifier<MatchRules> {
  @override
  MatchRules build() {
    return ref.watch(storageRepositoryProvider).loadMatchRules();
  }

  Future<void> update(MatchRules next) async {
    state = next;
    await ref.read(storageRepositoryProvider).saveMatchRules(next);
  }

  Future<void> setRuleType(RuleType ruleType) =>
      update(state.copyWith(ruleType: ruleType));

  Future<void> toggleTimeLimit(bool enabled) =>
      update(state.copyWith(useTimeLimit: enabled));

  Future<void> setTurnTimeLimitSeconds(int seconds) =>
      update(state.copyWith(turnTimeLimitSeconds: seconds));

  Future<void> setUndoLimit(UndoLimit limit) =>
      update(state.copyWith(undoLimit: limit));
}

/// Per-difficulty win/loss/draw statistics stored offline.
final statsProvider =
    NotifierProvider<StatsNotifier, Map<AiDifficulty, DifficultyStats>>(
  StatsNotifier.new,
);

class StatsNotifier extends Notifier<Map<AiDifficulty, DifficultyStats>> {
  @override
  Map<AiDifficulty, DifficultyStats> build() {
    return ref.watch(storageRepositoryProvider).loadAllStats();
  }

  Future<void> recordResult({
    required AiDifficulty difficulty,
    required GameStatus status,
    required Stone humanStone,
  }) async {
    if (!status.isFinished) return;
    final current = state[difficulty] ?? const DifficultyStats();
    final DifficultyStats updated;
    if (status == GameStatus.draw) {
      updated = current.recordDraw();
    } else if (status.winner == humanStone) {
      updated = current.recordWin();
    } else {
      updated = current.recordLoss();
    }

    final nextMap = {...state, difficulty: updated};
    state = nextMap;
    await ref.read(storageRepositoryProvider).saveAllStats(nextMap);
  }

  Future<void> resetAll() async {
    await ref.read(storageRepositoryProvider).clearStats();
    state = {
      for (final d in AiDifficulty.values) d: const DifficultyStats(),
    };
  }
}

/// Tracks the currently auto-saved unfinished match for Home screen "이어하기".
final savedMatchProvider =
    NotifierProvider<SavedMatchNotifier, SavedMatch?>(SavedMatchNotifier.new);

class SavedMatchNotifier extends Notifier<SavedMatch?> {
  @override
  SavedMatch? build() {
    return ref.watch(storageRepositoryProvider).loadSavedMatch();
  }

  Future<void> save(SavedMatch match) async {
    state = match;
    await ref.read(storageRepositoryProvider).saveMatch(match);
  }

  Future<void> clear() async {
    state = null;
    await ref.read(storageRepositoryProvider).clearSavedMatch();
  }
}
