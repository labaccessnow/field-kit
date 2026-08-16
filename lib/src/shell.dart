import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'theme.dart';
import 'tools.dart';

const appVersion = '1.0.0';

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int selected = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 232,
            color: const Color(0xFF081020),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
                  child: Row(children: [
                    const Text('Field ',
                        style: TextStyle(
                            fontSize: 19, fontWeight: FontWeight.w800)),
                    const Text('Kit',
                        style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            color: netGreen)),
                  ]),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: 10),
                    children: [
                      _groupLabel('NETWORK', netGreen),
                      for (var i = 0; i < tools.length; i++)
                        if (!tools[i].security) _item(i),
                      _groupLabel('SECURITY', secCyan),
                      for (var i = 0; i < tools.length; i++)
                        if (tools[i].security) _item(i),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _link('netopsfieldnotes.com'),
                      _link('secopsfieldnotes.com'),
                      _link('whatismynetip.com'),
                      const SizedBox(height: 6),
                      const Text('v$appVersion · free & open source',
                          style: TextStyle(color: mut, fontSize: 11)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: IndexedStack(
              index: selected,
              children: [for (final t in tools) t.page],
            ),
          ),
        ],
      ),
    );
  }

  Widget _groupLabel(String label, Color color) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
        child: Text(label,
            style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2)),
      );

  Widget _item(int i) {
    final t = tools[i];
    final sel = selected == i;
    final accent = t.security ? secCyan : netGreen;
    return InkWell(
      onTap: () => setState(() => selected = i),
      child: Container(
        color: sel ? surface2 : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        child: Row(children: [
          Icon(t.icon, size: 16, color: sel ? accent : mut),
          const SizedBox(width: 10),
          Expanded(
            child: Text(t.name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 13.5,
                    color: sel ? ink : mut,
                    fontWeight: sel ? FontWeight.w600 : FontWeight.w400)),
          ),
        ]),
      ),
    );
  }

  Widget _link(String host) => InkWell(
        onTap: () => launchUrl(Uri.parse('https://$host/')),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text(host,
              style: const TextStyle(color: mut, fontSize: 11.5)),
        ),
      );
}
