#!/bin/bash

# auth ksh770
# get status from php-fpm info

var=$1  # variable from php-fpm status
url=$2  # url on server(ex. http://localhost/fpm_status)

[[ -z "$var" || -z "$url" ]] && exit 1

curlcmd=/usr/bin/curl
[[ ! -x $curlcmd ]] && exit 1

cache_ttl=55                                  # use cache data 
url_md5=$(echo $url | md5sum | cut -d" " -f1) # md5 sum
cache_file=/dev/shm/phpfpmstat-$url_md5.cache

# check file exists and contains data => get change time for file
cache_tm=0
check_tm=$(date +%s)
[[ -s $cache_file ]] && cache_tm=$(stat -c"%Z" $cache_file)

# test change cache time and current time
if [[ $(($check_tm - $cache_tm)) -gt $cache_ttl ]]; then
  $curlcmd -s "$url" >$cache_file 2>/dev/null || exit 1
fi

# output requested variable
case "$var" in
  "pool")
    awk -F':' '/^pool:/{print $2}' $cache_file | sed -e 's/^\s\+//;s/\s\+$//;'
    ;;
  "pm")
    awk -F':' '/^process manager:/{print $2}' $cache_file | sed -e 's/^\s\+//;s/\s\+$//;'
    ;;
  "start_time")
    awk -F':' '/^start time:/{print $2}' $cache_file | sed -e 's/^\s\+//;s/\s\+$//;'
    ;;
  "start_since")
    awk -F':' '/^start since:/{print $2}' $cache_file | sed -e 's/^\s\+//;s/\s\+$//;'
    ;;
  "accepted_conn")
    awk -F':' '/^accepted conn:/{print $2}' $cache_file | sed -e 's/^\s\+//;s/\s\+$//;'
    ;;
  "listen_queue")
    awk -F':' '/^listen queue:/{print $2}' $cache_file | sed -e 's/^\s\+//;s/\s\+$//;'
    ;;
  "max_listen_queue")
    awk -F':' '/^max listen queue:/{print $2}' $cache_file | sed -e 's/^\s\+//;s/\s\+$//;'
    ;;
  "listen_queue_len")
    awk -F':' '/^listen queue len:/{print $2}' $cache_file | sed -e 's/^\s\+//;s/\s\+$//;'
    ;;
  "idle_processes")
    awk -F':' '/^idle processes:/{print $2}' $cache_file | sed -e 's/^\s\+//;s/\s\+$//;'
    ;;
  "active_processes")
    awk -F':' '/^active processes:/{print $2}' $cache_file | sed -e 's/^\s\+//;s/\s\+$//;'
    ;;
  "total_processes")
    awk -F':' '/^total processes:/{print $2}' $cache_file | sed -e 's/^\s\+//;s/\s\+$//;'
    ;;
  "max_active_processes")
    awk -F':' '/^max active processes:/{print $2}' $cache_file | sed -e 's/^\s\+//;s/\s\+$//;'
    ;;
  "max_children_reached")
    awk -F':' '/^max children reached:/{print $2}' $cache_file | sed -e 's/^\s\+//;s/\s\+$//;'
    ;;
  "slow_requests")
    awk -F':' '/^slow requests:/{print $2}' $cache_file | sed -e 's/^\s\+//;s/\s\+$//;'
    ;;
  "ping")
    [[ $(grep -c "pong" $cache_file) -gt 0 ]] && echo 1 || echo 0
    ;;
  *)
    exit 1
    ;;
esac


