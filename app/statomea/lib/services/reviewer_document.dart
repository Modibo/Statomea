import 'dart:typed_data';

import 'package:statomea_core/statomea_core.dart' hide Step;

import 'protocol_document.dart' show packDocx;

String _esc(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

/// Lettre de réponse aux relecteurs (Word) : chaque commentaire cité en italique, la réponse, la modification apportée
/// au manuscrit ; les éléments « à compléter » sont surlignés.
Uint8List reviewerLetterDocx(Project p) {
  String run(String t, {bool bold = false, bool italic = false, bool highlight = false}) {
    final props = [if (bold) '<w:b/>', if (italic) '<w:i/>', if (highlight) '<w:highlight w:val="yellow"/>'].join();
    return '<w:r>${props.isEmpty ? '' : '<w:rPr>$props</w:rPr>'}<w:t xml:space="preserve">${_esc(t)}</w:t></w:r>';
  }

  String text(String t, {bool bold = false, bool italic = false}) {
    final b = StringBuffer();
    var i = 0;
    for (final m in RegExp(r'\[(?:À compléter|To complete)[^\]]*\]').allMatches(t)) {
      if (m.start > i) b.write(run(t.substring(i, m.start), bold: bold, italic: italic));
      b.write(run(m.group(0)!, highlight: true));
      i = m.end;
    }
    if (i < t.length) b.write(run(t.substring(i), bold: bold, italic: italic));
    return b.toString();
  }

  String para(String inner, {String? style, bool indent = false}) =>
      '<w:p>${style != null || indent ? '<w:pPr>${style == null ? '' : '<w:pStyle w:val="$style"/>'}${indent ? '<w:ind w:left="567"/>' : ''}</w:pPr>' : ''}$inner</w:p>';
  final body = StringBuffer()
    ..write(para(text(tr('Réponse aux relecteurs', 'Response to reviewers')), style: 'Title'))
    ..write(para(text(p.title), style: 'Subtitle'))
    ..write(para(text(tr('Madame, Monsieur l\'Éditeur,', 'Dear Editor,'))))
    ..write(para(text(tr('Nous remercions l\'éditeur et les relecteurs pour leurs commentaires, qui ont permis d\'améliorer le manuscrit. Nos réponses figurent ci-dessous, point par point ; les modifications sont indiquées dans le manuscrit révisé.',
        'We thank the editor and the reviewers for their comments, which have improved the manuscript. Our point-by-point responses are given below; changes are indicated in the revised manuscript.'))));
  var reviewer = '\u0000';
  var k = 0;
  for (final it in p.reviewerItems) {
    if (it.reviewer != reviewer) {
      reviewer = it.reviewer;
      k = 0;
      body.write(para(text(reviewer.isEmpty ? tr('Commentaires', 'Comments') : reviewer), style: 'Heading1'));
    }
    k++;
    body
      ..write(para(text(tr('Commentaire $k', 'Comment $k'), bold: true)))
      ..write(para(text(it.comment, italic: true), indent: true))
      ..write(para(run(tr('Réponse : ', 'Response: '), bold: true) + text(it.response)))
      ..write(para(run(tr('Modification : ', 'Change: '), bold: true) + text(it.change)));
  }
  body.write(para(text(tr('Nous espérons que ces modifications répondent aux attentes des relecteurs. Veuillez agréer nos salutations distinguées.', 'We hope these revisions address the reviewers\' concerns. Yours sincerely,'))));
  body.write(para(text(tr('[À compléter : auteurs]', '[To complete: authors]'))));
  return packDocx(body.toString());
}
