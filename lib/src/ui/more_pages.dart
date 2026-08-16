import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../logic/emailheader.dart';
import '../logic/ioc.dart';
import '../logic/oui.dart';
import '../theme.dart';
import 'common.dart';

/// ---------- Whois (network) ----------
class WhoisPage extends StatefulWidget {
  const WhoisPage({super.key});
  @override
  State<WhoisPage> createState() => _WhoisPageState();
}

class _WhoisPageState extends State<WhoisPage> {
  final input = TextEditingController();
  String out = '';
  String? err;
  bool running = false;

  static Future<String> _query(String server, String q) async {
    final s = await Socket.connect(server, 43,
        timeout: const Duration(seconds: 8));
    s.write('$q\r\n');
    final bytes = <int>[];
    await s
        .listen(bytes.addAll)
        .asFuture<void>()
        .timeout(const Duration(seconds: 12));
    s.destroy();
    return utf8.decode(bytes, allowMalformed: true);
  }

  Future<void> _run() async {
    final q = input.text.trim();
    if (q.isEmpty || !RegExp(r'^[A-Za-z0-9.:_-]+$').hasMatch(q)) {
      setState(() => err = 'Enter a domain or an IP.');
      return;
    }
    setState(() {
      running = true;
      err = null;
      out = '';
    });
    final buf = StringBuffer();
    try {
      final isIp = RegExp(r'^[\d.]+$').hasMatch(q) || q.contains(':');
      var server = isIp ? 'whois.arin.net' : 'whois.iana.org';
      var query = q;
      for (var hop = 0; hop < 3; hop++) {
        buf.writeln('===== $server =====');
        // ARIN needs a prefix to return the full object for plain queries.
        final sendQ =
            (server == 'whois.arin.net' && isIp) ? 'n + $query' : query;
        final resp = await _query(server, sendQ);
        buf.writeln(resp.trim());
        buf.writeln();
        String? next;
        final refer =
            RegExp(r'^\s*refer:\s*(\S+)', multiLine: true).firstMatch(resp);
        final registrar = RegExp(r'Registrar WHOIS Server:\s*(\S+)')
            .firstMatch(resp);
        final referral =
            RegExp(r'ReferralServer:\s*(?:r?whois://)?([^\s:/]+)')
                .firstMatch(resp);
        next = refer?[1] ?? registrar?[1] ?? referral?[1];
        if (next == null || next.isEmpty || next == server) break;
        server = next;
      }
      if (!mounted) return;
      setState(() => out = buf.toString().trim());
    } on SocketException catch (e) {
      if (mounted) setState(() => err = 'Whois failed: ${e.message}');
    } on TimeoutException {
      if (mounted) setState(() => err = 'Whois timed out.');
    } catch (e) {
      if (mounted) setState(() => err = 'Whois failed: $e');
    } finally {
      if (mounted) setState(() => running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ToolPage(
      title: 'Whois',
      subtitle:
          'Raw whois over TCP/43, following referrals (IANA → registry → registrar, or ARIN for addresses). No website in the middle.',
      accent: netGreen,
      children: [
        Row(children: [
          SizedBox(
              width: 320,
              child: MonoField(controller: input, hint: 'example.com or 203.0.113.9')),
          const SizedBox(width: 10),
          RunButton(running ? 'Querying…' : 'Whois',
              onPressed: running ? () {} : _run, accent: netGreen),
        ]),
        ErrText(err),
        OutCard(out),
      ],
    );
  }
}

/// ---------- Traceroute (network) ----------
class TraceroutePage extends StatefulWidget {
  const TraceroutePage({super.key});
  @override
  State<TraceroutePage> createState() => _TrPageState();
}

class _TrPageState extends State<TraceroutePage> {
  final host = TextEditingController(text: '1.1.1.1');
  String out = '';
  String? err;
  bool running = false;
  Process? _proc;

  Future<void> _run() async {
    final h = host.text.trim();
    if (h.isEmpty || h.startsWith('-') || !RegExp(r'^[A-Za-z0-9.:_-]+$').hasMatch(h)) {
      setState(() => err = 'Enter a hostname or IP.');
      return;
    }
    setState(() {
      running = true;
      err = null;
      out = '';
    });
    try {
      Future<Process> start() {
        if (Platform.isWindows) {
          return Process.start('tracert', ['-d', '-w', '1000', h]);
        }
        return Process.start('traceroute', ['-n', '-w', '2', h]);
      }

      try {
        _proc = await start();
      } on ProcessException {
        if (Platform.isLinux) {
          _proc = await Process.start('tracepath', ['-n', h]); // usual fallback
        } else {
          rethrow;
        }
      }
      final p = _proc!;
      final killTimer = Timer(const Duration(seconds: 60), () => p.kill());
      p.stdout.transform(utf8.decoder).listen((chunk) {
        if (mounted) setState(() => out += chunk);
      });
      p.stderr.transform(utf8.decoder).listen((chunk) {
        if (mounted) setState(() => out += chunk);
      });
      await p.exitCode;
      killTimer.cancel();
    } on ProcessException catch (e) {
      if (mounted) {
        setState(() =>
            err = 'Could not run traceroute (${e.message}). Is it installed?');
      }
    } catch (e) {
      if (mounted) setState(() => err = 'Traceroute failed: $e');
    } finally {
      _proc = null;
      if (mounted) setState(() => running = false);
    }
  }

  @override
  void dispose() {
    _proc?.kill();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ToolPage(
      title: 'Traceroute',
      subtitle:
          'The hop-by-hop path via your system traceroute, streamed as it goes. Numeric output — no reverse-DNS stalls.',
      accent: netGreen,
      children: [
        Row(children: [
          SizedBox(
              width: 300, child: MonoField(controller: host, hint: 'host or IP')),
          const SizedBox(width: 10),
          RunButton(running ? 'Tracing…' : 'Trace',
              onPressed: running ? () {} : _run, accent: netGreen),
        ]),
        ErrText(err),
        OutCard(out),
      ],
    );
  }
}

/// ---------- MAC / OUI lookup (network, offline) ----------
class OuiPage extends StatefulWidget {
  const OuiPage({super.key});
  @override
  State<OuiPage> createState() => _OuiPageState();
}

class _OuiPageState extends State<OuiPage> {
  final input = TextEditingController();
  static Map<String, String>? _db; // loaded once per app run
  String? loadErr;

  Future<void> _load() async {
    if (_db != null) return;
    try {
      final raw = await rootBundle.load('assets/oui.tsv.gz');
      final text = utf8.decode(gzip.decode(raw.buffer.asUint8List()));
      _db = parseOuiDb(text);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => loadErr = 'Could not load the OUI table: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    OuiLookup? r;
    if (_db != null && input.text.trim().isNotEmpty) {
      r = lookupOui(_db!, input.text);
    }
    return ToolPage(
      title: 'MAC / OUI lookup',
      subtitle:
          'Vendor lookup against the bundled IEEE registry — works fully offline. Any separator style.',
      accent: netGreen,
      children: [
        SizedBox(
            width: 340,
            child: MonoField(
                controller: input,
                hint: '28:6f:b9:aa:bb:cc',
                onChanged: (_) => setState(() {}))),
        ErrText(loadErr),
        if (_db == null && loadErr == null)
          const NoteText('Loading the IEEE registry…'),
        if (r != null) ...[
          ErrText(r.err),
          if (r.err == null)
            KvTable([
              ('OUI', r.oui),
              ('Vendor', r.vendor ?? '— not in the registry —'),
              if (r.locallyAdministered)
                ('Note',
                    'Locally administered bit set — a randomized/private MAC, so no vendor is expected.'),
              if (r.multicast) ('Note', 'Multicast bit set.'),
            ]),
        ],
        if (_db != null)
          NoteText('${_db!.length} IEEE MA-L assignments bundled with the app.'),
      ],
    );
  }
}

/// ---------- IOC extractor (security) ----------
class IocPage extends StatefulWidget {
  const IocPage({super.key});
  @override
  State<IocPage> createState() => _IocPageState();
}

class _IocPageState extends State<IocPage> {
  final input = TextEditingController();
  bool defangOut = true;
  IocResult? res;

  void _run() => setState(() => res = extractIocs(input.text));

  @override
  Widget build(BuildContext context) {
    return ToolPage(
      title: 'IOC extractor',
      subtitle:
          'Paste a report, an email, a log — get every IP, domain, URL, email, hash and CVE out of it, deduplicated and defanged for sharing. Defanged input is understood too.',
      accent: secCyan,
      children: [
        MonoField(
            controller: input,
            hint: 'paste anything…',
            minLines: 8,
            maxLines: 16),
        const SizedBox(height: 10),
        Row(children: [
          RunButton('Extract', onPressed: _run, accent: secCyan),
          const SizedBox(width: 14),
          Checkbox(
              value: defangOut,
              activeColor: secCyan,
              onChanged: (v) => setState(() => defangOut = v ?? true)),
          const Text('defang the output', style: TextStyle(color: mut, fontSize: 13)),
        ]),
        if (res != null) ...[
          NoteText(res!.total == 0
              ? 'No indicators found.'
              : '${res!.total} indicators: ${res!.ips.length} IPv4 · ${res!.ips6.length} IPv6 · ${res!.domains.length} domains · ${res!.urls.length} URLs · ${res!.emails.length} emails · ${res!.cves.length} CVEs · ${res!.md5.length + res!.sha1.length + res!.sha256.length} hashes'),
          if (res!.total > 0) OutCard(iocReport(res!, defanged: defangOut)),
        ],
      ],
    );
  }
}

/// ---------- Email header analyzer (security) ----------
class EmailHeaderPage extends StatefulWidget {
  const EmailHeaderPage({super.key});
  @override
  State<EmailHeaderPage> createState() => _EmailHeaderPageState();
}

class _EmailHeaderPageState extends State<EmailHeaderPage> {
  final input = TextEditingController();
  HeaderAnalysis? res;

  void _run() => setState(() =>
      res = input.text.trim().isEmpty ? null : analyzeHeaders(input.text));

  @override
  Widget build(BuildContext context) {
    final a = res;
    return ToolPage(
      title: 'Email header analyzer',
      subtitle:
          'Paste raw headers ("Show original" in most clients) — hop chain with per-hop delay, SPF/DKIM/DMARC verdicts, and the mismatches phishing rides on.',
      accent: secCyan,
      children: [
        MonoField(
            controller: input,
            hint: 'Received: from ...\nFrom: ...\nSubject: ...',
            minLines: 8,
            maxLines: 16),
        const SizedBox(height: 10),
        RunButton('Analyze', onPressed: _run, accent: secCyan),
        if (a != null) ...[
          for (final w in a.warnings)
            Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('⚠ $w',
                    style: const TextStyle(color: warn, fontSize: 13))),
          KvTable([
            if (a.fields['from'] != null) ('From', a.fields['from']!),
            if (a.fields['reply-to'] != null) ('Reply-To', a.fields['reply-to']!),
            if (a.fields['return-path'] != null)
              ('Return-Path', a.fields['return-path']!),
            if (a.fields['subject'] != null) ('Subject', a.fields['subject']!),
            if (a.fields['date'] != null) ('Date', a.fields['date']!),
            if (a.originIp != null) ('Origin IP', a.originIp!),
            ('SPF / DKIM / DMARC',
                '${a.spf ?? '—'} / ${a.dkim ?? '—'} / ${a.dmarc ?? '—'}'),
          ]),
          if (a.hops.isNotEmpty) _hopsTable(a),
          if (a.hops.isEmpty)
            const NoteText('No Received headers found — is this the full header block?'),
        ],
      ],
    );
  }

  Widget _hopsTable(HeaderAnalysis a) {
    final head = TextStyle(
        color: mut, fontSize: 12, fontWeight: FontWeight.w600, height: 2);
    var total = 0;
    for (final h in a.hops) {
      total += (h.delaySec ?? 0) > 0 ? h.delaySec! : 0;
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: surface,
          border: Border.all(color: line),
          borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowHeight: 34,
            dataRowMinHeight: 30,
            dataRowMaxHeight: 34,
            horizontalMargin: 0,
            columnSpacing: 22,
            columns: [
              for (final h in ['#', 'From', 'By', 'IP', 'Delay'])
                DataColumn(label: Text(h, style: head)),
            ],
            rows: [
              for (var i = 0; i < a.hops.length; i++)
                DataRow(cells: [
                  DataCell(Text('${i + 1}', style: mono(size: 12.5))),
                  DataCell(Text(a.hops[i].from ?? '—', style: mono(size: 12.5))),
                  DataCell(Text(a.hops[i].by ?? '—', style: mono(size: 12.5))),
                  DataCell(SelectableText(a.hops[i].ip ?? '—',
                      style: mono(size: 12.5, color: secCyan))),
                  DataCell(Text(
                      a.hops[i].delaySec == null ? '—' : '${a.hops[i].delaySec}s',
                      style: mono(
                          size: 12.5,
                          color: (a.hops[i].delaySec ?? 0) > 300 ? warn : ink))),
                ]),
            ],
          ),
        ),
        NoteText(
            'Total measured transit ${total}s across ${a.hops.length} hops. Origin (earliest hop) first.'),
      ]),
    );
  }
}
