/** Copyright 2020 Alibaba Group Holding Limited.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * 	http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#include <filesystem>
#include <iostream>
#include "stdlib.h"

#include "flex/engines/http_server/codegen_proxy.h"
#include "flex/engines/http_server/service/hqps_service.h"
#include "flex/engines/http_server/workdir_manipulator.h"
#include "flex/storages/rt_mutable_graph/loading_config.h"
#include "flex/utils/service_utils.h"

#include <yaml-cpp/yaml.h>
#include <boost/program_options.hpp>

#include <glog/logging.h>

namespace bpo = boost::program_options;

namespace gs {

std::string parse_codegen_dir(const bpo::variables_map& vm) {
  std::string codegen_dir;

  if (vm.count("codegen-dir") == 0) {
    LOG(INFO) << "codegen-dir is not specified";
    codegen_dir = server::CodegenProxy::DEFAULT_CODEGEN_DIR;
  } else {
    codegen_dir = vm["codegen-dir"].as<std::string>();
  }
  // clear codegen dir
  if (std::filesystem::exists(codegen_dir)) {
    LOG(INFO) << "codegen dir exists, clear directory";
    std::filesystem::remove_all(codegen_dir);
  } else {
    // create codegen_dir
    LOG(INFO) << "codegen dir not exists, create directory";
    std::filesystem::create_directory(codegen_dir);
  }
  return codegen_dir;
}

// parse from yaml
void parse_from_server_config(const std::string& server_config_path,
                              server::ServiceConfig& service_config) {
  YAML::Node config = YAML::LoadFile(server_config_path);
  auto engine_node = config["compute_engine"];
  if (engine_node) {
    auto engine_type = engine_node["type"];
    if (engine_type) {
      auto engine_type_str = engine_type.as<std::string>();
      if (engine_type_str != "hiactor" && engine_type_str != "Hiactor") {
        LOG(FATAL) << "compute_engine type should be hiactor, found: "
                   << engine_type_str;
      }
    }
    auto shard_num_node = engine_node["thread_num_per_worker"];
    if (shard_num_node) {
      service_config.shard_num = shard_num_node.as<uint32_t>();
    } else {
      LOG(INFO) << "shard_num not found, use default value "
                << service_config.shard_num;
    }
  } else {
    LOG(FATAL) << "Fail to find compute_engine configuration";
  }
  auto http_service_node = config["http_service"];
  if (http_service_node) {
    auto query_port_node = http_service_node["query_port"];
    if (query_port_node) {
      service_config.query_port = query_port_node.as<uint32_t>();
    } else {
      LOG(INFO) << "query_port not found, use default value "
                << service_config.query_port;
    }
    auto admin_port_node = http_service_node["admin_port"];
    if (admin_port_node) {
      service_config.admin_port = admin_port_node.as<uint32_t>();
    } else {
      LOG(INFO) << "admin_port not found, use default value "
                << service_config.admin_port;
    }
  } else {
    LOG(FATAL) << "Fail to find http_service configuration";
  }
  auto default_graph_node = config["default_graph"];
  std::string default_graph;
  if (default_graph_node) {
    default_graph = default_graph_node.as<std::string>();
  } else {
    LOG(WARNING) << "Fail to find default_graph configuration";
  }
  service_config.default_graph = default_graph;
  service_config.engine_config_path = server_config_path;
}

void init_codegen_proxy(const bpo::variables_map& vm,
                        const std::string& graph_schema_file,
                        const std::string& engine_config_file) {
  std::string codegen_dir = parse_codegen_dir(vm);
  std::string codegen_bin;
  if (vm.count("codegen-bin") == 0) {
    LOG(INFO) << "codegen-bin is not specified";
    codegen_bin = find_codegen_bin();
  } else {
    LOG(INFO) << "codegen-bin is specified";
    codegen_bin = vm["codegen-bin"].as<std::string>();
    if (!std::filesystem::exists(codegen_bin)) {
      LOG(FATAL) << "codegen bin not exists: " << codegen_bin;
    }
  }
  server::CodegenProxy::get().Init(codegen_dir, codegen_bin, engine_config_file,
                                   graph_schema_file);
}

void initWorkspace(const std::string workspace, int32_t thread_num,
                   const std::string& default_graph) {
  if (!std::filesystem::exists(workspace)) {
    std::filesystem::create_directory(workspace);
  }
  // Create subdirectories
  auto data_dir_path =
      workspace + "/" + server::WorkDirManipulator::DATA_DIR_NAME;
  if (!std::filesystem::exists(data_dir_path)) {
    std::filesystem::create_directory(data_dir_path);
  }

  server::WorkDirManipulator::ClearRunningGraph();

  LOG(INFO) << "Finish creating workspace directory " << workspace;
  // Get current executable path

  server::WorkDirManipulator::SetWorkspace(workspace);

  VLOG(1) << "Finish init workspace";

  auto& db = gs::GraphDB::get();
  if (default_graph.empty()) {
    LOG(WARNING) << "No Default graph is specified";
  } else {
    auto schema_path =
        server::WorkDirManipulator::GetGraphSchemaPath(default_graph);
    auto schema_res = gs::Schema::LoadFromYaml(schema_path);
    if (!schema_res.ok()) {
      LOG(FATAL) << "Fail to load graph schema from yaml file: " << schema_path;
    }
    auto data_dir_res =
        server::WorkDirManipulator::GetDataDirectory(default_graph);
    if (!data_dir_res.ok()) {
      LOG(FATAL) << "Fail to get data directory for default graph: "
                 << data_dir_res.status().error_message();
    }
    std::string data_dir = data_dir_res.value();
    if (!std::filesystem::exists(data_dir)) {
      LOG(FATAL) << "Data directory not exists: " << data_dir
                 << ", for graph: " << default_graph;
    }
    db.Close();
    if (!db.Open(schema_res.value(), data_dir, thread_num).ok()) {
      LOG(FATAL) << "Fail to load graph from data directory: " << data_dir;
    }
    LOG(INFO) << "Successfully init graph db for default graph: "
              << default_graph;
    server::WorkDirManipulator::SetRunningGraph(default_graph);
  }
}

}  // namespace gs

/**
 * The main entrance for InteractiveServer.
 */
int main(int argc, char** argv) {
  bpo::options_description desc("Usage:");
  desc.add_options()("help,h", "Display help messages")(
      "enable-admin-service,e", bpo::value<bool>()->default_value(false),
      "whether or not to start admin service")("server-config,c",
                                               bpo::value<std::string>(),
                                               "path to server config yaml")(
      "codegen-dir,d",
      bpo::value<std::string>()->default_value("/tmp/codegen/"),
      "codegen working directory")(
      "workspace,w",
      bpo::value<std::string>()->default_value("/tmp/workspace/"),
      "directory to interactive workspace")(
      "graph-config,g", bpo::value<std::string>(), "graph schema config file")(
      "data-path,a", bpo::value<std::string>(), "data directory path")(
      "open-thread-resource-pool", bpo::value<bool>()->default_value(true),
      "open thread resource pool")("worker-thread-number",
                                   bpo::value<unsigned>()->default_value(2),
                                   "worker thread number");

  setenv("TZ", "Asia/Shanghai", 1);
  tzset();

  bpo::variables_map vm;
  bpo::store(bpo::command_line_parser(argc, argv).options(desc).run(), vm);
  bpo::notify(vm);

  if (vm.count("help")) {
    std::cout << desc << std::endl;
    return 0;
  }

  //// declare vars

  bool start_admin_service;
  std::string workspace, default_graph;

  start_admin_service = vm["enable-admin-service"].as<bool>();

  if (vm.count("workspace")) {
    workspace = vm["workspace"].as<std::string>();
  }
  auto engine_config_file = vm["server-config"].as<std::string>();
  // When only starting query service.
  server::ServiceConfig service_config;
  gs::parse_from_server_config(engine_config_file, service_config);
  auto& db = gs::GraphDB::get();

  if (start_admin_service) {
    // When start admin service, we need a workspace to put all the meta data
    // and graph indices. We will initiate the query service with default graph.
    if (vm.count("graph-config") || vm.count("data-path")) {
      LOG(FATAL) << "To start admin service, graph-config and "
                    "data-path should NOT be specified";
    }

    gs::initWorkspace(workspace, service_config.shard_num,
                      service_config.default_graph);
    // Suppose the default_graph is already loaded.
    LOG(INFO) << "Finish init workspace";

    // During the running of the server, we may use some file to denote the lock
    // or running graph.
    std::atexit([]() { server::WorkDirManipulator::ClearRunningGraph(); });
    std::atexit([]() { server::WorkDirManipulator::ClearLockFile(); });

    server::HQPSService::get().init_with_admin_service(
        service_config, false, vm["open-thread-resource-pool"].as<bool>(),
        vm["worker-thread-number"].as<unsigned>());
    server::HQPSService::get().run_and_wait_for_exit();
  } else {
    LOG(INFO) << "Start query service only";
    std::string graph_schema_path, data_path;
    if (!vm.count("server-config")) {
      LOG(FATAL) << "server-config is needed";
    }

    // init graph
    if (!vm.count("graph-config")) {
      LOG(ERROR) << "graph-config is required";
      return -1;
    }
    graph_schema_path = vm["graph-config"].as<std::string>();
    if (!vm.count("data-path")) {
      LOG(ERROR) << "data-path is required";
      return -1;
    }
    data_path = vm["data-path"].as<std::string>();

    auto schema = gs::Schema::LoadFromYaml(graph_schema_path);
    if (!schema.ok()) {
      LOG(FATAL) << "Failed to load graph schema from yaml file: "
                 << graph_schema_path;
    }

    // Ths schema is loaded just to get the plugin dir and plugin list
    gs::init_codegen_proxy(vm, graph_schema_path, engine_config_file);
    db.Close();
    auto load_res =
        db.Open(schema.value(), data_path, service_config.shard_num);
    if (!load_res.ok()) {
      LOG(FATAL) << "Failed to load graph from data directory: "
                 << load_res.status().error_message();
    }

    server::HQPSService::get().init_without_admin_service(
        service_config, false, vm["open-thread-resource-pool"].as<bool>(),
        vm["worker-thread-number"].as<unsigned>());
    server::HQPSService::get().run_and_wait_for_exit();
  }

  return 0;
}
