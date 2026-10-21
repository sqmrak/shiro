#!/usr/bin/env bash
set -euo pipefail
src="${SHIRO_OPENSSL_SRC:?set SHIRO_OPENSSL_SRC to the openssl source directory}"
prefix="${SHIRO_OPENSSL_VE:?set SHIRO_OPENSSL_VE to the arm64e openssl prefix}"
build="${SHIRO_OPENSSL_BUILD_VE:?set SHIRO_OPENSSL_BUILD_VE to a separate build directory}"
sdk="${SHIRO_SDK_VE:-${SHIRO_SDK_V64:?set SHIRO_SDK_V64}}"
cc="${SHIRO_MODERN_CC:?set SHIRO_MODERN_CC to a versioned arm64e compiler}"
tc="${SHIRO_TC:-${THEOS:?set THEOS or SHIRO_TC}/toolchain/linux/iphone/bin}"
[[ -f "$src/Configure" && -x "$cc" && -x "$tc/llvm-ar" ]] || { echo 'missing openssl source or compiler tools' >&2; exit 1; }
mkdir -p "$build" "$prefix/lib" "$prefix/include"
export SHIRO_ARM64E_CC="$cc" SHIRO_ARM64E_TC="$tc"
cat > "$build/arm64e-clang" <<'WRAPPER'
#!/usr/bin/env bash
set -euo pipefail
args=()
skip=0
for arg in "$@"; do
    if [[ "$skip" == 1 ]]; then skip=0; continue; fi
    if [[ "$arg" == -arch ]]; then skip=1; continue; fi
    args+=("$arg")
done
exec "$SHIRO_ARM64E_CC" -target arm64e-apple-ios14.0 -B"$SHIRO_ARM64E_TC" "${args[@]}"
WRAPPER
chmod 755 "$build/arm64e-clang"
mkdir -p "$build/cross-top/SDKs"
ln -sfn "$sdk" "$build/cross-top/SDKs/iPhoneOS.sdk"
export CROSS_TOP="$build/cross-top" CROSS_SDK=iPhoneOS.sdk
cd "$build"
"$src/Configure" ios64-cross "CC=$build/arm64e-clang" "AR=$tc/llvm-ar" "RANLIB=$tc/llvm-ranlib" \
    no-asm no-shared no-dso no-tests no-engine no-ui-console \
    -DBROKEN_CLANG_ATOMICS -O2 -fno-strict-aliasing \
    --prefix="$prefix" -miphoneos-version-min=14.0 -isysroot "$sdk"
make -j"${SHIRO_JOBS:-4}" build_libs
cp libssl.a libcrypto.a "$prefix/lib/"
cp -R "$src/include/openssl" "$prefix/include/"
cp -R include/openssl/. "$prefix/include/openssl/"
