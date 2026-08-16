import 'package:flutter/material.dart';

import '../logic/diff.dart';
import '../logic/ipv4.dart';
import '../logic/ipv6.dart';
import '../logic/mtu.dart';
import '../logic/xfer.dart';
import '../theme.dart';
import 'common.dart';

const _acc = netGreen;

/// ---------- Subnet calculator + VLSM splitter ----------
class SubnetPage extends StatefulWidget {
  const SubnetPage({super.key});
  @override
  State<SubnetPage> createState() => _SubnetPageState();
}

class _SubnetPageState extends State<SubnetPage> {
  final parent = TextEditingController(text: '10.0.0.0/24');
  final reqs = TextEditingController();
  VlsmPlan? plan;
  String? singleErr;
  SubnetInfo? single;
  Subnet6Info? six;

  void _run() {
    setState(() {
      plan = null;
      single = null;
      six = null;
      singleErr = null;
      if (parent.text.contains(':')) {
        final c6 = parseCidr6(parent.text);
        if (c6 == null) {
          singleErr = 'Could not read that as an IPv6 prefix (like 2001:db8::/48).';
        } else {
          six = subnet6Info(c6);
        }
        return;
      }
      if (reqs.text.trim().isEmpty) {
        final p = parseCidr(parent.text);
        if (p.err != null) {
          singleErr = p.err;
        } else {
          single = SubnetInfo.of(p.value!.base, p.value!.len);
        }
      } else {
        plan = vlsmPlan(parent.text, reqs.text);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  Widget build(BuildContext context) {
    return ToolPage(
      title: 'Subnet calculator / VLSM splitter',
      subtitle:
          'Leave the requests box empty for a plain subnet breakdown, or list subnets (one per line, "name: hosts" or "name: /26") to carve the block.',
      accent: _acc,
      children: [
        Row(children: [
          SizedBox(
              width: 260,
              child: MonoField(
                  controller: parent,
                  hint: '10.0.0.0/24',
                  onChanged: (_) => _run())),
          const SizedBox(width: 10),
          RunButton('Plan', onPressed: _run, accent: _acc),
        ]),
        const SizedBox(height: 10),
        MonoField(
            controller: reqs,
            hint: 'users: 100\nservers: 40\nuplinks: /30',
            minLines: 4,
            maxLines: 10,
            onChanged: (_) => _run()),
        ErrText(singleErr ?? plan?.err),
        if (six != null) ...[
          KvTable([
            ('Prefix', six!.cidr),
            ('Expanded', six!.expanded),
            ('First', six!.first),
            ('Last', six!.last),
            ('Addresses', six!.count),
          ]),
          const NoteText(
              'IPv6 shown as prefix info — the VLSM planner below is IPv4 (v6 plans are usually straight /64s per segment).'),
        ],
        if (single != null) ...[
          KvTable([
            ('Network', single!.cidr),
            ('Mask', single!.mask),
            ('Wildcard', single!.wildcard),
            ('Broadcast', single!.broadcast),
            ('Range', '${single!.first} – ${single!.last}'),
            ('Usable hosts', '${single!.usable}'),
          ]),
        ],
        if (plan != null && plan!.rows.isNotEmpty) ...[
          if (plan!.hostBits)
            NoteText(
                'Heads up: ${plan!.given} has host bits set — planned from ${plan!.parent!.cidr}.'),
          _vlsmTable(plan!),
          NoteText(
              '${plan!.free} addresses left unallocated in ${plan!.parent!.cidr}.'
              ' Host counts assume network+broadcast reserved; ask for /31 explicitly for point-to-point links.'),
        ],
      ],
    );
  }

  Widget _vlsmTable(VlsmPlan p) {
    final head = TextStyle(
        color: mut, fontSize: 12, fontWeight: FontWeight.w600, height: 2);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: surface,
          border: Border.all(color: line),
          borderRadius: BorderRadius.circular(8)),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowHeight: 34,
          dataRowMinHeight: 30,
          dataRowMaxHeight: 34,
          horizontalMargin: 0,
          columnSpacing: 22,
          columns: [
            for (final h in ['Name', 'Subnet', 'Mask', 'Usable range', 'Hosts'])
              DataColumn(label: Text(h, style: head)),
          ],
          rows: [
            for (final r in p.rows)
              DataRow(cells: [
                DataCell(Text(r.name, style: mono(size: 12.5))),
                DataCell(SelectableText(r.cidr,
                    style: mono(size: 12.5, color: _acc))),
                DataCell(Text(r.mask, style: mono(size: 12.5))),
                DataCell(Text('${r.first} – ${r.last}',
                    style: mono(size: 12.5))),
                DataCell(Text(
                    r.reqHosts != null
                        ? '${r.usable} (asked ${r.reqHosts})'
                        : '${r.usable}',
                    style: mono(size: 12.5))),
              ]),
          ],
        ),
      ),
    );
  }
}

/// ---------- CIDR summarizer ----------
class AggregatePage extends StatefulWidget {
  const AggregatePage({super.key});
  @override
  State<AggregatePage> createState() => _AggregatePageState();
}

class _AggregatePageState extends State<AggregatePage> {
  final input = TextEditingController();
  AggregateResult? res;
  List<String> res6 = [];
  String? err6;

  void _run() => setState(() {
        res6 = [];
        err6 = null;
        final toks = input.text
            .split(RegExp(r'[\s,;]+'))
            .map((t) => t.trim())
            .where((t) => t.isNotEmpty)
            .toList();
        final v4 = toks.where((t) => !t.contains(':')).toList();
        final v6 = toks.where((t) => t.contains(':')).toList();
        res = v4.isEmpty ? null : aggregate(v4.join('\n'));
        if (v6.isNotEmpty) {
          final parsed = <Cidr6>[];
          for (final t in v6) {
            final c = parseCidr6(t.contains('/') ? t : '$t/128');
            if (c == null) {
              err6 = '"$t": not a valid IPv6 prefix.';
              return;
            }
            parsed.add(c);
          }
          res6 = aggregate6(parsed);
        }
        if (v4.isEmpty && v6.isEmpty) {
          res = aggregate(''); // reuse its empty-input error
        }
      });

  @override
  Widget build(BuildContext context) {
    return ToolPage(
      title: 'CIDR summarizer',
      subtitle:
          'Paste a messy prefix list — one per line or space/comma separated. Overlaps collapse, neighbors merge, and you get the minimal route set back. IPv4.',
      accent: _acc,
      children: [
        MonoField(
            controller: input,
            hint: '10.1.0.0/24\n10.1.1.0/24\n10.1.2.0/23\n192.0.2.15',
            minLines: 6,
            maxLines: 14),
        const SizedBox(height: 10),
        RunButton('Summarize', onPressed: _run, accent: _acc),
        ErrText(err6),
        if (res != null) ...[
          ErrText(res!.err),
          if (res!.err == null) ...[
            OutCard(res!.list.join('\n'), color: _acc),
            NoteText(
                '${res!.inCount} IPv4 prefixes in → ${res!.list.length} out.'
                '${res!.notes.isEmpty ? '' : '\n${res!.notes.join('\n')}'}'),
          ],
        ],
        if (res6.isNotEmpty) ...[
          const NoteText('IPv6'),
          OutCard(res6.join('\n'), color: _acc),
        ],
      ],
    );
  }
}

/// ---------- Wildcard / ACL converter ----------
class WildcardPage extends StatefulWidget {
  const WildcardPage({super.key});
  @override
  State<WildcardPage> createState() => _WildcardPageState();
}

class _WildcardPageState extends State<WildcardPage> {
  final input = TextEditingController(text: '10.20.0.0/16');
  WildcardInfo? res;

  void _run() => setState(() => res = wildcardInfo(input.text));

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  Widget build(BuildContext context) {
    return ToolPage(
      title: 'Wildcard mask / ACL helper',
      subtitle:
          'Give it a CIDR (10.20.0.0/16) or an address + wildcard pair (10.20.0.0 0.0.255.255) — get the other form plus a ready ACL line.',
      accent: _acc,
      children: [
        Row(children: [
          SizedBox(
              width: 340,
              child: MonoField(
                  controller: input,
                  hint: '10.20.0.0/16   or   10.20.0.0 0.0.255.255',
                  onChanged: (_) => _run())),
          const SizedBox(width: 10),
          RunButton('Convert', onPressed: _run, accent: _acc),
        ]),
        if (res != null) ...[
          ErrText(res!.err),
          if (res!.err == null) ...[
            KvTable([
              if (res!.cidr != null) ('CIDR', res!.cidr!),
              if (res!.mask != null) ('Subnet mask', res!.mask!),
              ('Wildcard', res!.wildcard),
              ('Matches', '${res!.matched} addresses'),
              ('ACL example', res!.acl),
            ]),
            if (!res!.contiguous)
              NoteText(
                  'That wildcard is discontiguous — valid in an ACL, but it has no single CIDR equivalent.'),
            if (res!.normalized)
              NoteText('Address bits outside the mask were zeroed to get the base.'),
          ],
        ],
      ],
    );
  }
}

/// ---------- MTU / MSS calculator ----------
class MtuPage extends StatefulWidget {
  const MtuPage({super.key});
  @override
  State<MtuPage> createState() => _MtuPageState();
}

class _MtuPageState extends State<MtuPage> {
  final base = TextEditingController(text: '1500');
  final selected = <String>{};

  @override
  Widget build(BuildContext context) {
    final baseVal = int.tryParse(base.text.trim());
    MtuResult? r;
    if (baseVal != null && baseVal > 0) {
      r = mtuCalc(baseVal, encaps.where((e) => selected.contains(e.id)));
    }
    return ToolPage(
      title: 'MTU / MSS calculator',
      subtitle:
          'Stack the encapsulations on your path and get the effective MTU plus the TCP MSS to clamp. Values are the typical documented overheads — verify on your platform.',
      accent: _acc,
      children: [
        Row(children: [
          const Text('Base MTU', style: TextStyle(color: mut)),
          const SizedBox(width: 10),
          SizedBox(
              width: 110,
              child: MonoField(
                  controller: base, hint: '1500', onChanged: (_) => setState(() {}))),
        ]),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
              color: surface,
              border: Border.all(color: line),
              borderRadius: BorderRadius.circular(8)),
          child: Material(
              type: MaterialType.transparency,
              child: Column(children: [
            for (final e in encaps)
              CheckboxListTile(
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                activeColor: _acc,
                value: selected.contains(e.id),
                onChanged: (v) => setState(() =>
                    v == true ? selected.add(e.id) : selected.remove(e.id)),
                title: Text('${e.name}  —  ${e.bytes} bytes',
                    style: mono(size: 13)),
                subtitle: Text(e.note,
                    style: const TextStyle(color: mut, fontSize: 11.5)),
              ),
          ])),
        ),
        if (r != null)
          KvTable([
            ('Total overhead', '${r.total} bytes'),
            ('Effective MTU', '${r.mtu}'),
            ('TCP MSS (IPv4)', '${r.mssV4}'),
            ('TCP MSS (IPv6)', '${r.mssV6}'),
          ], valueColor: _acc),
        if (r != null && r.mtu < 1280)
          NoteText(
              'Below 1280 — IPv6 requires a minimum link MTU of 1280, this path would break it.'),
      ],
    );
  }
}

/// ---------- Transfer time ----------
class XferPage extends StatefulWidget {
  const XferPage({super.key});
  @override
  State<XferPage> createState() => _XferPageState();
}

class _XferPageState extends State<XferPage> {
  final size = TextEditingController(text: '500');
  final rate = TextEditingController(text: '1');
  double sizeUnit = 1e9;
  double rateUnit = 1e9;
  double eff = 94;

  static const sizeUnits = <String, double>{
    'MB': 1e6, 'GB': 1e9, 'TB': 1e12, 'GiB': 1073741824, 'TiB': 1099511627776,
  };
  static const rateUnits = <String, double>{
    'Kbps': 1e3, 'Mbps': 1e6, 'Gbps': 1e9,
  };

  @override
  Widget build(BuildContext context) {
    final s = double.tryParse(size.text) ?? 0;
    final rv = double.tryParse(rate.text) ?? 0;
    final res = xferTime(s, sizeUnit, rv, rateUnit, eff);
    return ToolPage(
      title: 'Transfer time',
      subtitle:
          'How long the copy, backup, or migration actually takes at a given rate.',
      accent: _acc,
      children: [
        Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SizedBox(
              width: 110,
              child: MonoField(
                  controller: size, hint: '500', onChanged: (_) => setState(() {}))),
          _dd(sizeUnits, sizeUnit, (v) => setState(() => sizeUnit = v)),
          const Text('at', style: TextStyle(color: mut)),
          SizedBox(
              width: 90,
              child: MonoField(
                  controller: rate, hint: '1', onChanged: (_) => setState(() {}))),
          _dd(rateUnits, rateUnit, (v) => setState(() => rateUnit = v)),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          const Text('Protocol efficiency', style: TextStyle(color: mut, fontSize: 13)),
          Expanded(
            child: Slider(
              value: eff, min: 50, max: 100, divisions: 50,
              activeColor: _acc,
              label: '${eff.round()}%',
              onChanged: (v) => setState(() => eff = v),
            ),
          ),
          Text('${eff.round()}%', style: mono()),
        ]),
        const NoteText(
            '~94% is a sane default for TCP over Ethernet once headers and ACKs take their cut. 100% = raw line rate.'),
        if (res.err == null)
          KvTable([
            ('Transfer time', res.human),
            ('Exact', '${res.seconds.toStringAsFixed(1)} s'),
          ], valueColor: _acc)
        else
          ErrText(res.err),
      ],
    );
  }

  Widget _dd(Map<String, double> units, double val, ValueChanged<double> onSel) {
    return DropdownButton<double>(
      value: val,
      dropdownColor: surface2,
      style: mono(),
      underline: const SizedBox.shrink(),
      items: [
        for (final e in units.entries)
          DropdownMenuItem(value: e.value, child: Text(' ${e.key} ')),
      ],
      onChanged: (v) => v != null ? onSel(v) : null,
    );
  }
}

/// ---------- Config diff ----------
class DiffPage extends StatefulWidget {
  const DiffPage({super.key});
  @override
  State<DiffPage> createState() => _DiffPageState();
}

class _DiffPageState extends State<DiffPage> {
  final a = TextEditingController();
  final b = TextEditingController();
  bool dropComments = false;
  bool squashWs = false;
  DiffResult? res;
  String? err;

  static const _maxLines = 20000;
  static const _maxRender = 3000;

  void _run() {
    setState(() {
      err = null;
      res = null;
      final la = prepLines(a.text, dropComments: dropComments, squashWs: squashWs);
      final lb = prepLines(b.text, dropComments: dropComments, squashWs: squashWs);
      if (la.length + lb.length > _maxLines) {
        err = 'Too big for an in-app diff (over $_maxLines total lines).';
        return;
      }
      res = diffLines(la, lb);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ToolPage(
      title: 'Config diff',
      subtitle:
          'Compare two configs without pasting them into some website. Optionally skip comment lines (!, #, ;) and collapse whitespace.',
      accent: _acc,
      children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
              child: MonoField(
                  controller: a, hint: 'before / running-config', minLines: 10, maxLines: 18)),
          const SizedBox(width: 10),
          Expanded(
              child: MonoField(
                  controller: b, hint: 'after / candidate config', minLines: 10, maxLines: 18)),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 16, crossAxisAlignment: WrapCrossAlignment.center, children: [
          _cb('Skip comment lines', dropComments, (v) => setState(() => dropComments = v)),
          _cb('Ignore whitespace', squashWs, (v) => setState(() => squashWs = v)),
          RunButton('Compare', onPressed: _run, accent: _acc),
        ]),
        ErrText(err),
        if (res != null) ...[
          NoteText(res!.changes == 0
              ? 'No differences.'
              : '${res!.changes} changed lines${res!.capped ? ' (too different for a minimal diff — showing full replace)' : ''}.'),
          if (res!.changes > 0) _diffView(res!),
        ],
      ],
    );
  }

  Widget _cb(String label, bool val, ValueChanged<bool> onSel) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Checkbox(
          value: val,
          activeColor: _acc,
          onChanged: (v) => onSel(v ?? false)),
      Text(label, style: const TextStyle(color: mut, fontSize: 13)),
    ]);
  }

  Widget _diffView(DiffResult r) {
    var ops = r.ops;
    var truncated = false;
    if (ops.length > _maxRender) {
      ops = ops.sublist(0, _maxRender);
      truncated = true;
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: surface,
          border: Border.all(color: line),
          borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SelectableText.rich(TextSpan(children: [
          for (final o in ops)
            TextSpan(
                text: '${o.t == ' ' ? '  ' : '${o.t} '}${o.s}\n',
                style: mono(
                    size: 12.5,
                    color: o.t == '+'
                        ? _acc
                        : o.t == '-'
                            ? bad
                            : mut)),
        ])),
        if (truncated)
          const NoteText('Output truncated — copy smaller sections for the full view.'),
      ]),
    );
  }
}
