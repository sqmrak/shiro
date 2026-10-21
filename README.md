# shiro

<p align="center">
  <img src="assets/shiro-phone.png" width="420" alt="shiro">
</p>

<p align="center"><b>cloudflare warp for the whole device, ios 5 and later, one deb</b></p>

> [!NOTE]
> all devices need a jailbreak. the deb installs the app, root daemon and status bar extension.

## devices

- armv7: ios 5 and later
- arm64: ios 7 and later
- arm64e: ios 14 and later

these are the binary deployment targets. installation, daemon startup and a WARP connection have been checked on an iphone 4s running ios 6.1.3.

## protocol

- cloudflare warp over wireguard
- system tunnel through utun
- automatic account registration on the first connection
- account keys stored by the root daemon
- registration over TLS 1.2 or newer, with bundled roots and certificate hostname checks

## routing

- settings, DNS: direct and blocked IPv4 networks, tunnel DNS
- unmatched IPv4 traffic uses WARP
- rules use network/prefix, for example `192.168.0.0/16`
- disconnect before changing rules or DNS
- IPv6 is blocked while the tunnel is active

## registration proxy

settings, advanced, registration proxy: enter a SOCKS5 or HTTP CONNECT URL.

```text
socks5://host:1080
socks5://user:password@host:1080
http://host:8080
http://user:password@host:8080
```

disconnect before changing the proxy. leave the field empty to disable it. percent-encode reserved characters in the login and password.

the proxy resolves the API hostname and carries the registration request. TLS still verifies Cloudflare's certificate. credentials stay in a root-owned file and are omitted from diagnostics and settings backups.

the WARP tunnel uses direct UDP after registration. its endpoints must be reachable from the device's network.

## features

- connect at startup, automatic reconnect and endpoint failover
- traffic counters and connection statistics
- light and dark raspberry palettes, with a system theme picker
- falling foxes, with an off switch
- english, russian and chinese
- logs in the app, with source filters, search, copy and sharing where available
- app crash reports and safe mode after repeated launch failures
- routing and DNS backup through the clipboard

the VPN badge uses a SpringBoard extension loaded by MobileSubstrate or a compatible injector. restart SpringBoard after installation to load it.

## install

use the deb from `build/`:

```bash
scp -O build/shiro-1.0.0-stable.deb root@<device-ip>:/var/mobile/
ssh root@<device-ip> 'dpkg -i /var/mobile/shiro-1.0.0-stable.deb'
```

old SSH servers may require `-o HostKeyAlgorithms=+ssh-rsa` for both commands.

remove: `dpkg -r com.shiro.daemon`. account keys and preferences are preserved.

on ios 6 with a missing launchd socket, upgrades restart an existing daemon job through KeepAlive. a first installation without a registered job needs a device reboot.

## troubleshooting

if the app does not launch, the VPN badge is missing or the Wi-Fi icon disappears, reboot the device first.

if the problem remains, open settings, system logs and check the app, shirod and status logs.

## paths

- account: `/var/root/Library/Shiro/shiro.account`
- registration proxy: `/var/root/Library/Shiro/registration.proxy`
- control socket: `/var/run/shiro/control.sock`
- daemon log: `/var/root/Library/Shiro/shiro.log`
- installation log: `/var/root/Library/Shiro/install.log`
- app log and crash reports: `/var/mobile/Library/Preferences/Shiro/`
- status extension log: `/var/mobile/Library/Preferences/com.shiro.status.log`
- packaged app: `/var/jb/Applications/Shiro.app`
- rootful app copy: `/Applications/Shiro.app`

## source tree

- `app/`: UIKit interface, themes and localization
- `common/`: local control interface shared by the app and daemon
- `core/`: portable C networking, wireguard and routing logic
- `daemon/`: privileged tunnel, account storage and device integration
- `status/`: SpringBoard status bar extension
- `assets/`, `resources/`: artwork and certificate roots
- `packaging/`: package metadata and installation scripts
- `scripts/`: cross builds, image generation and artifact checks
- `tests/`: host tests and installation fixtures

`build/` contains generated files and local packages and is excluded from git. SDKs, toolchains and OpenSSL builds stay outside the source tree. device accounts, proxy credentials and logs are runtime data.

## build

needs an iOS cross toolchain with `clang`, `lipo`, `otool` and `ldid`, legacy armv7 and modern arm64 SDKs, static OpenSSL builds for each slice, Python 3 with Pillow, and `dpkg-deb`. host tests need a C99 compiler and OpenSSL development headers and libraries.

```bash
export THEOS=/path/to/theos
export SHIRO_SDK_V7=/path/to/legacy-iphoneos.sdk
export SHIRO_SDK_V64=/path/to/modern-iphoneos.sdk
export SHIRO_OPENSSL_V7=/path/to/openssl/armv7
export SHIRO_OPENSSL_V64=/path/to/openssl/arm64
export SHIRO_OPENSSL_VE=/path/to/openssl/arm64e
export SHIRO_MODERN_CC=/path/to/modern/clang
export SHIRO_CRT_V7="$SHIRO_SDK_V7/usr/lib/crt1.o"

make test
make deb
```

outputs `build/shiro-1.0.0-stable.deb`. the package build runs host tests, inspects the architecture slices and checks package layout, ownership, permissions and signature records.

`SHIRO_TC` overrides the toolchain directory, `SHIRO_SDK_VE` overrides the arm64e SDK, `SHIRO_PYTHON` selects Python, and `SHIRO_LDID` selects the signer. `SHIRO_HOST_CC` selects the host compiler. arm64e uses the modern compiler; the other slices use the toolchain compiler.

`make sanitize` runs host tests with ASan and UBSan. `make app-unsigned` builds the app bundle, and `make inspect-unsigned` builds and inspects all binaries.

`make ipa` packages the app only. the root daemon and status extension are installed by the deb.

`make clean` removes build intermediates and staging directories. existing DEB and IPA archives in `build/` are preserved.

## license

[gpl v3](LICENSE).
