import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'data/repositories/local_storage_repository.dart';
import 'shared/layout/responsive_layout.dart';
import 'shared/providers/app_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
  await ResponsiveLayout.applyDeviceOrientationPolicy();
  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [
        storageRepositoryProvider.overrideWithValue(
          SharedPreferencesStorageRepository(prefs),
        ),
      ],
      child: const OmokApp(),
    ),
  );
}
