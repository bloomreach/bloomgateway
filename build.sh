#!/usr/bin/env bash
#
# Copyright 2016 BloomReach, Inc.
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

# usage : ./build.sh
set -o xtrace
echo "creating bloomgateway packages"

# the location of directory where build.sh exists
skiptest=${SKIPTEST:-"false"}
CWD="$(pwd)"
YEAR=$(date +%y)
MONTH=$(date +%m)
DAY=$(date +%d)
BASE_YEAR=16
BASE=0
major=`expr $YEAR - $BASE_YEAR`
minor=`expr $MONTH - $BASE`
patch=`expr $DAY - $BASE`
version=${major}.${minor}.${patch}

# set other flags
set -o errexit -o pipefail -o nounset

# build directory
build_dir="/tmp/build"
build_root_dir="/tmp/build/root"
build_openresty_install_dir="/tmp/build/root/usr/local/bloomgateway/openresty"
build_sockproc_install_dir="/tmp/build/root/usr/local/bloomgateway/sockproc"
build_log_dir="/tmp/build/root/var/log/bloomgateway"
build_bin_dir="/tmp/build/root/usr/local/bloomgateway/bin"
build_exposed_bin_dir="/tmp/build/root/usr/sbin"
logrotate_dir="/tmp/build/root/etc/logrotate.d"

# remover the prior build diretory if exists
rm -rf ${build_dir}

# create a build dir
mkdir -p ${build_dir}
mkdir -p ${build_root_dir}
mkdir -p ${build_openresty_install_dir}
mkdir -p ${build_sockproc_install_dir}
mkdir -p ${build_log_dir}
mkdir -p ${build_bin_dir}
mkdir -p ${build_exposed_bin_dir}
mkdir -p ${logrotate_dir}

# create bloomgateway prefix directory
bloomgateway_prefix="/usr/local/bloomgateway"
bloomgateway_openresty_prefix="/usr/local/bloomgateway/openresty"
mkdir -p $bloomgateway_prefix
mkdir -p $bloomgateway_openresty_prefix

# install necessary packages
apt-get update
apt-get install -y --force-yes wget unzip ruby-dev libreadline-dev libncurses5-dev libpcre3-dev libssl-dev libpq-dev perl make build-essential
gem install fpm

# build openresty
cd /tmp/build \
  &&  wget https://openresty.org/download/openresty-1.9.7.3.tar.gz \
  &&  tar xvf openresty-1.9.7.3.tar.gz

cd /tmp/build/openresty-1.9.7.3 \
  &&  ./configure --prefix=${bloomgateway_openresty_prefix} --with-pcre-jit \
      --with-ipv6 \
      --without-http_redis2_module \
      --with-http_iconv_module \
      --with-http_realip_module \
      --with-http_ssl_module \
      --with-http_stub_status_module \
      -j2 \
  &&  make \
  &&  make install DESTDIR=${build_root_dir}

# change the permission and copy binary
chmod a+x ${build_openresty_install_dir}/nginx/sbin/nginx
cp ${build_openresty_install_dir}/nginx/sbin/nginx ${build_bin_dir}/openresty

# build sockproc
cp -R ${CWD}/thirdparty/sockproc-0.5.19 /tmp/build
cd /tmp/build/sockproc-0.5.19 \
  && make \
  && cp sockproc ${build_sockproc_install_dir}/sockproc

# change permission and copy binary
chmod a+x ${build_sockproc_install_dir}/sockproc
cp ${build_sockproc_install_dir}/sockproc ${build_bin_dir}/sockproc

# copy bloomgateway modules + conf files
conf_dir=${build_openresty_install_dir}/nginx/conf/
bb_dir=${build_openresty_install_dir}/bb/
mkdir -p ${conf_dir}
mkdir -p ${bb_dir}

# build nginx.conf and config.version
local_conf_dir=${CWD}/src/bb-node/conf
cp ${local_conf_dir}/nginx.conf ${conf_dir}/nginx.conf
cp ${local_conf_dir}/config.version ${conf_dir}/config.version
cp -R ${local_conf_dir}/conf.d ${conf_dir}

# copy lualib directory
local_lualib_dir=${CWD}/src/bb-node/lualib
cp -R ${local_lualib_dir} ${bb_dir}

# copy startup script
local_scripts_dir=${CWD}/scripts
cp -R ${local_scripts_dir} ${bb_dir}
chmod -R a+x ${bb_dir}/scripts/
cp ${bb_dir}/scripts/bloomgateway.sh ${build_exposed_bin_dir}/bloomgateway

# copy logrotate file
cp ${local_conf_dir}/nginx.logrotate.default ${logrotate_dir}/bloomgateway

# build deb package
cd /tmp/build/root \
  &&  fpm -s dir -t deb \
      -n bloomgateway \
      -v ${version} \
      -C /tmp/build/root \
      -p bloomgateway_VERSION_ARCH.deb \
      --description 'A BloomGateway Service' \
      --url 'http://bloomreach.com/' \
      --category httpd \
      --maintainer 'ronak.kothari@gmail.com' \
      --after-remove ${CWD}/scripts/postremove.sh

# store the package name
deb_pkg_name=$(echo `ls ${build_root_dir}/bloomgateway_${version}_*.deb`)

# copy test data and run tests
if [[ ${skiptest} == "true" ]]; then
  echo "Skipping tests!!"
else
  # copy test data and run tests
  echo "Running tests..."
  local_test_dir=${CWD}/src/bb-node/tests
  cp -R ${local_test_dir} ${build_dir}
  bash ${CWD}/scripts/run_tests.sh ${deb_pkg_name} ${build_dir}/tests
  if [[ $? != 0 ]]; then
    echo "[ERROR] Tests failed!!"
    rm -rf ${bloomgateway_prefix}
    rm -rf ${build_dir}
    exit 1
  fi
fi

# display information
rm -rf ${bloomgateway_prefix}
ls ${build_root_dir}/bloomgateway_${version}_*.deb
echo "[SUCCESS] Package ${deb_pkg_name} is at ${build_root_dir}"
