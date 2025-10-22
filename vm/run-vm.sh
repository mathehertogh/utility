#!/bin/bash

set -ue

NAME=$(basename `pwd`)
PORT=`cat $NAME.port`
CPUS=`cat $NAME.cpus`

sudo tmux new -s $NAME -d "./_run-vm.sh $NAME $PORT $CPUS"
sleep 1
if [ -f $NAME.pid ]; then
	echo "VM is booting now on cpus $CPUS!"
	echo "See boot terminal here:"
	echo "        sudo tmux a -t $NAME"
	echo "ssh access:"
	echo "        ssh $NAME"
else
	echo "Failed to start up VM..."
	echo "Debug via ./_run-vm.sh $NAME $PORT $CPUS"
fi
