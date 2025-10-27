#!/bin/bash
set -e

LINUX_VERSION=
LINUX_FLAVOUR=generic
BINONLY=false

# Display help function
display_help() {
    echo "Usage: $0 [option...] " >&2
    echo "   -v, --version            Linux version (Ubuntu style). Default: latest stable release"
    echo "   -f, --flavour            Linux flavour (Ubuntu style). Default: generic"
    echo "   -b, --binonly            Only get binaries and headers (no source nor debug symbols)."
    echo "   -h, --help               Display help message"
    echo
}

while true; do
    if [ $# -eq 0 ];then
    echo $#
    break
    fi
    case "$1" in
        -h | --help)
            display_help
            exit 0
            ;;
        -v | --version)
        LINUX_VERSION=$2
            shift 2
            ;;
        -f | --flavour)
        LINUX_FLAVOUR=$2
            shift 2
            ;;
        -b | --binonly)
        BINONLY=true
            shift 1
            ;;
        -*)
            echo "Error: Unknown option: $1" >&2
            exit 1
            ;;
        *)  # No more options
            break
            ;;
    esac
done

if [ -z "$LINUX_VERSION" ]; then
    # Lookup the latest up-to-date kernel of that flavour.
    apt download linux-image-$LINUX_FLAVOUR
    DEBFILE=$(basename linux-image-$LINUX_FLAVOUR*.deb)
    LINUX_VERSION_FULL=$(echo $DEBFILE | cut -d "_" -f 2)
    LINUX_VERSION=$(echo $LINUX_VERSION_FULL | cut -d "." -f 4 --complement)
    rm $DEBFILE
fi

LINUX_NAME=${LINUX_VERSION}-${LINUX_FLAVOUR}

if [ -e $LINUX_NAME ]; then
    echo "ERROR: $LINUX_NAME already exists."
    exit 1
fi

DDEB_FILE="/etc/apt/sources.list.d/ddebs.list"

if [ ! -f $DDEB_FILE ]; then
    echo "Setting up debug symbol package source.."
    sudo apt install ubuntu-dbgsym-keyring
    echo "deb http://ddebs.ubuntu.com $(lsb_release -cs) main restricted universe multiverse
deb http://ddebs.ubuntu.com $(lsb_release -cs)-updates main restricted universe multiverse
deb http://ddebs.ubuntu.com $(lsb_release -cs)-proposed main restricted universe multiverse" | \
    sudo tee -a /etc/apt/sources.list.d/ddebs.list
    sudo apt update
fi

echo "Downloading Ubuntu's $LINUX_NAME kernel into directory $LINUX_NAME..."
mkdir $LINUX_NAME
cd $LINUX_NAME

# Download linux image
apt download linux-image-${LINUX_NAME}

# Extract vmlinuz and vmlinux
dpkg-deb --fsys-tarfile linux-image-*.deb | tar Ox --wildcards  './boot/vmlinuz-*' > vmlinuz
/usr/src/linux-headers-$(uname -r)/scripts/extract-vmlinux vmlinuz > vmlinux

# Download linux headers
apt download linux-headers-${LINUX_VERSION}
apt download linux-headers-${LINUX_NAME}

# Extract config
dpkg-deb --fsys-tarfile linux-headers-${LINUX_NAME}*.deb | tar Ox --wildcards './usr/src/*/.config' > config

# Download linux modules
apt download linux-modules-${LINUX_NAME}

if [ ! $BINONLY ]; then
    # Download linux debug image
    apt download linux-image-unsigned-${LINUX_NAME}-dbgsym

    # Extract vmlinux-dbg
    dpkg-deb --fsys-tarfile linux-image-unsigned-*.ddeb  | tar Ox --wildcards  './usr/lib/debug/boot/vmlinux-*' > vmlinux-dbg

    # Download source code
    if [ -z "$LINUX_VERSION_FULL" ]; then
        LINUX_VERSION_FULL=$(echo linux-headers-${LINUX_NAME}*.deb | cut -d "_" -f 2)
    fi
    git clone --depth 1 --branch Ubuntu-${LINUX_VERSION_FULL} git://git.launchpad.net/~ubuntu-kernel/ubuntu/+source/linux/+git/`lsb_release -c -s` src
fi

cd ..
