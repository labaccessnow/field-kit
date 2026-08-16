import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

void copyText(BuildContext context, String text, {String label = 'Copied'}) {
  Clipboard.setData(ClipboardData(text: text));
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(
        content: Text(label), duration: const Duration(milliseconds: 700)));
}

String mdTable(List<(String, String)> rows) {
  final buf = StringBuffer('| Field | Value |\n|---|---|\n');
  for (final r in rows) {
    buf.writeln('| ${r.$1} | ${r.$2.replaceAll('|', r'\|')} |');
  }
  return buf.toString();
}

String mdFence(String text) => '```\n$text\n```';

/// Standard page frame: header + scrollable body, capped width.
class ToolPage extends StatelessWidget {
  final String title;
  final String subtitle;
  final Color accent;
  final List<Widget> children;
  const ToolPage(
      {super.key,
      required this.title,
      required this.subtitle,
      required this.accent,
      required this.children});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 40),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(width: 4, height: 22, color: accent),
                const SizedBox(width: 10),
                Text(title,
                    style: const TextStyle(
                        fontSize: 21, fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 6),
              Text(subtitle, style: const TextStyle(color: mut, fontSize: 13.5)),
              const SizedBox(height: 18),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

/// Bordered monospace output block with a copy button.
class OutCard extends StatelessWidget {
  final String text;
  final Color? color;
  const OutCard(this.text, {super.key, this.color});

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      decoration: BoxDecoration(
        color: surface,
        border: Border.all(color: line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
              child: SelectableText(text, style: mono(color: color ?? ink))),
          Column(mainAxisSize: MainAxisSize.min, children: [
            IconButton(
              icon: const Icon(Icons.copy, size: 16, color: mut),
              tooltip: 'Copy',
              onPressed: () => copyText(context, text),
            ),
            IconButton(
              icon: const Icon(Icons.notes, size: 16, color: mut),
              tooltip: 'Copy as Markdown',
              onPressed: () =>
                  copyText(context, mdFence(text), label: 'Copied as Markdown'),
            ),
          ]),
        ],
      ),
    );
  }
}

class ErrText extends StatelessWidget {
  final String? msg;
  const ErrText(this.msg, {super.key});
  @override
  Widget build(BuildContext context) => msg == null || msg!.isEmpty
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(msg!, style: const TextStyle(color: bad, fontSize: 13)),
        );
}

class NoteText extends StatelessWidget {
  final String msg;
  const NoteText(this.msg, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text(msg, style: const TextStyle(color: mut, fontSize: 12.5)),
      );
}

/// Label/value grid for structured results.
class KvTable extends StatelessWidget {
  final List<(String, String)> rows;
  final Color? valueColor;
  const KvTable(this.rows, {super.key, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surface,
        border: Border.all(color: line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Stack(children: [
        Padding(
          padding: const EdgeInsets.only(right: 30),
          child: Table(
            columnWidths: const {
              0: IntrinsicColumnWidth(),
              1: FlexColumnWidth()
            },
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              for (final r in rows)
                TableRow(children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Text(r.$1,
                        style: const TextStyle(color: mut, fontSize: 12.5)),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 18),
                    child: SelectableText(r.$2,
                        style: mono(color: valueColor ?? ink)),
                  ),
                ]),
            ],
          ),
        ),
        Positioned(
          top: -6,
          right: -6,
          child: IconButton(
            icon: const Icon(Icons.notes, size: 15, color: mut),
            tooltip: 'Copy as Markdown',
            onPressed: () => copyText(context, mdTable(rows),
                label: 'Copied as Markdown'),
          ),
        ),
      ]),
    );
  }
}

class MonoField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final int maxLines;
  final int minLines;
  final ValueChanged<String>? onChanged;
  const MonoField(
      {super.key,
      required this.controller,
      required this.hint,
      this.maxLines = 1,
      this.minLines = 1,
      this.onChanged});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      minLines: minLines,
      onChanged: onChanged,
      style: mono(),
      decoration: InputDecoration(hintText: hint),
    );
  }
}

class RunButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final Color accent;
  final bool secondary;
  const RunButton(this.label,
      {super.key,
      required this.onPressed,
      required this.accent,
      this.secondary = false});

  @override
  Widget build(BuildContext context) {
    if (secondary) {
      return OutlinedButton(
        style: OutlinedButton.styleFrom(
            foregroundColor: ink, side: const BorderSide(color: line)),
        onPressed: onPressed,
        child: Text(label),
      );
    }
    return FilledButton(
      style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: const Color(0xFF06222A),
          textStyle: const TextStyle(fontWeight: FontWeight.w700)),
      onPressed: onPressed,
      child: Text(label),
    );
  }
}
