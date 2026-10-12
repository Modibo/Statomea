import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// Charge un fichier de référence produit par validation/r/*.R.
Map<String, dynamic> loadRef(String name) =>
    jsonDecode(File('test/reference/$name.json').readAsStringSync()) as Map<String, dynamic>;

double? asD(Object? v) => switch (v) {
      null => null,
      num n => n.toDouble(),
      'Inf' => double.infinity,
      '-Inf' => double.negativeInfinity,
      'NaN' || 'NA' => double.nan,
      _ => throw ArgumentError('valeur non numérique : $v'),
    };

/// Égalité à une tolérance relative (et absolue près de zéro).
Matcher closeRel(num expected, {double rel = 1e-8, double abs = 1e-12}) =>
    predicate<num>((a) {
      if (expected.isInfinite) return a == expected;
      final d = (a - expected).abs();
      return d <= abs || d <= rel * expected.abs();
    }, 'à ${rel.toStringAsExponential(0)} près de $expected');
