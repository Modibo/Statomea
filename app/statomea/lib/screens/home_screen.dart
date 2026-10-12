import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/gen/app_localizations.dart';
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

class _HomeScreenState extends State<HomeScreen> {
  int index = 0;

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
    final modeSwitch = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: SegmentedButton<bool>(
        segments: [
          ButtonSegment(value: false, label: Text(t.modeGuided), icon: const Icon(Icons.assistant_outlined)),
          ButtonSegment(value: true, label: Text(t.modeExpert), icon: const Icon(Icons.tune)),
        ],
        selected: {state.expertMode},
        showSelectedIcon: false,
        onSelectionChanged: (s) => state.setExpert(s.first),
      ),
    );
    final langMenu = PopupMenuButton<String>(
      tooltip: t.languageLabel,
      icon: const Icon(Icons.translate),
      onSelected: (code) {
        state.setLocale(code);
        // Les textes passent par tr() : reconstruire tout l'arbre, routes ouvertes comprises.
        void rebuild(Element e) {
          e.markNeedsBuild();
          e.visitChildren(rebuild);
        }
        WidgetsBinding.instance.rootElement?.visitChildren(rebuild);
      },
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'fr', child: Text('Français')),
        PopupMenuItem(value: 'en', child: Text('English')),
      ],
    );
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 900;
      final appBar = AppBar(
        title: Row(children: [
          Icon(Icons.insights, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Text(t.appTitle, style: const TextStyle(fontWeight: FontWeight.w700)),
        ]),
        actions: [if (c.maxWidth >= 420) modeSwitch, langMenu],
        bottom: c.maxWidth < 420 ? PreferredSize(preferredSize: const Size.fromHeight(48), child: Padding(padding: const EdgeInsets.only(bottom: 6), child: modeSwitch)) : null,
      );
      if (!state.loaded) return const Scaffold(body: Center(child: CircularProgressIndicator()));
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
            Expanded(child: pages[index]),
          ]),
        );
      }
      return Scaffold(
        appBar: appBar,
        body: pages[index],
        bottomNavigationBar: NavigationBar(
          selectedIndex: index,
          onDestinationSelected: (i) => setState(() => index = i),
          destinations: [for (final (a, b, l) in dest) NavigationDestination(icon: Icon(a), selectedIcon: Icon(b), label: l)],
        ),
      );
    });
  }
}
