#!/usr/bin/env bash

declare -r GROOT_DIR=${GROOT_HOME:-/usr/local/groot}
${GROOT_DIR}/bin/start_local_cluster.sh &
python3 ${HOME}/httpserver.py
