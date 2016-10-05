#!/usr/bin/python
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

#This module will generate nginx.conf file from a template
from string import Template

def build_nginx_conf(infile, outfile, dict):
  """
  Takes the replacement dict of key-value pair which can be substituted
  to python string template.
  @infile : template file of python string template format
  @outfile : output file
  @dict : substitution key-value pairs
  """
  outdata = None
  with open(infile, "r") as file:
    content = Template( file.read() )
    outdata  = content.substitute(dict)

  with open(outfile, "w") as file:
    file.write(outdata)

  return