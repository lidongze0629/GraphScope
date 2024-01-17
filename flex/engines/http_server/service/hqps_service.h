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
#ifndef ENGINES_HTTP_SERVER_HQPS_SERVICE_H_
#define ENGINES_HTTP_SERVER_HQPS_SERVICE_H_

#include <string>

#include "flex/engines/graph_db/database/graph_db.h"
#include "flex/engines/http_server/actor_system.h"
#include "flex/engines/http_server/handler/admin_http_handler.h"
#include "flex/engines/http_server/handler/hqps_http_handler.h"
#include "flex/utils/result.h"
#include "flex/utils/service_utils.h"

namespace server {

/* Stored service configuration, read from engine_config.yaml
 */
struct ServiceConfig {
  static constexpr const uint32_t DEFAULT_SHARD_NUM = 1;
  static constexpr const uint32_t DEFAULT_QUERY_PORT = 10000;
  static constexpr const uint32_t DEFAULT_ADMIN_PORT = 7777;
  static constexpr const uint32_t DEFAULT_BOLT_PORT = 7687;

  // Those has default value
  uint32_t bolt_port;
  uint32_t admin_port;
  uint32_t query_port;
  uint32_t shard_num;

  // Those has not default value
  std::string default_graph;
  std::string engine_config_path;  // used for codegen.
  ServiceConfig();
};

class HQPSService {
 public:
  static const std::string DEFAULT_GRAPH_NAME;
  static HQPSService& get();
  ~HQPSService();

  // only start the query service.
  void init_with_admin_service(const ServiceConfig& service_config,
                               bool dpdk_mode, bool enable_thread_resource_pool,
                               unsigned external_thread_num);

  void init_without_admin_service(const ServiceConfig& service_config,
                                  bool dpdk_mode,
                                  bool enable_thread_resource_pool,
                                  unsigned external_thread_num);

  bool is_initialized() const;

  bool is_running() const;

  uint16_t get_query_port() const;

  std::string get_engine_config_path() const;

  const ServiceConfig& get_service_config() const;

  gs::Result<seastar::sstring> service_status();

  void run_and_wait_for_exit();

  void set_exit_state();

  // Actually stop the actors, the service is still on, but returns error code
  // for each request.
  seastar::future<> stop_query_actors();

  // Actually create new actors with a different scope_id,
  // Because we don't know whether the previous scope_id can be reused.
  void start_query_actors();

 private:
  HQPSService() = default;

 private:
  std::unique_ptr<actor_system> actor_sys_;
  std::unique_ptr<admin_http_handler> admin_hdl_;
  std::unique_ptr<hqps_http_handler> query_hdl_;
  std::atomic<bool> running_{false};
  std::atomic<bool> initialized_{false};
  std::mutex mtx_;

  ServiceConfig service_config_;
};

}  // namespace server

#endif  // ENGINES_HTTP_SERVER_HQPS_SERVICE_H_
