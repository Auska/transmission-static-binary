#!/bin/sh
# download-sources.sh
#
# Downloads and extracts all dependency source tarballs to /build/.
# Version variables must be set in the environment (e.g. via fetch-versions.sh).
#
# Usage: eval "$(./fetch-versions.sh)" && ./download-sources.sh

set -eu

: "${MUSL_VERSION:?MUSL_VERSION not set}"
: "${RPMALLOC_VERSION:?RPMALLOC_VERSION not set}"
: "${ZLIB_NG_VERSION:?ZLIB_NG_VERSION not set}"
: "${LIBRESSL_VERSION:?LIBRESSL_VERSION not set}"
: "${NGHTTP2_VERSION:?NGHTTP2_VERSION not set}"
: "${LIBPSL_VERSION:?LIBPSL_VERSION not set}"
: "${CARES_VERSION:?CARES_VERSION not set}"
: "${CURL_VERSION:?CURL_VERSION not set}"

# ---------------------------------------------------------------------------
# musl libc
# ---------------------------------------------------------------------------
mkdir -p /build
cd /build
curl -fsSLO --retry 3 --retry-delay 5 "https://git.musl-libc.org/cgit/musl/snapshot/musl-${MUSL_VERSION}.tar.gz"
tar xf "musl-${MUSL_VERSION}.tar.gz"

# ---------------------------------------------------------------------------
# rpmalloc
# ---------------------------------------------------------------------------
mkdir -p /build
cd /build
curl -fsSLO --retry 3 --retry-delay 5 "https://github.com/mjansson/rpmalloc/archive/refs/tags/${RPMALLOC_VERSION}.tar.gz"
tar xf "${RPMALLOC_VERSION}.tar.gz"

# ---------------------------------------------------------------------------
# zlib-ng
# ---------------------------------------------------------------------------
mkdir -p /build
cd /build
curl -fsSLO --retry 3 --retry-delay 5 "https://github.com/zlib-ng/zlib-ng/archive/refs/tags/${ZLIB_NG_VERSION}.tar.gz"
tar xf "${ZLIB_NG_VERSION}.tar.gz"

# ---------------------------------------------------------------------------
# LibreSSL
# ---------------------------------------------------------------------------
mkdir -p /build
cd /build
curl -fsSLO --retry 3 --retry-delay 5 "https://ftp.openbsd.org/pub/OpenBSD/LibreSSL/libressl-${LIBRESSL_VERSION}.tar.gz"
tar xf "libressl-${LIBRESSL_VERSION}.tar.gz"

# ---------------------------------------------------------------------------
# nghttp2
# ---------------------------------------------------------------------------
mkdir -p /build
cd /build
curl -fsSLO --retry 3 --retry-delay 5 "https://github.com/nghttp2/nghttp2/archive/refs/tags/v${NGHTTP2_VERSION}.tar.gz"
tar xf "v${NGHTTP2_VERSION}.tar.gz"

# ---------------------------------------------------------------------------
# libpsl
# ---------------------------------------------------------------------------
mkdir -p /build
cd /build
curl -fsSLO --retry 3 --retry-delay 5 "https://github.com/rockdaboot/libpsl/releases/download/${LIBPSL_VERSION}/libpsl-${LIBPSL_VERSION}.tar.gz"
tar xf "libpsl-${LIBPSL_VERSION}.tar.gz"

# ---------------------------------------------------------------------------
# c-ares
# ---------------------------------------------------------------------------
mkdir -p /build
cd /build
curl -fsSLO --retry 3 --retry-delay 5 "https://github.com/c-ares/c-ares/releases/download/v${CARES_VERSION}/c-ares-${CARES_VERSION}.tar.gz"
tar xf "c-ares-${CARES_VERSION}.tar.gz"

# ---------------------------------------------------------------------------
# curl
# ---------------------------------------------------------------------------
mkdir -p /build
cd /build
curl -fsSLO --retry 3 --retry-delay 5 "https://github.com/curl/curl/archive/refs/tags/curl-${CURL_VERSION//./_}.tar.gz"
tar xf "curl-${CURL_VERSION//./_}.tar.gz"
