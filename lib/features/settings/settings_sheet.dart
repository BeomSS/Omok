import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_strings.dart';
import '../../../shared/layout/responsive_layout.dart';
import '../../../shared/providers/app_providers.dart';
import '../../../shared/theme/app_theme.dart';

/// Modal settings sheet accessible from both Home and Game screens.
class SettingsSheet extends ConsumerWidget {
  const SettingsSheet({super.key});

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
      builder: (_) => const SettingsSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
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
              s.settingsSheetTitle,
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: AppTheme.inkPrimary,
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(s.confirmBeforePlaceTitle),
              subtitle: Text(s.confirmBeforePlaceSubtitle),
              value: settings.confirmBeforePlace,
              onChanged: notifier.toggleConfirmBeforePlace,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(s.showForbiddenTitle),
              subtitle: Text(s.showForbiddenSubtitle),
              value: settings.showForbiddenMarkers,
              onChanged: notifier.toggleShowForbiddenMarkers,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(s.showMoveNumbersTitle),
              subtitle: Text(s.showMoveNumbersSubtitle),
              value: settings.showMoveNumbers,
              onChanged: notifier.toggleShowMoveNumbers,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(s.showCoordinatesTitle),
              subtitle: Text(s.showCoordinatesSubtitle),
              value: settings.showCoordinates,
              onChanged: notifier.toggleShowCoordinates,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(s.soundEffectsTitle),
              subtitle: Text(s.soundEffectsSubtitle),
              value: settings.soundEnabled,
              onChanged: notifier.toggleSoundEnabled,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(s.hapticFeedbackTitle),
              subtitle: Text(s.hapticFeedbackSubtitle),
              value: settings.hapticEnabled,
              onChanged: notifier.toggleHapticEnabled,
            ),
            const Divider(height: 20),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text(s.resetStatsDialogTitle),
                      content: Text(s.resetStatsDialogContent),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: Text(s.cancel),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: Text(s.resetAction),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true) {
                    await ref.read(statsProvider.notifier).resetAll();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(s.resetStatsDone)),
                      );
                    }
                  }
                },
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: AppTheme.forbiddenCrimson,
                ),
                label: Text(
                  s.resetStatsButton,
                  style: const TextStyle(color: AppTheme.forbiddenCrimson),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
