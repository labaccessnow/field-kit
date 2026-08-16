/// Transfer-time math.
library;

String humanDur(double s) {
  if (!s.isFinite) return '—';
  if (s < 1) return '${(s * 1000).round()} ms';
  if (s < 60) return s < 10 ? '${s.toStringAsFixed(1)} s' : '${s.round()} s';
  final d = s ~/ 86400;
  final h = (s % 86400) ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final sec = (s % 60).round();
  final parts = <String>[];
  if (d > 0) parts.add('${d}d');
  if (h > 0) parts.add('${h}h');
  if (m > 0) parts.add('${m}m');
  if (sec > 0 && d == 0) parts.add('${sec}s');
  return parts.isEmpty ? '0s' : parts.join(' ');
}

class XferResult {
  final double seconds;
  final String human;
  final String? err;
  XferResult(this.seconds, this.human) : err = null;
  XferResult.fail(this.err)
      : seconds = 0,
        human = '';
}

XferResult xferTime(
    double sizeVal, double sizeUnitBytes, double rateVal, double rateUnitBits,
    double effPct) {
  final bytes = sizeVal * sizeUnitBytes;
  final bps = rateVal * rateUnitBits * (effPct / 100);
  if (bytes <= 0) return XferResult.fail('Enter a data size.');
  if (bps <= 0) return XferResult.fail('Enter a link rate.');
  final s = bytes * 8 / bps;
  return XferResult(s, humanDur(s));
}
