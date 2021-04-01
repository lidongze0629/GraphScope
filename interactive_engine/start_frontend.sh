#!/bin/bash
ROOT_DIR=$PWD

echo $1
object_id=$1
schema_path=$2
worker_num=$3

mkdir -p mkdir /home/maxgraph/logs/frontend/frontend_${object_id}

LOG_DIR=/home/maxgraph/logs/frontend/frontend_${object_id}


JAVA_OPT="-server -verbose:gc -Xloggc:./gc.log -XX:+PrintGCDetails -XX:+PrintGCDateStamps -XX:+PrintHeapAtGC -XX:+PrintTenuringDistribution -Djava.awt.headless=true -Dsun.net.client.defaultConnectTimeout=10000 -Dsun.net.client.defaultReadTimeout=30000 -XX:+DisableExplicitGC -XX:-OmitStackTraceInFastThrow -XX:+UseG1GC -XX:InitiatingHeapOccupancyPercent=75 -Dfile.encoding=UTF-8 -Dsun.jnu.encoding=UTF-8 -Dlogfilename=${LOG_DIR}/maxgraph-frontend.log -Dlogbasedir=/home/maxgraph/logs/frontend -Dlog4j.configurationFile=file:${ROOT_DIR}/build/0.0.1-SNAPSHOT/conf/log4j2.xml -classpath ${ROOT_DIR}/build/0.0.1-SNAPSHOT/conf/*:${ROOT_DIR}/build/0.0.1-SNAPSHOT/lib/*:"

#inner_config=$ROOT_DIR/deploy/docker/dockerfile/frontend.vineyard.properties

REPLACE_SCHEMA_PATH=`echo ${schema_path//\//\\\/}`

rm -rf $ROOT_DIR/deploy/local/frontend.vineyard.properties
cp $ROOT_DIR/deploy/local/frontend.vineyard.properties.bak $ROOT_DIR/deploy/local/frontend.vineyard.properties
sed -i "s/VINEYARD_SCHEMA_PATH/${REPLACE_SCHEMA_PATH}/g" $ROOT_DIR/deploy/local/frontend.vineyard.properties
sed -i "s/RESOURCE_EXECUTOR_COUNT/${worker_num}/g" $ROOT_DIR/deploy/local/frontend.vineyard.properties
sed -i "s/PARTITION_NUM/${worker_num}/g" $ROOT_DIR/deploy/local/frontend.vineyard.properties

inner_config=$ROOT_DIR/deploy/local/frontend.vineyard.properties

cd ./src/frontend/frontendservice/target/classes/

java ${JAVA_OPT} com.alibaba.maxgraph.frontendservice.FrontendServiceMain $inner_config $object_id 1>$LOG_DIR/maxgraph-frontend.out 2>$LOG_DIR/maxgraph-frontend.err &

echo "FRONTEND_PORT:127.0.0.1:8182"

echo $! > $ROOT_DIR/frontend_${object_id}.pid