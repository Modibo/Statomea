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
    // Nouvelle version : au démarrage, toutes les 10 minutes tant que l'application est ouverte, et à chaque retour
    // sur l'onglet ou l'application (une page restée ouverte voit ainsi passer une mise à jour).
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
    _updateTimer = Timer.periodic(const Duration(minutes: 10), (_) => _check());
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
    if (last != null && DateTime.now().difference(last) < const Duration(minutes: 1)) return;
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
    // Sélecteur Guidé / Expert : dans la barre sur grand écran ; sur téléphone, sous la barre et sur toute la largeur.
    Widget modeSwitch({bool expanded = false}) => SegmentedButton<bool>(
          expandedInsets: expanded ? EdgeInsets.zero : null,
          segments: [
            ButtonSegment(value: false, label: Text(t.modeGuided), icon: Icon(Icons.lightbulb_rounded, color: dark ? Colors.amber.shade300 : Colors.amber.shade800)),
            ButtonSegment(value: true, label: Text(t.modeExpert), icon: Icon(Icons.science_rounded, color: dark ? const Color(0xFF5FD3A6) : const Color(0xFF0B8A60))),
          ],
          selected: {state.expertMode},
          showSelectedIcon: false,
          onSelectionChanged: (s) => state.setExpert(s.first),
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

    // Bouton de langue unique : affiche la langue active (FR ou EN) ; un appui bascule vers l'autre.
    final isFr = state.localeCode != 'en';
    final langMenu = Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Semantics(
        button: true,
        label: isFr ? 'Langue : français. Passer en anglais' : 'Language: English. Switch to French',
        excludeSemantics: true,
        child: Tooltip(
          message: isFr ? 'Passer en anglais (English)' : 'Switch to French (Français)',
          child: OutlinedButton.icon(
            onPressed: () => switchLang(isFr ? 'en' : 'fr'),
            // Même hauteur visuelle (40) que le sélecteur Guidé / Expert ; zone tactile portée à 48 (padded).
            style: OutlinedButton.styleFrom(
                minimumSize: const Size(64, 40), tapTargetSize: MaterialTapTargetSize.padded, padding: const EdgeInsets.symmetric(horizontal: 12), shape: const StadiumBorder()),
            icon: const Icon(Icons.language_rounded, size: 20),
            label: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, a) => ScaleTransition(scale: a, child: child),
              child: Text(isFr ? 'FR' : 'EN', key: ValueKey(isFr), style: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.5)),
            ),
          ),
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
        titleSpacing: 16,
        actions: [if (c.maxWidth >= 600) ...[modeSwitch(), const SizedBox(width: 12)], langMenu],
        bottom: c.maxWidth < 600
            ? PreferredSize(preferredSize: const Size.fromHeight(56), child: Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8), child: modeSwitch(expanded: true)))
            : null,
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

/// Bandeau « nouvelle version » : recharger (web) ou télécharger et installer l'APK (Android, dans l'application, avec
/// progression), ou écarter cette version.
class _UpdateBanner extends StatefulWidget {
  final UpdateInfo u;
  const _UpdateBanner(this.u);
  @override
  State<_UpdateBanner> createState() => _UpdateBannerState();
}

class _UpdateBannerState extends State<_UpdateBanner> {
  double? progress; // null = au repos
  String? note;

  Future<void> _go() async {
    final u = widget.u;
    if (u.url == null) {
      await applyUpdate(u);
      return;
    }
    setState(() {
      progress = 0;
      note = null;
    });
    final r = await installUpdate(u, (p) {
      if (mounted) setState(() => progress = p);
    });
    if (!mounted) return;
    setState(() {
      progress = null;
      note = switch (r) {
        'permission' => tr('Autorisez Statoméa à installer des applications (réglage ouvert), revenez ici puis appuyez sur « Installer ».',
            'Allow Statoméa to install apps (settings opened), come back here and tap "Install".'),
        'browser' => tr('Téléchargement ouvert dans le navigateur : ouvrez ensuite le fichier téléchargé pour l\'installer.',
            'Download opened in the browser: then open the downloaded file to install it.'),
        _ => tr('Installateur ouvert : confirmez la mise à jour.', 'Installer opened: confirm the update.'),
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.u;
    final cs = Theme.of(context).colorScheme;
    final busy = progress != null;
    return Material(
      color: cs.primaryContainer,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 4, children: [
              Icon(Icons.system_update_alt_rounded, color: cs.onPrimaryContainer),
              Text(tr('Nouvelle version ${u.version} disponible (installée : $appVersion).', 'New version ${u.version} available (installed: $appVersion).'),
                  style: TextStyle(color: cs.onPrimaryContainer, fontWeight: FontWeight.w600)),
              if (!busy) TextButton(onPressed: () => context.read<AppState>().dismissUpdate(), child: Text(tr('Plus tard', 'Later'))),
              FilledButton.icon(
                onPressed: busy ? null : _go,
                icon: Icon(u.url == null ? Icons.refresh_rounded : Icons.download_rounded),
                label: Text(u.url == null
                    ? tr('Recharger', 'Reload')
                    : busy
                        ? tr('Téléchargement… ${(progress! * 100).round()} %', 'Downloading… ${(progress! * 100).round()}%')
                        : (note == null ? tr('Télécharger et installer', 'Download and install') : tr('Installer', 'Install'))),
              ),
            ]),
            if (busy) Padding(padding: const EdgeInsets.only(top: 6, right: 8), child: LinearProgressIndicator(value: progress! > 0 ? progress : null)),
            if (note != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(note!, style: TextStyle(color: cs.onPrimaryContainer))),
          ]),
        ),
      ),
    );
  }
}
