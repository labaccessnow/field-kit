# Field Kit

A free app with the small network and security tools you keep opening
sketchy websites for — subnet math, CVSS scoring, JWT decoding, defanging IOCs,
cert checks — in one window, running entirely on your machine.

Built by [NetOps Field Notes](https://netopsfieldnotes.com) and
[SecOps Field Notes](https://secopsfieldnotes.com). Windows, macOS, Linux and
Android — portable, no installer, no signup, no telemetry.

## The tools

**Network**

- **Subnet calculator / VLSM splitter** — carve a block into named subnets and get the full allocation table (IPv4 and IPv6)
- **CIDR summarizer** — paste a messy prefix list, get the minimal aggregated route set back
- **Wildcard / ACL helper** — CIDR ↔ Cisco wildcard, with a ready ACL line, and it flags discontiguous masks
- **MTU / MSS calculator** — stack VLAN/GRE/IPsec/VXLAN/WireGuard overheads, get the MTU and the MSS clamp
- **Transfer time** — how long that copy actually takes at that rate
- **Config diff** — compare two configs without pasting them into someone's website; can skip comments and whitespace
- **Ping, TCP port check, DNS lookup** — the quick liveness trio; DNS shows your resolver next to 1.1.1.1 so split-horizon surprises jump out
- **Traceroute** — hop by hop, streamed as it goes (not on iPhone, which doesn't allow it)
- **Whois** — domains and IPs, following the referral from IANA to the registry to the registrar
- **TLS certificate inspector** — what cert a host really serves, expiry countdown, and whether your machine trusts the chain
- **MAC / OUI lookup** — vendor from the IEEE list bundled in the app, plus the locally-administered and multicast bits
- **Local interfaces / public IP** — both ends of your connectivity at a glance

**Security**

- **IOC defang / refang** — hxxps[://], [.], [at], both directions
- **IOC extractor** — pull IPs, domains, URLs, emails, CVEs and hashes out of any pasted text, defanged and ready to share
- **Email header analyzer** — the Received chain in order with per-hop delay, SPF/DKIM/DMARC results, and From/Reply-To mismatch warnings
- **CVSS v3.1 calculator** — metric buttons ↔ vector string ↔ score
- **JWT decoder** — claims, expiry status, and a loud warning on `alg:none`. Decode-only, local
- **Hashes** — MD5/SHA-1/SHA-256/SHA-512 of text or files, compare against a published hash, identify unknown hash formats
- **Timestamp converter** — epoch in s/ms/µs, Windows FILETIME, ISO 8601
- **Decoder workbench** — Base64/URL/hex/HTML entities/ROT13, with output-to-input chaining for peeling layered payloads

## Download

Grab the latest build from the [releases page](../../releases). `SHA256SUMS`
is published with every release if you want to verify the download.

- **Windows / macOS** — extract the zip anywhere and run. No installer, no
  admin rights, nothing written to the system. Delete the folder and it's gone.
  The Mac build needs macOS 12 or later.
- **Linux** — `sudo apt install ./fieldkit_<version>_amd64.deb` on
  Debian/Ubuntu-family (desktop entry and icon included), or the tarball's
  `./install.sh` for everything else — it stays inside `~/.local`, no root.
- **Android** — download the `.apk` on your phone and open it. Android asks
  once to allow installs from your browser or Files app. On a phone the app
  opens to a list of the tools; on a tablet or unfolded phone you get the
  sidebar.

### The one-time unsigned-app prompt

These builds aren't code-signed yet, so the first launch asks for a click:

- **Windows** — SmartScreen will interject. Click **More info → Run anyway**.
  That's it, once.
- **macOS** — right-click the app → **Open** (macOS 14 and earlier), or go to
  **System Settings → Privacy & Security** and hit **Open Anyway** (macOS 15+).
  Terminal people: `xattr -dr com.apple.quarantine "Field Kit.app"` does the
  same thing.

## What talks to the network

Almost nothing. Every converter, calculator, decoder and hash runs locally —
paste a config or a token into this app and it does not leave your machine.
The exceptions are the tools whose whole job is the network: ping, traceroute,
port check and the TLS inspector talk to the host you point them at, whois
asks the public whois servers, DNS lookup also
queries 1.1.1.1 over HTTPS, and the public-IP check calls
[whatismynetip.com](https://whatismynetip.com). No analytics, no update
phone-home, nothing else. On an IPv6-only network (plenty of phone carriers
run one) an IPv4 address is reached through the network's NAT64 gateway, and
finding it takes one resolver question for `ipv4only.arpa`.

The same thing in policy form:
[privacy policy](https://netopsfieldnotes.com/tools/fieldkit/privacy/).

## Building from source

It's a standard Flutter app:

```bash
flutter pub get
flutter test          # 187 tests, including the CVSS/RFC vectors and phone layouts
flutter build windows # or: macos / linux / apk
```

## License

MIT. Do whatever you want with it. If it saves you a bad paste into a random
website, tell a colleague.
