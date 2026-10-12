import 'package:flutter/material.dart';
import 'package:statomea_core/statomea_core.dart';

class StatusChip extends StatelessWidget {
  final MethodStatus status;
  const StatusChip(this.status, {super.key});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ok = status == MethodStatus.validated;
    return Chip(
      avatar: Icon(ok ? Icons.verified_outlined : Icons.construction, size: 16, color: ok ? cs.onPrimaryContainer : cs.onErrorContainer),
      label: Text(ok ? tr('Méthode validée', 'Validated method') : tr('En développement', 'In development')),
      backgroundColor: ok ? cs.primaryContainer : cs.errorContainer,
      labelStyle: TextStyle(color: ok ? cs.onPrimaryContainer : cs.onErrorContainer, fontSize: 12),
      visualDensity: VisualDensity.compact,
    );
  }
}

Color severityColor(BuildContext context, Severity s) => switch (s) {
      Severity.info => Colors.blueGrey,
      Severity.caution => const Color(0xFFB7791F),
      Severity.serious => const Color(0xFFC05621),
      Severity.critical => Theme.of(context).colorScheme.error,
    };

/// Bandeau « données de démonstration » : jaune pâle en clair, brun foncé en
/// sombre ; le texte est fixé avec le fond (contraste ≥ 7:1 dans les deux thèmes).
({Color background, Color foreground}) demoBannerColors(Brightness b) => b == Brightness.light
    ? (background: const Color(0xFFFFF5D6), foreground: const Color(0xFF3D3000))
    : (background: const Color(0xFF3A3000), foreground: const Color(0xFFFFF0C2));

IconData severityIcon(Severity s) => switch (s) {
      Severity.info => Icons.info_outline,
      Severity.caution => Icons.warning_amber_outlined,
      Severity.serious => Icons.report_outlined,
      Severity.critical => Icons.block,
    };

/// Bandeau d'alerte (gravité, message, suggestion).
class Banner2 extends StatelessWidget {
  final Severity severity;
  final String message;
  final String? suggestion;
  final String? trigger;
  const Banner2(this.severity, this.message, {super.key, this.suggestion, this.trigger});
  @override
  Widget build(BuildContext context) {
    final c = severityColor(context, severity);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.08),
        border: Border(left: BorderSide(color: c, width: 4)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(severityIcon(severity), color: c, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${severityLabel(severity)} — $message'),
            if (trigger != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(tr('« $trigger »', '"$trigger"'), style: const TextStyle(fontStyle: FontStyle.italic)),
              ),
            if (suggestion != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('→ $suggestion', style: Theme.of(context).textTheme.bodySmall),
              ),
          ]),
        ),
      ]),
    );
  }
}

class CheckTile extends StatelessWidget {
  final Check check;
  final bool detailed;
  const CheckTile(this.check, {super.key, this.detailed = true});
  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (check.status) {
      CheckStatus.ok => (Icons.check_circle_outline, Colors.green.shade700),
      CheckStatus.warning => (Icons.error_outline, const Color(0xFFB7791F)),
      CheckStatus.violated => (Icons.cancel_outlined, Theme.of(context).colorScheme.error),
      CheckStatus.notAssessed => (Icons.help_outline, Colors.blueGrey),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${check.label} — ${checkStatusLabel(check.status)}', style: const TextStyle(fontWeight: FontWeight.w500)),
            if (detailed || check.status != CheckStatus.ok) Text(check.detail, style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
      ]),
    );
  }
}

class SectionLabel extends StatelessWidget {
  final String text;
  final IconData? icon;
  const SectionLabel(this.text, {super.key, this.icon});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 4),
        child: Row(children: [
          if (icon != null) Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
          if (icon != null) const SizedBox(width: 6),
          // Affiché en capitales, annoncé dans sa casse d'origine (sinon épelé par certaines synthèses vocales).
          Flexible(
            child: Semantics(
              header: true,
              label: text,
              excludeSemantics: true,
              child: Text(text.toUpperCase(),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(letterSpacing: 0.8, color: Theme.of(context).colorScheme.primary)),
            ),
          ),
        ]),
      );
}

/// Titre d'écran ou d'étape, annoncé comme titre par les lecteurs d'écran.
class Heading extends StatelessWidget {
  final String text;
  final TextStyle? style;
  const Heading(this.text, {super.key, this.style});
  @override
  Widget build(BuildContext context) => Semantics(header: true, child: Text(text, style: style ?? Theme.of(context).textTheme.headlineSmall));
}

/// Tableau défilant horizontalement (lisible sur téléphone).
class DataTableView extends StatelessWidget {
  final ResultTable table;
  const DataTableView(this.table, {super.key});
  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(table.title, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowHeight: 32,
            dataRowMinHeight: 28,
            dataRowMaxHeight: 64,
            columnSpacing: 16,
            horizontalMargin: 8,
            headingTextStyle: style?.copyWith(fontWeight: FontWeight.bold),
            columns: [for (final h in table.header) DataColumn(label: Text(h))],
            rows: [
              for (final r in table.rows)
                DataRow(cells: [
                  for (var j = 0; j < table.header.length; j++)
                    DataCell(ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 320), child: Text(j < r.length ? r[j] : '', style: style))),
                ])
            ],
          ),
        ),
      ]),
    );
  }
}

/// Champ numérique (virgule décimale acceptée).
class NumField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String? helper;
  final double width;
  const NumField(this.label, this.controller, {super.key, this.helper, this.width = 140});
  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        child: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
          decoration: InputDecoration(labelText: label, helperText: helper, isDense: true, border: const OutlineInputBorder()),
        ),
      );
}

double? readNum(TextEditingController c) => parseNumber(c.text);
int? readInt(TextEditingController c) {
  final v = parseNumber(c.text);
  return v == null || v != v.roundToDouble() ? null : v.toInt();
}

/// Menu déroulant générique.
class Pick<T> extends StatelessWidget {
  final String label;
  final T? value;
  final List<(T, String)> items;
  final ValueChanged<T?> onChanged;
  final double width;
  const Pick(this.label, this.value, this.items, this.onChanged, {super.key, this.width = 260});
  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        child: DropdownButtonFormField<T>(
          initialValue: items.any((i) => i.$1 == value) ? value : null,
          isExpanded: true,
          decoration: InputDecoration(labelText: label, isDense: true, border: const OutlineInputBorder()),
          items: [for (final (v, l) in items) DropdownMenuItem(value: v, child: Text(l, overflow: TextOverflow.ellipsis))],
          onChanged: onChanged,
        ),
      );
}

void showError(BuildContext context, Object e) {
  final msg = e is StatInputError ? e.message : e.toString();
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 6)));
}

/// Gabarit de page à largeur de lecture limitée.
/// Grille adaptative : autant de colonnes que la largeur en permet (largeur minimale [minItemWidth]) ; les éléments
/// s'étirent pour remplir toute la ligne, y compris la dernière (une seule colonne pleine largeur sur téléphone). [equalHeights] : même hauteur
/// pour les éléments d'une ligne (cartes) ; à éviter pour des éléments dépliables.
class ResponsiveGrid extends StatelessWidget {
  final List<Widget> children;
  final double minItemWidth, spacing;
  final bool equalHeights;
  const ResponsiveGrid({super.key, required this.children, this.minItemWidth = 300, this.spacing = 12, this.equalHeights = true});

  /// Nombre de colonnes pour une largeur donnée.
  static int columnsFor(double width, double minItemWidth, double spacing) => ((width + spacing) / (minItemWidth + spacing)).floor().clamp(1, 6);

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final cols = columnsFor(box.maxWidth, minItemWidth, spacing);
        // Une colonne (téléphone) : éléments empilés pleine largeur (pas d'étirement vertical dans une zone défilante).
        if (cols == 1) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var i = 0; i < children.length; i++) ...[if (i > 0) SizedBox(height: spacing), children[i]],
          ]);
        }
        final rows = <Widget>[];
        for (var i = 0; i < children.length; i += cols) {
          // Dernière ligne incomplète : ses éléments se partagent toute la largeur (pas de case vide).
          final n = (children.length - i).clamp(0, cols);
          final row = Row(crossAxisAlignment: equalHeights ? CrossAxisAlignment.stretch : CrossAxisAlignment.start, children: [
            for (var j = 0; j < n; j++) ...[
              if (j > 0) SizedBox(width: spacing),
              Expanded(child: children[i + j]),
            ],
          ]);
          if (rows.isNotEmpty) rows.add(SizedBox(height: spacing));
          rows.add(equalHeights ? IntrinsicHeight(child: row) : row);
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
      });
}

class PageBody extends StatelessWidget {
  final List<Widget> children;
  final double maxWidth;
  const PageBody({super.key, required this.children, this.maxWidth = 1400});
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 48),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
          ),
        ),
      );
}
