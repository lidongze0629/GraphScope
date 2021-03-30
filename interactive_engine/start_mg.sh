#!/bin/bash

set -x

#bash deploy/shell/local_deploy.sh build all debug

bash ./start_coordinator.sh
sleep 10
bash ./start_frontend.sh
sleep 10
bash ./start_executor.sh

