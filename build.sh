#!/bin/sh
# build.sh
#
# Compiles a fully-static transmission binary inside an Alpine Linux container.
#
# Required environment variables:
#   TRANSMISSION_VERSION  Transmission version without the leading 'v'
#                         (e.g. 4.1.3)
#   TRANSMISSION_SHA      Git commit hash in case of a nightly build (e.g. 1a2b3c4)
#   ARCH                  Output filename suffix that identifies the target CPU
#                         (e.g.  amd64  or  arm64)
# Optional environment variables:
#   SUFFIX                Extra suffix for the output file

set -eux

: "${TRANSMISSION_VERSION:=}"
: "${TRANSMISSION_SHA:=}"
: "${ARCH:?ARCH must be set (e.g. amd64 or arm64)}"
: "${SUFFIX:=}"

if [ -z "${TRANSMISSION_VERSION}" ] && [ -z "${TRANSMISSION_SHA}" ]; then
    echo "TRANSMISSION_VERSION must be set for release builds, or TRANSMISSION_SHA must be set for nightly builds." >&2
    exit 1
fi

# Set architecture-specific compiler flags
case "${ARCH}" in
    amd64|x86_64)
        ARCH_CFLAGS="-march=x86-64-v2"
        ZLIB_AVX2="OFF"
        ;;
    amd64-gracemont|x86_64-gracemont)
        ARCH_CFLAGS="-march=gracemont -mtune=gracemont"
        ZLIB_AVX2="ON"
        ;;
    amd64-tremont|x86_64-tremont)
        ARCH_CFLAGS="-march=tremont -mtune=tremont"
        ZLIB_AVX2="OFF"
        ;;
    amd64-v3|x86_64-v3)
        ARCH_CFLAGS="-march=x86-64-v3"
        ZLIB_AVX2="ON"
        ;;
    arm64|aarch64)
        ARCH_CFLAGS="-march=armv8-a"
        ZLIB_AVX2="OFF"
        ;;
    *)
        ARCH_CFLAGS=""
        ZLIB_AVX2="OFF"
        ;;
esac
BASE_CFLAGS="${ARCH_CFLAGS} -static -O3 -pipe"

# ---------------------------------------------------------------------------
# 1. System packages
# ---------------------------------------------------------------------------
apk add --no-cache \
    autoconf \
    automake \
    build-base \
    cmake \
    curl \
    gawk \
    git \
    jq \
    libtool \
    ninja \
    pkgconf \
    python3

export PKG_CONFIG_PATH="/usr/local/lib/pkgconfig"
export LD_LIBRARY_PATH="/usr/local/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

# ---------------------------------------------------------------------------
# 2. Build musl libc (C standard library)
# ---------------------------------------------------------------------------
MUSL_VERSION="1.2.6"
echo "Building musl libc ${MUSL_VERSION}"

mkdir -p /build
cd /build
curl -fsSLO "https://git.musl-libc.org/cgit/musl/snapshot/musl-${MUSL_VERSION}.tar.gz"
tar xf "musl-${MUSL_VERSION}.tar.gz"
cd "musl-${MUSL_VERSION}"

./configure \
    --prefix=/usr/local \
    --disable-shared \
    CFLAGS="${ARCH_CFLAGS} -O3 -pipe"

make -j"$(nproc)"
make install

# Ensure subsequent builds find our musl libc first
export LIBRARY_PATH="/usr/local/lib${LIBRARY_PATH:+:$LIBRARY_PATH}"
export CPATH="/usr/local/include${CPATH:+:$CPATH}"

# ---------------------------------------------------------------------------
# 3. Build rpmalloc (modern heap memory allocator)
# ---------------------------------------------------------------------------
RPMALLOC_VERSION=$(curl -fsS "https://api.github.com/repos/mjansson/rpmalloc/releases/latest" | jq -r '.tag_name')
echo "Latest rpmalloc version: ${RPMALLOC_VERSION}"

mkdir -p /build
cd /build
curl -fsSLO "https://github.com/mjansson/rpmalloc/archive/refs/tags/${RPMALLOC_VERSION}.tar.gz"
tar xf "${RPMALLOC_VERSION}.tar.gz"
cd "rpmalloc-${RPMALLOC_VERSION}"

# Map ARCH to rpmalloc architecture name
case "${ARCH}" in
    amd64*|x86_64*)  RPMALLOC_ARCH="x86-64"  ;;
    arm64|aarch64)   RPMALLOC_ARCH="arm64"    ;;
    *)               RPMALLOC_ARCH=""         ;;
esac

python3 configure.py --lto -c release --toolchain gcc ${RPMALLOC_ARCH:+-a "${RPMALLOC_ARCH}"}

ninja -j"$(nproc)" "lib/linux/release/${RPMALLOC_ARCH}/librpmalloc.a"

# Copy the static library
mkdir -p /usr/local/lib
cp -f "lib/linux/release/${RPMALLOC_ARCH}/librpmalloc.a" /usr/local/lib/

# ---------------------------------------------------------------------------
# 4. Build zlib-ng (zlib replacement with optimizations)
# ---------------------------------------------------------------------------
ZLIB_NG_VERSION=$(curl -fsS "https://api.github.com/repos/zlib-ng/zlib-ng/releases/latest" | jq -r '.tag_name')
echo "Latest zlib-ng version: ${ZLIB_NG_VERSION}"

mkdir -p /build
cd /build
curl -fsSLO "https://github.com/zlib-ng/zlib-ng/archive/refs/tags/${ZLIB_NG_VERSION}.tar.gz"
tar xf "${ZLIB_NG_VERSION}.tar.gz"
cd "zlib-ng-${ZLIB_NG_VERSION}"

cmake -B build \
    -DCMAKE_INSTALL_PREFIX=/usr/local \
    -DBUILD_SHARED_LIBS=OFF \
    -DBUILD_TESTING=OFF \
    -DZLIB_COMPAT=ON \
    -DWITH_AVX512=OFF \
    -DWITH_AVX2=${ZLIB_AVX2} \
    -DCMAKE_C_FLAGS="${BASE_CFLAGS}" \
    -DCMAKE_EXE_LINKER_FLAGS="-static" \
    -DCMAKE_INSTALL_LIBDIR=lib

cmake --build build -j"$(nproc)"
cmake --install build

# Remove the system zlib .pc file so pkg-config prefers zlib-ng
rm -f /usr/lib/pkgconfig/zlib.pc 2>/dev/null || true

# ---------------------------------------------------------------------------
# 5. Build LibreSSL (replaces OpenSSL)
# ---------------------------------------------------------------------------
LIBRESSL_VERSION=$(curl -fsS "https://api.github.com/repos/libressl/portable/releases/latest" | jq -r '.tag_name' | sed 's/^v//')
echo "Latest LibreSSL version: ${LIBRESSL_VERSION}"

cd /build
curl -fsSLO "https://ftp.openbsd.org/pub/OpenBSD/LibreSSL/libressl-${LIBRESSL_VERSION}.tar.gz"
tar xf "libressl-${LIBRESSL_VERSION}.tar.gz"
cd "libressl-${LIBRESSL_VERSION}"

cmake -B build \
    -DCMAKE_INSTALL_PREFIX=/usr/local \
    -DBUILD_SHARED_LIBS=OFF \
    -DLIBRESSL_APPS=OFF \
    -DLIBRESSL_TESTS=OFF \
    -DCMAKE_C_FLAGS="${BASE_CFLAGS}" \
    -DCMAKE_EXE_LINKER_FLAGS="-static" \
    -DCMAKE_INSTALL_LIBDIR=lib

cmake --build build -j"$(nproc)"
cmake --install build

# ---------------------------------------------------------------------------
# 6. Build nghttp2 (HTTP/2 library)
# ---------------------------------------------------------------------------
NGHTTP2_VERSION=$(curl -fsS "https://api.github.com/repos/nghttp2/nghttp2/releases/latest" | jq -r '.tag_name' | sed 's/^v//')
echo "Latest nghttp2 version: ${NGHTTP2_VERSION}"

cd /build
curl -fsSLO "https://github.com/nghttp2/nghttp2/archive/refs/tags/v${NGHTTP2_VERSION}.tar.gz"
tar xf "v${NGHTTP2_VERSION}.tar.gz"
cd "nghttp2-${NGHTTP2_VERSION}"

autoreconf -fi
./configure \
    --enable-static \
    --disable-shared \
    --disable-debug \
    --enable-lib-only \
    PKG_CONFIG="pkg-config --static" \
    CFLAGS="${BASE_CFLAGS}" \
    CXXFLAGS="${BASE_CFLAGS}"

make -j"$(nproc)"
make install

# ---------------------------------------------------------------------------
# 7. Build libpsl (Public Suffix List library)
# ---------------------------------------------------------------------------
LIBPSL_VERSION=$(curl -fsS "https://api.github.com/repos/rockdaboot/libpsl/releases/latest" | jq -r '.tag_name')
echo "Latest libpsl version: ${LIBPSL_VERSION}"

cd /build
curl -fsSLO "https://github.com/rockdaboot/libpsl/releases/download/${LIBPSL_VERSION}/libpsl-${LIBPSL_VERSION}.tar.gz"
tar xf "libpsl-${LIBPSL_VERSION}.tar.gz"
cd "libpsl-${LIBPSL_VERSION}"

./configure \
    --prefix=/usr/local \
    --enable-static \
    --disable-shared \
    --disable-gtk-doc \
    --disable-runtime \
    PKG_CONFIG="pkg-config --static" \
    CFLAGS="${BASE_CFLAGS}"

make -j"$(nproc)"
make install

# ---------------------------------------------------------------------------
# 8. Build c-ares (asynchronous DNS resolver)
# ---------------------------------------------------------------------------
CARES_VERSION=$(curl -fsS "https://api.github.com/repos/c-ares/c-ares/releases/latest" | jq -r '.tag_name' | sed 's/^v//')
echo "Latest c-ares version: ${CARES_VERSION}"

cd /build
curl -fsSLO "https://github.com/c-ares/c-ares/releases/download/v${CARES_VERSION}/c-ares-${CARES_VERSION}.tar.gz"
tar xf "c-ares-${CARES_VERSION}.tar.gz"
cd "c-ares-${CARES_VERSION}"

cmake -B build \
    -DCMAKE_INSTALL_PREFIX=/usr/local \
    -DBUILD_SHARED_LIBS=OFF \
    -DCARES_STATIC=ON \
    -DCARES_SHARED=OFF \
    -DCARES_BUILD_TOOLS=OFF \
    -DCARES_BUILD_TESTS=OFF \
    -DCMAKE_C_FLAGS="${BASE_CFLAGS}" \
    -DCMAKE_EXE_LINKER_FLAGS="-static" \
    -DCMAKE_INSTALL_LIBDIR=lib

cmake --build build -j"$(nproc)"
cmake --install build

# ---------------------------------------------------------------------------
# 9. Build curl (HTTP/HTTPS tool and library, with c-ares)
# ---------------------------------------------------------------------------
CURL_TAG=$(curl -fsS "https://api.github.com/repos/curl/curl/releases/latest" | jq -r '.tag_name')
CURL_VERSION=$(echo "$CURL_TAG" | sed 's/curl-//' | tr '_' '.')
echo "Latest curl version: ${CURL_VERSION}"

cd /build
curl -fsSLO "https://github.com/curl/curl/archive/refs/tags/curl-${CURL_VERSION//./_}.tar.gz"
tar xf "curl-${CURL_VERSION//./_}.tar.gz"
cd "curl-curl-${CURL_VERSION//./_}"

autoreconf -fi
./configure \
    --prefix=/usr/local \
    --enable-static \
    --disable-shared \
    --disable-debug \
    --disable-unix-sockets \
    --disable-headers-api \
    --disable-alt-svc \
    --disable-hsts \
    --enable-ares \
    --without-brotli \
    --disable-docs \
    --disable-ipfs \
    --with-openssl \
    --with-nghttp2 \
    --without-nghttp3 \
    --without-ngtcp2 \
    --without-openssl-quic \
    --with-zlib \
    --enable-ipv6 \
    --disable-ldap \
    --disable-ldaps \
    --disable-manual \
    --disable-dict \
    --disable-gopher \
    --disable-imap \
    --disable-mqtt \
    --disable-pop3 \
    --disable-rtsp \
    --disable-smb \
    --disable-smtp \
    --disable-telnet \
    --disable-tftp \
    PKG_CONFIG="pkg-config --static" \
    CFLAGS="${BASE_CFLAGS}" \
    CXXFLAGS="${BASE_CFLAGS}"

make -j"$(nproc)"
make install

# ---------------------------------------------------------------------------
# 10. Build Transmission
# ---------------------------------------------------------------------------
cd /build

if [ -n "${TRANSMISSION_VERSION}" ]; then
    curl -fsSLO \
        "https://github.com/transmission/transmission/releases/download/${TRANSMISSION_VERSION}/transmission-${TRANSMISSION_VERSION}.tar.xz"
    tar xf "transmission-${TRANSMISSION_VERSION}.tar.xz"
    cd "transmission-${TRANSMISSION_VERSION}"
else
    git clone --filter=blob:none --single-branch --recurse-submodules https://github.com/transmission/transmission.git
    cd transmission
    git checkout "$TRANSMISSION_SHA"
    git submodule update --init --recursive
fi

cmake -B build -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr/local \
    -DBUILD_SHARED_LIBS=OFF \
    -DENABLE_DAEMON=ON \
    -DENABLE_GTK=OFF \
    -DENABLE_QT=OFF \
    -DENABLE_MAC=OFF \
    -DREBUILD_WEB=OFF \
    -DINSTALL_WEB=ON \
    -DENABLE_UTILS=ON \
    -DENABLE_CLI=OFF \
    -DENABLE_TESTS=OFF \
    -DENABLE_UTP=ON \
    -DENABLE_WERROR=OFF \
    -DENABLE_NLS=OFF \
    -DINSTALL_DOC=OFF \
    -DINSTALL_LIB=OFF \
    -DENABLE_DEPRECATED=OFF \
    -DRUN_CLANG_TIDY=OFF \
    -DUSE_SYSTEM_EVENT2=OFF \
    -DUSE_SYSTEM_DEFLATE=OFF \
    -DUSE_SYSTEM_DHT=OFF \
    -DUSE_SYSTEM_MINIUPNPC=OFF \
    -DUSE_SYSTEM_NATPMP=OFF \
    -DUSE_SYSTEM_UTP=OFF \
    -DUSE_SYSTEM_B64=OFF \
    -DUSE_SYSTEM_PSL=ON \
    -DWITH_INOTIFY=OFF \
    -DWITH_KQUEUE=OFF \
    -DWITH_APPINDICATOR=OFF \
    -DWITH_SYSTEMD=OFF \
    -DCMAKE_C_FLAGS="${BASE_CFLAGS}" \
    -DCMAKE_CXX_FLAGS="${BASE_CFLAGS}" \
    -DCMAKE_EXE_LINKER_FLAGS="-static -l:librpmalloc.a -Wl,--undefined=malloc -Wl,--undefined=free -Wl,--undefined=calloc -Wl,--undefined=realloc"

cmake --build build -j"$(nproc)"
cmake --install build

# ---------------------------------------------------------------------------
# 11. Copy and verify the output binary
# ---------------------------------------------------------------------------
OUTPUT="/output/transmission-linux-${ARCH}${SUFFIX}"

cp /usr/local/bin/transmission-daemon "${OUTPUT}"
strip "${OUTPUT}"

echo "=== Build complete ==="
file "${OUTPUT}"
ls -lh "${OUTPUT}"
