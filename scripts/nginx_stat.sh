#!/bin/bash
# discovery status for devices for nginx by stab module
# usage in template via zabbix agent
# additional info: 
# http://wiki.enchtex.info/howto/zabbix/nginx_monitoring
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
DEFAULT_URL="http://127.0.0.1/nginx_status"

CURLCMD="/usr/bin/curl -k"
PGREP="sudo /usr/bin/pgrep -x"

. $PROGPATH/zabbix_utils.sh || exit 1

print_usage(){
  code=$1
  echo "Usage: $PROGNAME [-hv] -m active|accepts|handled|requests|reading|writing|waiting|process -u url"
  echo " $PROGNAME -m active -u http://127.0.0.1:8080/nginx_status"
  echo
  exit $code
}

nginx_status(){
  url=$1
  metric=$2

  [[ ( -z $metric ) || ( -z $url ) ]] && exit 1

  metric_cache=${TMPFILE}_$(echo "$url" | md5sum | awk '{print $1}')
  metric_ttl=56

  # test if cache file is valid
  use_cache=$(test_cache $metric_cache $metric_ttl)

  # create cache
  if [[ $use_cache -eq 1 ]]; then
    $CURLCMD -s "$url" >$metric_cache 2>&1
    if [[ $? -gt 0 ]]; then
      print_debug "cmd=\`$CURLCMD -s \"$url\"\` return error: $(head -1 $metric_cache)"
      rm -f $metric_cache
      exit 1
    fi
  fi

  # use cache
  case "$metric" in
    "active")   cat $metric_cache | grep "Active connections" | cut -d':' -f2 ;;
    "accepts")  cat $metric_cache | sed -n '3p' | cut -d" " -f2 ;;
    "handled")  cat $metric_cache | sed -n '3p' | cut -d" " -f3 ;;
    "requests") cat $metric_cache | sed -n '3p' | cut -d" " -f4 ;;
    "reading")  cat $metric_cache | grep "Reading" | cut -d':' -f2 | cut -d' ' -f2 ;;
    "writing")  cat $metric_cache | grep "Writing" | cut -d':' -f2 | cut -d' ' -f2 ;;
    "waiting")  cat $metric_cache | grep "Waiting" | cut -d':' -f2 | cut -d' ' -f2 ;;
    "process")  $PGREP nginx | wc -l ;;
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

nginx_status "$URL" "$METRIC"

