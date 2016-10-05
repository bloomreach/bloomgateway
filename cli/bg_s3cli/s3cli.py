#!/usr/bin/env python
#
# Copyright 2016 BloomReach, Inc.
# Copyright 2016 Ronak Kothari <ronak.kothari@gmail.com>.
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
"""
This is the commnad line interface for updating rules to s3 for bloomgateway

exampels of each commands, and requires args for that command.
1. Create Cluster : initilized the cluster with given name.
usage : python s3cli.py --cmd create --cluster_id test.fe --data '{
  "service_port" : <port number>,
  "ping_port" : <status check prot>,
  "nodes" : ["service1.net", "service2.net"],
  "upstream_server" : "<upstream host:port>",
  "nginx_conf_template"  : "../template/nginx.conf.bg.template"
}'

2. Update Module Confings
2.1 Update access control rule : User can adds new rule or remove the old rule. To add new rule,
the value of "method" is "add", and for removing, use "remove" as value.
usage : python s3cli.py --cmd update --cluster_id test.fe --type module --module access --data '{
  "method"  : "add",
  "rule_type" : "param",
  "rule_uri"  : "/api/v1/core/",
  "rule_key"  : "account_id",
  "rule_value"  : "1234",
  "rule_access" : "deny"
}'

2.2 Update Ratelimiter control rule : The structure is same access control rules. It needs an extra
argument called "rule_threshold".
usage : python s3cli.py --cmd update --cluster_id test.fe --type module --module ratelimiter --data '{
  "method"  : "add",
  "rule_type" : "param",
  "rule_uri"  : "/api/v1/core/",
  "rule_key"  : "account_id",
  "rule_value"  : "1234",
  "rule_threshold"  : "3"
}'

2.3 Update Router rule : This module allows A/B testing scenario. It helps to redirect request based
on matched param or regex. User can configre, different end-points if it matches the pattern for redirecting
request.
usage : python s3cli.py --cmd update --cluster_id test.fe --type module --module router --data '{
  "method"  : "add",
  "rule_type" : "param",
  "rule_uri"  : "/api/v1/core/",
  "rule_key"  : "account_id",
  "rule_value"  : "1234",
  "rule_endpoint" : "localhost:8080"
}'

2.4 Update Fallback Rule : This module retry the request to given host and port on 5xx error scenario.
This commands helps to configure rules for API endpoint.
usage : python s3cli.py --cmd update --cluster_id test.fe --type module --module fallback --data '{
  "method" : "add",
  "rule_uri"  : "/api/v1/core/",
  "rule_errors" : ["500","502","503","504"],
  "rule_fallbacks"  : ["localhost:80", "service.fallback:80"],
  "rule_params"  : { "is_fallback" : "true" , "fallback_from" : "service1.net" },
  "rule_headers"  : { }
}'

3. Update nginx conf
This commands update the nginx conf for a given cluster.
usage : python s3cli.py --cmd update --cluster_id test.fe --type conf --data '{
  "service_port" : <service port>,
  "ping_port" : <status port>,
  "upstream_server" : "<upstream host:port>",
  "nginx_conf_template"  : "../template/nginx.conf.bg.template"
}'

4. Delete Cluster : Delete the complete cluster.
usage : python s3cli.py --cmd delete --cluster_id test.fe

"""

import argparse
import json
import sys

from conf import s3
from scripts.s3Persistence import S3Persistence
from scripts.utils import utils
from scripts.utils import module_rule_utils

def bootstrap_cluster(cluster_id, data):
  """
  Creates a new cluster with given cluster_id and data
  """
  print "executing bootstrap_cluster"
  assert cluster_id
  assert data
  assert data["service_port"]
  assert data["ping_port"]
  assert data["nodes"]
  assert data["upstream_server"]

  if not data["nginx_conf_template"]:
    data["nginx_conf_template"] = "../template/nginx.conf.bg.template"

  base_path = s3.get_cluster_info_base_path()
  persistence = S3Persistence(cluster_id, data["service_port"], data["ping_port"], base_path, data["nodes"], data["upstream_server"])
  persistence.bootstrapCluster(data["nginx_conf_template"])

def delete_cluster(cluster_id):
  """
  Delete existing cluster with name - cluster_id
  """
  print "executing delete_cluster"
  assert cluster_id
  base_path = s3.get_cluster_info_base_path()
  persistence = S3Persistence(cluster_id, None, None, base_path, None, None)
  (response, msg) = persistence.deleteCluster()
  print msg

def update_nginx_conf(cluster_id, data):
  """
  Updates the nginx.conf of a given cluster.

  Pl. use nginx.conf.bg.template
  with your specific configs. Removal of default configs will lead to
  un-avaibility of bloomgateway service.
  """
  print "executing update_nginx_conf"
  assert cluster_id
  assert data
  assert data["service_port"]
  assert data["ping_port"]
  assert data["upstream_server"]

  if not data["nginx_conf_template"]:
    data["nginx_conf_template"] = "../template/nginx.conf.bg.template"

  base_path = s3.get_cluster_info_base_path()
  persistence = S3Persistence(cluster_id, data["service_port"], data["ping_port"], base_path, None, data["upstream_server"])
  (response, msg) = persistence.updateNginxConfig(data["nginx_conf_template"])
  print msg

def update_access_rules(cluster_id, data):
  """
  Updates the Access Module Configs/Rule for a given cluster_id
  """
  print "executing update_access_rules"
  assert cluster_id
  assert data["method"]
  assert data["rule_type"]
  assert data["rule_uri"]
  assert data["rule_key"]
  assert data["rule_value"]
  assert data["rule_access"] and (data["rule_access"] == "deny")

  base_path = s3.get_cluster_info_base_path()
  persistence = S3Persistence(cluster_id, None, None, base_path, None)
  (response, msg) = (None, None)
  if data["method"] == "add":
    (response, msg) = persistence.updateModuleRule(utils.ACCESS_PHASE, utils.ACCESS_MODULE, data["method"], data)
  elif data["method"] == 'remove':
    (response, msg) = persistence.removeModuleRule(utils.ACCESS_PHASE, utils.ACCESS_MODULE, data["method"], data)
  else:
    print "Wrong method, supported methods are (add/remove)"
    exit(1)

  print msg

def update_ratelimiter_rules(cluster_id, data):
  """
  Updates the RateLimiter Module Configs/Rule for a given cluster_id
  """
  print "executing update_ratelimiter_rules"
  assert cluster_id
  assert data["method"]
  assert data["rule_type"]
  assert data["rule_uri"]
  assert data["rule_key"]
  assert data["rule_value"]
  assert data["rule_threshold"]

  base_path = s3.get_cluster_info_base_path()
  persistence = S3Persistence(cluster_id, None, None, base_path, None)
  (response, msg) = (None, None)
  if data["method"] == "add":
    (response, msg) = persistence.updateModuleRule(utils.ACCESS_PHASE, utils.RATELIMITER_MODULE, data["method"], data)
  elif data["method"] == 'remove':
    (response, msg) = persistence.removeModuleRule(utils.ACCESS_PHASE, utils.RATELIMITER_MODULE, data["method"], data)
  else:
    print "Wrong method, supported methods are (add/remove)"
    exit(1)

  print msg

def update_router_rules(cluster_id, data):
  """
  Updates the Router Module Configs/Rule for a given cluster_id
  """
  print "executing update_router_rules"
  assert cluster_id
  assert data["method"]
  assert data["rule_type"]
  assert data["rule_uri"]
  assert data["rule_key"]
  assert data["rule_value"]
  assert data["rule_endpoint"]

  base_path = s3.get_cluster_info_base_path()
  persistence = S3Persistence(cluster_id, None, None, base_path, None)
  (response, msg) = (None, None)
  if data["method"] == 'add':
    response, msg = persistence.updateModuleRule(module_rule_utils.access_phase, module_rule_utils.router_module, data["method"], data)
  elif data["method"] == 'remove':
    response, msg = persistence.removeModuleRule(module_rule_utils.access_phase, module_rule_utils.router_module, data["method"], data)
  else:
    print "Wrong method, supported methods are (add/remove)"
    exit(1)

  print msg

def update_fallback_rules(cluster_id, data):
  """
  Updates the Fallback Module Configs/Rule for a given cluster_id
  """
  print "executing update_fallback_rules"
  assert cluster_id
  assert data["method"]
  assert data["rule_uri"]
  assert data["rule_errors"]
  assert data["rule_fallbacks"]

  if not data.get("rule_params", None):
    data["rule_params"] = {}

  if not data.get("rule_headers", None):
    data["rule_headers"] = {}

  base_path = s3.get_cluster_info_base_path()
  persistence = S3Persistence(cluster_id=cluster_id, service_port=None, ping_port=None, s3_base_path=base_path, nodes=None)

  (response, msg) = (None, None)
  if data["method"] == 'add':
    response, msg = persistence.updateFallbackRule("error", "fallback", data)
  elif data["method"] == 'remove':
    response, msg = persistence.removeFallbackRule("error", "fallback", data)
  else:
    print "Wrong method, supported methods are (add/remove)"
    exit(1)

  print msg

def main():
  parser = argparse.ArgumentParser(description = "Utility for updating bloomgateway rules to s3, it uses boto")
  parser.add_argument("--cmd", required=True, choices=['create', 'update', 'delete'], help="choose the action to be performed")
  parser.add_argument("--cluster_id", required=True, help="Name of the cluster")
  parser.add_argument("--data", required=False, help="data is a json string for choosen command, see the examples.")
  parser.add_argument("--type", required=False, choices=['conf', 'module'], help="type of configs needs to be updated")
  parser.add_argument("--module", required=False, choices=['fallback', 'access', 'ratelimiter', 'router'],  help="Name of the module for which we need to update the rules")

  args = parser.parse_args()
  data = json.loads(args.data) if args.cmd != "delete" else None

  if args.cmd == "create":
    bootstrap_cluster(args.cluster_id, data)
  elif args.cmd == "delete":
    delete_cluster(args.cluster_id)
  else:
    assert args.type
    if args.type == "conf":
      update_nginx_conf(args.cluster_id, data)
    else:
      assert args.module
      if args.module == "access":
        update_access_rules(args.cluster_id, data)
      elif args.module == "ratelimiter":
        update_ratelimiter_rules(args.cluster_id, data)
      elif args.module == "router":
        update_router_rules(args.cluster_id, data)
      elif args.module == "fallback":
        update_fallback_rules(args.cluster_id, data)

  print "Finish execution!!"

if __name__ == "__main__":
  main()