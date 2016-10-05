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
###knows how to build rules based on module, rule_data
###throws exception if data invalid or insufficient to build rule

from utils import module_rule_utils
from rate_limiter_rule import RateLimiterRule
from access_control_rule import AccessControlRule
from router_rule import RouterRule

class ModuleRuleFactory:

  @staticmethod
  def buildModule(module_name, rule_dict):
    """builds the corresponding module rule
    return rule if build successfully
    throws exception if error in building rule
    TODO handle error conditions
    """
    module_rule = None

    if(module_name == module_rule_utils.ratelimiter_module):
      module_rule = RateLimiterRule(rule_dict)
    elif(module_name == module_rule_utils.access_module):
      module_rule = AccessControlRule(rule_dict)
    elif(module_name == module_rule_utils.router_module):
      module_rule = RouterRule(rule_dict)

    #TODO handle module == None case
    return module_rule
