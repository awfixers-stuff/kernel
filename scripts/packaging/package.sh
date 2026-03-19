#!/bin/bash
# Microkernel Packaging Script
# Creates .deb, .rpm, .tar, and .tar.gz packages for the kernel

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Default values
VERSION="${VERSION:-$(grep '^version' "${PROJECT_ROOT}/Cargo.toml" | head -1 | cut -d'"' -f2)}"
ARCH="${ARCH:-$(uname -m)}"
OUTPUT_DIR="${OUTPUT_DIR:-${PROJECT_ROOT}/packages}"
BUILD_DIR="${BUILD_DIR:-${PROJECT_ROOT}/target/${ARCH}}"

# Normalize architecture names
normalize_arch() {
    local arch="$1"
    case "${arch}" in
        x86_64|amd64) echo "x86_64" ;;
        i686|i386|x86) echo "i686" ;;
        aarch64|arm64) echo "aarch64" ;;
        riscv64|riscv64gc) echo "riscv64" ;;
        *) echo "${arch}" ;;
    esac
}

# Get Debian architecture name
get_deb_arch() {
    local arch="$1"
    case "${arch}" in
        x86_64) echo "amd64" ;;
        i686) echo "i386" ;;
        aarch64) echo "arm64" ;;
        riscv64) echo "riscv64" ;;
        *) echo "${arch}" ;;
    esac
}

# Get RPM architecture name
get_rpm_arch() {
    local arch="$1"
    case "${arch}" in
        x86_64) echo "x86_64" ;;
        i686) echo "i686" ;;
        aarch64) echo "aarch64" ;;
        riscv64) echo "riscv64" ;;
        *) echo "${arch}" ;;
    esac
}

ARCH=$(normalize_arch "${ARCH}")
DEB_ARCH=$(get_deb_arch "${ARCH}")
RPM_ARCH=$(get_rpm_arch "${ARCH}")

usage() {
    cat << EOF
Usage: $0 [OPTIONS] [FORMAT...]

Create packages for the Microkernel.

Options:
    -v, --version VERSION   Set package version (default: from Cargo.toml)
    -a, --arch ARCH         Target architecture (default: host architecture)
    -o, --output DIR        Output directory (default: ./packages)
    -b, --build DIR         Build directory with kernel artifacts (default: ./target/ARCH)
    -h, --help              Show this help message

Formats:
    tar                     Create .tar archive
    tar.gz                  Create .tar.gz archive (default if no format specified)
    deb                     Create Debian package
    rpm                     Create RPM package
    all                     Create all package formats

Examples:
    $0                      # Create tar.gz for host architecture
    $0 all                  # Create all package formats
    $0 -a aarch64 deb rpm   # Create deb and rpm for aarch64
    $0 -v 1.0.0 tar.gz      # Create tar.gz with custom version
EOF
}

# Parse arguments
FORMATS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        -v|--version)
            VERSION="$2"
            shift 2
            ;;
        -a|--arch)
            ARCH=$(normalize_arch "$2")
            DEB_ARCH=$(get_deb_arch "${ARCH}")
            RPM_ARCH=$(get_rpm_arch "${ARCH}")
            BUILD_DIR="${PROJECT_ROOT}/target/${ARCH}"
            shift 2
            ;;
        -o|--output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -b|--build)
            BUILD_DIR="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        tar|tar.gz|deb|rpm|all)
            FORMATS+=("$1")
            shift
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Default to tar.gz if no format specified
if [[ ${#FORMATS[@]} -eq 0 ]]; then
    FORMATS=("tar.gz")
fi

# Expand 'all' format
if [[ " ${FORMATS[*]} " =~ " all " ]]; then
    FORMATS=("tar" "tar.gz" "deb" "rpm")
fi

echo "=== Microkernel Packaging ==="
echo "Version: ${VERSION}"
echo "Architecture: ${ARCH}"
echo "Build directory: ${BUILD_DIR}"
echo "Output directory: ${OUTPUT_DIR}"
echo "Formats: ${FORMATS[*]}"
echo ""

# Check for kernel binary
if [[ ! -f "${BUILD_DIR}/kernel" ]]; then
    echo "Error: Kernel binary not found at ${BUILD_DIR}/kernel"
    echo "Please build the kernel first: TARGET=${ARCH}-unknown make BUILD=${BUILD_DIR}"
    exit 1
fi

# Create output directory
mkdir -p "${OUTPUT_DIR}"

# Create tarball packages
create_tarball() {
    local format="$1"
    local tarball_dir="kernel-${VERSION}-${ARCH}"
    local work_dir
    work_dir=$(mktemp -d)

    echo "Creating ${format} package..."

    mkdir -p "${work_dir}/${tarball_dir}/boot"
    mkdir -p "${work_dir}/${tarball_dir}/usr/share/doc/kernel"

    cp "${BUILD_DIR}/kernel" "${work_dir}/${tarball_dir}/boot/${ARCH}" || true
    [[ -f "${BUILD_DIR}/kernel.sym" ]] && cp "${BUILD_DIR}/kernel.sym" "${work_dir}/${tarball_dir}/boot/${ARCH}.sym"

    cat > "${work_dir}/${tarball_dir}/usr/share/doc/kernel/README" << EOF
Microkernel v${VERSION}
Architecture: ${ARCH}

Installation:
  Copy boot/${ARCH} to your boot partition
  Configure your bootloader to load this kernel

Debug Symbols:
  boot/${ARCH}.sym contains debug symbols for debugging
EOF

    cd "${work_dir}"
    case "${format}" in
        tar)
            tar -cvf "${OUTPUT_DIR}/kernel-${VERSION}-${ARCH}.tar" "${tarball_dir}"
            ;;
        tar.gz)
            tar -czvf "${OUTPUT_DIR}/kernel-${VERSION}-${ARCH}.tar.gz" "${tarball_dir}"
            ;;
    esac
    cd - > /dev/null

    rm -rf "${work_dir}"
    echo "Created: ${OUTPUT_DIR}/kernel-${VERSION}-${ARCH}.${format}"
}

# Create Debian package
create_deb() {
    echo "Creating DEB package..."

    local deb_dir
    deb_dir=$(mktemp -d)

    mkdir -p "${deb_dir}/DEBIAN"
    mkdir -p "${deb_dir}/boot"
    mkdir -p "${deb_dir}/usr/share/doc/kernel"

    cp "${BUILD_DIR}/kernel" "${deb_dir}/boot/${ARCH}" || true
    [[ -f "${BUILD_DIR}/kernel.sym" ]] && cp "${BUILD_DIR}/kernel.sym" "${deb_dir}/boot/${ARCH}.sym"

    local installed_size
    installed_size=$(du -sk "${deb_dir}" | cut -f1)

    cat > "${deb_dir}/DEBIAN/control" << EOF
Package: kernel
Version: ${VERSION}
Architecture: ${DEB_ARCH}
Maintainer: AWFixer OSS Team <oss@awfixer.me>
Installed-Size: ${installed_size}
Section: kernel
Priority: optional
Homepage: https://github.com/awfixer-platform/kernel
Description: Microkernel
 A Unix-like microkernel written in Rust, supporting multiple architectures.
 This package contains the kernel binary for ${ARCH} architecture.
EOF

    cat > "${deb_dir}/usr/share/doc/kernel/copyright" << EOF
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: kernel
Source: https://github.com/awfixer-platform/kernel

Files: *
Copyright: AWFixer Enterprises OSS
License: MIT
EOF

    cat > "${deb_dir}/usr/share/doc/kernel/changelog.Debian" << EOF
kernel (${VERSION}) unstable; urgency=medium

  * Release ${VERSION}

 -- AWFixer OSS Team <oss@awfixer.me>  $(date -R)
EOF
    gzip -9 "${deb_dir}/usr/share/doc/kernel/changelog.Debian"

    dpkg-deb --build "${deb_dir}" "${OUTPUT_DIR}/kernel_${VERSION}_${DEB_ARCH}.deb"
    rm -rf "${deb_dir}"

    echo "Created: ${OUTPUT_DIR}/kernel_${VERSION}_${DEB_ARCH}.deb"
}

# Create RPM package
create_rpm() {
    echo "Creating RPM package..."

    local rpm_dir
    rpm_dir=$(mktemp -d)

    mkdir -p "${rpm_dir}/rpmbuild"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}

    local source_dir="${rpm_dir}/kernel-${VERSION}"
    mkdir -p "${source_dir}/boot"
    cp "${BUILD_DIR}/kernel" "${source_dir}/boot/${ARCH}" || true
    [[ -f "${BUILD_DIR}/kernel.sym" ]] && cp "${BUILD_DIR}/kernel.sym" "${source_dir}/boot/${ARCH}.sym"

    tar -C "${rpm_dir}" -czvf "${rpm_dir}/rpmbuild/SOURCES/kernel-${VERSION}.tar.gz" "kernel-${VERSION}"

    cat > "${rpm_dir}/rpmbuild/SPECS/kernel.spec" << EOF
Name:           kernel
Version:        ${VERSION}
Release:        1%{?dist}
Summary:        Microkernel for ${ARCH}

License:        MIT
URL:            https://github.com/awfixer-platform/kernel
Source0:        %{name}-%{version}.tar.gz

BuildArch:      ${RPM_ARCH}

%description
A Unix-like microkernel written in Rust, supporting multiple architectures.
This package contains the kernel binary for ${ARCH} architecture.

%prep
%setup -q

%install
mkdir -p %{buildroot}/boot
install -m 644 boot/${ARCH} %{buildroot}/boot/ || true
install -m 644 boot/${ARCH}.sym %{buildroot}/boot/ || true

%files
/boot/${ARCH}
/boot/${ARCH}.sym

%changelog
* $(date "+%a %b %d %Y") AWFixer OSS Team <oss@awfixer.me> - ${VERSION}-1
- Release ${VERSION}
EOF

    rpmbuild --define "_topdir ${rpm_dir}/rpmbuild" \
             --define "debug_package %{nil}" \
             --target "${RPM_ARCH}" \
             -bb "${rpm_dir}/rpmbuild/SPECS/kernel.spec"

    find "${rpm_dir}/rpmbuild/RPMS" -name "*.rpm" -exec cp {} "${OUTPUT_DIR}/" \;
    rm -rf "${rpm_dir}"

    echo "Created: ${OUTPUT_DIR}/kernel-${VERSION}-1.${RPM_ARCH}.rpm"
}

# Build requested formats
for format in "${FORMATS[@]}"; do
    case "${format}" in
        tar|tar.gz)
            create_tarball "${format}"
            ;;
        deb)
            if command -v dpkg-deb &> /dev/null; then
                create_deb
            else
                echo "Warning: dpkg-deb not found, skipping DEB package"
            fi
            ;;
        rpm)
            if command -v rpmbuild &> /dev/null; then
                create_rpm
            else
                echo "Warning: rpmbuild not found, skipping RPM package"
            fi
            ;;
    esac
done

echo ""
echo "=== Packaging complete ==="
echo "Packages created in: ${OUTPUT_DIR}"
ls -la "${OUTPUT_DIR}/"
