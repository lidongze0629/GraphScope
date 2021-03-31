#!/bin/bash

cd ~/yuxing.hyx/tmp/GraphScope/interactive_engine

object_id=$1

coordinator_id=`cat coordinator_${object_id}.pid`
frontend_id=`cat frontend_${object_id}.pid`
executor_id=`cat executor_${object_id}.pid`

sudo kill -9 $coordinator_id
sudo kill -9 $frontend_id
sudo kill -9 $executor_id