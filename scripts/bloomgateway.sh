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

# This scripts helps to start|stop|restart bloomgateway service
export SERVICE_BASE_PATH="/usr/local/bloomgateway"
export SERVICE_BIN_PATH="/usr/local/bloomgateway/bin"
export OPENRESTY_PID="/var/run/bloomgateway.openresty.pid"
export SOCKPROC_PID="/var/run/bloomgateway.sockproc.pid"
export SHELL_SOCK="/tmp/shell.sock"

. /lib/init/vars.sh
. /lib/lsb/init-functions

# usage function
function usage() {
    echo "usage: $0 {start|stop|restart} [-i] <clusterid> [-s] <s3 path>"
    echo "  -i    clusterid while running service in PULL mode"
    echo "  -s    config storage path while running service in PULL mode"
    exit 1
}

# read first arg
if [[ "$1" != "" ]]; then
  cmd=$1
fi

if [[ -z $cmd ]] ; then
  usage
fi

# read optinal remaing args
while [ "$1" != "" ]; do
  case $1 in
    -i) shift
        export clusterid=$1
        ;;

    -s) shift
        export s3basepath=$1
         ;;

    -h) usage ;;
  esac
  shift
done

function start_openresty() {
  local DAEMON_OPTS="-p $SERVICE_BASE_PATH/openresty/nginx -c $SERVICE_BASE_PATH/openresty/nginx/conf/nginx.conf"

  # check if already running
  start-stop-daemon --start --quiet --pidfile $OPENRESTY_PID --exec $SERVICE_BIN_PATH/openresty --test > /dev/null \
    || return 1

  # start the process if not running
  start-stop-daemon --start --quiet --pidfile $OPENRESTY_PID --exec $SERVICE_BIN_PATH/openresty -- \
    $DAEMON_OPTS 2>/dev/null \
    || return 2

  return 0
}

function stop_openresty() {
  start-stop-daemon --stop --quiet --retry=TERM/30/KILL/5 --pidfile $OPENRESTY_PID --name openresty
  RETVAL="$?"
  sleep 1
  return "$RETVAL"
}

function start_sockproc() {
  local DAEMON_OPTS="$SHELL_SOCK $SOCKPROC_PID"
  start-stop-daemon --start --quiet --pidfile $SOCKPROC_PID --exec $SERVICE_BIN_PATH/sockproc --test > /dev/null \
    || return 1

  start-stop-daemon --start --quiet --pidfile $SOCKPROC_PID --exec $SERVICE_BIN_PATH/sockproc -- \
    $DAEMON_OPTS 2>/dev/null \
    || return 2

  sleep 1
  chmod 777 $SHELL_SOCK
  return 0
}

function stop_sockproc() {
  start-stop-daemon --stop --quiet --retry=TERM/30/KILL/5 --pidfile $SOCKPROC_PID --name sockproc
  RETVAL="$?"
  sleep 1
  return "$RETVAL"
}

function start_service() {
  # start openresty --> success -> start sockproc -> success return
  start_openresty
  case "$?" in
    0)
      start_sockproc
      case "$?" in
        0|1)  return 0 ;;
        *)  stop_openresty
            return 1 ;; # Failed to start
      esac
      ;;
    1)
      start_sockproc
      case "$?" in
        0)  return 0 ;;
        1)  log_daemon_msg "service is already running."
            return 0;;
        *)  stop_openresty
            return 1 ;; # Failed to start
      esac
      ;;
    *) return 1 ;;
  esac
  return 0
}

function stop_service() {
  # stop openresty -> failed -> failed to stop
  # stop openresty -> success -> stop sockproc -> failed -> failed
  stop_openresty
  case "$?" in
    0)
      stop_sockproc
      case "$?" in
        0) return 0 ;;
        *) return 1 ;; # Failed to start
      esac
      ;;
    *) return 1 ;;
  esac
  return 0
}

function init_gk_conf() {
  if [[ -z $clusterid || -z $s3basepath ]]; then
    log_daemon_msg "service will start in PUSH config update mode."
    chmod -R 777 $SERVICE_BASE_PATH/openresty/bb/lualib/bb/plugins
    echo "{}" > $SERVICE_BASE_PATH/openresty/nginx/conf/gk.conf
  else
    log_daemon_msg "service will start in PULL config update mode with cluster id:$clusterid and path:$s3basepath"
    echo "{\"cluster_id\" : \"$clusterid\", \"s3basepath\" : \"$s3basepath\"}" > $SERVICE_BASE_PATH/openresty/nginx/conf/gk.conf
  fi
}

case "$cmd" in
  start)  log_daemon_msg "Staring BloomGateway Service"
          init_gk_conf
          start_service
          case "$?" in
            0) log_end_msg 0 ;;
            *) log_end_msg 1 ;; # Failed to start
          esac
          ;;

  restart)log_daemon_msg "Stopping BloomGateway Service"
          stop_service
          case "$?" in
            0)  log_daemon_msg "Staring BloomGateway Service"
                start_service
                case "$?" in
                  0) log_end_msg 0 ;;
                  *) log_end_msg 1 ;; # Old process is still running
                esac
                ;;
            *)  log_end_msg 1 ;; # Failed to stop
          esac
          ;;

  stop) log_daemon_msg "Stopping BloomGateway Service"
            stop_service
            case "$?" in
              0) log_end_msg 0 ;;
              *) log_end_msg 1 ;; # Failed to stop
            esac
            ;;
  *) usage ;; # Failed to start
esac