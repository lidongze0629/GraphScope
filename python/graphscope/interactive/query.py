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

import datetime
import logging
import random
from concurrent.futures import ThreadPoolExecutor
from copy import deepcopy
from enum import Enum

from gremlin_python.driver.client import Client
from gremlin_python.driver.driver_remote_connection import DriverRemoteConnection
from gremlin_python.process.anonymous_traversal import traversal

from graphscope.config import GSConfig as gs_config
from graphscope.framework.dag import DAGNode
from graphscope.framework.dag_utils import close_interactive_query
from graphscope.framework.dag_utils import create_interactive_query
from graphscope.framework.dag_utils import fetch_gremlin_result
from graphscope.framework.dag_utils import gremlin_query
from graphscope.framework.dag_utils import gremlin_to_subgraph
from graphscope.framework.loader import Loader

logger = logging.getLogger("graphscope")


class InteractiveQueryStatus(Enum):
    """A enumeration class of current status of InteractiveQuery"""

    Initializing = 0
    Running = 1
    Failed = 2
    Closed = 3


class ResultSetDAGNode(DAGNode):
    """A class represents a result set node in a DAG.

    This is a wrapper for :class:`gremlin_python.driver.resultset.ResultSet`,
    and you can get the result by :method:`one()` or :method:`all()`.
    """

    def __init__(self, dag_node, op):
        self._session = dag_node.session
        self._op = op
        # add op to dag
        self._session.dag.add_op(self._op)

    def one(self):
        """See details in :method:`gremlin_python.driver.resultset.ResultSet.one`"""
        # avoid circular import
        from graphscope.framework.context import ResultDAGNode

        op = fetch_gremlin_result(self, "one")
        return ResultDAGNode(self, op)

    def all(self):
        """See details in :method:`gremlin_python.driver.resultset.ResultSet.all`

        Note that this method is equal to `ResultSet.all().result()`
        """
        # avoid circular import
        from graphscope.framework.context import ResultDAGNode

        op = fetch_gremlin_result(self, "all")
        return ResultDAGNode(self, op)


class ResultSet(object):
    def __init__(self, result_set_node):
        self._result_set_node = result_set_node
        self._session = self._result_set_node.session
        # copy and set op evaluated
        self._result_set_node.op = deepcopy(self._result_set_node.op)
        self._result_set_node.evaluated = True
        self._session.dat.add_op(self._interactive_query_node.op)

    def one(self):
        return self._session._wrapper(self._result_set_node.one())

    def all(self):
        return self._session._wrapper(self._result_set_node.all())


class InteractiveQueryDAGNode(DAGNode):
    """A class represents an interactive query node in a DAG.

    The following example demonstrates its usage:

    .. code:: python

        >>> # lazy node
        >>> import graphscope as gs
        >>> sess = gs.session(mode="lazy")
        >>> g = sess.g() # <graphscope.framework.graph.GraphDAGNode object>
        >>> ineractive = sess.gremlin(g)
        >>> print(ineractive) # <graphscope.interactive.query.InteractiveQueryDAGNode object>
        >>> rs = ineractive.execute("g.V()")
        >>> print(rs) # <graphscope.ineractive.query.ResultSetDAGNode object>
        >>> r = rs.one()
        >>> print(r) # <graphscope.framework.context.ResultDAGNode>
        >>> print(sess.run(r))
        [2]
        >>> subgraph = ineractive.subgraph("xxx")
        >>> print(subgraph) # <graphscope.framework.graph.GraphDAGNode object>
        >>> g2 = sess.run(subgraph)
        >>> print(g2) # <graphscope.framework.graph.Graph object>
    """

    def __init__(self, session, graph, engine_params=None):
        """
        Args:
            session (:class:`Session`): instance of GraphScope session.
            graph (:class:`graphscope.framework.graph.GraphDAGNode`):
                A graph instance that the gremlin query on.
            engine_params (dict, optional):
                Configuration to startup the interactive engine. See detail in:
                `interactive_engine/deploy/docker/dockerfile/executor.vineyard.properties`
        """
        self._session = session
        self._graph = graph
        self._engine_params = engine_params
        self._op = create_interactive_query(
            self._graph,
            self._engine_params,
            gs_config.k8s_gie_gremlin_server_cpu,
            gs_config.k8s_gie_gremlin_server_mem,
        )
        # add op to dag
        self._session.dag.add_op(self._op)

    def execute(self, query, request_options=None):
        """Execute gremlin querying scripts.

        Args:
            query (str): Scripts that written in gremlin quering language.
            request_options (dict, optional): Gremlin request options. format:
            {
                "engine": "gae"
            }

        Returns:
            :class:`graphscope.framework.context.ResultDAGNode`:
                A result holds the gremlin result, evaluated in eager mode.
        """
        op = gremlin_query(self, query, request_options)
        return ResultSetDAGNode(self, op)

    def subgraph(self, gremlin_script, request_options=None):
        """Create a subgraph, which input is the result of the execution of `gremlin_script`.

        Any gremlin script that output a set of edges can be used to contruct a subgraph.

        Args:
            gremlin_script (str): Gremlin script to be executed.
            request_options (dict, optional): Gremlin request options. format:
            {
                "engine": "gae"
            }

        Returns:
            :class:`graphscope.framework.graph.GraphDAGNode`:
                A new graph constructed by the gremlin output, that also stored in vineyard.
        """
        # avoid circular import
        from graphscope.framework.graph import GraphDAGNode

        op = gremlin_to_subgraph(
            self,
            gremlin_script=gremlin_script,
            request_options=request_options,
            oid_type=self._graph._oid_type,
        )
        return GraphDAGNode(self._session, op)

    def close(self):
        """Close interactive engine and release the resources.

        Returns:
            :class:`graphscope.interactive.query.ClosedInteractiveQuery`
                Evaluated in eager mode.
        """
        op = close_interactive_query(self)
        return ClosedInteractiveQuery(self._session, op)


class InteractiveQuery(object):
    """`InteractiveQuery` class, is a simple wrapper around
    `Gremlin-Python <https://pypi.org/project/gremlinpython/>`_,
    which implements Gremlin within the Python language.
    It also can expose gremlin endpoint which can be used by
    any other standard gremlin console, with the method `graph_url()`.

    It also has a method called `subgraph` which can extract some fragments
    from origin graph, produce a new, smaller but concise graph stored in vineyard,
    which lifetime is independent from the origin graph.

    User can either use `execute()` to submit a script, or use `traversal_source()`
    to get a `GraphTraversalSource` for further traversal.
    """

    def __init__(self, interactive_query_node=None, frontend_endpoint=None):
        """Construct a :class:`InteractiveQuery` object."""

        self._status = InteractiveQueryStatus.Initializing
        self._graph_url = None
        # interactive_query_node is None used for create a interative query
        # implicitly in eager mode
        if interactive_query_node is not None:
            self._interactive_query_node = interactive_query_node
            self._session = self._interactive_query_node.session
            # copy and set op evaluated
            self._interactive_query_node.op = deepcopy(self._interactive_query_node.op)
            self._interactive_query_node.evaluated = True
            self._session.dag.add_op(self._interactive_query_node.op)
        if frontend_endpoint is not None:
            self._graph_url = "ws://{0}/gremlin".format(frontend_endpoint)
            self._client = Client(self._graph_url, "g")

    @property
    def graph_url(self):
        """The gremlin graph url can be used with any standard gremlin console, e.g., tinkerpop."""
        return self._graph_url

    @property
    def status(self):
        return self._status

    @status.setter
    def status(self, value):
        self._status = value

    @property
    def error_msg(self):
        return self._error_msg

    @error_msg.setter
    def error_msg(self, error_msg):
        self._error_msg = error_msg

    def closed(self):
        """Return if the current instance is closed."""
        return self._status == InteractiveQueryStatus.Closed

    def subgraph(self, gremlin_script):
        """Create a subgraph, which input is the result of the execution of `gremlin_script`.
        Any gremlin script that will output a set of edges can be used to contruct a subgraph.
        Args:
            gremlin_script (str): gremlin script to be executed

        Raises:
            RuntimeError: If the interactive instance is not running.

        Returns:
            :class:`Graph`: constructed subgraph. which is also stored in vineyard.
        """
        if self._status != InteractiveQueryStatus.Running:
            raise RuntimeError(
                "Interactive query is unavailable with %s status.", str(self._status)
            )

        now_time = datetime.datetime.now().strftime("%Y%m%d%H%M%S")
        random_num = random.randint(0, 10000000)
        graph_name = "%s_%s" % (str(now_time), str(random_num))

        # create graph handle by name
        self._client.submit(
            "g.createGraph('%s').with('graphType', 'vineyard')" % graph_name
        ).all().result()

        # start a thread to launch the graph
        def load_subgraph(name):
            import vineyard

            graph = self._session.load_from(
                vertices=[Loader(vineyard.ObjectName("__%s_vertex_stream" % name))],
                edges=[Loader(vineyard.ObjectName("__%s_edge_stream" % name))],
                generate_eid=False,
            )
            logger.info("subgraph has been loaded")
            return graph

        pool = ThreadPoolExecutor()
        subgraph_task = pool.submit(load_subgraph, (graph_name,))

        # add subgraph vertices and edges
        subgraph_script = "%s.subgraph('%s').outputVineyard('%s')" % (
            gremlin_script,
            graph_name,
            graph_name,
        )
        self._client.submit(subgraph_script).all().result()

        return subgraph_task.result()

    def execute(self, query):
        """Execute gremlin querying scripts.
        Behind the scene, it uses `gremlinpython` to send the query.

        Args:
            query (str): Scripts that written in gremlin quering language.

        Raises:
            RuntimeError: If the interactive script is not running.

        Returns:
            execution results
        """
        if self._status != InteractiveQueryStatus.Running:
            raise RuntimeError(
                "Interactive query is unavailable with %s status.", str(self._status)
            )
        return self._client.submit(query)

    def traversal_source(self):
        """Create a GraphTraversalSource and return.
        Once `g` has been created using a connection, we can start to write
        Gremlin traversals to query the remote graph.

        Raises:
            RuntimeError: If the interactive script is not running.

        Examples:

            .. code:: python

                sess = graphscope.session()
                graph = load_modern_graph(sess, modern_graph_data_dir)
                interactive = sess.gremlin(graph)
                g = interactive.traversal_source()
                print(g.V().both()[1:3].toList())
                print(g.V().both().name.toList())

        Returns:
            `GraphTraversalSource`
        """
        if self._status != InteractiveQueryStatus.Running:
            raise RuntimeError(
                "Interactive query is unavailable with %s status.", str(self._status)
            )
        return traversal().withRemote(DriverRemoteConnection(self._graph_url, "g"))

    def close(self):
        """Close interactive instance and release resources"""
        if not self.closed():
            self._session._close_interactive_instance(self)
            self._status = InteractiveQueryStatus.Closed


class ClosedInteractiveQuery(DAGNode):
    """Closed interactive query node in a DAG."""

    def __init__(self, session, op):
        self._session = session
        self._op = op
        # add op to dag
        self._session.dag.add_op(self._op)
