#!/bin/bash
# get memcached statistics 
# $1 - opt
# $2 - host
# $3 - port

### ZABBIZ OPTIONS
DEBUG=0
export PATH=$PATH:/sbin:/usr/sbin

# get information for cluster
# send it by trapper
zabbix_prefix='memcached.status'
ZABBIX_BIN=zabbix_sender

zabbix_server=""
zabbix_client=""



### FUNCTIONS
# obtaining data that will be needed to send the values by the zabbix sender
function get_agent_info {
  service_name=$1
  service_check=$2
  service_desc=$3
  
  zabbix_workdir='/home/zabbix'
  [[ -d ${zabbix_workdir}20 ]] && zabbix_workdir=${zabbix_workdir}20
  
  zabbix_cache=$zabbix_workdir/tmp/$service_check
  [[ ! -d $zabbix_cache ]] && mkdir -p $zabbix_cache
  
  zabbix_config=$zabbix_workdir/etc/zabbix-agentd-$service_name.conf
  [[ ! -f $zabbix_config ]] && exit

  # get zabbix server name or address
  if [[ -z $zabbix_server ]]; then
    zabbix_server=$(grep -v "^$\|^#" $zabbix_config | grep "Server="  | cut -d'=' -f2)
    is_several=$(echo "$zabbix_server" | grep -c ',')
    [[ $is_several -gt 0 ]] && zabbix_server=$(echo "$zabbix_server" | cut -d',' -f1)
  fi
  
  # get hostname
  if [[ -z $zabbix_client ]]; then
    zabbix_client=$(grep -v "^$\|^#" $zabbix_config | grep "Hostname="  | cut -d'=' -f2)
    [[ -z $zabbix_client ]] && zabbix_client=$(hostname)
  fi
  
  [[ $DEBUG -gt 0 ]] && printf "%-15s: %s\n%-15s: %s\n" "Client" "$zabbix_client" "Server" "$zabbix_server"

  # date values
  send_date=$(date '+%s')

  # cache/send file
  zabbix_cachefile=$zabbix_cache/${send_date}_$service_desc
}

# send data to zabbix server by sender
function send_by_sender {
  sender_server=$1
  sender_host=$2
  sender_file=$3

  SENDER_DATA=`$ZABBIX_BIN --zabbix-server $sender_server -s $sender_host -i $sender_file  --with-timestamps`
  SENDER_FAILED=$(echo $SENDER_DATA | egrep -o 'Failed [0-9]+' | awk '{print $2}')

  [[ $DEBUG -gt 0 ]] && printf "%-15s: %s\n" "Temp file" "$sender_file"
  [[ $DEBUG -gt 0 ]] && printf "%-15s: %s\n" "Failed" "$SENDER_FAILED"
  # check is data send or not
  if [[ $SENDER_FAILED -eq 0 ]]; then
    #[[ $DEBUG -eq 0 ]] && rm -f $sender_file
    echo 0
    exit 0
  fi
  echo 1
  exit 1
}

# function send info by simple check
function memcached_by_one {
  mcopt=$1
  mcsrv=$2
  mcprt=$3
  
  /usr/bin/memcached-tool $mcsrv:$mcprt stats | grep -v '^#' | sed -e 's/^\s\+//' | grep "^$mcopt " | awk '{print $2}'
  exit 0
}

# function send info by trapper
function memcached_by_all {
  mcsrv=$1
  mcprt=$2
  
  mcopts='version\|uptime\|bytes_read\|bytes_written\|total_connections\|get_hits\|get_misses\|total_items\|evictions\|cmd_get\|cmd_set\|limit_maxbytes\|bytes'
  mcdata=$(/usr/bin/memcached-tool $mcsrv:$mcprt stats | grep -v '^#' | sed -e 's/^\s\+//' | grep "^\($mcopts\) " | sed -e 's/\s\+$//' | sed -e 's/\s\+/:/')
  if [[ -n "$mcdata" ]]; then
    for data in $mcdata
    do
      mckey=$(echo $data| cut -d':' -f1)
      mcval=$(echo $data| cut -d':' -f2)
      [[ $DEBUG -gt 0 ]] && printf "%-20s: %20s\n" "$mckey" "$mcval"
      printf "%-20s %-40s %-20s %s\n" "$zabbix_client" "$zabbix_prefix[$mckey,$mcsrv,$mcprt]"  "$send_date"  "$mcval"  >> $zabbix_cachefile
    done
  else
    printf "Not found options\n"
    exit 1
  fi
  
}


#### MAIN PART
opt=$1
srv=$2
prt=$3
cln=$4

[[ -z $opt ]] && exit 1
[[ -z $srv ]] && srv="127.0.0.1"
[[ -z $prt ]] && prt="11211"

case $opt in
  "all")
  get_agent_info "$cln" "$zabbix_prefix" "${srv}_${prt}"
  memcached_by_all "$srv" "$prt"
  send_by_sender $zabbix_server $zabbix_client $zabbix_cachefile
  ;;
  version|uptime|bytes_read|bytes_written|total_connections|get_hits|get_misses|total_items|evictions|cmd_get|cmd_set|limit_maxbytes|bytes)
  memcached_by_one $opt $srv $prt
  ;;
  *)
    exit
  ;;
esac