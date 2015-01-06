#!/bin/bash
# discovery status for devices by smartctl utility
# usage in template via zabbix agent
# additional info: 
# http://files-recovery.blogspot.ru/2009/06/free-hard-drive-monitor-from-pulse.html
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

# smartctl utility
[[ -f /usr/sbin/smartctl ]] || exit 1
SMARTCLI="sudo /usr/sbin/smartctl"

[[ -f /sbin/parted ]] || exit 1
PARTEDCLI="sudo /sbin/parted"

print_usage(){
  code=$1
  echo "Usage: $PROGNAME [-hv] -m metric -d device_name"
  echo "Discovery device names:"
  echo " $PROGNAME -m discovery"
  echo "Get metrics for the device:"
  echo " $PROGNAME -t ad -m health|type|Raw_Read_Error_Rate -d /dev/<device_name>"
  echo

  exit $code
}

# discovery devices which support SMART
smart_discovery(){
  exclude_dev='\(Linux device-mapper\|Unknown|Virtual Block Device\)'
  metric_cache=${TMPFILE}_parted
  metric_ttl=3600

  # test if cache file is valid
  use_cache=$(test_cache $metric_cache $metric_ttl)

  if [[ $use_cache -eq 1 ]]; then
    $PARTEDCLI -l | grep '^\(Model:\|Disk\s\+\)' >$metric_cache 2>/dev/null
    [[ $? -gt 0 ]] && exit 0
  fi

  is_tested=0
  dev_list=
  while read line; do
    # test disk models
    if [[ $(echo "$line" | grep -c "^Model:" ) -gt 0 ]]; then
      [[ $(echo "$line" | grep -ci "$exclude_dev") -eq 0 ]] && is_tested=1
    fi

    # disk name found
    if [[ $(echo "$line" | grep -c "^Disk\s\+") -gt 0 ]]; then
      if [[ $is_tested -eq 1 ]]; then
        dev_name=$(echo "$line" | awk '{print $2}' | sed -e 's/:$//')
        smart_info=$($SMARTCLI --info "$dev_name")
        smart_support=$(echo "$smart_info" | grep -c 'SMART support is: Enabled')
        [[ $smart_support -gt 0 ]] && dev_list=$dev_list"$dev_name "
      fi
    fi
  done < $metric_cache
  dev_list=$(echo "$dev_list" | sed -e 's/\s\+$//')

  echo_simple_json "$dev_list" "SDEVICE"
  exit 0
}

# smartctl metrics
smetric(){
  metric=$1
  device_name=$2

  [[ "$metric" == "discovery" ]] && smart_discovery
  [[ -z $device_name ]] && exit 1

  metric_cache=${TMPFILE}_$(basename ${device_name})_smart
  metric_ttl=300
  metric_keys="Raw_Read_Error_Rate Seek_Error_Rate Temperature_Celsius Reallocated_Sector_Ct
Reported_Uncorrect Command_Timeout Current_Pending_Sector Offline_Uncorrectable Power_On_Hours"

  # test if cache file is valid
  use_cache=$(test_cache $metric_cache $metric_ttl)
  if [[ $use_cache -eq 1 ]]; then
    smart_attributes=$(${SMARTCLI} --all ${device_name})
    [[ -z $smart_attributes ]] && exit 1

    # device type: SAS => 1, SSD => 2
    smart_type=255
    [[ -n $(echo "$smart_attributes" | \
     grep '^SMART Health Status:') ]] && smart_type=1
    [[ -n $(echo "$smart_attributes" | \
     grep '^SMART overall-health self-assessment test result:') ]] && smart_type=2
    echo "type:$smart_type" > $metric_cache

    # smart health
    smart_health_code=0
    if [[ $smart_type -eq 2 ]]; then
      smart_health_code=$(echo "$smart_attributes" | \
       awk -F':' '/SMART overall-health self-assessment test result:/{print $2}' | \
       sed -e 's/\s\+//g' | grep -wc 'PASSED')
    elif [[ $smart_type -eq 1 ]]; then
      smart_health_code=$(echo "$smart_attributes" | \
       awk -F':' '/SMART Health Status:/{print $2}' | \
       sed -e 's/\s\+//g' | grep -wc 'OK')
    fi
    echo "health:$smart_health_code" >> $metric_cache

    for key in $metric_keys; do
      val=$(echo "$smart_attributes" | \
       grep -w "$key" | awk '{print $10}')
      [[ -z $val ]] && val=0
      echo "$key:$val" >> $metric_cache
    done
  fi 
  egrep -o "^$metric:[0-9\.]+" $metric_cache | awk -F':' '{print $2}'
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

smetric "$METRIC" "$DEVICE" 

