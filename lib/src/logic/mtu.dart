/// MTU / MSS math for stacked encapsulations.
/// Overheads are typical documented values; real numbers vary by platform and
/// cipher, which the UI says out loud.
library;

class Encap {
  final String id;
  final String name;
  final int bytes;
  final String note;
  const Encap(this.id, this.name, this.bytes, this.note);
}

const encaps = <Encap>[
  Encap('vlan', '802.1Q VLAN tag', 4, 'only matters on a strict 1500-byte L2 path'),
  Encap('qinq', 'Q-in-Q (double tag)', 8, 'two 802.1Q tags'),
  Encap('pppoe', 'PPPoE', 8, 'common on DSL/FTTH handoffs'),
  Encap('gre', 'GRE', 24, '20 outer IP + 4 GRE'),
  Encap('grekey', 'GRE with key', 28, '20 outer IP + 8 GRE'),
  Encap('ipip', 'IPIP / 6in4', 20, 'one extra IPv4 header'),
  Encap('ipsec', 'IPsec ESP tunnel', 58, 'typ. AES-CBC/SHA; varies with cipher and padding'),
  Encap('natt', 'NAT-T (UDP 4500)', 8, 'add when ESP rides UDP'),
  Encap('vxlan', 'VXLAN', 50, 'outer IP + UDP + VXLAN header'),
  Encap('wg', 'WireGuard (IPv4 outer)', 60, '80 if the outer is IPv6'),
];

class MtuResult {
  final int mtu, total, mssV4, mssV6;
  MtuResult(int base, this.total)
      : mtu = base - total,
        mssV4 = base - total - 40,
        mssV6 = base - total - 60;
}

MtuResult mtuCalc(int base, Iterable<Encap> selected) {
  var total = 0;
  for (final e in selected) {
    total += e.bytes;
  }
  return MtuResult(base, total);
}
