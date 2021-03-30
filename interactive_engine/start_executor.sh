#!/bin/bash

export LD_LIBRARY_PATH=${LD_LIBRARY_PATH}:/apsara/alicpp/built/gcc-4.9.2/gcc-4.9.2/lib64/:/apsara/alicpp/built/gcc-4.9.2/openssl-1.0.2a/lib/:/usr/local/hadoop-2.8.4/lib/native/:/usr/local/jdk1.8.0_191/jre/lib/amd64/server/:/usr/local/hadoop-2.8.4/lib/native/:/usr/local/lib64

ROOT_DIR=$PWD

echo $1
object_id=$1
echo $2
server_id=$2
echo $3
export VINEYARD_IPC_SOCKET=$3

mkdir -p /home/maxgraph/logs/executor/logs_$object_id

export LOG_DIRS=/home/maxgraph/logs/executor/logs_$object_id

inner_config=$ROOT_DIR/deploy/docker/dockerfile/executor.vineyard.properties

server_id=1
export flag="maxgraph"$object_id"executor"
#export VINEYARD_IPC_SOCKET=/tmp/vineyard.sock.1617013756979
RUST_BACKTRACE=full $ROOT_DIR/build/0.0.1-SNAPSHOT/bin/executor --config $inner_config $flag $server_id 1>> $ROOT_DIR/logs/maxgraph-executor.out 2>> $ROOT_DIR/logs/maxgraph-executor.err  
