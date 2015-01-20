#!/bin/bash
# test powerdns service, use /etc/init.d/pdns 
# notes: rnds stats
# usage in template via zabbix agent
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

. $PROGPATH/zabbix_utils.sh || exit 1

print_usage(){
  code=$1
  echo "Usage: $PROGNAME [-hv] -m status -i pdns_name"
  echo " or"
  echo "Usage: $PROGNAME [-hv] -m discovery"
  exit $code
}

service_discovery(){
  pdns_services=$(/sbin/chkconfig --list | \
   grep '^pdns' | awk '/[234]:on/{printf "%s ",$1}')
  [[ -z $pdns_services ]] && exit 1
  pdns_services=$(echo "$pdns_services" | sed -e 's/\s\+$//')

  echo_simple_json "$pdns_services" "PDNS_NAME"
}

service_status(){
  metric=$1
  srv_name=$2

  [[ -z $metric ]] && exit 1
  [[ "$metric" == "discovery" ]] && service_discovery

  [[ -z $srv_name ]] && exit 1
  status_cmd="sudo /etc/init.d/$srv_name status"
  dump_cmd="sudo /etc/init.d/$srv_name dump"

  if [[ "$metric" == "status" ]]; then  
    $status_cmd | grep '[0-9]\+: Child running on pid [0-9]\+' -c
  else
    metric_cache=${TMPFILE}_$(echo "$srv_name" | md5sum | awk '{print $1}')
    metric_ttl=56

    use_cache=$(test_cache $metric_cache $metric_ttl)
    if [[ $use_cache -eq 1 ]]; then
      $dump_cmd | sed -e 's/,/\n/g;s/=/:/g;s/-/_/g' >$metric_cache 2>&1
      if [[ $? -gt 0 ]]; then
        print_debug "cmd=\`$dump_cmd\` return error: $(head -1 $metric_cache)"
        rm -f $metric_cache
        exit 1
      fi
    fi
    grep "^$metric:" $metric_cache | cut -d':' -f2
  fi
}

while getopts ":m:i:vh" opt; do
  case $opt in
    "m")
      METRIC=$OPTARG          # requested metric
      ;;
    "i")
      PDNS=$OPTARG            # pdns service name (ex. pdns, pdns-legacy)
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

[[ -z $PDNS ]] && PDNS=pdns

service_status "$METRIC" "$PDNS"
