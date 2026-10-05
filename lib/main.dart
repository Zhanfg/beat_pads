import 'package:beat_pads/screen_fl_studio/fl_studio_screen.dart';
import 'package:beat_pads/services/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final sharedPrefProvider = Provider<Prefs>((ref) {
  throw UnimplementedError();
});

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await DeviceUtils.enableRotation();
  await DeviceUtils.hideSystemUi();

  final preferences = await Prefs.initAsync();

  runApp(
    ProviderScope(
      overrides: <Override>[
        sharedPrefProvider.overrideWithValue(preferences),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
        ),
        home: const FlStudioScreen(),
      ),
    ),
  );
}
