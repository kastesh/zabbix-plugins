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
# URL for providers with external pings
. $PROGPATH/external_ping_vars.sh || exit 1

CURLCMD="/usr/bin/curl -s"
CONNECT_TIMEOUT=30
MAX_TIMEOUT=300
AGENT_STRING="Mozilla/4.0 (compatible; MSIE 6.01; Windows NT 6.0)"
CURLCMD=$CURLCMD" --connect-timeout $CONNECT_TIMEOUT --max-time $MAX_TIMEOUT"

print_usage(){
  code=$1
  echo "Usage: $PROGNAME [-hv] -m status|send|receive|min|avg|max -u url_name -i ip -d post_name -t 1|2|3"
  echo " -m   - metric name"
  echo " -u   - requested url"
  echo " -i   - ip address - finished url string"
  echo " -d   - post request data - if defined IP address finished it"
  echo " -t   - type used check:"
  echo "        1: create cache file; not return data for zabbix"
  echo "        2: create cache file; used it (default)"
  echo "        3: not created cache file; but used it for return data to zabbix"
  echo "        this option helps separate long test (crond) from quick zabbix_agent check"
  echo 
  exit $code
}

var_to_value(){
  var_name=$1
  
  eval "var_value=\$$var_name"
  [[ $VERBOSE -gt 0 ]] && echo $var_value
  [[ -z $var_value ]] && exit 1
}

# status:
# 0 - OK: send pings = receive pings
# 1 - Warning: send pings > receive pings
# 2 - Critical:  receive pings = 0
# 3 - Unknown: Remote server return error
# 4 - Unknown: Result is empty
# 5 - Unknown: We need to correct awk script
service_cache(){
  url_var=$1
  metric_cache=$2
  ip=$3
  post_var=$4

  # get url from variable name
  var_to_value $url_var
  url=$var_value
  if [[ -n $post_var ]]; then
    var_to_value $post_var
    post=$var_value
    post=${post}${ip}
  else
    url=${url}${ip}
  fi
 
  # cache command and lock file
  url_cache=${metric_cache}.tmp
  # test if there is other cache creation process
  [[ -f $url_cache ]] && exit 1

  if [[ -z $post_var ]]; then
    $CURLCMD -A "$AGENT_STRING" "$url" >$url_cache 2>&1
  else
    $CURLCMD -A "$AGENT_STRING" --data "$post" "$url" >$url_cache 2>&1
  fi

  if [[ $? -gt 0 ]]; then
    echo "status:3" > $metric_cache
  else
    result_ping=$(cat $url_cache | \
     tr -d '\0' | \
     sed -e 's/<[^>]*>/\n/g;' | \
     egrep -e "^Success" -e "packet loss"  -e "^round-trip" -e "^rtt" -e "packet loss" | \
     sed -e 's/\([0-9{1,}]\) received/\1 packets received/' -e 's/time [0-9]*ms//')
    if [[ -z "$result_ping" ]]; then
      echo "status:4" > $metric_cache
    else
      echo ${result_ping} | \
       awk '$0~/packet loss/{print $1,$4, $13;} $0~/^Success/{print $6, $10;}' - | \
       sed -e 's/[\(\)\,]//g' -e 's/[ \/]/;/g' | \
       awk -F';' 'BEGIN{status=5; p_loss=0; p_receive=0}\
       {if (NF == 6){max=$5;} else {max=$6;};\
        if ($2 == 0)\
          status=2;\
        else if ($2<$1)\
          status=1;\
        else\
          status=0;\
        if ($1>0){\
          p_receive=$2*100/$1;\
          p_loss=100-p_receive;\
        };\
        printf "p_loss:%.2f\np_receive:%.2f\nstatus:%s\nsend:%s\nreceive:%s\nmin:%s\navg:%s\nmax:%s\n",p_loss,p_receive,status,$1,$2,$3,$4,max;\
       }' > $metric_cache
    fi
  fi
  # delete lock file
  rm -f $url_cache
}

service_status(){
  metric=$1   # metric_name: status,max,min,avg,send,receive
  url_var=$2  # url variable
  cache=$3    # 1 - create cache, 
              # 2 - get data (if cache old, it will create/update the cache file), 
              # 3 - get data (if cache exist, doesn't create new)
  ip=$4       # ip address, if exists add to the end of the url string
  post_var=$5     # post request variable name

  [[ ( -z $metric ) || ( -z $url_var ) ]] && exit 1
  [[ -z $cache ]] && cache=2
  
  metric_cache=${TMPFILE}_${url_var}_${ip}
  metric_ttl=299

  if [[ $cache -eq 1 ]]; then
    service_cache "$url_var" "$metric_cache" "$ip" "$post_var"
    exit 1
  fi

  # need new cache
  use_cache=$(test_cache $metric_cache $metric_ttl)
  if [[ $use_cache -eq 1 ]]; then
    if [[ $cache -eq 2 ]]; then
      service_cache "$url_var" "$metric_cache" "$ip" "$post_var"
    fi
  fi
  grep "^$metric:" $metric_cache | cut -d':' -f2
}

while getopts ":m:i:u:d:c:vh" opt; do
  case $opt in
    "m")
      METRIC=$OPTARG            # requested metric
      ;;
    "u")
      URL_VAR=$OPTARG           # url name
    ;;
    "i")
      IP=$OPTARG                # IP address
    ;;
    "c")
      CACHE=$OPTARG             # cache type
    ;;
    "d")
      POST_VAR=$OPTARG              # post request name
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

service_status "$METRIC" "$URL_VAR" "$CACHE" "$IP" "$POST_VAR"
