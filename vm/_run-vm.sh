#!/bin/bash

set -ue

NAME=$1
PORT=$2
CPUS=$3

sudo taskset -c $CPUS \
	qemu-system-x86_64 \
		-cpu host,kvm=on \
		-smp sockets=1,cores=1,threads=2 \
		-m 8192 \
		-kernel $NAME.bz \
		-append "root=/dev/sda ro console=ttyS0 earlyprintk=serial" \
		-drive file=$NAME.img,format=raw \
		-net user,hostfwd=tcp::$PORT-:22 -net nic \
		-net nic -netdev tap,id=tap0 -device e1000,netdev=tap0 \
		-nographic \
		-serial mon:stdio \
		-D /dev/stdout \
		-pidfile $NAME.pid \
		--enable-kvm \

# Debug: "-s" and append+="nokaslr"
# Shared files: "-virtfs local,path=shared,mount_tag=shared,security_model=mapped-xattr"
