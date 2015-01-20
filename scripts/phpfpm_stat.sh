#!/bin/bash
# discovery status for php-fpm by status and ping
# usage in template via zabbix agent
# additional info:
# https://rtcamp.com/tutorials/php/fpm-status-page/
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
DEFAULT_URL="http://127.0.0.1/phpfpm_status"

CONNECT_TIMEOUT=5
MAX_TIMEOUT=25
CURLCMD="/usr/bin/curl -k"
CURLCMD=$CURLCMD" --connect-timeout $CONNECT_TIMEOUT --max-time $MAX_TIMEOUT"

PGREP="sudo /usr/bin/pgrep -x"

. $PROGPATH/zabbix_utils.sh || exit 1

print_usage(){
  code=$1
  echo "Usage: $PROGNAME [-hv] -m start_time|accepted_conn|listen_queue|listen_queue_len|idle_processes|active_processes|total_processes|ping|process -u url"
  echo " $PROGNAME -m TotalAccesses -u http://127.0.0.1:8081/phpfpm_status"
  echo
  exit $code
}

phpfpm_ping(){
  url=$1

  [[ -z $url ]] && exit 1
  metric_cache=${TMPFILE}_$(echo "$url" | md5sum | awk '{print $1}')
  $CURLCMD -s "$url" >$metric_cache 2>&1
  if [[ $? -gt 0 ]]; then
    print_debug "cmd=\`$CURLCMD -s \"$url\"\` return error: $(head -1 $metric_cache)"
    rm -f $metric_cache
    echo 0
    exit
  fi
  grep -c "pong" $metric_cache
}

phpfpm_status(){
  url=$1
  metric=$2

  [[ ( -z $metric ) || ( -z $url ) ]] && exit 1

  metric_cache=${TMPFILE}_$(echo "$url" | md5sum | awk '{print $1}')
  metric_ttl=56

  # test if cache file is valid
  use_cache=$(test_cache $metric_cache $metric_ttl)

  # create cache
  if [[ $use_cache -eq 1 ]]; then
    $CURLCMD -s "$url" | \
     grep -v '\(start time\|pool\|process manager\):' | \
     awk -F':' '{gsub(/[ ]+/,"_",$1);printf "%s:%d\n",$1,$2}' >$metric_cache 2>&1
    if [[ $? -gt 0 ]]; then
      print_debug "cmd=\`$CURLCMD -s \"$url\"\` return error: $(head -1 $metric_cache)"
      rm -f $metric_cache
      exit 1
    fi
  fi

  # get metrics
  grep "^$metric:" $metric_cache | awk -F':' '{print $2}'
}

while getopts ":m:u:vh" opt; do
  case $opt in
    "m")
      METRIC=$OPTARG          # requested metric
      ;;
    "u")
      URL=$OPTARG             # http url with nginx stab info
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

[[ -z "$URL" ]] && URL=$DEFAULT_URL

if [[ $METRIC == "ping" ]]; then
  phpfpm_ping "$URL"
elif [[ $METRIC == "process" ]]; then
  $PGREP "php-fpm" | wc -l
else
  phpfpm_status "$URL" "$METRIC"
fi

