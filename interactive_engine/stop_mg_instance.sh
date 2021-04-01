#!/bin/bash
set -x

cd ~/yuxing.hyx/tmp/GraphScope/interactive_engine

object_id=$1
worker_num=$2

coordinator_id=`cat coordinator_${object_id}.pid`
frontend_id=`cat frontend_${object_id}.pid`
sudo kill -9 $coordinator_id
sudo kill -9 $frontend_id

for worker_id in $(seq 1 $worker_num);
do
  sudo kill -9 `cat executor_${object_id}_${worker_id}.pid`
done



