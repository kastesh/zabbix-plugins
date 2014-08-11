#!/bin/sh

### statistics for disk installed on the server
### auth by ksh770
### modify 10.08.2014
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

TST_TYPE="status"
EXCL_DEV="drbd"
WAITTIME=60         # iostat collects information within the specified time


print_usage(){
  code=$1

  echo "Usage: $PROGNAME [-hv] [-t iostat] [-e exclude_devices]"
  echo "Options: "
  echo " -h - print help message"
  echo " -v - print verbode info"
  echo " -t - type requested variables (default: iostat, smart)"
  echo " -e - list excluded devices from output, comma separeted (default: drbd)"
  echo "Ex."
  echo " $PROGNAME -t status"
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

# create zabbix send file
save_in_send(){
  key=$1
  disk=$2
  value=$3

  ZABBIX_PREFIX="ext_"${TEST}"."$TST_TYPE

  printf "%-20s %-40s %-20s %.2f\n" \
    "${HOST}" "${ZABBIX_PREFIX}[$key,$disk]"  "$DATE_TM"  "$value"  >> $TMPFILE
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

# get iostat info for system's disks
get_iostat() {
  exclude_list=$1

  exclude_regx='\('$(echo "$exclude_list" | sed -e 's/,/\\\|/g')'\)'


  # get iostat info
  CACHEDATA=$(iostat -dkx $WAITTIME 2 2>/dev/null) 

  # iostat output is empty => exit
  if [[ -z "$CACHEDATA" ]]; then
    print_to_log "Cannot get info from iostat"
    exit
  fi

  # different version of iostat => different output, try catch it
  disks_switch=$(echo "$CACHEDATA" | grep -c 'rsec/s')
  print_to_log "iostat_output_switcher=$disks_switch"


  # get disk lables list
  disks_labels=$(echo "$CACHEDATA" | \
   grep -v '^$' | grep -v '^\(Device\|Linux\)' | grep -v "$exclude_regx" | \
   awk '{print $1}' | sort | uniq)

  # process them
  for dl in $disks_labels; do
    print_to_log "processing dl=$dl"


    # get_stats for this disk
    disk_data=$(echo "$CACHEDATA" | grep "^$dl "| tail -1)

    read_request=$(echo "$disk_data"  | awk '{printf "%.2f", $4}')
    write_request=$(echo "$disk_data" | awk '{printf "%.2f", $5}')
    
    # Device:    rrqm/s wrqm/s   r/s   w/s  rsec/s  wsec/s    rkB/s    wkB/s avgrq-sz avgqu-sz   await  svctm  %util
    # sda          0.04  42.05 14.92 43.13   37.44   31.02    18.72    15.51     6.11     0.01    0.89   0.17   0.19
    if [[ $switch -gt 0 ]]; then
    
      read_bytes=` echo "$disk_data" | awk '{printf "%.2f", $8*1024}'`
      write_bytes=`echo "$disk_data" | awk '{printf "%.2f", $9*1024}'`

      await=`      echo "$disk_data" | awk '{printf "%.2f", $12}'`
      utils=`      echo "$disk_data" | awk '{printf "%.2f", $14}'`

    # Device:         rrqm/s   wrqm/s     r/s     w/s    rkB/s    wkB/s avgrq-sz avgqu-sz   await  svctm  %util
    # vda               0.00     5.88    9.02    6.68    31.47    49.07    10.26     0.09    5.69   1.59   2.50
    else
    
      read_bytes=` echo "$disk_data" | awk '{printf "%.2f", $6*1024}'`
      write_bytes=`echo "$disk_data" | awk '{printf "%.2f", $7*1024}'`

      await=`      echo "$disk_data" | awk '{printf "%.2f", $10}'`
      utils=`      echo "$disk_data" | awk '{printf "%.2f", $12}'`

    fi

    print_to_log "r/s=$read_request w/s=$write_request rB/s=$read_bytes wB/s=$write_bytes"
    save_in_send "read_request" "$dl" "$read_request"
    save_in_send "write_request" "$dl" "$write_request"
    save_in_send "read_bytes" "$dl" "$read_bytes"
    save_in_send "write_bytes" "$dl" "$write_bytes"
    save_in_send "await" "$dl" "$await"
    save_in_send "util" "$dl" "$utils"

done
}

# get command line options
while getopts ":t:e:vh" opt; do
  case $opt in
    t)
      TST_TYPE=$OPTARG     # type of testing
      ;;
    e)
      EXCL_DEV=$OPTARG     # excluded devices
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
  status|iostat)
    get_iostat "$EXCL_DEV"
    ;;
  *)
    print_usage 1
    ;;
esac

# send statistics to the server
send_statuses

exit 0
