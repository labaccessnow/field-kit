/// Timestamp parsing and conversion: Unix epoch (s/ms/us), Windows FILETIME,
/// ISO 8601 / free-form date strings.
library;

final BigInt filetimeEpochDiff = BigInt.parse('116444736000000000');

class TsParse {
  final int? ms;
  final String src;
  final String? err;
  TsParse(this.ms, this.src) : err = null;
  TsParse.fail(this.err)
      : ms = null,
        src = '';
}

TsParse tsParse(String input, int nowMs) {
  final t = input.trim();
  if (t.isEmpty) return TsParse.fail('Enter a timestamp.');
  if (RegExp(r'^now$', caseSensitive: false).hasMatch(t)) {
    return TsParse(nowMs, 'current time');
  }
  if (RegExp(r'^-?\d+$').hasMatch(t)) {
    final digits = t.replaceFirst('-', '').length;
    if (digits <= 10) return TsParse(int.parse(t) * 1000, 'Unix epoch (seconds)');
    if (digits <= 13) return TsParse(int.parse(t), 'Unix epoch (milliseconds)');
    if (digits <= 16) {
      return TsParse(int.parse(t) ~/ 1000, 'Unix epoch (microseconds)');
    }
    final ms = ((BigInt.parse(t) - filetimeEpochDiff) ~/ BigInt.from(10000)).toInt();
    return TsParse(ms, 'Windows FILETIME (100ns since 1601)');
  }
  final d = DateTime.tryParse(t);
  if (d != null) return TsParse(d.toUtc().millisecondsSinceEpoch, 'date string');
  return TsParse.fail('Could not parse that — use epoch digits, ISO 8601, or "now".');
}

class TsFormats {
  final String iso, utc, local, filetime, relative;
  final int epochS, epochMs;
  TsFormats(this.iso, this.utc, this.local, this.filetime, this.relative,
      this.epochS, this.epochMs);
}

String tsRelative(int ms, int nowMs) {
  var d = (nowMs - ms) / 1000;
  final future = d < 0;
  d = d.abs();
  final String u;
  if (d < 60) {
    u = '${d.round()} seconds';
  } else if (d < 3600) {
    u = '${(d / 60).round()} minutes';
  } else if (d < 86400) {
    u = '${(d / 3600).toStringAsFixed(1)} hours';
  } else {
    u = '${(d / 86400).toStringAsFixed(1)} days';
  }
  return future ? 'in $u' : '$u ago';
}

TsFormats tsFormats(int ms, int nowMs) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  final local = d.toLocal();
  final ft = (BigInt.from(ms) * BigInt.from(10000) + filetimeEpochDiff).toString();
  String two(int n) => n.toString().padLeft(2, '0');
  final localStr =
      '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}:${two(local.second)} (${local.timeZoneName})';
  return TsFormats(d.toIso8601String(), d.toString(), localStr, ft,
      tsRelative(ms, nowMs), ms ~/ 1000, ms);
}
