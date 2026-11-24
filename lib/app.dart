import 'package:material_ui/material_ui.dart';

import 'features/home/home_screen.dart';
import 'l10n/app_strings.dart';
import 'shared/theme/app_theme.dart';

class OmokApp extends StatelessWidget {
  const OmokApp({super.key, this.locale});

  /// Optional explicit locale override (used by tests & screenshot harness).
  /// When `null` (production), follows the device system locale automatically.
  final Locale? locale;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => AppStrings.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      locale: locale,
      supportedLocales: AppStrings.supportedLocales,
      localeResolutionCallback: AppStrings.resolveLocale,
      localizationsDelegates: const [
        AppStrings.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      theme: AppTheme.light(),
      home: const HomeScreen(),
    );
  }
}
