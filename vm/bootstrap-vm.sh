#!/usr/bin/env bash
# 
# Create a fresh Debian VM disk.
# Derived from syzkaller's create-image.sh script (Apache 2 lincense).

set -eux

# Variables affected by options
NAME=vm
SIZE=$((8 * 1024 - 1))
CPUS=0-9999
K_SRC_DBG=false
RELEASE=stable
ARCH=$(uname -m)
PERF=false

# Display help function
display_help() {
    set +x
    echo "Usage: $0 [option...] " >&2
    echo "   -n, --name                 Name for the VM. Default: vm"
    echo "   -s, --size                 Disk size (GB). Default: 8 GB"
    echo "   -c, --cpus                 CPU affinity list. Default: all."
    echo "   -k, --k-src-dbg            Also download kernel source and debug symbols."
    echo "   -r, --release              Debian release. Default: stable"
    echo "   -a, --arch                 CPU architecture. Default: same as host"
    echo "   -p, --add-perf             Add perf support with this option enabled. Please set environment variable \$KERNEL at first"
    echo "   -h, --help                 Display help message"
    echo
    set -x
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
        -n | --name)
        NAME=$2
            shift 2
            ;;
        -s | --size)
        SIZE=$((1024 * $2 - 1))
            shift 2
            ;;
        -c | --cpus)
        CPUS=$2
            shift 2
            ;; 
        -k | --k-src-dbg)
        K_SRC_DBG=true
            shift 1
            ;;
        -a | --arch)
	    ARCH=$2
            shift 2
            ;;
        -r | --release)
	    RELEASE=$2
            shift 2
            ;;
        -p | --add-perf)
	    PERF=true
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

# Check arguments.
HOST_NAMES=`grep "Host " ~/.ssh/config | awk '{print $2}'`
if [[  $HOST_NAMES == *"$NAME"* ]]; then
    echo "ERROR: VM name '$NAME' already taken!"
    echo "See ~/.ssh/config:"
    echo `grep $NAME ~/.ssh/config -A4`
    exit 1
fi
if ! taskset -c $CPUS true; then
    echo "ERROR: Invalid CPU affinity list."
    exit 1
fi
# Double check KERNEL when PERF is enabled.
if [ $PERF = "true" ] && [ -z ${KERNEL+x} ]; then
    echo "Please set KERNEL environment variable when PERF is enabled"
    exit 1
fi

# Create a minimal Debian distribution in a directory.
DIR="$NAME"
DISK_DIR="$NAME/img"

if [ -e $DIR ]; then
    echo "Directory/file $DIR already exists! Choose different VM name with '-n NAME'."
    exit 1
fi
mkdir $DIR
mkdir $DISK_DIR

# Handle cases where qemu and Debian use different arch names.
case "$ARCH" in
    ppc64le)
        DEBARCH=ppc64el
        ;;
    aarch64)
        DEBARCH=arm64
        ;;
    arm)
        DEBARCH=armel
        ;;
    x86_64)
        DEBARCH=amd64
        ;;
    *)
        DEBARCH=$ARCH
        ;;
esac

# Foreign architecture.
FOREIGN=false
if [ $ARCH != $(uname -m) ]; then
    # i386 on an x86_64 host is exempted, as we can run i386 binaries natively
    if [ $ARCH != "i386" -o $(uname -m) != "x86_64" ]; then
        FOREIGN=true
    fi
fi
if [ $FOREIGN = "true" ]; then
    # Check for according qemu static binary
    if ! which qemu-$ARCH-static; then
        echo "Please install qemu static binary for architecture $ARCH (package 'qemu-user-static' on Debian/Ubuntu/Fedora)"
        exit 1
    fi
    # Check for according binfmt entry
    if [ ! -r /proc/sys/fs/binfmt_misc/qemu-$ARCH ]; then
        echo "binfmt entry /proc/sys/fs/binfmt_misc/qemu-$ARCH does not exist"
        exit 1
    fi
fi

# 1. debootstrap stage
PKGS=openssh-server,curl,tar,gcc,libc6-dev,time,strace,sudo,less,psmisc,selinux-utils,policycoreutils,checkpolicy,selinux-policy-default,firmware-atheros,debian-ports-archive-keyring,make,tmux,git,cmake,libgmp3-dev,python3-pycryptodome,wget,build-essential,linux-base
DEBOOTSTRAP_PARAMS="--arch=$DEBARCH --include=$PKGS --components=main,contrib,non-free,non-free-firmware $RELEASE $DISK_DIR"
if [ $FOREIGN = "true" ]; then
    DEBOOTSTRAP_PARAMS="--foreign $DEBOOTSTRAP_PARAMS"
fi

# riscv64 is hosted in the debian-ports repository
# debian-ports doesn't include non-free, so we exclude firmware-atheros
if [ $DEBARCH == "riscv64" ]; then
    DEBOOTSTRAP_PARAMS="--keyring /usr/share/keyrings/debian-ports-archive-keyring.gpg --exclude firmware-atheros $DEBOOTSTRAP_PARAMS http://deb.debian.org/debian-ports"
fi
sudo --preserve-env=http_proxy,https_proxy,ftp_proxy,no_proxy debootstrap $DEBOOTSTRAP_PARAMS

# 2. debootstrap stage: only necessary if target != host architecture
if [ $FOREIGN = "true" ]; then
    sudo cp $(which qemu-$ARCH-static) $DISK_DIR/$(which qemu-$ARCH-static)
    sudo chroot $DISK_DIR /bin/bash -c "/debootstrap/debootstrap --second-stage"
fi

# Set some defaults and enable promtless ssh to the machine for root.
sudo sed -i '/^root/ { s/:x:/::/ }' $DISK_DIR/etc/passwd
echo 'T0:23:respawn:/sbin/getty -L ttyS0 115200 vt100' | sudo tee -a $DISK_DIR/etc/inittab
printf '\nauto eth0\niface eth0 inet dhcp\n' | sudo tee -a $DISK_DIR/etc/network/interfaces
echo '/dev/root / ext4 defaults 0 0' | sudo tee -a $DISK_DIR/etc/fstab
echo 'debugfs /sys/kernel/debug debugfs defaults 0 0' | sudo tee -a $DISK_DIR/etc/fstab
echo 'securityfs /sys/kernel/security securityfs defaults 0 0' | sudo tee -a $DISK_DIR/etc/fstab
echo 'configfs /sys/kernel/config/ configfs defaults 0 0' | sudo tee -a $DISK_DIR/etc/fstab
echo 'binfmt_misc /proc/sys/fs/binfmt_misc binfmt_misc defaults 0 0' | sudo tee -a $DISK_DIR/etc/fstab
echo -en "127.0.0.1\tlocalhost\n" | sudo tee $DISK_DIR/etc/hosts
echo "nameserver 8.8.8.8" | sudo tee -a $DISK_DIR/etc/resolve.conf
echo "$NAME" | sudo tee $DISK_DIR/etc/hostname
ssh-keygen -f $DIR/$NAME.id_rsa -t rsa -N ''
sudo mkdir -p $DISK_DIR/root/.ssh/
cat $DIR/$NAME.id_rsa.pub | sudo tee $DISK_DIR/root/.ssh/authorized_keys
echo "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCcTYddSyKc3UnqV5PMRCs7KaE4sFyrl8716ZQPLA908NbKviM2dsOLbcwfydJnwZiVitQ+2vh9oRhXdKpyH3JS9Ejg3fivpCKpLZmAAYQ+JL9zS5qF2aJs2ZSlOZIsPyWtxturSyfCMDO2aPuClBKNlIMnosyMDU/bkORIefREHz2XU4KWRtjnMNaKdb6PCl0h6Zex2o4deDSuPnlfj0HDZZFEbQmlTwfL11esG/SALNErtLVbQeGylva0ZQS3GbU3+KPXnyQlf6jPCA6nYDn2+j31uvGJbspyEhdz2r++k219f71GnykC+J6ujVPZBkETTJE9D+8boBnYAJjj4gmgwVEtJmBaK/E7jc7x9m8Ydezo2I0gZJwCmHtuRiVZ4Su3mfo/KQnvfKWGo6+oDheMEc4o9E2rKDT9HoXld8b1JhPdXoZfE9j3XX1VWrsr6zx83Z5so83d0azlTa/sfSw6V5h6xcze/yKHZwnLnAKsBbHPWDzwL8qgxeZm6lQJoiU= mathe@laptop-mathe" | sudo tee -a $DISK_DIR/root/.ssh/authorized_keys

# Add perf support.
if [ $PERF = "true" ]; then
    cp -r $KERNEL $DISK_DIR/tmp/
    BASENAME=$(basename $KERNEL)
    sudo chroot $DISK_DIR /bin/bash -c "apt-get update; apt-get install -y flex bison python-dev libelf-dev libunwind8-dev libaudit-dev libslang2-dev libperl-dev binutils-dev liblzma-dev libnuma-dev"
    sudo chroot $DISK_DIR /bin/bash -c "cd /tmp/$BASENAME/tools/perf/; make"
    sudo chroot $DISK_DIR /bin/bash -c "cp /tmp/$BASENAME/tools/perf/perf /usr/bin/"
    rm -r $DISK_DIR/tmp/$BASENAME
fi

# Get the latest up-to-date Ubuntu kernel.
cp ./get-kernel.sh $DIR/get-kernel.sh
cd $DIR
GET_KERNEL_ARGS=""
if [ $K_SRC_DBG == false ]; then
    GET_KERNEL_ARGS="--binonly"
fi
./get-kernel.sh $GET_KERNEL_ARGS
KERN=$(ls | grep generic)
cd ..
sudo dpkg -i --root=$DISK_DIR $DIR/$KERN/linux-*.deb
ln -s $KERN/vmlinuz $DIR/$NAME.bz

# Build a disk image.
dd if=/dev/zero of=$DIR/$NAME.img bs=1M seek=$SIZE count=1
sudo mkfs.ext4 -F $DIR/$NAME.img
sudo mkdir -p /mnt/$DISK_DIR
sudo mount -o loop $DIR/$NAME.img /mnt/$DISK_DIR
sudo cp -a $DISK_DIR/. /mnt/$DISK_DIR/.
sudo umount /mnt/$DISK_DIR

# Delete the copy on the host file system. Leave directory for mounting.
sudo rm -rf $DISK_DIR/*

# Save the CPU affinity list.
echo "$CPUS" > $DIR/$NAME.cpus

# Select an SSH port for the VM.
TAKEN_PORTS=`grep Port ~/.ssh/config | awk '{print $2}' | sort | uniq`
for PORT in {7700..8000};
do
    if [[ $TAKEN_PORTS != *"$PORT"* ]]; then
        break;
    fi
done
echo "$PORT" > $DIR/$NAME.port

# Add VM to SSH credentials.
if [ ! -f ~/.ssh/config ]; then
    touch ~/.ssh/config
fi
cat >> ~/.ssh/config<< EOF

Host $NAME
     User root
     IdentityFile `pwd`/$DIR/$NAME.id_rsa
     Hostname localhost
     Port $PORT
EOF

# Copy over run-scripts.
cp *run-vm.sh $DIR
