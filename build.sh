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
    linux-headers \
    ninja \
    pkgconf \
    python3

export PKG_CONFIG_PATH="/usr/local/lib/pkgconfig"
export LD_LIBRARY_PATH="/usr/local/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

# ---------------------------------------------------------------------------
# Fetch latest dependency versions & download sources
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
eval "$("${SCRIPT_DIR}/fetch-versions.sh")"
"${SCRIPT_DIR}/download-sources.sh"

# Ensure subsequent builds find our musl libc first
export LIBRARY_PATH="/usr/local/lib${LIBRARY_PATH:+:$LIBRARY_PATH}"
export CPATH="/usr/local/include${CPATH:+:$CPATH}"

# ---------------------------------------------------------------------------
# 2. Build musl libc (C standard library)
# ---------------------------------------------------------------------------
echo "Building musl libc ${MUSL_VERSION}"

cd "/build/musl-${MUSL_VERSION}"

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
echo "Building rpmalloc ${RPMALLOC_VERSION}"

cd "/build/rpmalloc-${RPMALLOC_VERSION}"

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
echo "Building zlib-ng ${ZLIB_NG_VERSION}"

cd "/build/zlib-ng-${ZLIB_NG_VERSION}"

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
echo "Building LibreSSL ${LIBRESSL_VERSION}"

cd "/build/libressl-${LIBRESSL_VERSION}"

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
echo "Building nghttp2 ${NGHTTP2_VERSION}"

cd "/build/nghttp2-${NGHTTP2_VERSION}"

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
echo "Building libpsl ${LIBPSL_VERSION}"

cd "/build/libpsl-${LIBPSL_VERSION}"

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
echo "Building c-ares ${CARES_VERSION}"

cd "/build/c-ares-${CARES_VERSION}"

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
echo "Building curl ${CURL_VERSION}"

cd "/build/curl-curl-${CURL_VERSION//./_}"

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
    curl -fsSLO --retry 3 --retry-delay 5 \
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
    -DCMAKE_INSTALL_PREFIX=/opt/transmission \
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
# 11. Strip binaries and package the installation directory
# ---------------------------------------------------------------------------
OUTPUT="/output/transmission-linux-${ARCH}${SUFFIX}"

# Strip all binaries in the installation directory
if [ -d /opt/transmission/bin ]; then
    find /opt/transmission/bin -type f -executable -exec strip {} \; 2>/dev/null || true
fi

# Create a tar.xz archive of the entire installation directory
cd /opt
tar -cJf "${OUTPUT}.tar.xz" transmission

echo "=== Build complete ==="
file "${OUTPUT}.tar.xz"
ls -lh "${OUTPUT}.tar.xz"
