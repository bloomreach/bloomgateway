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

# Helps to build command line interface

from setuptools import setup, find_packages

__author__ = 'Ronak Kothari'
__author_email__ = 'ronak.kothari@gmail.com'
__copyright__ = 'Copyright 2016 BloomReach, Inc.'
__license__ = 'http://www.apache.org/licenses/LICENSE-2.0'
__version__ = '0.10.5'
__maintainer__ = __author__
__status__ = 'Development'

setup(name='bg_s3cli',
      version=__version__,
      description='BloomGateay S3 Commnad Line Interface',
      author=__author__,
      author_email='ronak.kothari@gmail.com',
      license=__license__,
      url='https://github.com/bloomreach/bloomgateway',
      packages=find_packages(),
      py_modules=['bg_s3cli', 'bg_s3cli.conf', 'bg_s3cli.scripts', 'bg_s3cli.scripts.schemas', 'bg_s3cli.scripts.utils'],
      install_requires=['boto==2.5.1', 's3cmd==1.5.2', 'jsonschema==2.5.1'],
      entry_points = {
        'console_scripts': ['bg_s3cli=bg_s3cli.s3cli:main'],
      },
      include_package_data=True,
      zip_safe=False
     )