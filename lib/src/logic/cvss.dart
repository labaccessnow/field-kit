/// CVSS v3.1 base score, straight from the FIRST specification.
library;
import 'dart:math' as math;

const cvssMetrics = <String, List<String>>{
  'AV': ['N', 'A', 'L', 'P'],
  'AC': ['L', 'H'],
  'PR': ['N', 'L', 'H'],
  'UI': ['N', 'R'],
  'S': ['U', 'C'],
  'C': ['N', 'L', 'H'],
  'I': ['N', 'L', 'H'],
  'A': ['N', 'L', 'H'],
};

const cvssLabels = <String, String>{
  'AV': 'Attack Vector',
  'AC': 'Attack Complexity',
  'PR': 'Privileges Required',
  'UI': 'User Interaction',
  'S': 'Scope',
  'C': 'Confidentiality',
  'I': 'Integrity',
  'A': 'Availability',
};

const cvssOptionNames = <String, Map<String, String>>{
  'AV': {'N': 'Network', 'A': 'Adjacent', 'L': 'Local', 'P': 'Physical'},
  'AC': {'L': 'Low', 'H': 'High'},
  'PR': {'N': 'None', 'L': 'Low', 'H': 'High'},
  'UI': {'N': 'None', 'R': 'Required'},
  'S': {'U': 'Unchanged', 'C': 'Changed'},
  'C': {'N': 'None', 'L': 'Low', 'H': 'High'},
  'I': {'N': 'None', 'L': 'Low', 'H': 'High'},
  'A': {'N': 'None', 'L': 'Low', 'H': 'High'},
};

double _roundup(double x) {
  final i = (x * 100000).round();
  if (i % 10000 == 0) return i / 100000;
  return ((i ~/ 10000) + 1) / 10;
}

String cvssSeverity(double s) {
  if (s <= 0) return 'None';
  if (s < 4) return 'Low';
  if (s < 7) return 'Medium';
  if (s < 9) return 'High';
  return 'Critical';
}

class CvssResult {
  final double score;
  final String severity;
  final String vector;
  final String? err;
  CvssResult(this.score, this.severity, this.vector) : err = null;
  CvssResult.fail(this.err)
      : score = 0,
        severity = '',
        vector = '';
}

CvssResult cvssScore(Map<String, String> m) {
  for (final k in cvssMetrics.keys) {
    if (!cvssMetrics[k]!.contains(m[k])) {
      return CvssResult.fail('Missing or invalid metric: $k');
    }
  }
  const av = {'N': 0.85, 'A': 0.62, 'L': 0.55, 'P': 0.2};
  const ac = {'L': 0.77, 'H': 0.44};
  const prU = {'N': 0.85, 'L': 0.62, 'H': 0.27};
  const prC = {'N': 0.85, 'L': 0.68, 'H': 0.5};
  const ui = {'N': 0.85, 'R': 0.62};
  const cia = {'H': 0.56, 'L': 0.22, 'N': 0.0};
  final changed = m['S'] == 'C';
  final iss =
      1 - ((1 - cia[m['C']]!) * (1 - cia[m['I']]!) * (1 - cia[m['A']]!));
  final impact = changed
      ? 7.52 * (iss - 0.029) - 3.25 * math.pow(iss - 0.02, 15)
      : 6.42 * iss;
  final expl = 8.22 *
      av[m['AV']]! *
      ac[m['AC']]! *
      (changed ? prC : prU)[m['PR']]! *
      ui[m['UI']]!;
  final score = impact <= 0
      ? 0.0
      : _roundup(math.min(changed ? 1.08 * (impact + expl) : impact + expl, 10));
  final vector =
      'CVSS:3.1/AV:${m['AV']}/AC:${m['AC']}/PR:${m['PR']}/UI:${m['UI']}/S:${m['S']}/C:${m['C']}/I:${m['I']}/A:${m['A']}';
  return CvssResult(score, cvssSeverity(score), vector);
}

/// Parses a vector string like CVSS:3.1/AV:N/AC:L/... into a metric map.
({Map<String, String>? m, String? err}) cvssParse(String str) {
  final m = <String, String>{};
  final body = str.trim().replaceFirst(RegExp(r'^CVSS:3\.[01]/', caseSensitive: false), '');
  for (final p in body.split('/')) {
    final kv = p.split(':');
    if (kv.length == 2) {
      final k = kv[0].toUpperCase();
      if (cvssMetrics.containsKey(k)) m[k] = kv[1].toUpperCase();
    }
  }
  for (final k in cvssMetrics.keys) {
    if (!m.containsKey(k)) {
      return (m: null, err: 'Vector is missing $k (${cvssLabels[k]})');
    }
  }
  return (m: m, err: null);
}
