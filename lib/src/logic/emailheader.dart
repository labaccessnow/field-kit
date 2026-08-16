/// Email header analysis: the Received chain with per-hop delay,
/// authentication verdicts, and the mismatches phishing triage looks for.
library;

import 'ipv4.dart';

class Hop {
  final String raw;
  final String? from, by, ip;
  final DateTime? date;
  int? delaySec; // vs previous (earlier) hop
  Hop(this.raw, this.from, this.by, this.ip, this.date);
}

class HeaderAnalysis {
  final Map<String, String> fields; // last-seen simple headers, lowercased keys
  final List<Hop> hops; // chronological: origin first
  final String? spf, dkim, dmarc;
  final String? originIp;
  final List<String> warnings;
  HeaderAnalysis(this.fields, this.hops, this.spf, this.dkim, this.dmarc,
      this.originIp, this.warnings);
}

const _months = {
  'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
  'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
};

/// Parses an RFC 2822 date ("Sat, 16 Aug 2026 02:00:00 -0400 (EDT)").
DateTime? parseRfc2822(String s) {
  final m = RegExp(
          r'(\d{1,2})\s+([A-Za-z]{3})\w*\s+(\d{2,4})\s+(\d{1,2}):(\d{2})(?::(\d{2}))?\s*([+-]\d{4}|[A-Z]{2,4})?')
      .firstMatch(s);
  if (m == null) return null;
  final mon = _months[m[2]!.toLowerCase()];
  if (mon == null) return null;
  var year = int.parse(m[3]!);
  if (year < 100) year += year < 70 ? 2000 : 1900;
  var offMin = 0;
  final tz = m[7];
  if (tz != null && RegExp(r'^[+-]\d{4}$').hasMatch(tz)) {
    final sign = tz.startsWith('-') ? -1 : 1;
    offMin = sign * (int.parse(tz.substring(1, 3)) * 60 + int.parse(tz.substring(3, 5)));
  } else {
    const named = {'UT': 0, 'GMT': 0, 'EST': -300, 'EDT': -240, 'CST': -360,
      'CDT': -300, 'MST': -420, 'MDT': -360, 'PST': -480, 'PDT': -420};
    offMin = named[tz] ?? 0;
  }
  final local = DateTime.utc(year, mon, int.parse(m[1]!), int.parse(m[4]!),
      int.parse(m[5]!), int.parse(m[6] ?? '0'));
  return local.subtract(Duration(minutes: offMin));
}

bool _isPublicV4(String ip) {
  final n = ip2int(ip);
  if (n == null) return false;
  bool inRange(String cidr) {
    final p = parseCidr(cidr).value!;
    return (n & maskOf(p.len)) == p.base;
  }

  for (final c in [
    '10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16', '127.0.0.0/8',
    '169.254.0.0/16', '100.64.0.0/10', '0.0.0.0/8',
  ]) {
    if (inRange(c)) return false;
  }
  return true;
}

HeaderAnalysis analyzeHeaders(String raw) {
  // Unfold: continuation lines start with whitespace. Stop at the blank line
  // separating headers from body.
  final lines = raw.replaceAll('\r\n', '\n').split('\n');
  final unfolded = <String>[];
  for (final line in lines) {
    if (line.trim().isEmpty) {
      if (unfolded.isNotEmpty) break; // header block over
      continue;
    }
    if ((line.startsWith(' ') || line.startsWith('\t')) && unfolded.isNotEmpty) {
      unfolded[unfolded.length - 1] += ' ${line.trim()}';
    } else {
      unfolded.add(line);
    }
  }

  final fields = <String, String>{};
  final received = <String>[];
  final authResults = <String>[];
  for (final h in unfolded) {
    final i = h.indexOf(':');
    if (i <= 0) continue;
    final k = h.substring(0, i).trim().toLowerCase();
    final v = h.substring(i + 1).trim();
    if (k == 'received') {
      received.add(v);
    } else if (k == 'authentication-results' || k == 'received-spf') {
      authResults.add(v);
      fields.putIfAbsent(k, () => v);
    } else {
      fields.putIfAbsent(k, () => v); // keep the topmost occurrence
    }
  }

  // Received headers are prepended, so header order is newest-first.
  final hops = <Hop>[];
  for (final r in received.reversed) {
    final fromM = RegExp(r'from\s+([^\s;()]+)', caseSensitive: false).firstMatch(r);
    final byM = RegExp(r'\bby\s+([^\s;()]+)', caseSensitive: false).firstMatch(r);
    String? ip;
    for (final m in RegExp(r'[\[\(](?:IPv6:)?((?:\d{1,3}\.){3}\d{1,3})[\]\)]')
        .allMatches(r)) {
      ip = m[1];
      break;
    }
    final semi = r.lastIndexOf(';');
    final date = semi >= 0 ? parseRfc2822(r.substring(semi + 1)) : null;
    hops.add(Hop(r, fromM?[1], byM?[1], ip, date));
  }
  for (var i = 1; i < hops.length; i++) {
    final a = hops[i - 1].date, b = hops[i].date;
    if (a != null && b != null) hops[i].delaySec = b.difference(a).inSeconds;
  }

  String? verdict(String key) {
    for (final a in authResults) {
      final m = RegExp('$key=(\\w+)', caseSensitive: false).firstMatch(a);
      if (m != null) return m[1]!.toLowerCase();
    }
    return null;
  }

  final spf = verdict('spf');
  final dkim = verdict('dkim');
  final dmarc = verdict('dmarc');

  String? originIp;
  for (final h in hops) {
    if (h.ip != null && _isPublicV4(h.ip!)) {
      originIp = h.ip;
      break;
    }
  }

  String? domainOf(String? addr) {
    if (addr == null) return null;
    final m = RegExp(r'@([a-z0-9.-]+)', caseSensitive: false).firstMatch(addr);
    return m?[1]?.toLowerCase().replaceAll(RegExp(r'[>\s].*$'), '');
  }

  final warnings = <String>[];
  final fromDom = domainOf(fields['from']);
  final rpDom = domainOf(fields['return-path']);
  final replyDom = domainOf(fields['reply-to']);
  if (fromDom != null && rpDom != null && fromDom != rpDom) {
    warnings.add('From domain ($fromDom) ≠ Return-Path domain ($rpDom) — '
        'common in bulk mail, also in spoofing.');
  }
  if (fromDom != null && replyDom != null && fromDom != replyDom) {
    warnings.add('Reply-To goes to a different domain ($replyDom) than From '
        '($fromDom) — classic BEC pattern.');
  }
  for (final e in [('spf', spf), ('dkim', dkim), ('dmarc', dmarc)]) {
    if (e.$2 == 'fail' || e.$2 == 'permerror' || e.$2 == 'softfail') {
      warnings.add('${e.$1.toUpperCase()} verdict: ${e.$2}.');
    }
  }
  for (var i = 1; i < hops.length; i++) {
    final d = hops[i].delaySec;
    if (d != null && d < -60) {
      warnings.add('Hop ${i + 1} is timestamped ${-d}s BEFORE the previous '
          'hop — clock skew or forged Received header.');
    }
  }

  return HeaderAnalysis(fields, hops, spf, dkim, dmarc, originIp, warnings);
}
