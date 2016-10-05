#!/usr/bin/env python
#
# Copyright 2016 BloomReach, Inc.
# Copyright 2016 Ronak Kothari <ronak.kothari@gmail.com>.

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

# This python file defines JSON Schema for Ratelimiter Control Module of BloomGateay
# The rule for Ratelimiter are defined as JSON object which are of mainly three different
# types - node rule, api rule and param (or header) rule.

# example of node rule
# {
#   "type" : "node",
#   "threshold" : "3"
# }

# example of api rule
# {
#   "type" : "api",
#   "api" : "/api/v1/core/",
#   "threshold" : "3"
# }

# example of header rule with ipv4
# {
#   "type":"header",
#   "api":"/",
#   "key":"remote_addr",
#   "value":"10.01.1.1",
#   "threshold":"7"
# },

# schema definition
schema = {
  "definitions" : {
    # threshold is base property accross all the rules
    "threshold_base" : {
      "properties" : {
        "threshold": { "type": "string", "pattern": "^[0-9]+$"},
      },
      "required" : ["threshold"],
    },

    # api base ( api, threshold )
    "api_base" : {
      "allOf" : [
        { "$ref": "#/definitions/threshold_base" },
        { "properties" : { "api" : { "type" : "string", "format" : "uri" }},"required" : ["type", "api"]}
      ]
    },

    "pair" : {
      "oneOf" : [
        # key-value pair for ipv4
        {
          "type" : "object",
          "properties": {
                "key" : {"type" : "string", "enum" : ["remote_addr"]},
                "value" : {"type": "string", "pattern" : "^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$"},
          },
          "required": ["key", "value"],
        },

        # key-value pair for  non-IP
        {
          "type" : "object",
          "properties": {
            "key" : {"type" : "string", "not" : { "enum" : ["remote_addr"] }},
            "value" : {"type": "string"},
          },
          "required": ["key", "value"],
        },
      ]
    },

    "node_rule" : {
      "allOf" : [
        { "$ref": "#/definitions/threshold_base" },
        { "properties" : { "type": { "enum" : ["node"] },}, "required" : ["type"] }
      ]
    },

    "api_rule" : {
      "allOf" : [
        { "$ref": "#/definitions/api_base" },
        { "properties" : { "type": { "enum" : ["api"] },}, "required" : ["type"] }
      ]
    },

    "header_param_rule" : {
      "allOf" : [
        { "$ref": "#/definitions/api_base" },
        { "properties" : { "type": { "enum" : ["param", "header"] },}, "required" : ["type"] },
        { "$ref": "#/definitions/pair" },
      ]
    }

  },

  "oneOf": [
      { "$ref": "#/definitions/node_rule" },
      { "$ref": "#/definitions/api_rule" },
      { "$ref": "#/definitions/header_param_rule" },
  ],
}

# Note:
# You need to set the python path running from command prompt.
# PYTHONPATH=$PYTHONPATH:<bloomgateway repo> python ratelimiter.py
# ex. on my m/c :
# PYTHONPATH=$PYTHONPATH:/Users/ronak/br/bb python ratelimiter.py
if __name__ == "__main__":
  from scripts.utils import utils as utils

  # validate node rule
  ret, err = utils.validate({ "type" : "node", "threshold" : "3"}, schema)
  assert (ret == 0)

  # invalid node rule
  ret, err = utils.validate({ "type" : "node", "thresholdx" : "3"}, schema)
  assert (ret == -2)

  # validate api rule
  ret, err = utils.validate({ "type" : "api", "api" : "/api/v1/core/", "threshold" : "3" }, schema)
  assert (ret == 0)

  # invalid api rule
  ret, err = utils.validate({ "type" : "api", "threshold" : "3" }, schema)
  assert (ret == -2)

  # validate IP based threshold
  ret, err = utils.validate({ "type":"header", "api":"/", "key":"remote_addr", "value":"10.01.1.1", "threshold":"7" }, schema)
  assert (ret == 0)

  # invalid IP based threshold
  ret, err = utils.validate({ "type":"header", "api":"/", "key":"remote_addr", "value":"10.01.1", "threshold":"7" }, schema)
  assert (ret == -2)

  # validate IP based threshold
  ret, err = utils.validate({ "type":"param", "api":"/", "key":"account_id", "value":"1234", "threshold":"7" }, schema)
  assert (ret == 0)

  # missing type
  ret, err = utils.validate({ "api":"/", "key":"accout_id", "value":"10.01.1", "threshold":"7" }, schema)
  assert (ret == -2)

   # non-numeric threshold value
  ret, err = utils.validate({ "type":"header", "api":"/", "key":"remote_addr", "value":"10.01.1", "threshold":"7a" }, schema)
  assert (ret == -2)

  # exit message
  print "successfully verified all the Ratelimiter rules."
