import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/difficulty_stats.dart';
import '../../data/models/match_rules.dart';
import '../../data/models/saved_match.dart';
import '../../engine/engine.dart';
import '../../l10n/app_strings.dart';
import '../../shared/layout/responsive_layout.dart';
import '../../shared/providers/app_providers.dart';
import '../../shared/theme/app_theme.dart';
import '../game/controller/game_controller.dart';
import '../game/controller/game_state.dart';
import '../game/game_screen.dart';
import '../multiplayer/nearby_lobby_screen.dart';
import '../settings/rule_settings_sheet.dart';
import '../settings/settings_sheet.dart';

/// Offline-first Home screen supporting AI matches, Local 2-Player (1 device),
/// and serverless Nearby Wi-Fi / Hotspot P2P multiplayer.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  GameMode _selectedMode = GameMode.vsAi;
  AiDifficulty _selectedDifficulty = AiDifficulty.intermediate;
  StonePreference _selectedPreference = StonePreference.black;

  void _startAiMatch() {
    final rules = ref.read(matchRulesProvider);
    ref.read(gameControllerProvider.notifier).startNewGame(
          difficulty: _selectedDifficulty,
          stonePreference: _selectedPreference,
          rules: rules,
        );
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const GameScreen()),
    );
  }

  void _startLocalTwoPlayer() {
    final rules = ref.read(matchRulesProvider);
    ref
        .read(gameControllerProvider.notifier)
        .startLocalTwoPlayerGame(rules: rules);
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const GameScreen()),
    );
  }

  void _resumeMatch(SavedMatch saved) {
    ref.read(gameControllerProvider.notifier).resumeMatch(saved);
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const GameScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final stats = ref.watch(statsProvider);
    final savedMatch = ref.watch(savedMatchProvider);
    final rules = ref.watch(matchRulesProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          s.appTitle,
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22),
        ),
        actions: [
          IconButton(
            tooltip: s.settingsTooltip,
            icon: const Icon(Icons.tune_rounded),
            onPressed: () => SettingsSheet.show(context),
          ),
        ],
      ),
      body: SafeArea(
        child: Builder(
          builder: (context) {
            final isTablet = ResponsiveLayout.isTablet(context);
            final isSideBySide = ResponsiveLayout.useSideBySideLayout(context);

            final leftOverview = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _HeroBanner(ruleType: rules.ruleType),
                const SizedBox(height: 16),
                _ModeSelectorBar(
                  selected: _selectedMode,
                  onChanged: (mode) => setState(() => _selectedMode = mode),
                ),
                if (_selectedMode == GameMode.vsAi && savedMatch != null) ...[
                  const SizedBox(height: 14),
                  _ResumeCard(
                    saved: savedMatch,
                    onResume: () => _resumeMatch(savedMatch),
                    onDiscard: () =>
                        ref.read(savedMatchProvider.notifier).clear(),
                  ),
                ],
                const SizedBox(height: 14),
                _RuleSummaryCard(
                  rules: rules,
                  onTap: () => RuleSettingsSheet.show(context),
                ),
              ],
            );

            final rightModeSetup = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_selectedMode == GameMode.vsAi) ...[
                  Text(
                    s.selectDifficultyTitle,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.inkPrimary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ...AiDifficulty.values.map(
                    (difficulty) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _DifficultyTile(
                        difficulty: difficulty,
                        stats: stats[difficulty] ?? const DifficultyStats(),
                        selected: _selectedDifficulty == difficulty,
                        onTap: () =>
                            setState(() => _selectedDifficulty = difficulty),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    s.selectStoneTitle,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.inkPrimary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _StoneChoiceCard(
                          preference: StonePreference.black,
                          title: s.stoneBlackTitle,
                          subtitle: s.stoneBlackSubtitle(rules.ruleType),
                          selected:
                              _selectedPreference == StonePreference.black,
                          onTap: () => setState(
                            () => _selectedPreference = StonePreference.black,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _StoneChoiceCard(
                          preference: StonePreference.white,
                          title: s.stoneWhiteTitle,
                          subtitle: s.stoneWhiteSubtitle,
                          selected:
                              _selectedPreference == StonePreference.white,
                          onTap: () => setState(
                            () => _selectedPreference = StonePreference.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _StoneChoiceCard(
                          preference: StonePreference.random,
                          title: s.stoneRandomTitle,
                          subtitle: s.stoneRandomSubtitle,
                          selected:
                              _selectedPreference == StonePreference.random,
                          onTap: () => setState(
                            () => _selectedPreference = StonePreference.random,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _startAiMatch,
                      icon: const Icon(Icons.play_arrow_rounded, size: 22),
                      label: Text(s.startAiMatchButton(_selectedDifficulty)),
                    ),
                  ),
                ] else if (_selectedMode == GameMode.localTwoPlayer) ...[
                  _LocalTwoPlayerPanel(
                    rules: rules,
                    onStart: _startLocalTwoPlayer,
                  ),
                ] else ...[
                  _NearbyP2pPanel(
                    rules: rules,
                    onHost: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => NearbyLobbyScreen(
                          initialRole: NearbyRole.host,
                          hostStonePreference: _selectedPreference,
                        ),
                      ),
                    ),
                    onJoin: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const NearbyLobbyScreen(
                          initialRole: NearbyRole.guest,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            );

            if (isSideBySide) {
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(28, 12, 28, 28),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 960),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 5, child: leftOverview),
                        const SizedBox(width: 24),
                        Expanded(flex: 6, child: rightModeSetup),
                      ],
                    ),
                  ),
                ),
              );
            }

            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                isTablet ? 28 : 20,
                8,
                isTablet ? 28 : 20,
                24,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: isTablet ? 580 : 520),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      leftOverview,
                      const SizedBox(height: 20),
                      rightModeSetup,
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ModeSelectorBar extends StatelessWidget {
  const _ModeSelectorBar({
    required this.selected,
    required this.onChanged,
  });

  final GameMode selected;
  final ValueChanged<GameMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTheme.warmCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppTheme.accentWood.withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        children: GameMode.values.map((mode) {
          final isSelected = mode == selected;
          final icon = switch (mode) {
            GameMode.vsAi => Icons.smart_toy_outlined,
            GameMode.localTwoPlayer => Icons.people_outline_rounded,
            GameMode.nearbyP2p => Icons.wifi_tethering_rounded,
          };
          return Expanded(
            child: InkWell(
              onTap: () => onChanged(mode),
              borderRadius: BorderRadius.circular(10),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                decoration: BoxDecoration(
                  color: isSelected ? AppTheme.inkPrimary : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      icon,
                      size: 16,
                      color: isSelected
                          ? Colors.white
                          : AppTheme.inkPrimary.withValues(alpha: 0.72),
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        s.gameModeLabel(mode),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: isSelected
                              ? Colors.white
                              : AppTheme.inkPrimary.withValues(alpha: 0.78),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _LocalTwoPlayerPanel extends StatelessWidget {
  const _LocalTwoPlayerPanel({
    required this.rules,
    required this.onStart,
  });

  final MatchRules rules;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppTheme.warmCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppTheme.accentWood.withValues(alpha: 0.2),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.people_alt_rounded,
                    color: AppTheme.accentWood,
                    size: 24,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      s.local2pTitle,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.inkPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                s.local2pDescription(rules),
                style: TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: AppTheme.inkPrimary.withValues(alpha: 0.72),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _MiniInfoChip(
                    icon: Icons.block_rounded,
                    label: s.forbiddenChip(rules.ruleType),
                  ),
                  _MiniInfoChip(
                    icon: Icons.history_edu_rounded,
                    label: s.replaySupportedChip,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: onStart,
            icon: const Icon(Icons.play_arrow_rounded, size: 22),
            label: Text(s.startLocal2pButton),
          ),
        ),
      ],
    );
  }
}

class _NearbyP2pPanel extends StatelessWidget {
  const _NearbyP2pPanel({
    required this.rules,
    required this.onHost,
    required this.onJoin,
  });

  final MatchRules rules;
  final VoidCallback onHost;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppTheme.warmCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppTheme.accentWood.withValues(alpha: 0.2),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.wifi_tethering_rounded,
                    color: AppTheme.accentWood,
                    size: 24,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      s.nearbyP2pTitle,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.inkPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                s.nearbyP2pDescription(rules),
                style: TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: AppTheme.inkPrimary.withValues(alpha: 0.72),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _MiniInfoChip(
                    icon: Icons.devices_rounded,
                    label: s.crossPlatformChip,
                  ),
                  _MiniInfoChip(
                    icon: Icons.cloud_off_rounded,
                    label: s.serverlessP2pChip,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: onHost,
            icon: const Icon(Icons.add_circle_outline_rounded, size: 21),
            label: Text(s.createRoomButton),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: onJoin,
            icon: const Icon(Icons.search_rounded, size: 20),
            label: Text(s.joinRoomButton),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.inkPrimary,
              side: BorderSide(
                color: AppTheme.accentWood.withValues(alpha: 0.4),
              ),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              textStyle: const TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MiniInfoChip extends StatelessWidget {
  const _MiniInfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.warmSurface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppTheme.accentWood),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: AppTheme.inkPrimary.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroBanner extends StatelessWidget {
  const _HeroBanner({required this.ruleType});

  final RuleType ruleType;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.boardWoodLight, AppTheme.boardWoodDark],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppTheme.boardBorder.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppTheme.inkPrimary,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.grid_on_rounded,
              color: AppTheme.boardWoodLight,
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.heroTitle(ruleType),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.inkPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  s.heroSubtitle,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.inkPrimary.withValues(alpha: 0.78),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RuleSummaryCard extends StatelessWidget {
  const _RuleSummaryCard({
    required this.rules,
    required this.onTap,
  });

  final MatchRules rules;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: AppTheme.warmCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppTheme.accentWood.withValues(alpha: 0.22),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppTheme.warmSurface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.gavel_rounded,
                color: AppTheme.accentWood,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.ruleSettingsTitle,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.inkPrimary,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      _RulePill(label: s.ruleTypeLabel(rules.ruleType)),
                      _RulePill(label: s.timeLimitPill(rules)),
                      _RulePill(label: s.undoPill(rules.undoLimit)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Text(
              s.changeLabel,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppTheme.accentWood.withValues(alpha: 0.9),
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppTheme.accentWood,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

class _RulePill extends StatelessWidget {
  const _RulePill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.warmSurface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: AppTheme.inkPrimary.withValues(alpha: 0.78),
        ),
      ),
    );
  }
}

class _ResumeCard extends StatelessWidget {
  const _ResumeCard({
    required this.saved,
    required this.onResume,
    required this.onDiscard,
  });

  final SavedMatch saved;
  final VoidCallback onResume;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            const Icon(
              Icons.history_rounded,
              color: AppTheme.accentWood,
              size: 26,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.resumeCardTitle,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14.5,
                      color: AppTheme.inkPrimary,
                    ),
                  ),
                  Text(
                    s.resumeCardSubtitle(saved),
                    style: TextStyle(
                      fontSize: 12.5,
                      color: AppTheme.inkPrimary.withValues(alpha: 0.68),
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: s.discardSavedTooltip,
              icon: const Icon(Icons.close_rounded, size: 18),
              onPressed: onDiscard,
            ),
            FilledButton(
              onPressed: onResume,
              style: FilledButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                textStyle: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              child: Text(s.resumeButton),
            ),
          ],
        ),
      ),
    );
  }
}

class _DifficultyTile extends StatelessWidget {
  const _DifficultyTile({
    required this.difficulty,
    required this.stats,
    required this.selected,
    required this.onTap,
  });

  final AiDifficulty difficulty;
  final DifficultyStats stats;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final badgeColor = switch (difficulty) {
      AiDifficulty.beginner => const Color(0xFF4CAF50),
      AiDifficulty.intermediate => const Color(0xFF1E88E5),
      AiDifficulty.advanced => const Color(0xFFFB8C00),
      AiDifficulty.expert => const Color(0xFFC62828),
    };

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: AppTheme.warmCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? AppTheme.inkPrimary
                : AppTheme.accentWood.withValues(alpha: 0.16),
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 36,
              decoration: BoxDecoration(
                color: badgeColor,
                borderRadius: BorderRadius.circular(5),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        s.difficultyLabel(difficulty),
                        style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.inkPrimary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (stats.totalGames > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.warmSurface,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            s.statsBadge(
                              stats.wins,
                              stats.losses,
                              stats.winRatePercent,
                            ),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.inkPrimary.withValues(alpha: 0.72),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    s.difficultyDescription(difficulty),
                    style: TextStyle(
                      fontSize: 12.5,
                      color: AppTheme.inkPrimary.withValues(alpha: 0.65),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              color: selected
                  ? AppTheme.inkPrimary
                  : AppTheme.accentWood.withValues(alpha: 0.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _StoneChoiceCard extends StatelessWidget {
  const _StoneChoiceCard({
    required this.preference,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final StonePreference preference;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.warmCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? AppTheme.inkPrimary
                : AppTheme.accentWood.withValues(alpha: 0.16),
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PreferenceStoneIcon(preference: preference),
            const SizedBox(height: 8),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13.5,
                color: AppTheme.inkPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: AppTheme.inkPrimary.withValues(alpha: 0.62),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreferenceStoneIcon extends StatelessWidget {
  const _PreferenceStoneIcon({required this.preference});

  final StonePreference preference;

  @override
  Widget build(BuildContext context) {
    if (preference == StonePreference.random) {
      return Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            stops: [0.5, 0.5],
            colors: [Color(0xFF1A1A1A), Color(0xFFFFFFFF)],
          ),
          border: Border.all(
            color: Colors.black.withValues(alpha: 0.35),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.14),
              blurRadius: 3,
              offset: const Offset(0, 1),
            ),
          ],
        ),
      );
    }

    final isBlack = preference == StonePreference.black;
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: const Alignment(-0.3, -0.3),
          colors: isBlack
              ? const [Color(0xFF555555), Color(0xFF111111)]
              : const [Color(0xFFFFFFFF), Color(0xFFD5CFC3)],
        ),
        border: Border.all(
          color: Colors.black.withValues(alpha: isBlack ? 0.45 : 0.25),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
    );
  }
}
