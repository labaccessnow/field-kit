/// IOC defang / refang.
library;

String defang(String t) {
  var x = t;
  x = x
      .replaceAllMapped(RegExp(r'\bhttps://', caseSensitive: false),
          (_) => 'hxxps[://]')
      .replaceAllMapped(
          RegExp(r'\bhttp://', caseSensitive: false), (_) => 'hxxp[://]')
      .replaceAllMapped(
          RegExp(r'\bftp://', caseSensitive: false), (_) => 'fxp[://]');
  x = x.replaceAllMapped(
      RegExp(r'([a-z0-9._%+-]+)@([a-z0-9.-]+\.[a-z]{2,})', caseSensitive: false),
      (m) => '${m[1]}[at]${m[2]}');
  x = x.replaceAllMapped(RegExp(r'\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b'),
      (m) => m[0]!.replaceAll('.', '[.]'));
  x = x.replaceAllMapped(
      RegExp(r'\b(?:[a-z0-9_-]+\.)+[a-z]{2,}\b', caseSensitive: false),
      (m) => m[0]!.replaceAll('.', '[.]'));
  return x;
}

String refang(String t) {
  var x = t;
  x = x
      .replaceAll(RegExp(r'\[(?:\.|dot)\]', caseSensitive: false), '.')
      .replaceAll(RegExp(r'\((?:\.|dot)\)', caseSensitive: false), '.')
      .replaceAll(RegExp(r'\{(?:\.|dot)\}', caseSensitive: false), '.');
  x = x.replaceAll(
      RegExp(r'\[(?:at|@)\]|\((?:at|@)\)|\{(?:at|@)\}', caseSensitive: false),
      '@');
  x = x.replaceAll(RegExp(r'\[:\/\/\]|\[:\]\/\/|\[\/\/\]'), '://');
  x = x
      .replaceAllMapped(RegExp(r'\bhxxp(s?)\b', caseSensitive: false),
          (m) => 'http${m[1]!.toLowerCase()}')
      .replaceAll(RegExp(r'\bfxp\b', caseSensitive: false), 'ftp');
  x = x.replaceAllMapped(RegExp(r'\[:(\d+)\]'), (m) => ':${m[1]}');
  return x;
}
