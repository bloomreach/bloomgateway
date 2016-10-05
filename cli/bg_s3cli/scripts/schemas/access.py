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

# This python file defines JSON Schema for Access Control Module of BloomGateay
# The rule for Access Control are defined as JSON object which consists of
# 5 mandatory key, value pair. There is a special case for IP rule
# where key is remote_addr and value is IPv4.

# Rule example (IP)
# {
#  "type" : "header",
#  "api" : "/api/v1/core/",
#  "key" : "remote_addr",
#  "value" : "127.0.0.1",
#  "access" : "deny"
# }

# Rule example (Regular)
# {
#  "type" : "param",
#  "api" : "/api/v1/core/",
#  "key" : "account_id",
#  "value" : "1234",
#  "access" : "deny"
# }

# schema definition
schema = {
  "definitions" : {
    "specifics" : {
      "oneOf" : [
        {
          "type" : "object",
          "properties": {
            "type" : {"type" : "string", "enum" : ["header", "param"]},
            "key" : {"type" : "string", "enum" : ["remote_addr"]},
            "value" : {"type": "string", "pattern" : "^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$"},
          },
          "required": ["key", "value"],
        },
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
    "base" : {
      "properties" : {
        "type": { "enum": [ "header", "param" ] },
        "api": { "type": "string", "format": "uri"},
        "access": { "enum": ["deny", "allow"] },
      },
      "required" : ["type", "api", "access"],
    },
  },

  "allOf": [
      { "$ref": "#/definitions/base" },
      { "$ref": "#/definitions/specifics" },
  ],
}

# Note:
# You need to set the python path running from command prompt.
# PYTHONPATH=$PYTHONPATH:<bloomgateway repo> python access.py
# ex. on my m/c :
# PYTHONPATH=$PYTHONPATH:/Users/ronak/br/bb python access.py
if __name__ == "__main__":
  from scripts.utils import utils as utils
  # valid IP rule
  ret, err = utils.validate({"key" : "remote_addr", "value" : "10.10.1.11", "type" : "header", "api" : "/api/v1/core/", "access":"deny"}, schema)
  assert(ret == 0)
  # invalid IP rule
  ret, err = utils.validate({"key" : "remote_addr", "value" : "10.10.11", "type" : "header", "api" : "/api/v1/core/", "access":"deny"}, schema)
  assert (ret == -1)
  # valid non-IP rule
  ret, err = utils.validate({"key" : "account_id", "value" : "1234", "type" : "header", "api" : "/api/v1/core/", "access":"deny"}, schema)
  assert (ret == 0)
  # invalid non-IP rule
  ret, err = utils.validate({"key" : "account_id", "value" : "1234", "type" : "header", "api" : "/api/v1/core/", "access":"deny1"}, schema)
  assert (ret == -1)
  # exit message
  print "successfully verified all the access rules."
