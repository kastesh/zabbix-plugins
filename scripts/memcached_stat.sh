#!/bin/bash
# discovery status for memcached by stats command
# usage in template via zabbix agent
# additional info: 
# http://www.pal-blog.de/entwicklung/perl/memcached-statistics-stats-command.html
# ex
export LC_ALL=""
export LANG="en_US.UTF-8"
export PATH=$PATH:/sbin:/usr/sbin:$HOME/bin

PROGNAME=$(basename $0)
PROGPATH=$(dirname $0)
VERBOSE=0
TEST=$(echo $PROGNAME| sed -e 's/\.sh$//')
CACHESEC=55
DATE_TM=$(date +%s)

TMPDIR=/dev/shm
[[ ! -d $TMPDIR ]] && TMPDIR=/tmp

WORKDIR=/home/zabbix
[[ ! -d $WORKDIR ]] && WORKDIR=/var/lib/zabbix/local

LOGDIR=$WORKDIR/log
[[ ! -d $LOGDIR ]]  && mkdir $LOGDIR
LOGFILE=$LOGDIR/$TEST.log
TMPFILE=$TMPDIR/${TEST}
DEFAULT_CONNECT="127.0.0.1:11211"

# SOCAT CMD, for unix-socket you need add zabbix user to promary memcached group
SOCATCMD="/usr/bin/socat"
[[ -x $SOCATCMD ]] || exit 1

PGREP="sudo /usr/bin/pgrep -x"

. $PROGPATH/zabbix_utils.sh || exit 1

print_usage(){
  code=$1
  echo "Usage: $PROGNAME [-hv] -m uptime|..|discovery|process -c connect_str"
  echo "Discovery options for memcached:"
  echo " $PROGNAME -m discovery"
  echo
  echo "Get Memcached status options:"
  echo " $PROGNAME -m total_connections -c 127.0.0.1:11211"
  echo "or"
  echo " $PROGNAME -m total_connections -c /var/run/memcached/memcached.socket"
  echo
  exit $code
}

socat_connect_str(){
  connect_str=$1
  
  connect_type=TCP
  [[ $(echo "$connect_str" | grep -c '^/') -gt 0 ]] && connect_type=UNIX 
}

memcached_discovery(){
  # memcached services
  memcached_services=$(/sbin/chkconfig --list | \
   grep '^memcached' | awk '/[234]:on/{print $1}')
  [[ -z $memcached_services ]] && exit 1 

  # create mc_connect string
  mc_list=
  for mc in $memcached_services; do
    mc_config=/etc/sysconfig/$mc
    if [[ -f $mc_config ]]; then
      . $mc_config
      mc_port=$PORT
      mc_host=$HOST
      mc_socket=

      if [[ -n "$OPTIONS" ]]; then
        mc_socket=$(echo "$OPTIONS" | egrep -o '\-s[ ]+[a-Z\.\/\-]+' | awk '{print $2}')
        mc_host=$(echo "$OPTIONS" | egrep -o '\-l[ ]+[a-Z\.\/\-]+' | awk '{print $2}')
      fi

      if [[ -n $mc_socket ]]; then
        mc_list=$mc_list"$mc_socket "
      else
        [[ -z $mc_host ]] && mc_host="127.0.0.1"
        [[ -z $mc_port ]] && mc_port="11211"
        mc_list=$mc_list"$mc_host:$mc_port "
      fi
    fi
  done
  mc_list=$(echo "$mc_list" | sed -e 's/\s\+$//')
  echo_simple_json "$mc_list" "MC_CONNECT"
}

memcached_status(){
  metric=$1
  connect=$2

  [[ ( -z $metric ) && ( -z $connect ) ]] && exit 1

  # create socat connection string
  socat_connect_str "$connect"
  connect="$connect_type:$connect"

  metric_cache=${TMPFILE}_$(echo "$connect" | md5sum | awk '{print $1}')
  metric_ttl=56

  # test if cache file is valid
  use_cache=$(test_cache $metric_cache $metric_ttl)

  # create cache
  if [[ $use_cache -eq 1 ]]; then
    echo stats | $SOCATCMD - "$connect" 2>/dev/null | \
     grep '^STAT' | \
     awk '{printf "%s:%s\n", $2, $3}' >$metric_cache 2>&1
    if [[ $? -gt 0 ]]; then
      print_debug "cmd=\`$SOCATCMD - \"$connect\"\` return error: $(head -1 $metric_cache)"
      rm -f $metric_cache
      exit 1
    fi
  fi

  # get metric
  grep "^$metric:" $metric_cache | awk -F':' '{print $2}'
}

while getopts ":m:c:vh" opt; do
  case $opt in
    "m")
      METRIC=$OPTARG          # requested metric
      ;;
    "c")
      CONNECT=$OPTARG         # memcached connect string
      ;;
    h)
      print_usage 0
      ;;
    v)
      VERBOSE=1
      ;;
    \?)
      print_usage 1
      ;;
  esac
done

[[ -z "$CONNECT" ]] && CONNECT=$DEFAULT_CONNECT

if [[ -z "$METRIC" ]]; then
  print_usage
elif [[ "$METRIC" == "discovery" ]]; then
  memcached_discovery
elif [[ "$METRIC" == "process" ]]; then
  $PGREP "memcached" | wc -l
else
  # try get memcached status
  memcached_status "$METRIC" "$CONNECT"
fi
