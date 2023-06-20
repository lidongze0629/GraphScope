ARG REGISTRY=registry.cn-hongkong.aliyuncs.com
FROM $REGISTRY/graphscope/graphscope-store:0.22.0-arm64

COPY --chown=graphscope:graphscope ./k8s/utils/start_httpserver.sh /home/graphscope/start_httpserver.sh
COPY --chown=graphscope:graphscope ./k8s/utils/httpserver.py /home/graphscope/httpserver.py
COPY --chown=graphscope:graphscope ./interactive_engine/tests/src/main/resources/modern_graph /tmp/datasets/modern_graph

RUN sudo apt-get update -y && \
    sudo apt-get install -y vim python3-pip && \
    sudo apt-get clean -y && \
    sudo rm -rf /var/lib/apt/lists/*

RUN python3 -m pip install graphscope-client

ENTRYPOINT ["/home/graphscope/start_httpserver.sh"]
