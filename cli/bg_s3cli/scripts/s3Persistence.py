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
import json
import os
import time

from persistence import Persistence
import template
from utils import utils
from schemas import access
from schemas import ratelimiter
from utils import module_rule_utils
from utils import s3_util
from module_rule_factory import ModuleRuleFactory

class S3Persistence(Persistence):
  """
  AWS S3 hook for persisting nginx config or rules corresponding to different modules like ratelimiting and access control.
  """

  ratelimiter = "ratelimiter"
  access = "access"
  rule_access = "rule_access"
  rule_threshold = "rule_threshold"
  rule_type = { "param":1, "header":2 }

  def __init__(self, cluster_id, service_port, ping_port, s3_base_path, nodes, upstream_server='localhost:7072'):
    # TODO : remove the default value
    super(S3Persistence, self).__init__(cluster_id, service_port, ping_port, s3_base_path, nodes, upstream_server)


  @staticmethod
  def create_fallback_rule(rule_data):
    rule = {}
    rule["api"] = rule_data["rule_uri"]
    rule["errors"] = rule_data["rule_errors"]
    rule["key"] = rule["api"] + "_" + '_'.join(rule["errors"])

    fallbacks = rule_data["rule_fallbacks"]
    rule["endpoints"] = []
    idx = 1
    for fallback in fallbacks:
      fallback_entry = {}
      fallback_entry[idx] = {}
      fallback_entry[idx]["name"] = fallback
      fallback_entry[idx]["params"] = rule_data["rule_params"]
      fallback_entry[idx]["headers"] = rule_data["rule_headers"]
      idx = idx+1
      rule["endpoints"].append(fallback_entry)

    return rule

  def lock_cluster_for_update(self):
    """
    An helper function to aquire s3 file base lock
    """
    lock_file_path = self.base_path + "/" + self.cluster_id + "/cluster.lock"

    #throw error when cluster config is locked for update
    file_present = s3_util.get_item(lock_file_path)
    if file_present != None:
      raise ValueError("cluster config locked for update. Cluster lock file ..%s" % lock_file_path)

    s3_util.put_item_from_string(lock_file_path, "")

  def unlock_cluster_for_update(self):
    """
    An helper function to release s3 file base lock
    """
    lock_file_path = self.base_path + "/" + self.cluster_id + "/cluster.lock"
    s3_util.delete_item(lock_file_path)

  def validate_rule_data(self, module, rule_data):
    if module == S3Persistence.ratelimiter:
      if int(rule_data["rule_threshold"]) <= 0:
        msg = "rule_threshold value should be greater than zero"
        return 0, msg

    if rule_data["rule_type"] not in S3Persistence.rule_type:
      msg = "rule_type can be either [param/header]"
      return 0, msg

    return 1,""

  def get_nginx_template_dict(self):
    """
    Provides a template dict for building nginx.conf using template
    """
    template_dict = {
      'upstream_server': self.upstream_server,
      'service_port': self.service_port,
      'ping_port': self.ping_port
    }
    return template_dict


  @staticmethod
  def get_version_data(version_file_path_s3):
    """
    An helper method to get version data from s3
    """
    return s3_util.get_json_to_obj(version_file_path_s3)

  @staticmethod
  def is_rule_defined(existing_rules, new_rule):
    """
    An helper method to check if new rule is already exists
    """

    #default condition for rule not found and new rule to be added
    old_rule = None
    key_matched = False
    index_val = -1

    new_rule_errors = new_rule["errors"]
    no_of_errors_passed = len(new_rule_errors)
    index = 0
    for rule in existing_rules:
      if new_rule["api"] == rule["api"]:
        no_of_errors_rule = len(rule["errors"])
        no_of_errors_matched = 0
        for error in new_rule_errors:
          if error in rule["key"]:
            no_of_errors_matched += 1

        if no_of_errors_passed == no_of_errors_rule and no_of_errors_matched == no_of_errors_passed: #complete key matched (rule should be updated)
          key_matched = True
          old_rule = rule
          return old_rule, key_matched, index

        if no_of_errors_matched > 0:
          old_rule = rule
          return old_rule, key_matched, index

      index += 1

    return old_rule, key_matched, index_val

  def push_updated_rules_to_S3(self, updated_rules, module, phase, version_data_dict, version_file_path_s3):
    """
    Updates the in-memory rules of a module to appropriate s3 path
    """

    version = utils.get_timestamped_version()
    module_rules_file_new_path_s3 = utils.get_module_s3_path(self.cluster_id, phase, module, version)
    s3_util.put_obj_to_json(module_rules_file_new_path_s3, updated_rules)

    # update version information
    version_data_dict["modules"][phase][module] = version
    s3_util.put_obj_to_json(version_file_path_s3, version_data_dict)

  def removeFallbackRule(self, phase, module, rule_data):
    """
    Helps to remove the fallback rule
    """
    unlock_cluster = False
    retVal = 0
    response = "Fallback rule has been deleted successfully"
    try:
      self.lock_cluster_for_update()
      unlock_cluster = True
      version_file_path_s3 = utils.get_version_path(self.cluster_id)
      version_data_dict = S3Persistence.get_version_data(version_file_path_s3)

      ##Note: removed if block only here, no other change. If block was not required
      module_version = version_data_dict["modules"][phase][module]
      existing_rules = utils.get_existing_rules(self.cluster_id, phase, module, module_version)
      new_rule = S3Persistence.create_fallback_rule(rule_data)
      old_rule, key_matched, index = S3Persistence.is_rule_defined(existing_rules, new_rule)
      if old_rule is None:
        response = "Rule doesn't exists in the datastore!!"
      else:
        if key_matched is False:
          response = "Errors passed %s .Provide all errors available in key [%s] (and no other errors) for updating the rule"% (new_rule["errors"], old_rule["key"])
          retVal = -2
        else:
          del existing_rules[index]
          self.push_updated_rules_to_S3(existing_rules, module, phase, version_data_dict, version_file_path_s3)

    except Exception as e:
        (retVal, response) = (-1, str(e))

    if unlock_cluster is True:
      self.unlock_cluster_for_update()
    return retVal, response

  def updateFallbackRule(self, phase, module, rule_data):
    """
    This method helps to add new fallback rule or update existing one.
    """
    unlock_cluster = False
    retVal = 0
    response = "Fallback rule has been added/updated successfully"

    try:
      self.lock_cluster_for_update()
      unlock_cluster = True
      version_file_path_s3 = utils.get_version_path(self.cluster_id)
      version_data_dict = S3Persistence.get_version_data(version_file_path_s3)

      ##Note: removed if block only here, no other change. If block was not required
      module_version = version_data_dict["modules"][phase][module]
      existing_rules = utils.get_existing_rules(self.cluster_id, phase, module, module_version)
      new_rule = S3Persistence.create_fallback_rule(rule_data)
      old_rule, key_matched, index = S3Persistence.is_rule_defined(existing_rules, new_rule)
      if old_rule is None:
        existing_rules.append(new_rule)
        self.push_updated_rules_to_S3(existing_rules, module, phase, version_data_dict, version_file_path_s3)
      else:
        if key_matched is False:
          response = "Errors passed %s .Provide all errors available in key [%s] (and no other errors) for updating the rule"% (new_rule["errors"], old_rule["key"])
          retVal = -2
        else:
          del existing_rules[index]
          existing_rules.append(new_rule)
          self.push_updated_rules_to_S3(existing_rules, module, phase, version_data_dict, version_file_path_s3)

    except Exception as e:
      (response, response) = (-1, str(e))

    if unlock_cluster is True:
      self.unlock_cluster_for_update()
    return retVal, response

  def removeModuleRule(self, phase, module, method, rule_data):
    """
    This is a generic method to remove a rule of a given module.
    """
    unlock_cluster = False
    response = "Rule has been deleted successfully"
    retVal = 0
    try:
      self.lock_cluster_for_update()
      unlock_cluster = True

      version_file_path_s3 = utils.get_version_path(self.cluster_id)
      version_data_dict = S3Persistence.get_version_data(version_file_path_s3)
      module_version = version_data_dict[module_rule_utils.modules][module_rule_utils.access_phase][module]
      existing_rules = utils.get_existing_rules(self.cluster_id, phase, module, module_version)
      module_rule = ModuleRuleFactory.buildModule(module, rule_data)
      new_rule = module_rule.build()
      present, index = module_rule_utils.rule_present(existing_rules, new_rule)
      if present == False:
        retVal = -1
        response = "Rule was not found in datastore"
      else:
        del existing_rules[index]
        version = utils.get_timestamped_version()
        module_rules_file_new_path_s3 = utils.get_module_s3_path(self.cluster_id, phase, module, version)
        s3_util.put_obj_to_json(module_rules_file_new_path_s3, existing_rules)
        version_data_dict[module_rule_utils.modules][module_rule_utils.access_phase][module] = version
        s3_util.put_obj_to_json(version_file_path_s3, version_data_dict)

    except Exception as e:
      (response, response) = (-1, str(e))

    if unlock_cluster is True:
      self.unlock_cluster_for_update()
    return retVal, response

  def updateModuleRule(self, phase, module, method, rule_data):
    """
    Generic method to add new existing rule or update existing one for given module
    """
    unlock_cluster=False
    response = "Rule has been added/updated successfully"
    retVal = 0
    try:
      self.lock_cluster_for_update()
      unlock_cluster = True

      version_file_path_s3 = utils.get_version_path(self.cluster_id)
      version_data_dict = S3Persistence.get_version_data(version_file_path_s3)

      #read the version of module from version.json
      module_version = version_data_dict[module_rule_utils.modules][module_rule_utils.access_phase][module]
      existing_rules = utils.get_existing_rules(self.cluster_id, phase, module, module_version)
      module_rule = ModuleRuleFactory.buildModule(module, rule_data)
      new_rule = module_rule.build()

      #TODO (navneet) : Handle this better way
      err = None
      if module_rule_utils.access_module == module:
        retVal, err = utils.validate(new_rule, access.schema)
      elif module_rule_utils.ratelimiter_module == module:
        retVal, err = utils.validate(new_rule, ratelimiter.schema)

      if retVal != 0:
        raise Exception(err)

      present, index = module_rule_utils.rule_present(existing_rules, new_rule)
      if present == False:
        existing_rules.append(new_rule)
      else:
        existing_rule = existing_rules[index]
        if module_rule_utils.rule_already_present(existing_rule, new_rule):
          retVal = -1 #no need to update again since rule is there
          response = "Rule is already present in datastore"
        else:
          del existing_rules[index]
          existing_rules.append(new_rule)

      if retVal == 0: #update only if new rule or some change to existing rule
        #update the version in version.json for module
        version = utils.get_timestamped_version()
        module_rules_file_new_path_s3 = utils.get_module_s3_path(self.cluster_id, phase, module, version)
        s3_util.put_obj_to_json(module_rules_file_new_path_s3, existing_rules)
        version_data_dict[module_rule_utils.modules][module_rule_utils.access_phase][module] = version
        s3_util.put_obj_to_json(version_file_path_s3, version_data_dict)

    except Exception as e:
      (retVal, response) = (-1, str(e))

    if unlock_cluster is True:
      self.unlock_cluster_for_update()
    return (retVal, response)

  def deleteCluster(self):
    """
    Delete an entire cluster
    """
    response = "cluster (%s) is deleted successfully" %(self.cluster_id)
    retVal = 0
    unlock_cluster = False
    try:
      self.lock_cluster_for_update()
      unlock_cluster = True
      cluster_s3_path = self.base_path + "/" + self.cluster_id + "/"
      s3_util.delete_dir(cluster_s3_path)
      unlock_cluster = False
    except Exception as e:
      (retVal, response) = (-1, str(e))
    if unlock_cluster is True:
      self.unlock_cluster_for_update()
    return retVal, response

  def bootstrapCluster(self, nginx_conf_template):
    """
    Create a new cluster with given nginx conf template
    """

    version_file_path_s3 = utils.get_version_path(self.cluster_id)
    version_file = s3_util.get_item(version_file_path_s3)

    if version_file != None:
      print "Bootstrap already completed, please try other commands for updating"
      return

    #build version data
    version = utils.get_timestamped_version()
    version_data_dict = {}
    version_data_dict["nginx_conf"] = version
    version_data_dict["modules"] = {}
    version_data_dict["modules"]["access"] = {}
    version_data_dict["modules"]["error"] = {}
    version_data_dict["modules"]["access"]["ratelimiter"] = version
    version_data_dict["modules"]["access"]["access"] = version
    version_data_dict["modules"]["access"]["router"] = version
    version_data_dict["modules"]["error"]["fallback"] = version

    with open('/tmp/version.json', 'w') as outfile:
      json.dump(version_data_dict, outfile)

    #build cluster data
    cluster_data = {}
    cluster_data["cluster_id"] = self.cluster_id
    cluster_data["service_port"] = self.service_port
    cluster_data["ping_port"] = self.ping_port
    cluster_data["nodes"] = self.nodes

    #push cluster info file
    cluster_info_file_path_s3 = "%s/%s/%s/cluster.json"%(self.base_path, self.cluster_id, version)
    s3_util.put_obj_to_json(cluster_info_file_path_s3, cluster_data)

    #push cluster version file
    cluster_version_file_path_s3 = "%s/%s/cluster_version.json"%(self.base_path, self.cluster_id)
    cluster_version_dict = {}
    cluster_version_dict["cluster_version"] = version
    s3_util.put_obj_to_json(cluster_version_file_path_s3, cluster_version_dict)

    #build and push nginx config
    template_dict = self.get_nginx_template_dict()
    output_file = "/tmp/nginx.conf"
    template.build_nginx_conf(nginx_conf_template, output_file, template_dict)
    nginx_conf_file_path_s3 = "%s/%s/conf/%s/nginx.conf"%(self.base_path, self.cluster_id, version)

    with open('/tmp/nginx.conf', 'r') as infile:
      s3_util.put_item_from_file_pointer(nginx_conf_file_path_s3, infile)

    #push empty rules files for bootstrap
    empty_json_string = '[]'
    ratelimiter_file_path_s3 = "%s/%s/modules/access/ratelimiter/%s/ratelimiter.rules"%(self.base_path, self.cluster_id, version)
    accesscontrol_file_path_s3 = "%s/%s/modules/access/access/%s/access.rules"%(self.base_path, self.cluster_id, version)
    router_file_path_s3 = "%s/%s/modules/access/router/%s/router.rules"%(self.base_path, self.cluster_id, version)
    fallback_file_path_s3 = "%s/%s/modules/error/fallback/%s/fallback.rules"%(self.base_path, self.cluster_id, version)

    s3_util.put_item_from_string(ratelimiter_file_path_s3, empty_json_string)
    s3_util.put_item_from_string(accesscontrol_file_path_s3, empty_json_string)
    s3_util.put_item_from_string(router_file_path_s3, empty_json_string)
    s3_util.put_item_from_string(fallback_file_path_s3, empty_json_string)

    with open('/tmp/version.json', 'r') as infile:
      s3_util.put_item_from_file_pointer(version_file_path_s3, infile)

  def updateNginxConfig(self, nginx_conf_template):
    """
    Helps to modify nginx.conf using template
    """
    response = "Nginx Config updated successfully."
    retVal = 0
    unlock_cluster = False
    try:
      self.lock_cluster_for_update()
      unlock_cluster = True

      # get the current version file
      version_file_path_s3 = utils.get_version_path(self.cluster_id)
      version_data_dict = S3Persistence.get_version_data(version_file_path_s3)

      # build and push nginx config
      template_dict = self.get_nginx_template_dict()
      output_file = "/tmp/nginx.conf"
      template.build_nginx_conf(nginx_conf_template, output_file, template_dict)

      version = utils.get_timestamped_version()
      nginx_conf_file_path_s3 = "%s/%s/conf/%s/nginx.conf"%(self.base_path, self.cluster_id, version)

      with open('/tmp/nginx.conf', 'r') as infile:
        s3_util.put_item_from_file_pointer(nginx_conf_file_path_s3, infile)

      # update the version information
      version_data_dict["nginx_conf"] = version
      s3_util.put_obj_to_json(version_file_path_s3, version_data_dict)

    except Exception as e:
      (retVal, response) = (-3, str(e))

    if unlock_cluster is True:
      self.unlock_cluster_for_update()
    return retVal, response