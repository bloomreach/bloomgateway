#!/usr/bin/env bash
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

# usage : ./build_test.sh

DEB_BG_PKG=${1:?debian package not specified}
BUILD_TEST=${2:-"/tmp/build/tests"}

INSTALLED_BASE="/usr/local/bloomgateway/openresty"
PKG_NAME="bloomgateway"

# install test pkg
dpkg -i ${DEB_BG_PKG}

# INSTALL CPAN PACKAGES
export PERL_MM_USE_DEFAULT=1
cpan Test::Nginx::Socket::Lua

# EXPORT TEST VARS
export TEST_NGINX_PORT=6070
export TEST_NGINX_NO_NGINX_MANAGER=1
export TEST_NGINX_SERVROOT=${INSTALLED_BASE}/nginx
export PATH=${TEST_NGINX_SERVROOT}/sbin/:$PATH

# RUN ACCESS CONTROL TESTS
cp ${BUILD_TEST}/integration/data/access/access.rules ${INSTALLED_BASE}/bb/lualib/bb/plugins/access/
bloomgateway start
prove -I${BUILD_TEST}/integration/pm ${BUILD_TEST}/integration/t/access/access/t
rm ${INSTALLED_BASE}/bb/lualib/bb/plugins/access/access.rules
bloomgateway stop

# wait for 5 secs for socket to release
sleep 5

# RUN RATELIMITER CONTROL TESTS
cp ${BUILD_TEST}/integration/data/access/ratelimiter.rules ${INSTALLED_BASE}/bb/lualib/bb/plugins/access/
bloomgateway start
prove -I${BUILD_TEST}/integration/pm ${BUILD_TEST}/integration/t/access/ratelimiter/t
rm ${INSTALLED_BASE}/bb/lualib/bb/plugins/access/ratelimiter.rules
bloomgateway stop

# remove test pkg
dpkg -r ${PKG_NAME}

