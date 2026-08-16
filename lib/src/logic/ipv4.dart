/// IPv4 math: subnetting, VLSM planning, CIDR aggregation, wildcard masks.
/// Pure Dart, no I/O — everything is unit-tested in test/ipv4_test.dart.
library;

int? ip2int(String s) {
  final m = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$')
      .firstMatch(s.trim());
  if (m == null) return null;
  var n = 0;
  for (var i = 1; i <= 4; i++) {
    final o = int.parse(m[i]!);
    if (o > 255) return null;
    n = (n << 8) + o;
  }
  return n;
}

String int2ip(int n) =>
    '${(n >> 24) & 255}.${(n >> 16) & 255}.${(n >> 8) & 255}.${n & 255}';

int maskOf(int len) => len == 0 ? 0 : (0xFFFFFFFF << (32 - len)) & 0xFFFFFFFF;

class Cidr {
  final int base;
  final int len;
  final int given;
  final bool hostBits;
  Cidr(this.base, this.len, this.given) : hostBits = base != given;
}

class ParseResult<T> {
  final T? value;
  final String? err;
  ParseResult.ok(this.value) : err = null;
  ParseResult.fail(this.err) : value = null;
}

ParseResult<Cidr> parseCidr(String s) {
  final m = RegExp(r'^\s*([\d.]+)\s*/\s*(\d{1,2})\s*$').firstMatch(s);
  if (m == null) return ParseResult.fail('use CIDR form like 10.0.0.0/24');
  final ip = ip2int(m[1]!);
  final len = int.parse(m[2]!);
  if (ip == null) return ParseResult.fail('invalid IPv4 address');
  if (len > 32) return ParseResult.fail('prefix length must be 0-32');
  final base = ip & maskOf(len);
  return ParseResult.ok(Cidr(base, len, ip));
}

class SubnetInfo {
  final int base;
  final int len;
  final String network, cidr, mask, wildcard, broadcast, first, last;
  final int size, usable;
  String name;
  int? reqHosts;

  SubnetInfo._(this.base, this.len, this.network, this.cidr, this.mask,
      this.wildcard, this.broadcast, this.first, this.last, this.size,
      this.usable)
      : name = '';

  factory SubnetInfo.of(int base, int len) {
    final mask = maskOf(len);
    final bcast = base | (~mask & 0xFFFFFFFF);
    final size = len == 32 ? 1 : 1 << (32 - len);
    var first = base, last = bcast, usable = size;
    if (len <= 30) {
      first = base + 1;
      last = bcast - 1;
      usable = size - 2;
    }
    return SubnetInfo._(
      base,
      len,
      int2ip(base),
      '${int2ip(base)}/$len',
      int2ip(mask),
      int2ip(~mask & 0xFFFFFFFF),
      len >= 31 ? '—' : int2ip(bcast),
      int2ip(first),
      int2ip(last),
      size,
      usable,
    );
  }
}

int? hostsToLen(int h) {
  for (var len = 30; len >= 0; len--) {
    if ((1 << (32 - len)) - 2 >= h) return len;
  }
  return null;
}

class VlsmPlan {
  final List<SubnetInfo> rows;
  final SubnetInfo? parent;
  final int free;
  final bool hostBits;
  final String given;
  final String? err;
  VlsmPlan(this.rows, this.parent, this.free, this.hostBits, this.given,
      [this.err]);
}

VlsmPlan vlsmPlan(String parentStr, String reqText) {
  VlsmPlan fail(String e) => VlsmPlan(const [], null, 0, false, '', e);
  final p = parseCidr(parentStr);
  if (p.err != null) return fail('Parent network: ${p.err}');
  final parent = p.value!;
  final lines = reqText
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();
  if (lines.isEmpty) {
    return fail('Add at least one subnet request (one per line).');
  }
  if (lines.length > 256) return fail('Keep it under 256 subnet requests.');
  final reqs = <({String name, int len, int? hosts})>[];
  final lineRe = RegExp(r'^(?:(.*?)[\s:,]+)?(?:/(\d{1,2})|(\d+)\s*(?:hosts?)?)$',
      caseSensitive: false);
  for (final line in lines) {
    final m = lineRe.firstMatch(line);
    if (m == null) {
      return fail('Could not read "$line" — use "name: hosts" or "name: /len".');
    }
    var name = (m[1] ?? '').replaceAll(RegExp(r'[:,]+$'), '').trim();
    if (name.isEmpty) name = 'subnet-${reqs.length + 1}';
    int len;
    int? hosts;
    if (m[2] != null) {
      len = int.parse(m[2]!);
      if (len < 1 || len > 32) return fail('Bad prefix length in "$line".');
    } else {
      hosts = int.parse(m[3]!);
      final l = hostsToLen(hosts);
      if (l == null) return fail('"$line": that host count does not fit in IPv4.');
      len = l;
    }
    reqs.add((name: name, len: len, hosts: hosts));
  }
  final order = List.generate(reqs.length, (i) => i)
    ..sort((a, b) {
      final c = reqs[a].len.compareTo(reqs[b].len);
      return c != 0 ? c : a.compareTo(b);
    });
  var cursor = parent.base;
  final end = parent.base + (1 << (32 - parent.len));
  final rows = <SubnetInfo>[];
  for (final i in order) {
    final r = reqs[i];
    final size = 1 << (32 - r.len);
    final aligned = ((cursor + size - 1) ~/ size) * size;
    if (aligned + size > end) {
      return VlsmPlan(rows, SubnetInfo.of(parent.base, parent.len), 0,
          parent.hostBits, int2ip(parent.given),
          'Does not fit: "${r.name}" (/${r.len}) overflows ${int2ip(parent.base)}/${parent.len}.');
    }
    rows.add(SubnetInfo.of(aligned, r.len)
      ..name = r.name
      ..reqHosts = r.hosts);
    cursor = aligned + size;
  }
  return VlsmPlan(rows, SubnetInfo.of(parent.base, parent.len), end - cursor,
      parent.hostBits, int2ip(parent.given));
}

class AggregateResult {
  final List<String> list;
  final List<String> notes;
  final int inCount;
  final String? err;
  AggregateResult(this.list, this.notes, this.inCount, [this.err]);
}

AggregateResult aggregate(String text) {
  AggregateResult fail(String e) => AggregateResult(const [], const [], 0, e);
  final toks = text
      .split(RegExp(r'[\s,;]+'))
      .map((t) => t.trim())
      .where((t) => t.isNotEmpty)
      .toList();
  if (toks.isEmpty) {
    return fail('Paste at least one prefix (one per line, or space/comma separated).');
  }
  if (toks.length > 5000) return fail('Keep it under 5,000 prefixes.');
  final iv = <List<int>>[];
  final notes = <String>[];
  for (final tok in toks) {
    final s = tok.contains('/') ? tok : '$tok/32';
    final p = parseCidr(s);
    if (p.err != null) return fail('"$tok": ${p.err}');
    final c = p.value!;
    if (c.hostBits) {
      notes.add('$tok has host bits set — treated as ${int2ip(c.base)}/${c.len}');
    }
    iv.add([c.base, c.base + (1 << (32 - c.len)) - 1]);
  }
  iv.sort((a, b) => a[0] != b[0] ? a[0].compareTo(b[0]) : a[1].compareTo(b[1]));
  final merged = <List<int>>[];
  for (final r in iv) {
    if (merged.isNotEmpty && r[0] <= merged.last[1] + 1) {
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
      final alignSize = s == 0 ? (1 << 32) : s & -s;
      final remaining = e - s + 1;
      var size = 1;
      while (size * 2 <= remaining) {
        size *= 2;
      }
      if (alignSize < size) size = alignSize;
      final len = 32 - size.bitLength + 1;
      out.add('${int2ip(s)}/$len');
      s += size;
    }
  }
  return AggregateResult(out, notes, iv.length);
}

int popcount(int n) {
  var c = 0;
  var x = n & 0xFFFFFFFF;
  while (x != 0) {
    c += x & 1;
    x >>= 1;
  }
  return c;
}

class WildcardInfo {
  final String mode; // 'cidr' | 'wildcard'
  final String? cidr, mask;
  final String wildcard, base, acl;
  final int matched;
  final bool contiguous, normalized;
  final String? err;
  WildcardInfo(
      {required this.mode,
      this.cidr,
      this.mask,
      required this.wildcard,
      required this.base,
      required this.acl,
      required this.matched,
      required this.contiguous,
      required this.normalized,
      this.err});
  WildcardInfo.fail(this.err)
      : mode = '',
        cidr = null,
        mask = null,
        wildcard = '',
        base = '',
        acl = '',
        matched = 0,
        contiguous = false,
        normalized = false;
}

WildcardInfo wildcardInfo(String input) {
  final t = input.trim();
  final pair = RegExp(r'^([\d.]+)\s+([\d.]+)$').firstMatch(t);
  if (pair != null) {
    final ip = ip2int(pair[1]!);
    final wc = ip2int(pair[2]!);
    if (ip == null) return WildcardInfo.fail('invalid IPv4 address');
    if (wc == null) return WildcardInfo.fail('invalid wildcard mask');
    final contiguous = ((wc & (wc + 1)) & 0xFFFFFFFF) == 0;
    final base = ip & (~wc & 0xFFFFFFFF);
    String? cidr, mask;
    if (contiguous) {
      final len = 32 - (wc + 1).bitLength + 1;
      cidr = '${int2ip(base)}/$len';
      mask = int2ip(maskOf(len));
    }
    return WildcardInfo(
      mode: 'wildcard',
      cidr: cidr,
      mask: mask,
      wildcard: int2ip(wc),
      base: int2ip(base),
      acl: 'permit ip ${int2ip(base)} ${int2ip(wc)} any',
      matched: 1 << popcount(wc),
      contiguous: contiguous,
      normalized: base != ip,
    );
  }
  final p = parseCidr(t.contains('/') ? t : '$t/32');
  if (p.err != null) return WildcardInfo.fail(p.err);
  final c = p.value!;
  final wc = ~maskOf(c.len) & 0xFFFFFFFF;
  return WildcardInfo(
    mode: 'cidr',
    cidr: '${int2ip(c.base)}/${c.len}',
    mask: int2ip(maskOf(c.len)),
    wildcard: int2ip(wc),
    base: int2ip(c.base),
    acl: 'permit ip ${int2ip(c.base)} ${int2ip(wc)} any',
    matched: c.len == 32 ? 1 : 1 << (32 - c.len),
    contiguous: true,
    normalized: c.hostBits,
  );
}
