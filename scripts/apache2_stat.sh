#!/bin/bash
# discovery status for apache by status_module
# usage in template via zabbix agent
# additional info: 
# http://httpd.apache.org/docs/2.2/mod/mod_status.html
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
DEFAULT_URL="http://127.0.0.1/apache_status"

CONNECT_TIMEOUT=5
MAX_TIMEOUT=25
CURLCMD="/usr/bin/curl -k"
CURLCMD=$CURLCMD" --connect-timeout $CONNECT_TIMEOUT --max-time $MAX_TIMEOUT"

PGREP="sudo /usr/bin/pgrep -x"

. $PROGPATH/zabbix_utils.sh || exit 1

print_usage(){
  code=$1
  echo "Usage: $PROGNAME [-hv] -m TotalAccesses|TotalkBytes|CPULoad|Uptime|ReqPerSec|BytesPerSec|BytesPerReq|BusyWorkers|IdleWorkers|TotalWorkers|process -u url"
  echo " $PROGNAME -m TotalAccesses -u http://127.0.0.1:8881/apache_status"
  echo
  exit $code
}

apache_status(){
  url=$1
  metric=$2

  [[ ( -z $metric ) || ( -z $url ) ]] && exit 1

  metric_cache=${TMPFILE}_$(echo "$url" | md5sum | awk '{print $1}')
  metric_ttl=56

  # test if cache file is valid
  use_cache=$(test_cache $metric_cache $metric_ttl)

  # create cache
  if [[ $use_cache -eq 1 ]]; then
    $CURLCMD -s "$url?auto" | \
     grep -v 'Scoreboard' | sed -e 's/\s\+//g' | \
     awk -F':' '{printf "%s:%.2f\n",$1,$2}' >$metric_cache 2>&1
    if [[ $? -gt 0 ]]; then
      print_debug "cmd=\`$CURLCMD -s \"$url\"\` return error: $(head -1 $metric_cache)"
      rm -f $metric_cache
      exit 1
    fi
  fi

  # use cache
  case "$metric" in
    "TotalWorkers")   
      IdleWorkers=$(grep '^IdleWorkers:' $metric_cache | cut -d':' -f2)
      BusyWorkers=$(grep '^BusyWorkers:' $metric_cache | cut -d':' -f2)
      TotalWorkers=$(echo "$IdleWorkers+$BusyWorkers" | bc)
      echo $TotalWorkers
      ;;
    "process")  $PGREP "$url" | wc -l ;;
    TotalAccesses|TotalkBytes|CPULoad|Uptime|ReqPerSec|BytesPerSec|BytesPerReq|BusyWorkers|IdleWorkers)
    grep "^$metric:" $metric_cache | cut -d':' -f2 ;;
    *)
      print_debug "Cannot use metric=$metric"
      exit
    ;;
  esac
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

apache_status "$URL" "$METRIC"

