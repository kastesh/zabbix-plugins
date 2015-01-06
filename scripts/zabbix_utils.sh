# common scripts for zabbix

# print verbose message to log file
print_to_log(){
  message=$1

  if [[ ( $VERBOSE -gt 0 ) && ( -n "$LOGFILE" ) ]]; then
    log_date=$(date +'%Y-%m-%dT%H:%M:%S')
    printf "%-14s: %6d: %s\n" "$log_date" "$$" "$message" >> $LOGFILE
  fi
}

# print debug
print_debug(){
  msg=$1
  [[ $DEBUG -gt 0 ]] && echo "$msg"
}

# get server and host optionf for sender
function get_agent_info {

  # get zabbix server name or address
  if [[ "$SERVER" = "" ]]; then
    SERVER=$(grep -v "^$\|^#" $CONFFILE | grep "Server=" | \
      awk -F'=' '{print $2}' | awk -F',' '{print $1}')
  fi

  # get hostname
  if [[ "$HOST" = "" ]]; then
    HOST=$(grep -v "^$\|^#" $CONFFILE | grep "Hostname=" | \
      awk -F'=' '{print $2}' | awk -F',' '{print $1}')
  fi

  print_to_log "Server=$SERVER; Hostname=$HOST"
}

# create zabbix send file
save_in_send(){
  key1=$1
  key2=$2
  value=$3

  ZABBIX_PREFIX="ext_"${TEST}"."$TST_TYPE

  printf "%-20s %-40s %-20s %.2f\n" \
    "${HOST}" "${ZABBIX_PREFIX}[$key1,$key2]"  "$DATE_TM"  "$value"  >> $TMPFILE
}

# create cache zabbix file
save_in_cache(){
  key1=$1
  key2=$2
  value=$3

  echo "${key1}:${key2}:$value" >> $TMPFILE
}

# send statistics to zabbix server or proxy
send_statuses(){
  not_cron=$1

  ZABBIX_TRAP=$(zabbix_sender --zabbix-server ${SERVER} --host $HOST -i $TMPFILE --with-timestamps)
  ZABBIX_FAILED=$(echo $ZABBIX_TRAP | egrep -o 'failed: [0-9]+' | awk '{print $2}')

  print_to_log "DataFile=$TMPFILE SendFailed=$ZABBIX_FAILED"
  print_to_log "zabbix_sender --zabbix-server ${SERVER} --host $HOST -i $TMPFILE --with-timestamps"

  # if no failed sending => delete send file and check for old data
  if [[ $ZABBIX_FAILED -eq 0 ]]; then
    rm -f $TMPFILE >> /dev/null
  else
    [[ $VERBOSE -eq 0 ]] && rm -f $TMPFILE >> /dev/null
  fi

  [[ $not_cron -gt 0 ]] && echo 1
}

# test cache file
# return 0 => when cache file can be used
# return 1 => when cache must be revalidate
test_cache(){
  cache_file=$1
  cache_age=$2
  exec_time=$3

  [[ -z $exec_time ]] && exec_time=2

  if [[ ! -f $cache_file ]]; then
    echo 1
  else
    cache_time=$(stat -c"%Y" "${cache_file}")
    now_time=$(date +%s)
    delta_time=$(($now_time - $cache_time))

    if [[ $delta_time -lt $exec_time ]]; then
      sleep $(($exec_time - $delta_time))
      echo 0
    elif [[ $delta_time -gt $cache_age ]]; then
      echo 1
    fi
  fi
}

# from list element and descovery avriable name => pritn json
echo_simple_json(){
  list=$1
  var=$2

  if [[ -n ${list} ]]; then
    JSON="{ \"data\":["
    JSON_EL=0
    for el in ${list}; do
      [[ $JSON_EL -eq 1 ]] && JSON=${JSON}','
      JSON=${JSON}"{\"{#$var}\":\"$el\"}"
      JSON_EL=1
    done
    JSON=${JSON}"]}"
    echo "$JSON"
  fi
}

# echo multivalue json
# input: key1=valueX;key2=valueY;key3=>valueK key1=>valueM;key2=valueB...
# output: [{key1:valueX,key2:valueY,key3:valueK},..]
echo_multi_json(){
  list=$1

  if [[ -n "$list" ]]; then
    JSON="{ \"data\":["
    JSON_EL=0
    for el in $list; do
      [[ $JSON_EL -eq 1 ]] && JSON=${JSON}','
      JSON_EL=1
      key_id=0
      JSON=$JSON"{"
      for pare in $(echo $el| sed -e 's/;/ /g'); do
        [[ $key_id -gt 0 ]] && JSON=${JSON}','
        key=$(echo "$pare" | awk -F'=' '{print $1}')
        val=$(echo "$pare" | awk -F'=' '{print $2}')
        JSON=$JSON"\"{#$key}\":\"$val\""
        key_id=$(( $key_id+1 ))
      done
      JSON=$JSON"}"
    done
    JSON=${JSON}"]}"
    echo $JSON
  fi
}
