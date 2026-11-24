import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../engine/engine.dart';
import '../models/app_settings.dart';
import '../models/difficulty_stats.dart';
import '../models/match_rules.dart';
import '../models/saved_match.dart';

/// Offline storage contract for settings, match rules, per-difficulty stats,
/// and active match auto-save.
abstract class LocalStorageRepository {
  AppSettings loadSettings();
  Future<void> saveSettings(AppSettings settings);

  MatchRules loadMatchRules();
  Future<void> saveMatchRules(MatchRules rules);

  Map<AiDifficulty, DifficultyStats> loadAllStats();
  Future<void> saveAllStats(Map<AiDifficulty, DifficultyStats> stats);
  Future<void> clearStats();

  SavedMatch? loadSavedMatch();
  Future<void> saveMatch(SavedMatch match);
  Future<void> clearSavedMatch();
}

/// Offline [SharedPreferences]-backed implementation (works 100% in airplane mode).
class SharedPreferencesStorageRepository implements LocalStorageRepository {
  SharedPreferencesStorageRepository(this._prefs);

  static const String _settingsKey = 'omok_settings_v1';
  static const String _rulesKey = 'omok_match_rules_v1';
  static const String _statsKey = 'omok_stats_v1';
  static const String _savedMatchKey = 'omok_saved_match_v1';

  final SharedPreferences _prefs;

  @override
  AppSettings loadSettings() {
    final raw = _prefs.getString(_settingsKey);
    if (raw == null) return const AppSettings();
    try {
      return AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const AppSettings();
    }
  }

  @override
  Future<void> saveSettings(AppSettings settings) async {
    await _prefs.setString(_settingsKey, jsonEncode(settings.toJson()));
  }

  @override
  MatchRules loadMatchRules() {
    final raw = _prefs.getString(_rulesKey);
    if (raw == null) return const MatchRules();
    try {
      return MatchRules.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const MatchRules();
    }
  }

  @override
  Future<void> saveMatchRules(MatchRules rules) async {
    await _prefs.setString(_rulesKey, jsonEncode(rules.toJson()));
  }

  @override
  Map<AiDifficulty, DifficultyStats> loadAllStats() {
    final base = {
      for (final d in AiDifficulty.values) d: const DifficultyStats(),
    };
    final raw = _prefs.getString(_statsKey);
    if (raw == null) return base;

    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      for (final d in AiDifficulty.values) {
        final entry = decoded[d.name];
        if (entry is Map<String, dynamic>) {
          base[d] = DifficultyStats.fromJson(entry);
        }
      }
    } catch (_) {
      // Fall back to empty stats if corrupted.
    }
    return base;
  }

  @override
  Future<void> saveAllStats(Map<AiDifficulty, DifficultyStats> stats) async {
    final payload = {
      for (final entry in stats.entries) entry.key.name: entry.value.toJson(),
    };
    await _prefs.setString(_statsKey, jsonEncode(payload));
  }

  @override
  Future<void> clearStats() async {
    await _prefs.remove(_statsKey);
  }

  @override
  SavedMatch? loadSavedMatch() {
    final raw = _prefs.getString(_savedMatchKey);
    if (raw == null) return null;
    try {
      final match = SavedMatch.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      if (match.moveIndices.isEmpty) return null;
      return match;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveMatch(SavedMatch match) async {
    await _prefs.setString(_savedMatchKey, jsonEncode(match.toJson()));
  }

  @override
  Future<void> clearSavedMatch() async {
    await _prefs.remove(_savedMatchKey);
  }
}

/// Lightweight in-memory repository for widget & unit testing.
class InMemoryStorageRepository implements LocalStorageRepository {
  AppSettings _settings = const AppSettings();
  MatchRules _rules = const MatchRules();
  Map<AiDifficulty, DifficultyStats> _stats = {
    for (final d in AiDifficulty.values) d: const DifficultyStats(),
  };
  SavedMatch? _savedMatch;

  @override
  AppSettings loadSettings() => _settings;

  @override
  Future<void> saveSettings(AppSettings settings) async {
    _settings = settings;
  }

  @override
  MatchRules loadMatchRules() => _rules;

  @override
  Future<void> saveMatchRules(MatchRules rules) async {
    _rules = rules;
  }

  @override
  Map<AiDifficulty, DifficultyStats> loadAllStats() => Map.of(_stats);

  @override
  Future<void> saveAllStats(Map<AiDifficulty, DifficultyStats> stats) async {
    _stats = Map.of(stats);
  }

  @override
  Future<void> clearStats() async {
    _stats = {
      for (final d in AiDifficulty.values) d: const DifficultyStats(),
    };
  }

  @override
  SavedMatch? loadSavedMatch() => _savedMatch;

  @override
  Future<void> saveMatch(SavedMatch match) async {
    _savedMatch = match;
  }

  @override
  Future<void> clearSavedMatch() async {
    _savedMatch = null;
  }
}
