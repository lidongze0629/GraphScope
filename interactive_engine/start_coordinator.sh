#!/bin/bash

#set -x

ROOT_DIR=$PWD
echo $1
object_id=$1
echo $2
worker_num=$2
#rm -rf /home/maxgraph/logs/coordinator
mkdir -p /home/maxgraph/logs/coordinator/coordinator_${object_id}
#mkdir -p $ROOT_DIR/logs/

LOG_DIR=/home/maxgraph/logs/coordinator/coordinator_${object_id}

JAVA_OPT="-server -Xmx1024m -Xms1024m -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=./java.hprof -verbose:gc -Xloggc:./gc.log -XX:+PrintGCDetails -XX:+PrintGCDateStamps -XX:+PrintHeapAtGC -XX:+PrintTenuringDistribution -Djava.awt.headless=true -Dsun.net.client.defaultConnectTimeout=10000 -Dsun.net.client.defaultReadTimeout=30000 -XX:+DisableExplicitGC -XX:-OmitStackTraceInFastThrow -XX:+UseG1GC -XX:InitiatingHeapOccupancyPercent=75 -Dfile.encoding=UTF-8 -Dsun.jnu.encoding=UTF-8 -Dlogfilename=${LOG_DIR}/maxgraph-coordinator.log -Dlogbasedir=/home/maxgraph/logs/coordinator -Dlog4j.configurationFile=file:${ROOT_DIR}/build/0.0.1-SNAPSHOT/conf/log4j2.xml -classpath ${ROOT_DIR}/build/0.0.1-SNAPSHOT/conf/*:${ROOT_DIR}/build/0.0.1-SNAPSHOT/lib/*:"

rm -rf $ROOT_DIR/deploy/local/coordinator.vineyard.properties
cp $ROOT_DIR/deploy/local/coordinator.vineyard.properties.bak $ROOT_DIR/deploy/local/coordinator.vineyard.properties
sed -i "s/RESOURCE_EXECUTOR_COUNT/${worker_num}/g" $ROOT_DIR/deploy/local/coordinator.vineyard.properties
sed -i "s/PARTITION_NUM/${worker_num}/g" $ROOT_DIR/deploy/local/coordinator.vineyard.properties

inner_config=$ROOT_DIR/deploy/local/coordinator.vineyard.properties

cd $ROOT_DIR/src/coordinator/target/classes/

java ${JAVA_OPT} com.alibaba.maxgraph.coordinator.CoordinatorMain $inner_config $object_id 1>$LOG_DIR/maxgraph-coordinator.out 2>$LOG_DIR/maxgraph-coordinator.err &

echo $! > $ROOT_DIR/coordinator_${object_id}.pid
