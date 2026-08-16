/// Line diff (Myers O(ND)) with prefix/suffix trimming and a depth cap.
library;

class DiffOp {
  final String t; // ' ' same, '-' removed, '+' added
  final String s;
  const DiffOp(this.t, this.s);
}

class DiffResult {
  final List<DiffOp> ops;
  final bool capped;
  final int changes;
  DiffResult(this.ops, {this.capped = false})
      : changes = ops.where((o) => o.t != ' ').length;
}

List<String> prepLines(String text,
    {bool dropComments = false, bool squashWs = false}) {
  var lines = text.replaceAll(RegExp(r'\r\n?'), '\n').split('\n');
  if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
  if (dropComments) {
    lines = lines.where((l) => !RegExp(r'^\s*[!#;]').hasMatch(l)).toList();
  }
  if (squashWs) {
    lines = lines.map((l) => l.replaceAll(RegExp(r'\s+'), ' ').trim()).toList();
  }
  return lines;
}

DiffResult diffLines(List<String> aLines, List<String> bLines) {
  var s0 = 0;
  while (s0 < aLines.length && s0 < bLines.length && aLines[s0] == bLines[s0]) {
    s0++;
  }
  var aEnd = aLines.length, bEnd = bLines.length;
  while (aEnd > s0 && bEnd > s0 && aLines[aEnd - 1] == bLines[bEnd - 1]) {
    aEnd--;
    bEnd--;
  }
  final a = aLines.sublist(s0, aEnd);
  final b = bLines.sublist(s0, bEnd);
  final n = a.length, m = b.length;
  final pre = aLines.sublist(0, s0).map((s) => DiffOp(' ', s)).toList();
  final post = aLines.sublist(aEnd).map((s) => DiffOp(' ', s)).toList();
  if (n == 0 && m == 0) return DiffResult([...pre, ...post]);
  if (n == 0) {
    return DiffResult([...pre, ...b.map((s) => DiffOp('+', s)), ...post]);
  }
  if (m == 0) {
    return DiffResult([...pre, ...a.map((s) => DiffOp('-', s)), ...post]);
  }
  final max = n + m, off = max + 1;
  const cap = 2500;
  final v = List<int>.filled(2 * max + 3, 0);
  final trace = <List<int>>[];
  var dFound = -1;
  outer:
  for (var d = 0; d <= (max < cap ? max : cap); d++) {
    trace.add(v.sublist(off - d - 1, off + d + 2));
    for (var k = -d; k <= d; k += 2) {
      int x;
      if (k == -d || (k != d && v[off + k - 1] < v[off + k + 1])) {
        x = v[off + k + 1];
      } else {
        x = v[off + k - 1] + 1;
      }
      var y = x - k;
      while (x < n && y < m && a[x] == b[y]) {
        x++;
        y++;
      }
      v[off + k] = x;
      if (x >= n && y >= m) {
        dFound = d;
        break outer;
      }
    }
  }
  if (dFound < 0) {
    return DiffResult(
        [...pre, ...a.map((s) => DiffOp('-', s)), ...b.map((s) => DiffOp('+', s)), ...post],
        capped: true);
  }
  var x = n, y = m;
  final mid = <DiffOp>[];
  for (var d = dFound; d > 0; d--) {
    final vd = trace[d];
    final o = d + 1;
    final k = x - y;
    int pk;
    if (k == -d || (k != d && vd[o + k - 1] < vd[o + k + 1])) {
      pk = k + 1;
    } else {
      pk = k - 1;
    }
    final px = vd[o + pk], py = px - pk;
    while (x > px && y > py) {
      mid.add(DiffOp(' ', a[x - 1]));
      x--;
      y--;
    }
    if (x == px) {
      mid.add(DiffOp('+', b[y - 1]));
      y--;
    } else {
      mid.add(DiffOp('-', a[x - 1]));
      x--;
    }
  }
  while (x > 0 && y > 0) {
    mid.add(DiffOp(' ', a[x - 1]));
    x--;
    y--;
  }
  while (x > 0) {
    mid.add(DiffOp('-', a[x - 1]));
    x--;
  }
  while (y > 0) {
    mid.add(DiffOp('+', b[y - 1]));
    y--;
  }
  return DiffResult([...pre, ...mid.reversed, ...post]);
}
