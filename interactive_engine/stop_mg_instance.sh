#!/bin/bash

cd ~/yuxing.hyx/tmp/GraphScope/interactive_engine

coordinator_id=`cat coordinator.pid`
frontend_id=`cat frontend.pid`
executor_id=`cat executor.pid`

sudo kill -9 $coordinator_id
sudo kill -9 $frontend_id
sudo kill -9 $executor_id