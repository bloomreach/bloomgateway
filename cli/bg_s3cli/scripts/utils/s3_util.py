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
# helper function for s3 using boto library
# This work was part of BloomReach other project. This work was taken with slight modification.
import ConfigParser
import commands
import json
import re
import sys

import boto
from boto.s3.connection import S3Connection

####################
# global settings #
###################
try:
  boto.config.add_section("Boto")
except ConfigParser.DuplicateSectionError:
  pass
boto.config.set("Boto", "metadata_service_num_attempts", "5")

s3regex = re.compile("s3://([^/]+)/(.*)")
def parse_s3_path(s3path):
  m = s3regex.match(s3path)
  if m:
    return (m.group(1), m.group(2))
  else:
    raise RuntimeError("Invalid S3 path: %s" % s3path)

###############################################
# get method to get content from s3 file path #
###############################################

def get_item(s3path):
  """
  Get file from s3 as a boto key; None if key does not exist
  """
  b_name, k_name = parse_s3_path(s3path)
  try:
    bucket = S3Connection().get_bucket(b_name)
  except RuntimeError,e:
    return None
  return bucket.get_key(k_name) #None if key DNE

def get_item_to_string(s3path):
  """
  Get file from s3 as a string
  """
  obj = get_item(s3path)
  if not obj:
    return None
  return obj.get_contents_as_string()

def get_json_to_obj(s3path):
  """
  Get json file from s3 as python object
  """
  try:
    obj = get_item_to_string(s3path)
    json_obj = json.loads(obj)
    return json_obj
  except ValueError, e:
    print "Error while converting to json for " + s3path
    return None
  except Exception, e:
    print "Unexpected error :" + str(e)
    return None

def delete_item(s3path):
  """
  delete the s3file
  """
  obj = get_item(s3path)
  obj.delete()

def delete_dir(s3path):
  """
  Delete all the files given by s3path
  """
  return commands.getoutput("s3cmd del %s -r -f" % s3path)

############################################
# Helper method to put contents to s3 file #
############################################
def new_item(s3path):
  """
  Helper method to create a new key at the s3path. Returns None if the bucket doesn't exist
  """
  b_name, k_name = parse_s3_path(s3path)
  try:
    bucket = S3Connection().get_bucket(b_name)
  except RuntimeError, e:
    print "Error: Bucket s3://%s/ does not exist; ensure this is the correct name (or create the bucket before running this method" % b_name
    return None
  return bucket.new_key(k_name)

def put_obj_to_json(s3path, contents):
  """
  put json content to s3 file
  """
  try:
    obj = json.dumps(contents)
  except Exception, e:
    print "Error : invalid json data, failed in conversion"
    return False
  return put_item_from_string(s3path, obj)

def put_item_from_string(s3path, contents):
  """
  put the string content into given s3 file
  """
  key = new_item(s3path)
  if not key:
    return False
  key.set_contents_from_string(contents)
  print >> sys.stderr, "s3_util.py: s3cmd put (string) %s" % s3path
  return True

def put_item_from_file_pointer(s3path, fp):
  """
  put the content of file pointed by file pointer to s3 path
  """
  key = new_item(s3path)
  if not key:
    return False
  key.set_contents_from_file(fp)
  print >> sys.stderr, "s3_util.py: s3cmd put %s %s" % (fp.name, s3path)
  return True
