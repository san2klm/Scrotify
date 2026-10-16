# Entorno de compilación del AppImage portable: Debian 12 (glibc 2.36), así el
# binario corre también en Ubuntu 22.04+, Mint, Debian 12+, Fedora, Arch, etc.
# Compilar en una distro de rolling release (Arch/CachyOS) lo ata a su glibc.
FROM debian:12
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl git unzip xz-utils file clang cmake ninja-build build-essential \
      pkg-config libgtk-3-dev libmpv-dev libkeybinder-3.0-dev libsecret-1-dev \
      libsqlite3-dev libasound2-dev liblzma-dev ffmpeg \
    && rm -rf /var/lib/apt/lists/*
