import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/match_rules.dart';
import '../../../engine/engine.dart';
import '../../../l10n/app_strings.dart';
import '../../../shared/layout/responsive_layout.dart';
import '../../../shared/providers/app_providers.dart';
import '../../../shared/theme/app_theme.dart';

/// Modal bottom sheet dedicated to configuring Omok match rules
/// (Renju vs Freestyle, per-turn time limit 1–100s, and undo limit).
class RuleSettingsSheet extends ConsumerWidget {
  const RuleSettingsSheet({super.key});

  static const List<int> _timePresets = [10, 30, 60, 100];

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      constraints: const BoxConstraints(
        maxWidth: ResponsiveLayout.modalSheetMaxWidth,
      ),
      backgroundColor: AppTheme.warmCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => const RuleSettingsSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final rules = ref.watch(matchRulesProvider);
    final notifier = ref.read(matchRulesProvider.notifier);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.accentWood.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              s.ruleSheetTitle,
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: AppTheme.inkPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              s.ruleSheetSubtitle,
              style: TextStyle(
                fontSize: 12.5,
                color: AppTheme.inkPrimary.withValues(alpha: 0.62),
              ),
            ),
            const SizedBox(height: 18),

            // 1. Rule type (Renju vs Freestyle)
            Text(
              s.ruleTypeSectionTitle,
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w800,
                color: AppTheme.inkPrimary,
              ),
            ),
            const SizedBox(height: 8),
            ...RuleType.values.map(
              (type) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _RuleTypeOption(
                  type: type,
                  selected: rules.ruleType == type,
                  onTap: () => notifier.setRuleType(type),
                ),
              ),
            ),

            const Divider(height: 22),

            // 2. Per-turn time limit (1~100 seconds, User & AI both)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                s.turnTimerSwitchTitle,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.inkPrimary,
                ),
              ),
              subtitle: Text(s.turnTimerSwitchSubtitle),
              value: rules.useTimeLimit,
              onChanged: notifier.toggleTimeLimit,
            ),
            if (rules.useTimeLimit) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: BoxDecoration(
                  color: AppTheme.warmSurface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppTheme.accentWood.withValues(alpha: 0.16),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          s.secondsPerMoveLabel,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.inkPrimary,
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton.outlined(
                              visualDensity: VisualDensity.compact,
                              tooltip: s.decreaseOneSecTooltip,
                              onPressed: rules.turnTimeLimitSeconds >
                                      MatchRules.minTurnSeconds
                                  ? () => notifier.setTurnTimeLimitSeconds(
                                        rules.turnTimeLimitSeconds - 1,
                                      )
                                  : null,
                              icon: const Icon(Icons.remove_rounded, size: 16),
                            ),
                            SizedBox(
                              width: 56,
                              child: Text(
                                s.secondsShort(rules.turnTimeLimitSeconds),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  color: AppTheme.accentWood,
                                ),
                              ),
                            ),
                            IconButton.outlined(
                              visualDensity: VisualDensity.compact,
                              tooltip: s.increaseOneSecTooltip,
                              onPressed: rules.turnTimeLimitSeconds <
                                      MatchRules.maxTurnSeconds
                                  ? () => notifier.setTurnTimeLimitSeconds(
                                        rules.turnTimeLimitSeconds + 1,
                                      )
                                  : null,
                              icon: const Icon(Icons.add_rounded, size: 16),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Slider(
                      value: rules.turnTimeLimitSeconds.toDouble(),
                      min: MatchRules.minTurnSeconds.toDouble(),
                      max: MatchRules.maxTurnSeconds.toDouble(),
                      divisions:
                          MatchRules.maxTurnSeconds - MatchRules.minTurnSeconds,
                      activeColor: AppTheme.accentWood,
                      onChanged: (v) =>
                          notifier.setTurnTimeLimitSeconds(v.round()),
                    ),
                    Wrap(
                      spacing: 8,
                      children: _timePresets.map((sec) {
                        final isSelected = rules.turnTimeLimitSeconds == sec;
                        return ChoiceChip(
                          label: Text(s.secondsShort(sec)),
                          selected: isSelected,
                          onSelected: (_) =>
                              notifier.setTurnTimeLimitSeconds(sec),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ],

            const Divider(height: 24),

            // 3. Undo limit
            Text(
              s.undoLimitSectionTitle,
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w800,
                color: AppTheme.inkPrimary,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: UndoLimit.values.map((limit) {
                final selected = rules.undoLimit == limit;
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: limit == UndoLimit.values.last ? 0 : 6,
                    ),
                    child: InkWell(
                      onTap: () => notifier.setUndoLimit(limit),
                      borderRadius: BorderRadius.circular(12),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 140),
                        padding: const EdgeInsets.symmetric(
                          vertical: 11,
                          horizontal: 4,
                        ),
                        decoration: BoxDecoration(
                          color: selected
                              ? AppTheme.inkPrimary
                              : AppTheme.warmSurface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: selected
                                ? AppTheme.inkPrimary
                                : AppTheme.accentWood.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Text(
                          s.undoLimitLabel(limit),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: selected ? Colors.white : AppTheme.inkPrimary,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(s.confirm),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RuleTypeOption extends StatelessWidget {
  const _RuleTypeOption({
    required this.type,
    required this.selected,
    required this.onTap,
  });

  final RuleType type;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? AppTheme.warmSurface : AppTheme.warmCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? AppTheme.inkPrimary
                : AppTheme.accentWood.withValues(alpha: 0.18),
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.ruleTypeLabel(type),
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.inkPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    s.ruleTypeDescription(type),
                    style: TextStyle(
                      fontSize: 12,
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
