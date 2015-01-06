#!/bin/bash
# discovery status for software raid(mdadm)
# usage in template via zabbix agent
# set -x
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

# mdadm utility
[[ -f /sbin/mdadm ]] || exit 1
MDADMCLI="sudo /sbin/mdadm"

print_usage(){
  code=$1
  echo "Usage: $PROGNAME [-hv] -m metric_name -d device_name"
  echo "Discovery software RAID devices:"
  echo " $PROGNAME -m discovery"
  echo "Get metrics for the device:"
  echo " $PROGNAME -m level|state|size|active|working|failed|spare -d device_name]"
  echo

  exit $code
}

# discovery configured RAID devices
discovery(){
 
  md_list=$(cat /proc/mdstat | \
   egrep -o '^md[0-9]+' | awk '{printf "/dev/%s\n", $1}')

  print_debug "$md_list"

  if [[ -z $print ]]; then 
    echo_simple_json "$md_list" "MD_DEV"
    exit 0
  fi
}

# get mdadm information about device
mdadm_metric(){
  device=$1
  metric=$2

  [[ -z $device ]] && exit 1

  metric_cache=${TMPFILE}_$(basename $device)
  metric_ttl=299
  metric_keys='\(Raid Level\|Array Size\|State\|Active Devices\|Working Devices\|Failed Devices\|Spare Devices\)'

  # test if cache file is valid
  use_cache=$(test_cache $metric_cache $metric_ttl)

  if [[ $use_cache -eq 1 ]]; then
    mdadm_info=$($MDADMCLI --detail $device)
    [[ -z $mdadm_info ]] && exit 1

    [[ $VERBOSE -gt 0 ]] && echo "$mdadm_info"


    mdadm_raid_level=$(echo "$mdadm_info" | \
     awk -F':' '/Raid Level/{print $2}' | sed -e 's/\s\+//g;s/raid//')

    mdadm_array_size=$(echo "$mdadm_info" | \
     awk -F':' '/Array Size/{print $2}' | awk '{print $1}')

    mdadm_state=$(echo "$mdadm_info" | \
     awk -F':' '/State/{print $2}' | sed -e 's/\s\+//g')
    
    mdadm_state_code=0
    # https://www.kernel.org/doc/Documentation/md.txt
    [[ "$mdadm_state" == "clear" ]]         && mdadm_state_code=1
    [[ "$mdadm_state" == "inactive" ]]      && mdadm_state_code=2
    [[ "$mdadm_state" == "suspended" ]]     && mdadm_state_code=3
    [[ "$mdadm_state" == "readonly" ]]      && mdadm_state_code=4
    [[ "$mdadm_state" == "read-auto" ]]     && mdadm_state_code=5
    [[ "$mdadm_state" == "clean" ]]         && mdadm_state_code=6
    [[ "$mdadm_state" == "active" ]]        && mdadm_state_code=7
    [[ "$mdadm_state" == "write-pending" ]] && mdadm_state_code=8
    [[ "$mdadm_state" == "active-idle" ]]   && mdadm_state_code=9
    [[ "$mdadm_state" == "active,checking" ]] && mdadm_state_code=10

    active_devices=$(echo "$mdadm_info" | \
     awk -F':' '/Active Devices/{print $2}' | sed -e 's/\s\+//g')
    working_devices=$(echo "$mdadm_info" | \
     awk -F':' '/Working Devices/{print $2}' | sed -e 's/\s\+//g')
    failed_devices=$(echo "$mdadm_info" | \
     awk -F':' '/Failed Devices/{print $2}' | sed -e 's/\s\+//g')
    spare_devices=$(echo "$mdadm_info" | \
     awk -F':' '/Spare Devices/{print $2}' | sed -e 's/\s\+//g')
 
    echo "level:$mdadm_raid_level" > $metric_cache
    echo "size:$mdadm_array_size" >> $metric_cache
    echo "state:$mdadm_state_code" >> $metric_cache
    echo "working:$working_devices" >> $metric_cache
    echo "active:$active_devices" >> $metric_cache
    echo "failed:$failed_devices" >> $metric_cache
    echo "spare:$spare_devices" >> $metric_cache
  fi

  egrep -o "^$metric:[0-9]+" $metric_cache | awk -F':' '{print $2}'
}

# get command line options
# PROGNAME [-hv] -t ad|ld|pd -m metric -a adapter_id -d device_id"
while getopts ":m:d:vh" opt; do
  case $opt in
    "m")
      METRIC=$OPTARG          # requested metric
      ;;
    "d")
      DEVICE=$OPTARG          # device id
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

# 
case $METRIC in
  'discovery') discovery ;;
  *) mdadm_metric "$DEVICE" "$METRIC" ;;
esac

