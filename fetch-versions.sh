#!/bin/sh
# fetch-versions.sh
#
# Queries GitHub API for the latest versions of all dependencies
# and outputs them as shell-compatible variable assignments.
#
# Usage: eval "$(./fetch-versions.sh)"

set -eu

MUSL_VERSION="1.2.6"

RPMALLOC_VERSION=$(curl -fsS --retry 3 --retry-delay 5 "https://api.github.com/repos/mjansson/rpmalloc/releases/latest" | jq -r '.tag_name')
echo "Latest rpmalloc version: ${RPMALLOC_VERSION}" >&2

ZLIB_NG_VERSION=$(curl -fsS --retry 3 --retry-delay 5 "https://api.github.com/repos/zlib-ng/zlib-ng/releases/latest" | jq -r '.tag_name')
echo "Latest zlib-ng version: ${ZLIB_NG_VERSION}" >&2

LIBRESSL_VERSION=$(curl -fsS --retry 3 --retry-delay 5 "https://api.github.com/repos/libressl/portable/releases/latest" | jq -r '.tag_name' | sed 's/^v//')
echo "Latest LibreSSL version: ${LIBRESSL_VERSION}" >&2

NGHTTP2_VERSION=$(curl -fsS --retry 3 --retry-delay 5 "https://api.github.com/repos/nghttp2/nghttp2/releases/latest" | jq -r '.tag_name' | sed 's/^v//')
echo "Latest nghttp2 version: ${NGHTTP2_VERSION}" >&2

LIBPSL_VERSION=$(curl -fsS --retry 3 --retry-delay 5 "https://api.github.com/repos/rockdaboot/libpsl/releases/latest" | jq -r '.tag_name')
echo "Latest libpsl version: ${LIBPSL_VERSION}" >&2

CARES_VERSION=$(curl -fsS --retry 3 --retry-delay 5 "https://api.github.com/repos/c-ares/c-ares/releases/latest" | jq -r '.tag_name' | sed 's/^v//')
echo "Latest c-ares version: ${CARES_VERSION}" >&2

CURL_TAG=$(curl -fsS --retry 3 --retry-delay 5 "https://api.github.com/repos/curl/curl/releases/latest" | jq -r '.tag_name')
CURL_VERSION=$(echo "$CURL_TAG" | sed 's/curl-//' | tr '_' '.')
echo "Latest curl version: ${CURL_VERSION}" >&2

cat <<VERSIONS
MUSL_VERSION="${MUSL_VERSION}"
RPMALLOC_VERSION="${RPMALLOC_VERSION}"
ZLIB_NG_VERSION="${ZLIB_NG_VERSION}"
LIBRESSL_VERSION="${LIBRESSL_VERSION}"
NGHTTP2_VERSION="${NGHTTP2_VERSION}"
LIBPSL_VERSION="${LIBPSL_VERSION}"
CARES_VERSION="${CARES_VERSION}"
CURL_VERSION="${CURL_VERSION}"
VERSIONS
