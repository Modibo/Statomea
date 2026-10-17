import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:statomea/main.dart';
import 'package:statomea/services/storage.dart';
import 'package:statomea/state/app_state.dart';
import 'package:statomea/widgets/common.dart';

/// Les listes remplissent la largeur : une colonne pleine largeur sur téléphone, plusieurs colonnes sur grand écran,
/// sans erreur de mise en page.
void main() {
  for (final (label, size, cols) in [('téléphone', const Size(375, 812), 1), ('tablette', const Size(820, 1180), 2), ('ordinateur', const Size(1440, 900), 4)]) {
    testWidgets('accueil en largeur $label : cartes de démonstration sur $cols colonne(s), pleine largeur', (t) async {
      await t.binding.setSurfaceSize(size);
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      final state = AppState(MemoryStorage());
      await state.load();
      await t.pumpWidget(ChangeNotifierProvider.value(value: state, child: const StatomeaApp()));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      final card = find.ancestor(of: find.textContaining('Métaanalyse avec forest plot'), matching: find.byType(Card)).first;
      final grid = find.ancestor(of: card, matching: find.byType(ResponsiveGrid)).first;
      final cw = t.getSize(card).width, gw = t.getSize(grid).width;
      // Largeur d'une carte = (largeur de la grille − espacements) / colonnes : la ligne est remplie.
      expect(cw, closeTo((gw - 12 * (cols - 1)) / cols, 0.5));
      // 8 démonstrations : la dernière ligne (même incomplète) occupe toute la largeur.
      const demos = 8;
      final last = find.ancestor(of: find.textContaining('Survie avancée'), matching: find.byType(Card)).first;
      final lastCount = demos % cols == 0 ? cols : demos % cols;
      expect(t.getSize(last).width, closeTo((gw - 12 * (lastCount - 1)) / lastCount, 0.5));
      t.view.resetPhysicalSize();
      t.view.resetDevicePixelRatio();
    });
  }
}
