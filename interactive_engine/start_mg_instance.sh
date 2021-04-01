#!/bin/bash

set -x

ROOT_DIR=$PWD
#wget https://archive.apache.org/dist/zookeeper/zookeeper-3.4.10/zookeeper-3.4.10.tar.gz
#tar xf zookeeper-3.4.14.tar.gz -C /usr/local/
#cd /usr/local
#ln -s zookeeper-3.4.14 zookeeper
#mkdir -p /usr/local/zookeeper/data
#mkdir -p /usr/local/zookeeper/logs
#
#/usr/local/zookeeper/bin/zkServer.sh start
#cd $ROOT_DIR

#bash deploy/shell/local_deploy.sh build all debug

### example: start_mg_instance.sh 26758028691315914 /tmp/graph_fa37JncC.json 1 /tmp/vineyard.sock.1617013756979

cd ~/yuxing.hyx/tmp/GraphScope/interactive_engine

object_id=$1
schema_path=$2
worker_num=$3
VINEYARD_IPC_SOCKET=$4

bash ./start_coordinator.sh $object_id $worker_num
sleep 10
bash ./start_frontend.sh $object_id $schema_path $worker_num
sleep 10
bash ./start_executor.sh $object_id $worker_num $VINEYARD_IPC_SOCKET

