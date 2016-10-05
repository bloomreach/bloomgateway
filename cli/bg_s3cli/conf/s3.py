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

import os

def get_base_path():
  """
  s3 base bucket where the module level and nginx conf are stored
  """
  s3_base_bucket = os.getenv('S3_BASE_BUCKET', None)
  if not s3_base_bucket:
    raise Exception("Environment S3_BASE_BUCKET is not set. To use this utiliy, pl. provide it.")
  return s3_base_bucket

def get_cluster_info_base_path():
  """
  All the configs specific to cluster are stored under,
  s3 base bucket + /bloomgateway/cluster
  """
  return "%s/bloomgateway/cluster"%(get_base_path())

