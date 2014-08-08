#!/bin/sh

### system resource usage by proccess type (process name)
### auth by ksh770
### modify 08.08.2014
### send values to server by trigger
export PATH=$PATH:/sbin:/usr/sbin:$HOME/bin
export LANG=en_US.UTF-8

PROGNAME=$(basename $0)
PROGPATH=$(dirname $0)
VERBOSE=0
TEST=$(echo $PROGNAME| sed -e 's/\.sh$//')
DATE_TM=$(date +%s)

TMPDIR=/dev/shm
[[ ! -d $TMPDIR ]] && TMPDIR=/tmp

WORKDIR=/home/zabbix
[[ ! -d $WORKDIR ]] && WORKDIR=/var/lib/zabbix

CONFFILE=/etc/zabbix/zabbix_agentd.conf
[[ ! -f $CONFFILE ]] && CONFFILE=$WORKDIR/etc/zabbix_agentd.conf

LOGDIR=$WORKDIR/log
[[ ! -d $LOGDIR ]]  && mkdir $LOGDIR
LOGFILE=$LOGDIR/$TEST.log
TMPFILE=$TMPDIR/${DATE_TM}_${TEST}

SERVER=""       # Zabbix Server from config file
HOST=""         # Zabbix Client Name from config file

which bc 1>/dev/null 2>&1
if [[ $? -gt 0 ]]; then
  echo "Not found bc util, yum install bc"
  exit 1
fi

# default values
TST_TYPE="status"
SRV_DESR="mysqld:3306;php-fpm:9000;nginx:80,443;memcached:11211"


print_usage(){
  code=$1

  echo "Usage: $PROGNAME [-hv] [-t status|network] [-d services_description]"
  echo "Options: "
  echo " -h - print help message"
  echo " -v - print verbode info"
  echo " -t - type requested variables (default: status)"
  echo " -d - services description(default: mysqld:3306;php-fpm:9000;nginx:80,443;memcached:11211)"
  echo "Ex."
  echo " $PROGNAME -t status -d mysqld:3306;php-fpm:9000,9001;nginx:80,443;memcached:11211"
  echo

  exit $code
}

print_to_log(){
  message=$1

  if [[ ( $VERBOSE -gt 0 ) && ( -n "$LOGFILE" ) ]]; then
    log_date=$(date +'%Y-%m-%dT%H:%M:%S')
    printf "%-14s: %6d: %s\n" "$log_date" "$$" "$message" >> $LOGFILE
  fi
  
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
#
# create zabbix send file
#
save_in_send(){
  key=$1
  service=$2
  value=$3

  ZABBIX_PREFIX="ext_"${TEST}"."$TST_TYPE

  printf "%-20s %-40s %-20s %.2f\n" \
    "${HOST}" "${ZABBIX_PREFIX}[$key,$service]"  "$DATE_TM"  "$value"  >> $TMPFILE
}

#
# get status for process from PS util
#       pcpu         cpu utilization0
#       vsize        total VM size in kB
#       rss          resident set size
#       pmem         ratio of the process’s resident set size  to the physical memory on the machine, expressed as a percentage. (alias pmem)
get_ps_status(){
  points=$1

  PS_SNAPSHOT=$(ps axo vsize,rss,%mem,pcpu,comm,args)     # for all process in the system
  CPU_COUNT=$(cat /proc/cpuinfo | grep -c "^processor")   # core and threads
  print_to_log "CPU and Memory status for processes"

  TARGET_PCPU=0 # CPU usage by all services in definition
  TARGET_PMEM=0
  TARGET_VSIZE=0
  TARGET_RSS=0

  TOTAL_VSIZE=$(echo "$PS_SNAPSHOT"  | awk '{sum+=$1} END {printf "%.2f",sum*1024}')
  TOTAL_RSS=$(echo "$PS_SNAPSHOT"    | awk '{sum+=$2} END {printf "%.2f",sum*1024}')
  TOTAL_PMEM=$(echo "$PS_SNAPSHOT"   | awk '{sum+=$3} END {printf "%.2f",sum}')
  TOTAL_PCPU=$(echo "$PS_SNAPSHOT"   | awk '{sum+=$4} END {printf "%.2f",sum}')
  TOTAL_PCPU_BYCORE=$(echo "$PS_SNAPSHOT" | \
    awk -v cpu=$CPU_COUNT '{sum+=$4} END {printf "%.2f",sum/cpu}')

  print_to_log "Count options for complete system"
  print_to_log "VSIZE=${TOTAL_VSIZE}B RSS=${TOTAL_RSS}B PMEM=$TOTAL_PMEM PCPU=$TOTAL_PCPU PCPU_PER_CORE=$TOTAL_PCPU_BYCORE"


  IFS_BAK=$IFS
  IFS=$';'
  for service_descr in $points; do
    service=$(echo "$service_descr"  | awk -F':' '{print $1}')
    ports=$(echo "$service_descr" | awk -F':' '{print $2}')

    pcpu_item=$(echo "$PS_SNAPSHOT"  | grep -w "$service" | \
      grep -v "$0"| grep -v 'zabbix' | grep -v grep | \
      awk -v cpu=$CPU_COUNT '{sum+=$4} END {printf "%.2f",sum/cpu}')
    save_in_send "pcpu" "$service" "$pcpu_item"

    pmem_item=$(echo "$PS_SNAPSHOT"  | grep -w "$service" | \
      grep -v "$0"| grep -v 'zabbix' | grep -v grep | \
      awk '{sum+=$3} END {printf "%.2f",sum}')
    save_in_send "pmem" "$service" "$pmem_item"

    rss_item=$(echo "$PS_SNAPSHOT"   | grep -w "$service" | \
      grep -v "$0"| grep -v 'zabbix' | grep -v grep | \
      awk '{sum+=$2} END {printf "%.2f",sum*1024}')
    save_in_send "rss" "$service" "$rss_item"

    vsize_item=$(echo "$PS_SNAPSHOT" | grep -w "$service" | \
      grep -v "$0"| grep -v 'zabbix' | grep -v grep | \
      awk '{sum+=$1} END {printf "%.2f",sum*1024}')
    save_in_send "vsize" "$service" "$vsize_item"

    TARGET_PCPU_BYCORE=$(echo "scale=3; $TARGET_PCPU+$pcpu_item" | bc)
    TARGET_PMEM=$(echo "scale=3; $TARGET_PMEM+$pmem_item" | bc)
    TARGET_VSIZE=$(echo "$TARGET_VSIZE+$vsize_item" | bc)
    TARGET_RSS=$(echo "$TARGET_RSS+$rss_item" | bc)
  done

  IFS=$IFS_BAK
  IFS_BAK=

  pcpu_other=$( echo "scale=3; $TOTAL_PCPU_BYCORE-$TARGET_PCPU_BYCORE"   |bc)
  save_in_send "pcpu" "others" "$pcpu_other"
  pmem_other=$( echo "scale=3; $TOTAL_PMEM-$TARGET_PMEM"   |bc)
  save_in_send "pmem" "others" "$pmem_other"
  vsize_other=$( echo "$TOTAL_VSIZE-$TARGET_VSIZE"   |bc)
  save_in_send "vsize" "others" "$vsize_other"
  rss_other=$( echo "$TOTAL_RSS-$TARGET_RSS"   |bc)
  save_in_send "rss" "others" "$rss_other"
}

# get network statistics by SS util
# http://tcpipguide.com/free/t_TCPOperationalOverviewandtheTCPFiniteStateMachineF-2.htm
get_ss_status(){
  points=$1

  print_to_log "Network status for processes"

  TCP_DATA=$(ss -ant  | grep -v "^State\s\+")
  TCP_TOTAL=$(echo "$TCP_DATA" | wc -l)
  UDP_TOTAL=$(ss -anu | grep -v "^State\s\+" | wc -l)
  FS_TOTAL=$(ss -anx  | grep -v "^State\s\+" | wc -l)

  print_to_log "TCP=$TCP_TOTAL UDP=$UDP_TOTAL FS=$FS_TOTAL"
  save_in_send "tcp" "all" $TCP_TOTAL
  save_in_send "udp" "all" $UDP_TOTAL
  save_in_send "file_socket" "all" $FS_TOTAL

  # statistics by connection type, only status
  ESTAB=0
  SYN_SENT=0
  SYN_RECV=0
  FIN_WAIT_1=0
  FIN_WAIT_2=0
  TIME_WAIT=0
  CLOSE_WAIT=0
  LAST_ACK=0
  CLOSING=0
  LISTEN=0
  TOTAL=$TCP_TOTAL

  TCP_STATS=$(echo "$TCP_DATA" | awk '{print $1}' | sort | uniq -c)
  IFS_BAK=$IFS
  IFS=$'\n'
  for STATE2COUNT in $TCP_STATS; do
    state_count=$(echo "$STATE2COUNT" | awk '{print $1}')
    state_name=$(echo "$STATE2COUNT" | awk '{print $2}')
    print_to_log "$state_name: $state_count"

    total_state_var=$(echo "$state_name" | sed -e 's/\-/_/g')
    
    eval "$total_state_var=$state_count"  # set variables ESTAB, SYNC_SENT and etc.

    save_in_send "$state_name" "all" "$state_count"
  done
  IFS=$IFS_BAK
  IFS_BAK=

  print_to_log "ESTAB=$ESTAB LISTEN=$LISTEN TIME_WAIT=$TIME_WAIT ..."
  # get IP address for host
  netaddrs=$(ip addr list | egrep -o "inet [0-9.]+" | awk '{print $2}')
  addrs_regex='\('
  for addr in $netaddrs
  do
    # hide dot char
    addr_regex=`echo $addr | sed -e 's/\./\\\./g'`

    addrs_regex=$addrs_regex$addr_regex"\|"
  done
  addrs_regex=$addrs_regex"0\.0\.0\.0\)\:"
  print_to_log "regexp for local ip address: $addrs_regex"

  # statistics for process
  OTHERS_ESTAB=$ESTAB
  OTHERS_SYN_SENT=$SYN_SENT
  OTHERS_SYN_RECV=$SYN_RECV
  OTHERS_FIN_WAIT_1=$FIN_WAIT_1
  OTHERS_FIN_WAIT_2=$FIN_WAIT_2
  OTHERS_TIME_WAIT=$TIME_WAIT
  OTHERS_CLOSE_WAIT=$CLOSE_WAIT
  OTHERS_LAST_ACK=$LAST_ACK
  OTHERS_CLOSING=$CLOSING
  OTHERS_LISTEN=$LISTEN
  OTHERS_TOTAL=$TOTAL

  IFS_BAK=$IFS
  IFS=$';'
  for service_descr in $points; do
    service=$(echo "$service_descr"  | awk -F':' '{print $1}')
    ports=$(echo "$service_descr" | awk -F':' '{print $2}')
    ports_regexp=$(echo "$ports" | sed -e 's/,/\\\|/g')
    socket_regexp="$addrs_regex\($ports_regexp\)"
    print_to_log "regexp for ip:port => $socket_regexp"

    service_estab=$(echo "$TCP_DATA" | \
      grep " $socket_regexp " | grep -cw "ESTAB")
    save_in_send "ESTAB" "$service" "$service_estab"
    OTHERS_ESTAB=$(echo "$OTHERS_ESTAB-$service_estab" | bc)

    service_syn_sent=$(echo "$TCP_DATA" | \
      grep " $socket_regexp " | grep -cw "SYN-SENT")
    save_in_send "SYN-SENT" "$service" "$service_syn_sent"
    OTHERS_SYN_SENT=$(echo "$OTHERS_SYN_SENT-$service_syn_sent" | bc)

    service_syn_recv=$(echo "$TCP_DATA" | \
      grep " $socket_regexp " | grep -cw "SYN-RECV")
    save_in_send "SYN-RECV" "$service" "$service_syn_recv"
    OTHERS_SYN_RECV=$(echo "$OTHERS_SYN_RECV-$service_syn_recv" | bc)

    service_fin_wait1=$(echo "$TCP_DATA" | \
      grep " $socket_regexp " | grep -cw "FIN-WAIT-1")
    save_in_send "FIN-WAIT-1" "$service" "$service_fin_wait1"
    OTHERS_FIN_WAIT_1=$(echo "$OTHERS_FIN_WAIT_1-$service_fin_wait1" | bc)

    service_fin_wait2=$(echo "$TCP_DATA" | \
      grep " $socket_regexp " | grep -cw "FIN-WAIT-2")
    save_in_send "FIN-WAIT-2" "$service" "$service_fin_wait2"
    OTHERS_FIN_WAIT_2=$(echo "$OTHERS_FIN_WAIT_2-$service_fin_wait2" | bc)

    service_time_wait=$(echo "$TCP_DATA" | \
      grep " $socket_regexp " | grep -cw "TIME-WAIT")
    save_in_send "TIME-WAIT" "$service" "$service_time_wait"
    OTHERS_TIME_WAIT=$(echo "$OTHERS_TIME_WAIT-$service_time_wait" | bc)

    service_close_wait=$(echo "$TCP_DATA" | \
      grep " $socket_regexp " | grep -cw "CLOSE-WAIT")
    save_in_send "CLOSE-WAIT" "$service" "$service_close_wait"
    OTHERS_CLOSE_WAIT=$(echo "$OTHERS_CLOSE_WAIT-$service_close_wait" | bc)

    service_last_ack=$(echo "$TCP_DATA" | \
      grep " $socket_regexp " | grep -cw "LAST-ACK")
    save_in_send "LAST-ACK" "$service" "$service_last_ack"
    OTHERS_LAST_ACK=$(echo "$OTHERS_LAST_ACK-$service_last_ack" | bc)

    service_closing=$(echo "$TCP_DATA" | \
      grep " $socket_regexp " | grep -cw "CLOSING")
    save_in_send "CLOSING" "$service" "$service_closing"
    OTHERS_CLOSING=$(echo "$OTHERS_CLOSING-$service_closing" | bc)

    service_listen=$(echo "$TCP_DATA" | \
      grep " $socket_regexp " | grep -cw "LISTEN")
    save_in_send "LISTEN" "$service" "$service_listen"
    OTHERS_LISTEN=$(echo "$OTHERS_LISTEN-$service_listen" | bc)

    service_total=$(echo "$service_estab+$service_syn_sent+$service_syn_recv+$service_fin_wait1+$service_fin_wait2+$service_time_wait+$service_close_wait+$service_last_ack+$service_closing+$service_listen" | bc)
    save_in_send "TOTAL" "$service" "$service_total"
    OTHERS_TOTAL=$(echo "$OTHERS_TOTAL-$service_total" | bc)

  done
  IFS=$IFS_BAK
  IFS_BAK=
 
  save_in_send "ESTAB" "others" "$OTHERS_ESTAB"
  save_in_send "SYN-SENT" "others" "$OTHERS_SYN_SENT"
  save_in_send "SYN-RECV" "others" "$OTHERS_SYN_RECV"
  save_in_send "FIN-WAIT-1" "others" "$OTHERS_FIN_WAIT_1"
  save_in_send "FIN-WAIT-2" "others" "$OTHERS_FIN_WAIT_2"
  save_in_send "TIME-WAIT" "others" "$OTHERS_TIME_WAIT"
  save_in_send "CLOSE-WAIT" "others" "$OTHERS_CLOSE_WAIT"
  save_in_send "LAST-ACK" "others" "$OTHERS_LAST_ACK"
  save_in_send "CLOSING" "others" "$OTHERS_CLOSING"
  save_in_send "LISTEN" "others" "$OTHERS_LISTEN"
  save_in_send "TOTAL" "others" "$OTHERS_TOTAL"

}

# send statistics to zabbix server or proxy
send_statuses(){


  ZABBIX_TRAP=$(zabbix_sender --zabbix-server ${SERVER} --host $HOST -i $TMPFILE --with-timestamps)
  ZABBIX_FAILED=$(echo $ZABBIX_TRAP | egrep -o 'Failed [0-9]+' | awk '{print $2}')

  print_to_log "DataFile=$TMPFILE SendFailed=$ZABBIX_FAILED"
  print_to_log "zabbix_sender --zabbix-server ${SERVER} --host $HOST -i $TMPFILE --with-timestamps"

  # if no failed sending => delete send file and check for old data

  if [[ $ZABBIX_FAILED -eq 0 ]]; then
    rm -f $TMPFILE >> /dev/null
  else
    [[ $VERBOSE -eq 0 ]] && rm -f $TMPFILE >> /dev/null
  fi
}

# get command line options
while getopts ":d:t:vh" opt; do
  case $opt in
    t)
      TST_TYPE=$OPTARG     # type of testing
      ;;
    d)
      SRV_DESR=$OPTARG      # descriptions for services
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

# get client and service addresses
get_agent_info
TMPFILE=${TMPFILE}_${TST_TYPE}

# create statistics 
case $TST_TYPE in
  status)
    get_ps_status "$SRV_DESR"
    ;;
  network)
    get_ss_status "$SRV_DESR"
    ;;
  *)
    print_usage 1
    ;;
esac

# send statistics to the server
send_statuses

exit 0

