#!/bin/bash

ROOT_DIR=$PWD
rm -rf /home/maxgraph/logs/frontend
mkdir /home/maxgraph/logs/frontend
mkdir -p $ROOT_DIR/logs/

echo $1
object_id=$1
schema_path=$2

JAVA_OPT="-server -verbose:gc -Xloggc:./gc.log -XX:+PrintGCDetails -XX:+PrintGCDateStamps -XX:+PrintHeapAtGC -XX:+PrintTenuringDistribution -Djava.awt.headless=true -Dsun.net.client.defaultConnectTimeout=10000 -Dsun.net.client.defaultReadTimeout=30000 -XX:+DisableExplicitGC -XX:-OmitStackTraceInFastThrow -XX:+UseG1GC -XX:InitiatingHeapOccupancyPercent=75 -Dfile.encoding=UTF-8 -Dsun.jnu.encoding=UTF-8 -Dlogfilename=${ROOT_DIR}/logs/maxgraph-frontend.log -Dlogbasedir=/home/maxgraph/logs/frontend -Dlog4j.configurationFile=file:${ROOT_DIR}/build/0.0.1-SNAPSHOT/conf/log4j2.xml -classpath ${ROOT_DIR}/build/0.0.1-SNAPSHOT/conf/*:${ROOT_DIR}/build/0.0.1-SNAPSHOT/lib/*:"

inner_config=$ROOT_DIR/deploy/docker/dockerfile/frontend.vineyard.properties

sed -i "s/query.vineyard.schema.path=VINEYARD_SCHEMA_PATH/query.vineyard.schema.path=${schema_path}/g" inner_config

cd ./src/frontend/frontendservice/target/classes/

java ${JAVA_OPT} com.alibaba.maxgraph.frontendservice.FrontendServiceMain $inner_config $object_id 1>$ROOT_DIR/logs/maxgraph-frontend.out 2>$ROOT_DIR/logs/maxgraph-frontend.err 

echo $! > $ROOT_DIR/frontend.pid