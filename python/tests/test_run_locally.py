#!/usr/bin/env python3
# -*- coding: utf-8 -*-
#
# Copyright 2020 Alibaba Group Holding Limited. All Rights Reserved.
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

import importlib
import logging
import os
import random
import string
import sys

import numpy as np
import pytest

import graphscope
from graphscope.config import GSConfig as gs_config
from graphscope.dataset.ldbc import load_ldbc
from graphscope.dataset.modern_graph import load_modern_graph
from graphscope.dataset.ogbn_mag import load_ogbn_mag
from graphscope.framework.graph import Graph
from graphscope.framework.loader import Loader
from graphscope.learning.examples import GCN
from graphscope.learning.graphlearn.python.model.tf.optimizer import get_tf_optimizer
from graphscope.learning.graphlearn.python.model.tf.trainer import LocalTFTrainer


graphscope.set_option(show_log=True)
graphscope.set_option(initializing_interactive_engine=False)

test_repo_dir = os.path.expandvars("${GS_TEST_DIR}")


def train(config, graph):
    def model_fn():
        return GCN(
            graph,
            config["class_num"],
            config["features_num"],
            config["batch_size"],
            val_batch_size=config["val_batch_size"],
            test_batch_size=config["test_batch_size"],
            categorical_attrs_desc=config["categorical_attrs_desc"],
            hidden_dim=config["hidden_dim"],
            in_drop_rate=config["in_drop_rate"],
            neighs_num=config["neighs_num"],
            hops_num=config["hops_num"],
            node_type=config["node_type"],
            edge_type=config["edge_type"],
            full_graph_mode=config["full_graph_mode"],
        )

    trainer = LocalTFTrainer(
        model_fn,
        epoch=config["epoch"],
        optimizer=get_tf_optimizer(
            config["learning_algo"], config["learning_rate"], config["weight_decay"]
        ),
    )
    trainer.train_and_evaluate()


@pytest.fixture
def sess():
    graphscope.set_option(show_log=True)
    graphscope.set_option(initializing_interactive_engine=False)
    s = graphscope.session(cluster_type="hosts", num_workers=2)
    yield s
    s.close()


@pytest.fixture
def ogbn_mag_small():
    return "{}/ogbn_mag_small".format(test_repo_dir)


def demo(sess, ogbn_mag_small):
    graph = load_ogbn_mag(sess, ogbn_mag_small)

    # Interactive engine
    interactive = sess.gremlin(graph)
    papers = interactive.execute(
        "g.V().has('author', 'id', 2).out('writes').where(__.in('writes').has('id', 4307)).count()"
    ).one()

    sub_graph = interactive.subgraph(
        "g.V().has('year', inside(2014, 2020)).outE('cites')"
    )

    simple_g = sub_graph.project(vertices={"paper": []}, edges={"cites": []})

    ret1 = graphscope.k_core(simple_g, k=5)
    ret2 = graphscope.triangles(simple_g)

    sub_graph = sub_graph.add_column(ret1, {"kcore": "r"})
    sub_graph = sub_graph.add_column(ret2, {"tc": "r"})

    # GLE on ogbn_mag_small graph
    paper_features = []
    for i in range(128):
        paper_features.append("feat_" + str(i))
    paper_features.append("kcore")
    paper_features.append("tc")
    lg = sess.learning(
        sub_graph,
        nodes=[("paper", paper_features)],
        edges=[("paper", "cites", "paper")],
        gen_labels=[
            ("train", "paper", 100, (0, 75)),
            ("val", "paper", 100, (75, 85)),
            ("test", "paper", 100, (85, 100)),
        ],
    )

    # hyperparameters config.
    config = {
        "class_num": 349,  # output dimension
        "features_num": 130,  # 128 dimension + kcore + triangle count
        "batch_size": 500,
        "val_batch_size": 100,
        "test_batch_size": 100,
        "categorical_attrs_desc": "",
        "hidden_dim": 256,
        "in_drop_rate": 0.5,
        "hops_num": 2,
        "neighs_num": [5, 10],
        "full_graph_mode": False,
        "agg_type": "gcn",  # mean, sum
        "learning_algo": "adam",
        "learning_rate": 0.01,
        "weight_decay": 0.0005,
        "epoch": 5,
        "node_type": "paper",
        "edge_type": "cites",
    }

    train(config, lg)


def test_demo(ogbn_mag_small):
    sess = graphscope.session(cluster_type="hosts", num_workers=2)
    demo(sess, ogbn_mag_small)
    sess.close()


def test_multiple_session(ogbn_mag_small):
    sess1 = graphscope.session(cluster_type="hosts", num_workers=2)
    assert sess1.info["status"] == "active"

    sess2 = graphscope.session(cluster_type="hosts", num_workers=2)
    assert sess2.info["status"] == "active"

    demo(sess2, ogbn_mag_small)

    sess1.close()
    sess2.close()
