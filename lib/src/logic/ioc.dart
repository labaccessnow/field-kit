/// IOC extraction: pull every indicator out of an arbitrary blob of text.
/// Defanged input is refanged first, so pasting straight from a report works.
library;

import 'defang.dart';
import 'ipv4.dart';
import 'ipv6.dart';

class IocResult {
  final List<String> ips, ips6, domains, urls, emails, cves;
  final List<String> md5, sha1, sha256;
  IocResult(this.ips, this.ips6, this.domains, this.urls, this.emails,
      this.cves, this.md5, this.sha1, this.sha256);

  int get total =>
      ips.length +
      ips6.length +
      domains.length +
      urls.length +
      emails.length +
      cves.length +
      md5.length +
      sha1.length +
      sha256.length;
}

// File suffixes that the domain regex would misread as a TLD.
const _fileExts = {
  'php', 'exe', 'dll', 'pdf', 'doc', 'docx', 'xls', 'xlsx', 'txt', 'ps1',
  'bat', 'zip', 'rar', 'js', 'html', 'htm', 'png', 'jpg', 'jpeg', 'gif',
  'py', 'sh', 'bin', 'dat', 'tmp', 'log', 'ini', 'cfg', 'dmg', 'iso',
  'msi', 'vbs', 'lnk', 'json', 'xml', 'csv', 'yml', 'yaml', 'md', 'crt',
  'pem', 'key', 'jar', 'apk', 'elf', 'scr', 'gz', 'tar', 'bz2', '7z',
};

List<String> _dedupe(Iterable<String> xs) {
  final seen = <String>{};
  final out = <String>[];
  for (final x in xs) {
    if (seen.add(x)) out.add(x);
  }
  return out;
}

IocResult extractIocs(String input) {
  final t = refang(input);

  final urls = _dedupe(RegExp(r'''\bhttps?://[^\s"'<>()\[\]{}]+''',
          caseSensitive: false)
      .allMatches(t)
      .map((m) => m[0]!.replaceAll(RegExp(r'[.,;:]+$'), '')));

  final emails = _dedupe(RegExp(
          r'\b[a-z0-9._%+-]+@(?:[a-z0-9-]+\.)+[a-z]{2,}\b',
          caseSensitive: false)
      .allMatches(t)
      .map((m) => m[0]!.toLowerCase()));

  final ips = _dedupe(RegExp(r'\b(?:\d{1,3}\.){3}\d{1,3}\b')
      .allMatches(t)
      .map((m) => m[0]!)
      .where((s) => ip2int(s) != null));

  final ips6 = _dedupe(RegExp(r'\b[0-9a-fA-F:]*::?[0-9a-fA-F:.]+\b')
      .allMatches(t)
      .map((m) => m[0]!)
      .where((s) => s.contains(':') && parse6(s) != null)
      .map((s) => compress6(parse6(s)!)));

  final domains = _dedupe(RegExp(
          r'\b(?:[a-z0-9_-]+\.)+([a-z]{2,})\b',
          caseSensitive: false)
      .allMatches(t)
      .where((m) => !_fileExts.contains(m[1]!.toLowerCase()))
      .map((m) => m[0]!.toLowerCase()));

  List<String> hex(int n) => _dedupe(RegExp('\\b[0-9a-fA-F]{$n}\\b')
      .allMatches(t)
      .map((m) => m[0]!.toLowerCase())
      // require at least one digit and one letter mix is too strict for real
      // hashes, but pure-decimal runs of exactly n digits are almost always
      // not hashes (timestamps, ids) — drop those.
      .where((s) => RegExp(r'[a-f]').hasMatch(s)));

  final cves = _dedupe(RegExp(r'\bCVE-\d{4}-\d{4,7}\b', caseSensitive: false)
      .allMatches(t)
      .map((m) => m[0]!.toUpperCase()));

  return IocResult(ips, ips6, domains, urls, emails, cves, hex(32), hex(40),
      hex(64));
}

/// The whole result as a defanged, sectioned text block for tickets.
String iocReport(IocResult r, {bool defanged = true}) {
  final buf = StringBuffer();
  void sec(String name, List<String> xs) {
    if (xs.isEmpty) return;
    buf.writeln('# $name (${xs.length})');
    for (final x in xs) {
      buf.writeln(defanged ? defang(x) : x);
    }
    buf.writeln();
  }

  sec('IPv4', r.ips);
  sec('IPv6', r.ips6);
  sec('Domains', r.domains);
  sec('URLs', r.urls);
  sec('Emails', r.emails);
  sec('CVEs', r.cves);
  sec('MD5', r.md5);
  sec('SHA-1', r.sha1);
  sec('SHA-256', r.sha256);
  return buf.toString().trim();
}
