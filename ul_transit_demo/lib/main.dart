import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/app_shell.dart';
import 'src/features/gtfs/startup_helper.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Attempt to pre-load the Sweden GTFS stops into the in-memory demo tables.
  // This is a best-effort operation and will silently fall back to the
  // built-in sample seed if the file isn't available or cannot be read.
  try {
    // Construct a temporary database instance and invoke the loader. The
    // provider-created instance will still be used by the app, but loading
    // here helps populate the on-start memory state for web demos.
    final db = UlTransitApp._createTempGtfsDatabase();
    await db.loadSwedenIntoMemory();
  } catch (_) {}
  // Log Flutter framework errors to console for easier debugging in release/web.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exceptionAsString()}\n${details.stack}');
  };
  // Catch unhandled async errors.
  ui.PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Unhandled error: $error\n$stack');
    return true;
  };
  runApp(const ProviderScope(child: UlTransitApp()));
}

class UlTransitApp extends ConsumerWidget {
  const UlTransitApp({super.key});

  // Helper to create a temporary `GtfsDatabase` without needing a Provider.
  // Used only at startup to pre-populate in-memory demo data.
  static dynamic _createTempGtfsDatabase() {
    // Use a dynamic import to avoid a hard dependency in this file.
    // Import the class directly from its path.
    return importGtfsDatabaseForStartup();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'UL Transit Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF006699)),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(centerTitle: true),
      ),
      home: const AppShell(),
    );
  }
}
