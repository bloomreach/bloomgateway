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
from abc import ABCMeta, abstractmethod

class Persistence:
  """
  Base Class for persisting nginx config or rules corresponding to different modules like ratelimiting and access control

  http://stackoverflow.com/questions/13646245/is-it-possible-to-make-abstract-classes-in-python
  Using the method for version 2.x, might need changes when we move to Python 3.x
  """
  __metaclass__ = ABCMeta

  def __init__(self, cluster_id, service_port, ping_port, base_path, nodes, upstream_server):
    self.cluster_id = cluster_id
    self.service_port = service_port
    self.ping_port = ping_port
    self.base_path = base_path
    self.nodes = nodes
    self.upstream_server = upstream_server


  def setBGNodes(self, nodes):
    self.nodes = nodes

  def setRealm(self, realm):
    self.realm = realm

  @abstractmethod
  def bootstrapCluster(self):
    pass

  @abstractmethod
  def updateModuleRule(self):
    pass

  @abstractmethod
  def removeModuleRule(self):
    pass