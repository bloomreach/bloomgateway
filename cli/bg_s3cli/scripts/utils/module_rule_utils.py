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
from .. module_rule import ModuleRule

rule_key = "rule_key"
rule_value = "rule_value"
rule_type = "rule_type"
rule_uri = "rule_uri"
rule_threshold = "rule_threshold"
rule_access = "rule_access"
rule_endpoint = "rule_endpoint"

access_phase = "access"
error_phase = "error"

modules = "modules"
ratelimiter_module = "ratelimiter"
access_module = "access"
router_module = "router"
fallback_module = "fallback"

def rule_present(existing_rules, rule):
  """Checks if rule is present in existing_rules
  return True, index is present
  return False,-1 if absent
  """
  index = 0
  response = False, -1
  for existing_rule in existing_rules:
    if (existing_rule[ModuleRule.type] == rule[ModuleRule.type] and existing_rule[ModuleRule.key] == rule[ModuleRule.key]
        and existing_rule[ModuleRule.value] == rule[ModuleRule.value] and existing_rule[ModuleRule.api] == rule[ModuleRule.api]):
      response = True, index
      break
    index = index+1

  return response

def rule_already_present(rule1, rule2):
  for key in rule1.keys():
    if rule1[key] != rule2[key]:
      return False

  return True