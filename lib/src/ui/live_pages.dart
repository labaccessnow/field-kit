import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme.dart';
import 'common.dart';

const _acc = netGreen;

bool _saneHost(String h) =>
    h.isNotEmpty && !h.startsWith('-') && RegExp(r'^[A-Za-z0-9.:_-]+$').hasMatch(h);

/// ---------- Ping ----------
class PingPage extends StatefulWidget {
  const PingPage({super.key});
  @override
  State<PingPage> createState() => _PingPageState();
}

class _PingPageState extends State<PingPage> {
  final host = TextEditingController(text: '1.1.1.1');
  String out = '';
  String? err;
  bool running = false;

  Future<void> _run() async {
    final h = host.text.trim();
    if (!_saneHost(h)) {
      setState(() => err = 'Enter a hostname or IP.');
      return;
    }
    setState(() {
      running = true;
      err = null;
      out = '';
    });
    try {
      final args = Platform.isWindows ? ['-n', '4', h] : ['-c', '4', h];
      final r = await Process.run('ping', args)
          .timeout(const Duration(seconds: 25));
      if (mounted) setState(() => out = '${r.stdout}${r.stderr}'.trim());
    } on TimeoutException {
      if (mounted) setState(() => err = 'Ping timed out.');
    } catch (e) {
      if (mounted) setState(() => err = 'Could not run ping: $e');
    } finally {
      if (mounted) setState(() => running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ToolPage(
      title: 'Ping',
      subtitle: 'Four echoes via your system ping — reachability and latency at a glance.',
      accent: _acc,
      children: [
        Row(children: [
          SizedBox(
              width: 300,
              child: MonoField(controller: host, hint: 'host or IP')),
          const SizedBox(width: 10),
          RunButton(running ? 'Pinging…' : 'Ping',
              onPressed: running ? () {} : _run, accent: _acc),
        ]),
        ErrText(err),
        OutCard(out),
      ],
    );
  }
}

/// ---------- TCP port check ----------
class PortPage extends StatefulWidget {
  const PortPage({super.key});
  @override
  State<PortPage> createState() => _PortPageState();
}

class _PortPageState extends State<PortPage> {
  final host = TextEditingController();
  final ports = TextEditingController(text: '22, 80, 443');
  final results = <String>[];
  String? err;
  bool running = false;

  Future<void> _run() async {
    final h = host.text.trim();
    if (!_saneHost(h)) {
      setState(() => err = 'Enter a hostname or IP.');
      return;
    }
    final list = ports.text
        .split(RegExp(r'[\s,;]+'))
        .where((p) => p.isNotEmpty)
        .map(int.tryParse)
        .toList();
    if (list.isEmpty || list.contains(null)) {
      setState(() => err = 'Ports: numbers separated by commas.');
      return;
    }
    final good = list.cast<int>().where((p) => p > 0 && p < 65536).toList();
    if (good.length > 20) {
      setState(() => err = 'Keep it to 20 ports — this is a check, not a scanner.');
      return;
    }
    setState(() {
      running = true;
      err = null;
      results.clear();
    });
    for (final p in good) {
      final sw = Stopwatch()..start();
      String line;
      try {
        final s = await Socket.connect(h, p, timeout: const Duration(seconds: 4));
        sw.stop();
        s.destroy();
        line = 'tcp/$p   OPEN     ${sw.elapsedMilliseconds} ms';
      } on SocketException catch (e) {
        sw.stop();
        final refused = (e.osError?.message ?? '').toLowerCase().contains('refused');
        line = refused
            ? 'tcp/$p   CLOSED   (connection refused)'
            : 'tcp/$p   FILTERED / no answer (${sw.elapsedMilliseconds} ms)';
      } catch (_) {
        line = 'tcp/$p   error';
      }
      if (!mounted) return;
      setState(() => results.add(line));
    }
    if (mounted) setState(() => running = false);
  }

  @override
  Widget build(BuildContext context) {
    return ToolPage(
      title: 'TCP port check',
      subtitle:
          'Does that port actually answer? A few ports on a host you operate — deliberately not a scanner.',
      accent: _acc,
      children: [
        Wrap(spacing: 10, runSpacing: 10, children: [
          SizedBox(
              width: 300,
              child: MonoField(controller: host, hint: 'host or IP')),
          SizedBox(
              width: 220,
              child: MonoField(controller: ports, hint: '22, 80, 443')),
          RunButton(running ? 'Checking…' : 'Check',
              onPressed: running ? () {} : _run, accent: _acc),
        ]),
        ErrText(err),
        if (results.isNotEmpty) OutCard(results.join('\n')),
      ],
    );
  }
}

/// ---------- DNS lookup ----------
class DnsPage extends StatefulWidget {
  const DnsPage({super.key});
  @override
  State<DnsPage> createState() => _DnsPageState();
}

class _DnsPageState extends State<DnsPage> {
  final name = TextEditingController();
  String rtype = 'A';
  String out = '';
  String? err;
  bool running = false;

  static const types = ['A', 'AAAA', 'CNAME', 'MX', 'TXT', 'NS', 'SOA', 'PTR'];
  static const typeNames = {
    1: 'A', 2: 'NS', 5: 'CNAME', 6: 'SOA', 12: 'PTR',
    15: 'MX', 16: 'TXT', 28: 'AAAA', 257: 'CAA', 46: 'RRSIG',
  };

  Future<void> _run() async {
    final n = name.text.trim();
    if (!_saneHost(n)) {
      setState(() => err = 'Enter a name to look up.');
      return;
    }
    setState(() {
      running = true;
      err = null;
      out = '';
    });
    final buf = StringBuffer();
    try {
      if (rtype == 'A' || rtype == 'AAAA') {
        try {
          final sys = await InternetAddress.lookup(n,
                  type: rtype == 'A'
                      ? InternetAddressType.IPv4
                      : InternetAddressType.IPv6)
              .timeout(const Duration(seconds: 5));
          buf.writeln('# your system resolver');
          for (final a in sys) {
            buf.writeln(a.address);
          }
          buf.writeln();
        } catch (_) {
          buf.writeln('# your system resolver: no answer\n');
        }
      }
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
      try {
        final req = await client.getUrl(Uri.parse(
            'https://cloudflare-dns.com/dns-query?name=${Uri.encodeQueryComponent(n)}&type=$rtype'));
        req.headers.set('accept', 'application/dns-json');
        final resp = await req.close().timeout(const Duration(seconds: 8));
        final body = await resp.transform(utf8.decoder).join();
        final j = jsonDecode(body) as Map<String, dynamic>;
        buf.writeln('# 1.1.1.1 (DNS over HTTPS)');
        final ans = (j['Answer'] as List?) ?? [];
        if (ans.isEmpty) {
          buf.writeln('no $rtype records (status ${j['Status']})');
        }
        for (final a in ans.cast<Map<String, dynamic>>()) {
          final t = typeNames[a['type']] ?? 'T${a['type']}';
          buf.writeln('${a['name']}  ${a['TTL']}s  $t  ${a['data']}');
        }
      } finally {
        client.close();
      }
      if (mounted) setState(() => out = buf.toString().trim());
    } catch (e) {
      if (mounted) setState(() => err = 'Lookup failed: $e');
    } finally {
      if (mounted) setState(() => running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ToolPage(
      title: 'DNS lookup',
      subtitle:
          'Your system resolver next to 1.1.1.1 over HTTPS — a quick way to spot split-horizon and stale-cache surprises.',
      accent: _acc,
      children: [
        Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SizedBox(
              width: 300,
              child: MonoField(controller: name, hint: 'example.com')),
          DropdownButton<String>(
            value: rtype,
            dropdownColor: surface2,
            style: mono(),
            underline: const SizedBox.shrink(),
            items: [
              for (final t in types) DropdownMenuItem(value: t, child: Text(' $t '))
            ],
            onChanged: (v) => setState(() => rtype = v ?? 'A'),
          ),
          RunButton(running ? 'Looking up…' : 'Look up',
              onPressed: running ? () {} : _run, accent: _acc),
        ]),
        ErrText(err),
        OutCard(out),
      ],
    );
  }
}

/// ---------- TLS certificate inspector ----------
class TlsPage extends StatefulWidget {
  const TlsPage({super.key});
  @override
  State<TlsPage> createState() => _TlsPageState();
}

class _TlsPageState extends State<TlsPage> {
  final host = TextEditingController();
  final port = TextEditingController(text: '443');
  List<(String, String)> rows = [];
  String note = '';
  String? err;
  bool running = false;

  Future<void> _run() async {
    final h = host.text.trim();
    final p = int.tryParse(port.text.trim()) ?? 443;
    if (!_saneHost(h)) {
      setState(() => err = 'Enter a hostname.');
      return;
    }
    setState(() {
      running = true;
      err = null;
      rows = [];
      note = '';
    });
    SecureSocket? s;
    var trusted = true;
    try {
      try {
        s = await SecureSocket.connect(h, p,
            timeout: const Duration(seconds: 8));
      } on HandshakeException {
        trusted = false;
        s = await SecureSocket.connect(h, p,
            timeout: const Duration(seconds: 8),
            onBadCertificate: (_) => true);
      }
      final c = s.peerCertificate;
      if (!mounted) return;
      if (c == null) {
        setState(() => err = 'The server presented no certificate.');
        return;
      }
      final now = DateTime.now();
      final daysLeft = c.endValidity.difference(now).inDays;
      final fp = c.sha1.map((b) => b.toRadixString(16).padLeft(2, '0')).join(':');
      setState(() {
        rows = [
          ('Subject', c.subject),
          ('Issuer', c.issuer),
          ('Valid from', c.startValidity.toUtc().toIso8601String()),
          ('Valid until', c.endValidity.toUtc().toIso8601String()),
          ('Days left', '$daysLeft'),
          ('SHA-1 fingerprint', fp),
          ('Protocol', s!.selectedProtocol ?? '—'),
        ];
        note = [
          if (!trusted)
            '⚠ The chain did NOT validate against your system trust store.',
          if (daysLeft < 0)
            '⚠ EXPIRED.'
          else if (daysLeft < 21)
            '⚠ Renew soon — under three weeks left.',
        ].join('\n');
      });
    } on TimeoutException {
      if (mounted) setState(() => err = 'Connection timed out.');
    } catch (e) {
      if (mounted) setState(() => err = 'Could not connect: $e');
    } finally {
      s?.destroy();
      if (mounted) setState(() => running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ToolPage(
      title: 'TLS certificate inspector',
      subtitle:
          'Connect to a host and read the certificate it actually serves — expiry, issuer, and whether your machine trusts the chain.',
      accent: _acc,
      children: [
        Wrap(spacing: 10, runSpacing: 10, children: [
          SizedBox(
              width: 300,
              child: MonoField(controller: host, hint: 'example.com')),
          SizedBox(width: 90, child: MonoField(controller: port, hint: '443')),
          RunButton(running ? 'Connecting…' : 'Inspect',
              onPressed: running ? () {} : _run, accent: _acc),
        ]),
        ErrText(err),
        if (rows.isNotEmpty) KvTable(rows),
        if (note.isNotEmpty)
          Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(note,
                  style: const TextStyle(color: warn, fontSize: 13))),
        const NoteText(
            'Round-robin fleets: check each origin, not just the public name — one bad origin hides behind healthy ones.'),
      ],
    );
  }
}

/// ---------- Local interfaces ----------
class IfacesPage extends StatefulWidget {
  const IfacesPage({super.key});
  @override
  State<IfacesPage> createState() => _IfacesPageState();
}

class _IfacesPageState extends State<IfacesPage> {
  String out = '';
  String? err;

  Future<void> _run() async {
    try {
      final list = await NetworkInterface.list(
          includeLoopback: false, includeLinkLocal: true);
      final buf = StringBuffer();
      for (final i in list) {
        buf.writeln(i.name);
        for (final a in i.addresses) {
          buf.writeln('  ${a.address}${a.isLinkLocal ? '  (link-local)' : ''}');
        }
      }
      if (!mounted) return;
      setState(() {
        err = null;
        out = buf.isEmpty ? 'No non-loopback interfaces found.' : buf.toString().trim();
      });
    } catch (e) {
      if (mounted) setState(() => err = 'Could not list interfaces: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  Widget build(BuildContext context) {
    return ToolPage(
      title: 'Local interfaces',
      subtitle: 'Every address this machine holds right now.',
      accent: _acc,
      children: [
        RunButton('Refresh', onPressed: _run, accent: _acc, secondary: true),
        ErrText(err),
        OutCard(out),
      ],
    );
  }
}

/// ---------- Public IP ----------
class PublicIpPage extends StatefulWidget {
  const PublicIpPage({super.key});
  @override
  State<PublicIpPage> createState() => _PublicIpPageState();
}

class _PublicIpPageState extends State<PublicIpPage> {
  List<(String, String)> rows = [];
  String? err;
  bool running = false;

  static const preferred = [
    'ip', 'hostname', 'reverse', 'city', 'region', 'country',
    'asn', 'org', 'as_organization', 'asOrganization', 'timezone', 'is_hosting',
  ];

  Future<void> _run() async {
    setState(() {
      running = true;
      err = null;
      rows = [];
    });
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      final req = await client
          .getUrl(Uri.parse('https://api.whatismynetip.com/json'));
      final resp = await req.close().timeout(const Duration(seconds: 8));
      final body = await resp.transform(utf8.decoder).join();
      final j = jsonDecode(body) as Map<String, dynamic>;
      final done = <String>{};
      final r = <(String, String)>[];
      for (final k in preferred) {
        final v = j[k];
        if (v != null && v is! Map && v is! List) {
          r.add((k, '$v'));
          done.add(k);
        }
      }
      for (final e in j.entries) {
        if (!done.contains(e.key) && e.value is! Map && e.value is! List) {
          r.add((e.key, '${e.value}'));
        }
      }
      if (mounted) setState(() => rows = r);
    } catch (e) {
      if (mounted) setState(() => err = 'Could not reach the service: $e');
    } finally {
      client.close();
      if (mounted) setState(() => running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ToolPage(
      title: 'Public IP',
      subtitle: 'How the internet sees this machine right now.',
      accent: _acc,
      children: [
        RunButton(running ? 'Checking…' : 'Check my public IP',
            onPressed: running ? () {} : _run, accent: _acc),
        ErrText(err),
        if (rows.isNotEmpty) KvTable(rows),
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: InkWell(
            onTap: () => launchUrl(Uri.parse('https://whatismynetip.com')),
            child: const Text('Powered by whatismynetip.com — more checks live there ↗',
                style: TextStyle(color: mut, fontSize: 12.5, decoration: TextDecoration.underline, decorationColor: mut)),
          ),
        ),
      ],
    );
  }
}
