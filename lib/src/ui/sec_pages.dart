import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../logic/cvss.dart';
import '../logic/decoder.dart';
import '../logic/defang.dart';
import '../logic/hashes.dart';
import '../logic/jwtdec.dart';
import '../logic/timestampx.dart';
import '../theme.dart';
import 'common.dart';

const _acc = secCyan;

/// ---------- IOC defang / refang ----------
class DefangPage extends StatefulWidget {
  const DefangPage({super.key});
  @override
  State<DefangPage> createState() => _DefangPageState();
}

class _DefangPageState extends State<DefangPage> {
  final input = TextEditingController();
  String out = '';

  @override
  Widget build(BuildContext context) {
    return ToolPage(
      title: 'IOC defang / refang',
      subtitle:
          'Make indicators safe to paste into tickets and chat (hxxps[://], [.], [at]) — or turn a defanged report back into usable form. Nothing leaves this app.',
      accent: _acc,
      children: [
        MonoField(
            controller: input,
            hint:
                'https://malicious.example.com/payload.bin\n203.0.113.55\nphish@example.net',
            minLines: 6,
            maxLines: 14),
        const SizedBox(height: 10),
        Row(children: [
          RunButton('Defang',
              onPressed: () => setState(() => out = defang(input.text)),
              accent: _acc),
          const SizedBox(width: 10),
          RunButton('Refang',
              onPressed: () => setState(() => out = refang(input.text)),
              accent: _acc,
              secondary: true),
        ]),
        OutCard(out),
      ],
    );
  }
}

/// ---------- CVSS v3.1 ----------
class CvssPage extends StatefulWidget {
  const CvssPage({super.key});
  @override
  State<CvssPage> createState() => _CvssPageState();
}

class _CvssPageState extends State<CvssPage> {
  final vectorIn = TextEditingController();
  final metrics = <String, String>{
    'AV': 'N', 'AC': 'L', 'PR': 'N', 'UI': 'N',
    'S': 'U', 'C': 'N', 'I': 'N', 'A': 'N',
  };
  String? parseErr;

  Color _sevColor(String sev) => switch (sev) {
        'Critical' => bad,
        'High' => warn,
        'Medium' => const Color(0xFFEAB308),
        'Low' => netGreen,
        _ => mut,
      };

  @override
  Widget build(BuildContext context) {
    final r = cvssScore(metrics);
    return ToolPage(
      title: 'CVSS v3.1 calculator',
      subtitle:
          'Click the metrics or paste a vector string. Base score only — the number an advisory quotes.',
      accent: _acc,
      children: [
        Row(children: [
          Expanded(
              child: MonoField(
                  controller: vectorIn,
                  hint: 'CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H')),
          const SizedBox(width: 10),
          RunButton('Parse', accent: _acc, onPressed: () {
            final p = cvssParse(vectorIn.text);
            setState(() {
              parseErr = p.err;
              if (p.m != null) metrics.addAll(p.m!);
            });
          }),
        ]),
        ErrText(parseErr),
        const SizedBox(height: 14),
        for (final k in cvssMetrics.keys) _metricRow(k),
        const SizedBox(height: 6),
        if (r.err == null) ...[
          Container(
            margin: const EdgeInsets.only(top: 10),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: surface,
                border: Border.all(color: line),
                borderRadius: BorderRadius.circular(8)),
            child: Row(children: [
              Text(r.score.toStringAsFixed(1),
                  style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w800,
                      color: _sevColor(r.severity))),
              const SizedBox(width: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                    color: _sevColor(r.severity).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20)),
                child: Text(r.severity,
                    style: TextStyle(
                        color: _sevColor(r.severity),
                        fontWeight: FontWeight.w700)),
              ),
              const Spacer(),
              IconButton(
                  tooltip: 'Copy vector',
                  onPressed: () => copyText(context, r.vector),
                  icon: const Icon(Icons.copy, size: 16, color: mut)),
            ]),
          ),
          OutCard(r.vector),
        ],
      ],
    );
  }

  Widget _metricRow(String k) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        SizedBox(
            width: 170,
            child: Text(cvssLabels[k]!,
                style: const TextStyle(color: mut, fontSize: 13))),
        Wrap(spacing: 6, children: [
          for (final opt in cvssMetrics[k]!)
            ChoiceChip(
              label: Text(cvssOptionNames[k]![opt]!,
                  style: TextStyle(
                      fontSize: 12,
                      color: metrics[k] == opt ? const Color(0xFF06222A) : ink)),
              selected: metrics[k] == opt,
              selectedColor: _acc,
              backgroundColor: surface,
              side: const BorderSide(color: line),
              showCheckmark: false,
              onSelected: (_) => setState(() => metrics[k] = opt),
            ),
        ]),
      ]),
    );
  }
}

/// ---------- JWT decoder ----------
class JwtPage extends StatefulWidget {
  const JwtPage({super.key});
  @override
  State<JwtPage> createState() => _JwtPageState();
}

class _JwtPageState extends State<JwtPage> {
  final input = TextEditingController();
  JwtResult? res;

  static const _enc = JsonEncoder.withIndent('  ');

  void _run() => setState(() =>
      res = input.text.trim().isEmpty ? null : jwtDecode(input.text));

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final claims = <(String, String)>[];
    var expired = false;
    if (res?.payload != null) {
      for (final c in ['exp', 'iat', 'nbf']) {
        final v = res!.payload![c];
        if (v is num) {
          final ms = v.toInt() * 1000;
          final rel = tsRelative(ms, now);
          if (c == 'exp' && ms < now) expired = true;
          claims.add((
            c,
            '${DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toIso8601String()}  ($rel)'
          ));
        }
      }
    }
    return ToolPage(
      title: 'JWT decoder',
      subtitle:
          'Decode-only — the signature is shown, not verified. Decoding happens locally, so a pasted token is never sent anywhere.',
      accent: _acc,
      children: [
        MonoField(
            controller: input,
            hint: 'eyJhbGciOi... (or "Bearer eyJ...")',
            minLines: 3,
            maxLines: 8,
            onChanged: (_) => _run()),
        if (res != null) ...[
          ErrText(res!.err),
          for (final w in res!.warnings)
            Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('⚠ $w',
                    style: const TextStyle(color: warn, fontSize: 13))),
          if (expired)
            const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('⚠ This token is EXPIRED.',
                    style: TextStyle(color: bad, fontSize: 13))),
          if (claims.isNotEmpty) KvTable(claims),
          if (res!.header != null) ...[
            const NoteText('Header'),
            OutCard(_enc.convert(res!.header)),
          ],
          if (res!.payload != null) ...[
            const NoteText('Payload'),
            OutCard(_enc.convert(res!.payload)),
          ],
        ],
      ],
    );
  }
}

/// ---------- Hashing ----------
class HashPage extends StatefulWidget {
  const HashPage({super.key});
  @override
  State<HashPage> createState() => _HashPageState();
}

class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}

class _HashPageState extends State<HashPage> {
  final input = TextEditingController();
  final compare = TextEditingController();
  final identify = TextEditingController();
  Map<String, String> digests = {};
  String source = '';
  bool hashing = false;

  void _hashText() {
    final bytes = utf8.encode(input.text);
    setState(() {
      source = 'text (${bytes.length} bytes)';
      digests = {
        'MD5': md5.convert(bytes).toString(),
        'SHA-1': sha1.convert(bytes).toString(),
        'SHA-256': sha256.convert(bytes).toString(),
        'SHA-512': sha512.convert(bytes).toString(),
      };
    });
  }

  Future<void> _hashFile() async {
    final x = await openFile();
    if (x == null) return;
    setState(() {
      hashing = true;
      source = '';
      digests = {};
    });
    try {
      final algos = {'MD5': md5, 'SHA-1': sha1, 'SHA-256': sha256, 'SHA-512': sha512};
      final sinks = <String, _DigestSink>{};
      final convs = <String, ByteConversionSink>{};
      for (final e in algos.entries) {
        final s = _DigestSink();
        sinks[e.key] = s;
        convs[e.key] = e.value.startChunkedConversion(s);
      }
      var size = 0;
      await for (final chunk in File(x.path).openRead()) {
        size += chunk.length;
        for (final c in convs.values) {
          c.add(chunk);
        }
      }
      for (final c in convs.values) {
        c.close();
      }
      if (!mounted) return;
      setState(() {
        source = '${x.name} ($size bytes)';
        digests = {
          for (final e in sinks.entries) e.key: e.value.value!.toString()
        };
      });
    } catch (e) {
      if (mounted) setState(() => source = 'Could not read file: $e');
    } finally {
      if (mounted) setState(() => hashing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cmp = compare.text.trim().toLowerCase();
    String? matchLabel;
    if (cmp.isNotEmpty && digests.isNotEmpty) {
      for (final e in digests.entries) {
        if (e.value == cmp) {
          matchLabel = e.key;
          break;
        }
      }
    }
    return ToolPage(
      title: 'Hashes',
      subtitle:
          'Hash text or a file (MD5 for IOC matching, SHA for integrity), check it against an expected value, or identify an unknown hash.',
      accent: _acc,
      children: [
        MonoField(
            controller: input,
            hint: 'text to hash…',
            minLines: 3,
            maxLines: 8,
            onChanged: (_) => _hashText()),
        const SizedBox(height: 10),
        Row(children: [
          RunButton('Hash text', onPressed: _hashText, accent: _acc),
          const SizedBox(width: 10),
          RunButton(hashing ? 'Hashing…' : 'Hash a file…',
              onPressed: hashing ? () {} : () => _hashFile(),
              accent: _acc,
              secondary: true),
        ]),
        if (source.isNotEmpty) NoteText(source),
        if (digests.isNotEmpty)
          KvTable([for (final e in digests.entries) (e.key, e.value)]),
        const SizedBox(height: 16),
        const Text('Compare against an expected hash',
            style: TextStyle(color: mut, fontSize: 13)),
        const SizedBox(height: 6),
        MonoField(
            controller: compare,
            hint: 'paste the vendor-published hash…',
            onChanged: (_) => setState(() {})),
        if (cmp.isNotEmpty && digests.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
                matchLabel != null ? '✓ Matches $matchLabel' : '✗ No match',
                style: TextStyle(
                    color: matchLabel != null ? netGreen : bad,
                    fontWeight: FontWeight.w700)),
          ),
        const SizedBox(height: 16),
        const Text('Identify an unknown hash',
            style: TextStyle(color: mut, fontSize: 13)),
        const SizedBox(height: 6),
        MonoField(
            controller: identify,
            hint: r'e.g. $2b$10$… or 64 hex chars',
            onChanged: (_) => setState(() {})),
        if (identify.text.trim().isNotEmpty)
          NoteText(identifyHash(identify.text)),
      ],
    );
  }
}

/// ---------- Timestamp converter ----------
class TimestampPage extends StatefulWidget {
  const TimestampPage({super.key});
  @override
  State<TimestampPage> createState() => _TimestampPageState();
}

class _TimestampPageState extends State<TimestampPage> {
  final input = TextEditingController();
  TsParse? parsed;
  TsFormats? fmts;

  void _run([String? preset]) {
    if (preset != null) input.text = preset;
    setState(() {
      parsed = null;
      fmts = null;
      if (input.text.trim().isEmpty) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      parsed = tsParse(input.text, now);
      if (parsed!.ms != null) fmts = tsFormats(parsed!.ms!, now);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ToolPage(
      title: 'Timestamp converter',
      subtitle:
          'Epoch seconds, milliseconds or microseconds, Windows FILETIME, ISO 8601 — pasted from whatever log you are staring at.',
      accent: _acc,
      children: [
        Row(children: [
          Expanded(
              child: MonoField(
                  controller: input,
                  hint: '1755316800  ·  133997906000000000  ·  2026-08-16T12:00:00Z',
                  onChanged: (_) => _run())),
          const SizedBox(width: 10),
          RunButton('Now', onPressed: () => _run('now'), accent: _acc, secondary: true),
        ]),
        if (parsed?.err != null) ErrText(parsed!.err),
        if (fmts != null) ...[
          NoteText('Read as: ${parsed!.src}'),
          KvTable([
            ('ISO 8601 (UTC)', fmts!.iso),
            ('Local', fmts!.local),
            ('Epoch seconds', '${fmts!.epochS}'),
            ('Epoch ms', '${fmts!.epochMs}'),
            ('FILETIME', fmts!.filetime),
            ('Relative', fmts!.relative),
          ]),
        ],
      ],
    );
  }
}

/// ---------- Decoder workbench ----------
class DecoderPage extends StatefulWidget {
  const DecoderPage({super.key});
  @override
  State<DecoderPage> createState() => _DecoderPageState();
}

class _DecoderPageState extends State<DecoderPage> {
  final input = TextEditingController();
  String out = '';
  String? err;
  String lastOp = '';

  void _apply(String name, OpResult Function(String) op) {
    final r = op(input.text);
    setState(() {
      lastOp = name;
      err = r.err;
      out = r.out ?? '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final ops = <String, OpResult Function(String)>{
      'Base64 → text': b64decode,
      'text → Base64': b64encode,
      'URL decode': urlDecode,
      'URL encode': urlEncode,
      'hex → text': hexToText,
      'text → hex': textToHex,
      'HTML entities': htmlDecode,
      'ROT13': rot13,
    };
    return ToolPage(
      title: 'Decoder workbench',
      subtitle:
          'Peel encoded payloads layer by layer — decode, chain the output back in, decode again. All local.',
      accent: _acc,
      children: [
        MonoField(
            controller: input,
            hint: 'cG93ZXJzaGVsbCAtZW5jIC4uLg==',
            minLines: 5,
            maxLines: 12),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final e in ops.entries)
            RunButton(e.key,
                onPressed: () => _apply(e.key, e.value),
                accent: _acc,
                secondary: true),
        ]),
        ErrText(err),
        if (out.isNotEmpty) ...[
          NoteText(lastOp),
          OutCard(out),
          const SizedBox(height: 8),
          RunButton('↑ Use output as input', accent: _acc, onPressed: () {
            setState(() {
              input.text = out;
              out = '';
              err = null;
            });
          }),
        ],
      ],
    );
  }
}
