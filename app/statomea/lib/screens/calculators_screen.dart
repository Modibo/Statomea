import 'package:flutter/material.dart';

import 'package:statomea_core/statomea_core.dart';
import '../widgets/calculators.dart';
import '../widgets/common.dart';

/// Calculs rapides hors projet (rien n'est journalisé).
class CalculatorsScreen extends StatelessWidget {
  const CalculatorsScreen({super.key});
  @override
  Widget build(BuildContext context) => PageBody(children: [
        Heading(tr('Calculs rapides', 'Quick calculations')),
        Text(tr('Saisie directe d\'effectifs ou de séries de valeurs. Pour une analyse journalisée, avec contrôle des données et audit, travaillez dans un projet. Les ateliers de régression et de prédiction nécessitent un projet avec données.', 'Direct entry of counts or series of values. For a logged analysis, with data control and audit, work in a project. The regression and prediction workshops require a project with data.')),
        const SizedBox(height: 12),
        const CalculatorPanel(),
      ]);
}
