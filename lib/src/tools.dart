import 'package:flutter/material.dart';

import 'ui/live_pages.dart';
import 'ui/net_pages.dart';
import 'ui/sec_pages.dart';

class Tool {
  final String name;
  final IconData icon;
  final bool security;
  final Widget page;
  const Tool(this.name, this.icon, this.page, {this.security = false});
}

const _net = false;

final tools = <Tool>[
  // Network
  const Tool('Subnet / VLSM', Icons.grid_view, SubnetPage(), security: _net),
  const Tool('CIDR summarizer', Icons.merge_type, AggregatePage(), security: _net),
  const Tool('Wildcard / ACL', Icons.rule, WildcardPage(), security: _net),
  const Tool('MTU / MSS', Icons.unfold_less, MtuPage(), security: _net),
  const Tool('Transfer time', Icons.schedule, XferPage(), security: _net),
  const Tool('Config diff', Icons.difference, DiffPage(), security: _net),
  const Tool('Ping', Icons.network_ping, PingPage(), security: _net),
  const Tool('Port check', Icons.sensors, PortPage(), security: _net),
  const Tool('DNS lookup', Icons.dns, DnsPage(), security: _net),
  const Tool('TLS certificate', Icons.workspace_premium, TlsPage(), security: _net),
  const Tool('Local interfaces', Icons.settings_ethernet, IfacesPage(), security: _net),
  const Tool('Public IP', Icons.public, PublicIpPage(), security: _net),
  // Security
  const Tool('Defang / refang', Icons.link_off, DefangPage(), security: true),
  const Tool('CVSS calculator', Icons.speed, CvssPage(), security: true),
  const Tool('JWT decoder', Icons.key, JwtPage(), security: true),
  const Tool('Hashes', Icons.tag, HashPage(), security: true),
  const Tool('Timestamps', Icons.history, TimestampPage(), security: true),
  const Tool('Decoder workbench', Icons.code, DecoderPage(), security: true),
];
