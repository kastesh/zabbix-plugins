#!/bin/bash

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
[[ ! -d $WORKDIR ]] && WORKDIR=/var/lib/zabbix/local

CONFFILE=/etc/zabbix/zabbix_agentd.conf
[[ ! -f $CONFFILE ]] && CONFFILE=$WORKDIR/etc/zabbix_agentd.conf

LOGDIR=$WORKDIR/log
[[ ! -d $LOGDIR ]]  && mkdir $LOGDIR
LOGFILE=$LOGDIR/$TEST.log

SERVER=""       # Zabbix Server from config file
HOST=""         # Zabbix Client Name from config file

which bc 1>/dev/null 2>&1
if [[ $? -gt 0 ]]; then
  echo "Not found bc util, yum install bc"
  exit 1
fi

. $PROGPATH/zabbix_utils.sh || exit 1

TST_TYPE="status"
EXCL_DEV='drbd'
WAITTIME=60         # iostat collects information within the specified time
DEVICE="all"
TMPFILE=$TMPDIR/$(date +%s)_

print_usage(){
  code=$1

  echo "Usage: $PROGNAME [-hv] [-t iostat] [-e exclude_devices]"
  echo "Options: "
  echo " -h - print help message"
  echo " -v - print verbose info"
  echo " -t - type requested variables (default: iostat, smart)"
  echo " -e - list excluded devices from output, comma separeted (default: drbd)"
  echo " -d - disk name for smartctl options"
  echo "Ex."
  echo " $PROGNAME -t status"
  echo

  exit $code
}

disk_discovery(){
    exclude_list="${1}"

    exclude_regx='\('$(echo "$exclude_list" | sed -e 's/,/\\\|/g')'\)'


    disk_labels=`iostat -kxd | grep -v '^$' | \
        grep -v '^\(Device\|Linux\)' | grep -v "$exclude_regx" | \
        awk '{print $1}' | sort | uniq`


    d_list=
    if [[ -n "$disk_labels" ]]; then
        for label in $disk_labels; do

            lname=$label
            is_lvm=`echo $label | grep -c '^dm-'`
            if [[ $is_lvm -gt 0 ]]; then
                link_name=`find /dev/mapper/ -maxdepth 1 -type l -ls | \
                    grep "$label$" | awk '{print $11}' | sed -e 's:^/dev/mapper/::'`
                [[ -n $link_name ]] && lname=$link_name
                exclude_lv=$(echo "$link_name" | grep -c '\(lvsnap\)' )
                [[ $exclude_lv -gt 0 ]] && continue
            fi
            d_list=$d_list"DLABEL=$label;DNAME=$lname "
        done
        d_list=$(echo "$d_list" | sed -e 's/\s\+$//')
    fi

    echo_multi_json "$d_list"
    exit 0
}

# get smartctl info for disk (all options send by trapper, but initial created by zabbix_agent)
# http://files-recovery.blogspot.ru/2009/06/free-hard-drive-monitor-from-pulse.html
# Options:
# Raw_Read_Error_Rate   - Stores data related to the rate of hardware read errors 
#                         that occurred when reading data from a disk surface.
#                         The raw value has different structure for different vendors 
#                         and is often not meaningful as a decimal number.
# Seek_Error_Rate       - Rate of seek errors of the magnetic heads. 
#                         If there is a partial failure in the mechanical positioning system, 
#                         then seek errors will arise.
#                         Such a failure may be due to numerous factors, 
#                         such as damage to a servo, or thermal widening of the hard disk.
# Temperature_Celsius   - Drive Temperature
# Reallocated_Sector_Ct - Count of reallocated sectors. 
#                         When the hard drive finds a read/write/verification error, 
#                         it marks that sector as "reallocated" and 
#                         transfers data to a special reserved area (spare area).
#                         This process is also known as remapping, 
#                         and reallocated sectors are called "remaps".
#                         The raw value normally represents a count of the bad sectors 
#                         that have been found and remapped.
get_smartctl() {
  disk=$1
  device_type=$2

  which smartctl 1>/dev/null 2>&1
  if [[ $? -gt 0 ]]; then
    echo "Not found smartctl util, yum install smartmontools"
    exit 1
  fi

  define_device_type=""
  [[ -n "$device_type" ]] && define_device_type="-d $device_type"

  # test attributes 
  options='Raw_Read_Error_Rate\|Seek_Error_Rate\|Temperature_Celsius\|Reallocated_Sector_Ct\|Reported_Uncorrect\|Command_Timeout\|Current_Pending_Sector\|Offline_Uncorrectable\|Power_On_Hours'
  smart_data=$(sudo smartctl --attributes $disk $define_device_type | grep "\($options\)" | \
                tr -s ' ' | sed "s/^[[:space:]]*\(.*\)[[:space:]]*$/\1/" | \
                awk '{printf "%s:%s\n",$2,$10}' )
  
  for smart in $smart_data; do
    smartkey=$(echo $smart| cut -d':' -f1)
    smartval=$(echo $smart| cut -d':' -f2)
    save_in_send "$smartkey" "$disk" "$smartval"
  done 

  # test health status
  smart_health=$(sudo smartctl --health $disk $define_device_type)
  # device type: SAS => 1, SSD => 2 
  smart_type=255
  [[ -n $(echo "$smart_health" | \
   grep '^SMART Health Status:') ]] && smart_type=1
  [[ -n $(echo "$smart_health" | \
   grep '^SMART overall-health self-assessment test result:') ]] && smart_type=2

  # device health-test status
  # 0 = Error(not found predefined status), 1 = Ok
  smart_status=0
  [[ $smart_type -eq 1 ]] && \
   smart_status=$(echo "$smart_health" | grep -c '^SMART Health Status: OK')
  [[ $smart_type -eq 2 ]] && \
   smart_status=$(echo "$smart_health" | grep -c '^SMART overall-health self-assessment test result: PASSED')

  save_in_send "type" "$disk" "$smart_type"
  save_in_send "health" "$disk" "$smart_status"

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
while getopts ":t:e:d:vh" opt; do
  case $opt in
    t)
      TST_TYPE=$OPTARG     # type of testing
      ;;
    e)
      EXCL_DEV=$OPTARG     # excluded devices
      ;;
    d)
      DEVICE=$OPTARG       # smartctl device info
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

TMPFILE=${TMPFILE}_${TST_TYPE}_$(basename ${DEVICE})

# create statistics
case $TST_TYPE in
    status|iostat)
        get_agent_info
        get_iostat "$EXCL_DEV"; echo_val=0
        ;;
    discovery)
        disk_discovery "$EXCL_DEV"; echo_val=1
        ;;
    smart)
        get_smartctl "$DEVICE" "$DEVICE_TYPE"; echo_val=1
        ;;
    *)
        print_usage 1
        ;;
esac

[[ $echo_val -eq 0 ]] && send_statuses


exit 0
