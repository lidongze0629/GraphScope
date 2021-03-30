#!/bin/bash

ROOT_DIR=$PWD
rm -rf /home/maxgraph/logs/coordinator
mkdir /home/maxgraph/logs/coordinator
mkdir -p $ROOT_DIR/logs/

JAVA_OPT="-server -Xmx1024m -Xms1024m -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=./java.hprof -verbose:gc -Xloggc:./gc.log -XX:+PrintGCDetails -XX:+PrintGCDateStamps -XX:+PrintHeapAtGC -XX:+PrintTenuringDistribution -Djava.awt.headless=true -Dsun.net.client.defaultConnectTimeout=10000 -Dsun.net.client.defaultReadTimeout=30000 -XX:+DisableExplicitGC -XX:-OmitStackTraceInFastThrow -XX:+UseG1GC -XX:InitiatingHeapOccupancyPercent=75 -Dfile.encoding=UTF-8 -Dsun.jnu.encoding=UTF-8 -Dlogfilename=${ROOT_DIR}/logs/maxgraph-coordinator.log -Dlogbasedir=/home/maxgraph/logs/coordinator -Dlog4j.configurationFile=file:${ROOT_DIR}/build/0.0.1-SNAPSHOT/conf/log4j2.xml -classpath ${ROOT_DIR}/build/0.0.1-SNAPSHOT/conf/*:${ROOT_DIR}/build/0.0.1-SNAPSHOT/lib/*:"

inner_config=$ROOT_DIR/deploy/docker/dockerfile/coordinator.application.properties

cd $ROOT_DIR/src/coordinator/target/classes/

java ${JAVA_OPT} com.alibaba.maxgraph.coordinator.CoordinatorMain $inner_config $object_id 1>$ROOT_DIR/logs/maxgraph-coordinator.out 2>$ROOT_DIR/logs/maxgraph-coordinator.err 
