#!/bin/bash

set -x


ROOT_DIR=$PWD
wget https://archive.apache.org/dist/zookeeper/zookeeper-3.4.10/zookeeper-3.4.10.tar.gz
tar xf zookeeper-3.4.14.tar.gz -C /usr/local/
cd /usr/local
ln -s zookeeper-3.4.14 zookeeper
mkdir -p /usr/local/zookeeper/data
mkdir -p /usr/local/zookeeper/logs

/usr/local/zookeeper/bin/zkServer.sh start

cd $ROOT_DIR

bash deploy/shell/local_deploy.sh build all debug

bash ./start_coordinator.sh
sleep 10
bash ./start_frontend.sh
sleep 10
bash ./start_executor.sh

