import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_strings.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';

/// Root widget: theme, localization scaffolding (English now, Nepali-ready),
/// and the guarded router.
class GuidesNepalApp extends ConsumerWidget {
  const GuidesNepalApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      title: AppStrings.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: router,
      // Localization scaffolding: English is the active locale. Adding Nepali
      // later only requires a new AppStrings implementation + these delegates.
      locale: const Locale('en'),
      supportedLocales: const [Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}
