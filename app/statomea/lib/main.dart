import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'l10n/gen/app_localizations.dart';
import 'screens/home_screen.dart';
import 'services/storage.dart';
import 'state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // La langue enregistrée doit être active avant le premier affichage (les textes passent par tr()).
  final state = AppState(PrefsStorage());
  await state.load();
  runApp(ChangeNotifierProvider.value(value: state, child: const StatomeaApp()));
}

const seed = Color(0xFF1F4E79);

ThemeData buildTheme(Brightness b) {
  final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: b);
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    // Polices embarquées : rendu identique hors connexion (≤ ≥ √ ≈ → via NotoSansMath).
    fontFamily: 'NotoSans',
    fontFamilyFallback: const ['NotoSansMath'],
    visualDensity: VisualDensity.standard,
    cardTheme: CardThemeData(elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: scheme.outlineVariant))),
    inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder(), isDense: true),
  );
}

class StatomeaApp extends StatelessWidget {
  const StatomeaApp({super.key});
  @override
  Widget build(BuildContext context) {
    final locale = context.select<AppState, String>((s) => s.localeCode);
    return MaterialApp(
      title: 'Statoméa',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      locale: Locale(locale),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const HomeScreen(),
    );
  }
}
