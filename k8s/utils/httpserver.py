#! /usr/bin/env python3
# -*- coding: utf-8 -*-
#
# Copyright 2023 Alibaba Group Holding Limited.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

import json
import os
import time
import traceback
from http.server import HTTPServer
from http.server import SimpleHTTPRequestHandler
from urllib.parse import parse_qs
from urllib.parse import urlparse

import pandas as pd
import graphscope as gs
from graphscope.framework.record import EdgeRecordKey, VertexRecordKey
from gremlin_python.driver.client import Client


node_ip = os.environ.get("NODE_IP", "127.0.0.1")
grpc_port = os.environ.get("GRPC_PORT", "55556")
gremlin_port = os.environ.get("GREMLIN_PORT", "12312")
grpc_endpoint = f"{node_ip}:{grpc_port}"
gremlin_endpoint = f"{node_ip}:{gremlin_port}"


class GSHttpServer(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super(GSHttpServer, self).__init__(*args, **kwargs)

    def do_GET(self):
        try:
            if self.path.startswith("/api/v1/graph"):
                self._list_graph()
            else:
                # forbidden
                self._send_response(
                    403,
                    "Forbidden: GET request resource failed with invalid URL {0}.".format(
                        self.path
                    ),
                )
                return
        except Exception as e:
            print(e, traceback.format_exc())
            # internal server error
            self._send_response(
                200,
                "Error: {0}".format(str(e)),
                internal_error=True,
            )
        return

    def _send_response(self, code, message="", internal_error=False, **kwargs):
        if internal_error:
            success = False
        else:
            success = False if code >= 400 and code < 600 else True
        self.send_response(code)
        self.send_header("Content-type", "text/plain")
        self.end_headers()
        response_data = {"success": success, "code": code, "message": message}
        response_data.update(**kwargs)
        self.wfile.write(json.dumps(response_data).encode("utf-8"))

    def _list_graph(self):
        """GET /api/v1/graph"""
        client = get_client()
        conn = get_conn()
        graph = conn.g()
        rlt = [
            {
                "name": "crew_graph",
                "type": "GrootGraph",
                "creation_time": "",
                "schema": graph.schema().to_dict(),
                "gremlin_interface": {
                    "gremlin_endpoint": f"ws://{gremlin_endpoint}/gremlin",
                    "grpc_endpoint": grpc_endpoint,
                    "username": "",
                    "password": "",
                },
                "directed": True
            },
        ]
        self._send_response(200, "List graph successfully", data=json.dumps(rlt))


def get_client():
    graph_url = f"ws://{gremlin_endpoint}/gremlin"
    return Client(graph_url, "g")


def query(client, query_str):
    return client.submit(query_str).all().result()


def get_conn():
    return gs.conn(grpc_endpoint, gremlin_endpoint)


def loop_for_waiting_groot_ready():
    client = get_client()
    start_time = time.time()
    while True:
        time.sleep(3)
        try:
            if query(client, "g.V().count()"):
                return True
        except Exception:
            pass


def create_modern_graph_schema(graph):
    schema = graph.schema()
    schema.add_vertex_label("person").add_primary_key("id", "long").add_property(
        "name", "str"
    ).add_property("age", "int")
    schema.add_vertex_label("software").add_primary_key("id", "long").add_property(
        "name", "str"
    ).add_property("lang", "str")
    schema.add_edge_label("knows").source("person").destination("person").add_property(
        "edge_id", "long"
    ).add_property("weight", "double")
    schema.add_edge_label("created").source("person").destination(
        "software"
    ).add_property("edge_id", "long").add_property("weight", "double")
    schema.update()


def load_data_of_modern_graph(conn, graph, prefix):
    person = pd.read_csv(os.path.join(prefix, "person.csv"), sep="|")
    software = pd.read_csv(os.path.join(prefix, "software.csv"), sep="|")
    knows = pd.read_csv(os.path.join(prefix, "knows.csv"), sep="|")
    created = pd.read_csv(os.path.join(prefix, "created.csv"), sep="|")
    vertices = []
    vertices.extend(
        [
            [VertexRecordKey("person", {"id": v[0]}), {"name": v[1], "age": v[2]}]
            for v in person.itertuples(index=False)
        ]
    )
    vertices.extend(
        [
            [VertexRecordKey("software", {"id": v[0]}), {"name": v[1], "lang": v[2]}]
            for v in software.itertuples(index=False)
        ]
    )
    edges = []
    edges.extend(
        [
            [
                EdgeRecordKey(
                    "knows",
                    VertexRecordKey("person", {"id": e[0]}),
                    VertexRecordKey("person", {"id": e[1]}),
                ),
                {"weight": e[2]},
            ]
            for e in knows.itertuples(index=False)
        ]
    )
    edges.extend(
        [
            [
                EdgeRecordKey(
                    "created",
                    VertexRecordKey("person", {"id": e[0]}),
                    VertexRecordKey("software", {"id": e[1]}),
                ),
                {"weight": e[2]},
            ]
            for e in created.itertuples(index=False)
        ]
    )

    snapshot_id = graph.insert_vertices(vertices)
    snapshot_id = graph.insert_edges(edges)
    assert conn.remote_flush(snapshot_id, timeout_ms=5000)
    print("load modern graph done")


def create_modern_graph():
    client = get_client()
    conn = get_conn()
    graph = conn.g()
    create_modern_graph_schema(graph)
    load_data_of_modern_graph(conn, graph, "/tmp/datasets/modern_graph")


def run(server_class=HTTPServer, handler_class=GSHttpServer, port=9527):
    server_address = ("", port)
    httpd = server_class(server_address, handler_class)
    print("GSHttpService is listening on {0} ...".format(port))
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("KeyboardInterrupt received, stopping GSHttpService ...")
    httpd.server_close()


if __name__ == "__main__":
    loop_for_waiting_groot_ready()
    create_modern_graph()
    # http service
    run()
