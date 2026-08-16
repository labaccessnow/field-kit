/// MAC/OUI vendor lookup against the bundled IEEE MA-L registry
/// (assets/oui.tsv.gz — `ASSIGNMENT\tOrganization` per line).
library;

Map<String, String> parseOuiDb(String tsv) {
  final map = <String, String>{};
  for (final line in tsv.split('\n')) {
    final i = line.indexOf('\t');
    if (i == 6) map[line.substring(0, 6)] = line.substring(i + 1).trim();
  }
  return map;
}

class OuiLookup {
  final String? vendor;
  final String oui;
  final bool locallyAdministered;
  final bool multicast;
  final String? err;
  OuiLookup(this.vendor, this.oui,
      {this.locallyAdministered = false, this.multicast = false})
      : err = null;
  OuiLookup.fail(this.err)
      : vendor = null,
        oui = '',
        locallyAdministered = false,
        multicast = false;
}

OuiLookup lookupOui(Map<String, String> db, String mac) {
  final hex = mac.toUpperCase().replaceAll(RegExp(r'[^0-9A-F]'), '');
  if (hex.length < 6) {
    return OuiLookup.fail('Need at least the first three octets of a MAC.');
  }
  final oui = hex.substring(0, 6);
  final firstOctet = int.parse(oui.substring(0, 2), radix: 16);
  return OuiLookup(db[oui], oui,
      locallyAdministered: (firstOctet & 0x02) != 0,
      multicast: (firstOctet & 0x01) != 0);
}
