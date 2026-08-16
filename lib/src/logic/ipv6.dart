/// IPv6 math on BigInt: parse, RFC 5952 compression, subnet info,
/// aggregation. Mirrors the IPv4 module's shapes.
library;

final BigInt _mask128 = (BigInt.one << 128) - BigInt.one;

/// Parses an IPv6 address (supports ::, and a trailing embedded IPv4).
BigInt? parse6(String s) {
  var t = s.trim().toLowerCase();
  if (t.isEmpty || !t.contains(':')) return null;
  if (t.contains('%')) t = t.split('%').first; // zone index
  if (RegExp(r'[^0-9a-f:.]').hasMatch(t)) return null;
  if ('::'.allMatches(t).length > 1) return null;
  if (t.contains(':::')) return null;

  String head = t, tail = '';
  if (t.contains('::')) {
    final parts = t.split('::');
    head = parts[0];
    tail = parts[1];
  } else {
    tail = '';
  }

  List<String> groupsOf(String x) =>
      x.isEmpty ? [] : x.split(':').where((g) => true).toList();

  var headG = groupsOf(head);
  var tailG = t.contains('::') ? groupsOf(tail) : <String>[];
  if (!t.contains('::')) {
    headG = groupsOf(t);
    tailG = [];
  }

  // Embedded IPv4 in the last group of whichever side ends the address.
  List<String>? expandV4(List<String> gs) {
    if (gs.isEmpty || !gs.last.contains('.')) return gs;
    final oct = gs.last.split('.');
    if (oct.length != 4) return null;
    var v = 0;
    final parts = <int>[];
    for (final o in oct) {
      final n = int.tryParse(o);
      if (n == null || n > 255 || o.isEmpty) return null;
      parts.add(n);
    }
    v = (parts[0] << 8) + parts[1];
    final w = (parts[2] << 8) + parts[3];
    return [...gs.sublist(0, gs.length - 1), v.toRadixString(16), w.toRadixString(16)];
  }

  final h2 = expandV4(headG);
  if (h2 == null) return null;
  headG = h2;
  final t2 = expandV4(tailG);
  if (t2 == null) return null;
  tailG = t2;

  for (final g in [...headG, ...tailG]) {
    if (g.isEmpty || g.length > 4 || g.contains('.')) return null;
  }

  final total = headG.length + tailG.length;
  if (t.contains('::')) {
    if (total > 7) return null;
  } else {
    if (total != 8) return null;
  }

  final groups = [
    ...headG,
    ...List.filled(t.contains('::') ? 8 - total : 0, '0'),
    ...tailG,
  ];
  var v = BigInt.zero;
  for (final g in groups) {
    v = (v << 16) + BigInt.from(int.parse(g, radix: 16));
  }
  return v;
}

String expand6(BigInt v) {
  final gs = <String>[];
  for (var i = 7; i >= 0; i--) {
    final g = ((v >> (i * 16)) & BigInt.from(0xffff)).toInt();
    gs.add(g.toRadixString(16).padLeft(4, '0'));
  }
  return gs.join(':');
}

/// RFC 5952 canonical form: lowercase, no leading zeros, longest zero run
/// (of two or more groups) becomes ::, first one wins on a tie.
String compress6(BigInt v) {
  final gs = <int>[];
  for (var i = 7; i >= 0; i--) {
    gs.add(((v >> (i * 16)) & BigInt.from(0xffff)).toInt());
  }
  var bestStart = -1, bestLen = 0;
  var i = 0;
  while (i < 8) {
    if (gs[i] == 0) {
      var j = i;
      while (j < 8 && gs[j] == 0) {
        j++;
      }
      if (j - i > bestLen) {
        bestLen = j - i;
        bestStart = i;
      }
      i = j;
    } else {
      i++;
    }
  }
  if (bestLen < 2) {
    return gs.map((g) => g.toRadixString(16)).join(':');
  }
  final before = gs.sublist(0, bestStart).map((g) => g.toRadixString(16));
  final after = gs.sublist(bestStart + bestLen).map((g) => g.toRadixString(16));
  return '${before.join(':')}::${after.join(':')}';
}

class Cidr6 {
  final BigInt base;
  final int len;
  final bool hostBits;
  Cidr6(this.base, this.len, this.hostBits);
}

Cidr6? parseCidr6(String s) {
  final m = RegExp(r'^\s*([0-9a-fA-F:.%]+)\s*/\s*(\d{1,3})\s*$').firstMatch(s);
  if (m == null) return null;
  final v = parse6(m[1]!);
  final len = int.parse(m[2]!);
  if (v == null || len > 128) return null;
  final mask = len == 0 ? BigInt.zero : (_mask128 << (128 - len)) & _mask128;
  final base = v & mask;
  return Cidr6(base, len, base != v);
}

class Subnet6Info {
  final String cidr, expanded, first, last, count;
  final int len;
  Subnet6Info(this.cidr, this.expanded, this.first, this.last, this.count,
      this.len);
}

Subnet6Info subnet6Info(Cidr6 c) {
  final size = BigInt.one << (128 - c.len);
  final last = c.base + size - BigInt.one;
  final count = c.len >= 64
      ? size.toString()
      : '2^${128 - c.len}'; // beyond human-sized numbers, say it as a power
  return Subnet6Info('${compress6(c.base)}/${c.len}', expand6(c.base),
      compress6(c.base), compress6(last), count, c.len);
}

/// Merge a list of IPv6 prefixes into the minimal covering set.
List<String> aggregate6(List<Cidr6> input) {
  if (input.isEmpty) return const [];
  final iv = input
      .map((c) => [c.base, c.base + (BigInt.one << (128 - c.len)) - BigInt.one])
      .toList()
    ..sort((a, b) {
      final c = a[0].compareTo(b[0]);
      return c != 0 ? c : a[1].compareTo(b[1]);
    });
  final merged = <List<BigInt>>[];
  for (final r in iv) {
    if (merged.isNotEmpty && r[0] <= merged.last[1] + BigInt.one) {
      if (r[1] > merged.last[1]) merged.last[1] = r[1];
    } else {
      merged.add([r[0], r[1]]);
    }
  }
  final out = <String>[];
  for (final r in merged) {
    var s = r[0];
    final e = r[1];
    while (s <= e) {
      final alignBits = s == BigInt.zero ? 128 : _lowestSetBit(s);
      final remaining = e - s + BigInt.one;
      var sizeBits = remaining.bitLength - 1; // floor(log2)
      if (alignBits < sizeBits) sizeBits = alignBits;
      if (sizeBits > 128) sizeBits = 128;
      out.add('${compress6(s)}/${128 - sizeBits}');
      s += BigInt.one << sizeBits;
    }
  }
  return out;
}

int _lowestSetBit(BigInt v) {
  var n = 0;
  var x = v;
  while (x.isEven && n < 128) {
    x >>= 1;
    n++;
  }
  return n;
}
