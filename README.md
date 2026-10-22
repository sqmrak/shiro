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

## protocol

- cloudflare warp over wireguard, system tunnel through utun
- the account is registered on the first connection and its keys stay with the root daemon
- registration runs over TLS 1.2 or newer with bundled roots and hostname checks
- if registration fails, the app says why and asks to try again

## routing

- settings, DNS: direct and blocked IPv4 networks, tunnel DNS
- rules use network/prefix, for example `192.168.0.0/16`
- unmatched IPv4 traffic uses WARP, IPv6 is blocked while the tunnel is active
- disconnect before changing rules, DNS or the registration proxy

## registration proxy

settings, advanced, registration proxy: a SOCKS5 or HTTP CONNECT URL, empty to disable.

```text
socks5://user:password@host:1080
http://host:8080
```

the proxy carries only the registration request. TLS still verifies Cloudflare's certificate, and the login stays in a root-owned file, out of diagnostics and backups. after registration the tunnel uses direct UDP, so its endpoints must be reachable.

## features

- connect at startup, automatic reconnect and endpoint failover
- traffic counters and connection statistics
- material expressive interface, light and dark
- falling foxes, with an off switch
- english, russian and chinese
- logs in the app with filters, search, copy and sharing
- crash reports and safe mode after repeated launch failures
- routing and DNS backup through the clipboard

the VPN badge needs a SpringBoard extension loaded by MobileSubstrate or a compatible injector. restart SpringBoard after installation.

## install

repo: `https://sqmrak.github.io/sqmrakdev/`

```bash
scp -O shiro-*.deb root@<device-ip>:/var/mobile/
ssh root@<device-ip> dpkg -i /var/mobile/shiro-*.deb
```

old SSH servers may need `-o HostKeyAlgorithms=+ssh-rsa`. remove: `dpkg -r com.shiro.daemon`, account keys and preferences are kept.

on ios 6 without a launchd socket, upgrades restart the daemon through KeepAlive. a first installation needs a reboot. if the app does not launch or the badge is missing, reboot first, then check system logs in settings.

## paths

- account: `/var/root/Library/Shiro/shiro.account`
- registration proxy: `/var/root/Library/Shiro/registration.proxy`
- control socket: `/var/run/shiro/control.sock`
- logs: `/var/root/Library/Shiro/shiro.log`, `install.log`
- app log and crash reports: `/var/mobile/Library/Preferences/Shiro/`

## build

needs an iOS cross toolchain (`clang`, `lipo`, `otool`, `ldid`), armv7 and arm64 SDKs, static OpenSSL for each slice, Python 3 with Pillow and `dpkg-deb`.

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

outputs `build/shiro-1.1.0-stable.deb` after host tests, slice inspection and package layout, ownership and signature checks. `SHIRO_TC`, `SHIRO_SDK_VE`, `SHIRO_PYTHON`, `SHIRO_LDID` and `SHIRO_HOST_CC` override the toolchain, arm64e SDK, Python, signer and host compiler.

`make sanitize` runs host tests with ASan and UBSan, `make ipa` packages the app only, `make clean` keeps the archives in `build/`.

## license

[gpl v3](LICENSE).
