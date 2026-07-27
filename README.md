[![Build static Transmission binaries (release)](https://github.com/m3r3nix/transmission-static-binary/actions/workflows/release.yml/badge.svg)](https://github.com/m3r3nix/transmission-static-binary/actions/workflows/release.yml)
# Static Transmission Binaries

This repository provides fully static Transmission binaries built from the original source code of [transmission/transmission](https://github.com/transmission/transmission).

The goal is to provide portable Linux binaries that can run on most distributions without manually compiling Transmission or installing runtime library dependencies.

## Why Static Binaries?

A fully static binary includes the required libraries inside the executable itself.

This makes it useful for:

- Minimal Linux systems
- Containers
- NAS/server environments
- Older distributions
- Systems where compiling from source is inconvenient
- Deployments where you want a single portable executable

## Supported Platforms

Prebuilt binaries are provided for:

- `amd64`
- `arm64`

## Binary Variants

Each release may include multiple Transmission variants.

| Variant | Description |
|---|---|
| <code>transmission&#8209;linux&#8209;amd64</code> <br> <code>transmission&#8209;linux&#8209;arm64</code> | Modern Transmission build with Web UI, daemon, and utility tools (`transmission-daemon`, `transmission-remote`, `transmission-show`, `transmission-edit`) |

## Included Components

- **transmission-daemon** — BitTorrent client daemon with Web UI
- **transmission-remote** — Remote control CLI
- **transmission-show** — Torrent file inspector
- **transmission-edit** — Torrent file editor

## Installation

1. Download the binary for your architecture from the latest release: [here](https://github.com/m3r3nix/transmission-static-binary/releases).

2. Make it executable:

```sh
chmod +x transmission-linux-*
```

3. Move it into your PATH:
```sh
sudo mv transmission-linux-* /usr/local/bin/transmission-daemon
```

4. Verify it works:
```sh
transmission-daemon --help
```

## Notes

These binaries are built directly from upstream Transmission release sources using a fully static build chain inside an Alpine Linux container:

- **musl libc** for a consistent C standard library
- **rpmalloc** as the heap memory allocator
- **zlib-ng** as the zlib replacement
- **LibreSSL** as the TLS library
- **nghttp2** for HTTP/2 support
- **c-ares** for asynchronous DNS resolution
- **libpsl** for public suffix list handling

This repository does NOT modify Transmission functionality. It only automates the build process and publishes static Linux binaries.

For Transmission usage, configuration, and upstream documentation, refer to the original project: [transmission/transmission](https://github.com/transmission/transmission)
