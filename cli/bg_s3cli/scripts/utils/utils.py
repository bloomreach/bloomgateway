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
# -------------------------------------------------------------------
# imports relative to cli directory
# -------------------------------------------------------------------
import json
import jsonschema
import time

import s3_util
from bg_s3cli.conf import s3

ACCESS_PHASE = "access"
ERROR_PHASE = "error"

RATELIMITER_MODULE = "ratelimiter"
ACCESS_MODULE = "access"
FALLBACK_MODULE = "fallback"

def get_version_path(cluster_id):
  """
  Gives the s3 fullpath of version file of a given cluster_id
  """
  base_path = s3.get_cluster_info_base_path()
  return base_path + "/" + cluster_id + "/version.json"

def get_version_info(cluster_id):
  """
  Gives the version information of a given cluster_id as JSON.
  It is a dictonary with version information for each Modules and nginx.conf
  """
  version_file_path_s3 = get_version_path(cluster_id)
  version_file_contents = s3_util.get_item_to_string(version_file_path_s3)
  version_data_dict = json.loads(version_file_contents)
  return version_data_dict

def get_cluster_version_path(cluster_id):
  """
  Gives s3 full path of cluster_version file of a given cluster_id
  """
  base_path = s3.get_cluster_info_base_path()
  return "%s/%s/cluster_version.json"%(base_path, cluster_id)

def get_cluster_version_info(cluster_id):
  """
  Gives the cluster_version information as JSON
  """
  cluster_version_file_path_s3 = get_cluster_version_path(cluster_id)
  cluster_version_file_contents = s3_util.get_item_to_string(cluster_version_file_path_s3)
  cluster_version_data_dict = json.loads(cluster_version_file_contents)
  return cluster_version_data_dict

def get_cluster_info_path(cluster_id):
  """
  Gives s3 path for cluster.json files it contains book keeping information about cluster.
  """
  base_path = s3.get_cluster_info_base_path()
  cluster_version_path = get_cluster_version_path(cluster_id)
  cluster_version_file_contents = s3_util.get_item_to_string(cluster_version_path)
  cluster_version_data_dict = json.loads(cluster_version_file_contents)
  cluster_info_path = "%s/%s/%s/cluster.json"%(base_path, cluster_id, cluster_version_data_dict.get("cluster_version"))
  return cluster_info_path

def get_cluster_info(cluster_id):
  """
  Returns a dict for cluster.json
  """
  cluster_info_file_path_s3 = get_cluster_info_path(cluster_id)
  cluster_info_file_contents = s3_util.get_item_to_string(cluster_info_file_path_s3)
  cluster_info = json.loads(cluster_info_file_contents)
  cluster_info_data_dict = json.loads(cluster_info_file_contents)
  return cluster_info_data_dict

def get_module_s3_path(cluster_id, phase, module, module_version):
  """
  Gives s3 path for a given module's config/rule for a given version
  """
  base_path = s3.get_cluster_info_base_path()
  return "%s/%s/modules/%s/%s/%s/%s.rules"%(base_path, cluster_id, phase, module, module_version, module)

def get_module_info(cluster_id, module, phase):
  """
  Retruns a dict of module's rule of a current version.
  """
  version_info = get_version_info(cluster_id)
  module_version = version_info["modules"][phase][module]
  s3_module_path = get_module_s3_path(cluster_id, phase, module, module_version)
  contents = s3_util.get_item_to_string(s3_module_path)
  return json.loads(contents)

def push_cluster_config(cluster_id, cluster_version, cluster_info):
  """
  Update the book keeping information about a cluster with id : cluster_id
  """
  base_path = s3.get_cluster_info_base_path()
  #push cluster info
  s3_cluster_info_file_path_new = "%s/%s/%s/cluster.json"%(base_path, cluster_id, cluster_version)
  s3_util.put_obj_to_json(s3_cluster_info_file_path_new, cluster_info)

  #push cluster version info
  s3_cluster_version_file_path_new = "%s/%s/cluster_version.json"%(base_path, cluster_id)
  cluster_version_info = {}
  cluster_version_info["cluster_version"] = cluster_version
  s3_util.put_obj_to_json(s3_cluster_version_file_path_new, cluster_version_info)

def get_existing_rules(cluster_id, phase, module_name, version):
  """
  Returns the dict of all the rules of a given module and given version for a cluster
  """
  module_rules_file_path_s3 = get_module_s3_path(cluster_id, phase, module_name, version)
  rule_file_contents = s3_util.get_item_to_string(module_rules_file_path_s3)
  existing_rules = json.loads(rule_file_contents)
  return existing_rules

def get_timestamped_version():
	return time.strftime("%Y%m%d%.%H%M%S", time.gmtime(time.time()))

#converts a dictionary with unicode key value into byte strings key value recursively
#source - http://stackoverflow.com/questions/956867/how-to-get-string-objects-instead-of-unicode-ones-from-json-in-python
def byteify(input):
  if isinstance(input, dict):
    return {byteify(key): byteify(value)
            for key, value in input.iteritems()}
  elif isinstance(input, list):
    return [byteify(element) for element in input]
  elif isinstance(input, unicode):
    return input.encode('utf-8')
  else:
    return input

def verify_endpoint(endpoint):
  """
  check if the given endpoint is in the form host:port
  """
  if ':' not in endpoint:
    print "endpoint not passed correctly %s"%endpoint
    exit(1)

  host_port = endpoint.split(':')
  host = host_port[0]
  port = host_port[1]
  if ((host is None or host == "") or (port is None or port == "")):
    print "endpoint [%s] not passed correctly. Host/port values mandatory "%endpoint
    exit(1)


def verify_endpoints(endpoints):
  """
  Check all the endpoints have the needed host:port format
  """
  endpoints = endpoints.split(';')
  for endpoint in endpoints:
    verify_endpoint(endpoint)

def validate(json_obj, schema_def):
  """
    Validates json object agains given json schema using jsonchema
  """
  try:
    jsonschema.validate(json_obj, schema_def)
  except jsonschema.exceptions.ValidationError as e:
    return (-2, e)
  except Exception as e:
    return (-1, e)
  return (0, None)
