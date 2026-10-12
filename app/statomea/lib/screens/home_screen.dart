import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/gen/app_localizations.dart';
import '../app_version.dart';
import '../services/update/update_check.dart';
import 'package:statomea_core/statomea_core.dart' show tr;
import '../state/app_state.dart';
import 'calculators_screen.dart';
import 'learn_screen.dart';
import 'projects_screen.dart';
import 'validation_screen.dart';

/// Coquille adaptative : barre de navigation inférieure sur téléphone,
/// rail latéral sur tablette et ordinateur (largeur ≥ 900 px).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int index = 0;
  Timer? _updateTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Nouvelle version : au démarrage, puis toutes les 6 heures et au retour dans l'application.
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
    _updateTimer = Timer.periodic(const Duration(hours: 6), (_) => _check());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _updateTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    final state = context.read<AppState>();
    if (!state.loaded) return;
    final last = state.lastUpdateCheck;
    if (last != null && DateTime.now().difference(last) < const Duration(minutes: 30)) return;
    await state.checkForUpdate();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final state = context.watch<AppState>();
    final pages = [const ProjectsScreen(), const CalculatorsScreen(), const LearnScreen(), const ValidationScreen()];
    final dest = [
      (Icons.folder_outlined, Icons.folder, t.navProjects),
      (Icons.calculate_outlined, Icons.calculate, t.navCalculators),
      (Icons.school_outlined, Icons.school, t.navLearn),
      (Icons.verified_outlined, Icons.verified, t.navValidation),
    ];
    final dark = Theme.of(context).brightness == Brightness.dark;
    final modeSwitch = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: SegmentedButton<bool>(
        segments: [
          ButtonSegment(value: false, label: Text(t.modeGuided), icon: Icon(Icons.lightbulb_rounded, color: dark ? Colors.amber.shade300 : Colors.amber.shade800)),
          ButtonSegment(value: true, label: Text(t.modeExpert), icon: Icon(Icons.science_rounded, color: dark ? const Color(0xFF5FD3A6) : const Color(0xFF0B8A60))),
        ],
        selected: {state.expertMode},
        showSelectedIcon: false,
        onSelectionChanged: (s) => state.setExpert(s.first),
      ),
    );
    void switchLang(String code) {
      if (code == state.localeCode) return;
      state.setLocale(code);
      // Les textes passent par tr() : reconstruire tout l'arbre, routes ouvertes comprises.
      void rebuild(Element e) {
        e.markNeedsBuild();
        e.visitChildren(rebuild);
      }
      WidgetsBinding.instance.rootElement?.visitChildren(rebuild);
    }

    // Sélecteur de langue FR | EN : la langue active est mise en évidence, un appui suffit pour basculer.
    final langMenu = Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Tooltip(
        message: t.languageLabel,
        child: SegmentedButton<String>(
          style: const ButtonStyle(padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 4))),
          segments: const [
            ButtonSegment(value: 'fr', label: Text('FR', semanticsLabel: 'Français')),
            ButtonSegment(value: 'en', label: Text('EN', semanticsLabel: 'English')),
          ],
          selected: {state.localeCode},
          showSelectedIcon: false,
          onSelectionChanged: (s) => switchLang(s.first),
        ),
      ),
    );
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 900;
      final appBar = AppBar(
        title: Row(children: [
          // Emblème du logo sur une pastille blanche (lisible aussi en thème sombre).
          Semantics(
            label: 'Logo Statoméa',
            image: true,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
              child: Image.asset('assets/logo/statomea_embleme.png', height: 30, width: 30, excludeFromSemantics: true),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(child: Text(t.appTitle, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
        ]),
        actions: [if (c.maxWidth >= 600) modeSwitch, langMenu],
        bottom: c.maxWidth < 600 ? PreferredSize(preferredSize: const Size.fromHeight(48), child: Padding(padding: const EdgeInsets.only(bottom: 6), child: modeSwitch)) : null,
      );
      if (!state.loaded) return const Scaffold(body: Center(child: CircularProgressIndicator()));
      final upd = state.pendingUpdate;
      Widget withBanner(Widget body) => upd == null ? body : Column(children: [_UpdateBanner(upd), Expanded(child: body)]);
      if (wide) {
        return Scaffold(
          appBar: appBar,
          body: Row(children: [
            NavigationRail(
              selectedIndex: index,
              labelType: NavigationRailLabelType.all,
              onDestinationSelected: (i) => setState(() => index = i),
              destinations: [for (final (a, b, l) in dest) NavigationRailDestination(icon: Icon(a), selectedIcon: Icon(b), label: Text(l))],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: withBanner(pages[index])),
          ]),
        );
      }
      return Scaffold(
        appBar: appBar,
        body: withBanner(pages[index]),
        bottomNavigationBar: NavigationBar(
          selectedIndex: index,
          onDestinationSelected: (i) => setState(() => index = i),
          destinations: [for (final (a, b, l) in dest) NavigationDestination(icon: Icon(a), selectedIcon: Icon(b), label: l)],
        ),
      );
    });
  }
}

/// Bandeau « nouvelle version » : recharger (web) ou télécharger l'APK (Android), ou écarter cette version.
class _UpdateBanner extends StatelessWidget {
  final UpdateInfo u;
  const _UpdateBanner(this.u);
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.primaryContainer,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 4, children: [
            Icon(Icons.system_update_alt_rounded, color: cs.onPrimaryContainer),
            Text(tr('Nouvelle version ${u.version} disponible (installée : $appVersion).', 'New version ${u.version} available (installed: $appVersion).'),
                style: TextStyle(color: cs.onPrimaryContainer, fontWeight: FontWeight.w600)),
            TextButton(onPressed: () => context.read<AppState>().dismissUpdate(), child: Text(tr('Plus tard', 'Later'))),
            FilledButton.icon(
              onPressed: () => applyUpdate(u),
              icon: Icon(u.url == null ? Icons.refresh_rounded : Icons.download_rounded),
              label: Text(u.url == null ? tr('Recharger', 'Reload') : tr('Télécharger', 'Download')),
            ),
          ]),
        ),
      ),
    );
  }
}
