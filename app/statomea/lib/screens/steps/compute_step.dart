import 'package:flutter/material.dart';
import 'package:statomea_core/statomea_core.dart' hide Step;

import '../../widgets/calculators.dart';
import '../../widgets/common.dart';

/// Étape 6 : calcul. Chaque résultat est journalisé dans le projet.
class ComputeStep extends StatelessWidget {
  final Project p;
  final String? initialMethod;
  const ComputeStep(this.p, {super.key, this.initialMethod});
  @override
  Widget build(BuildContext context) => PageBody(children: [
        Heading(tr('6. Calcul', '6. Computation')),
        Text(tr('Le moteur statistique déterministe produit le résultat, ses hypothèses, ses diagnostics et un journal. Chaque calcul est ajouté au journal du projet (données, corrections, options, version du moteur).', 'The deterministic statistical engine produces the result, its assumptions, its diagnostics and a log. Each computation is added to the project log (data, corrections, options, engine version).')),
        const SizedBox(height: 12),
        CalculatorPanel(project: p, initialMethod: initialMethod),
      ]);
}
