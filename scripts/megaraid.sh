#!/bin/bash
# discovery status for devices by megaraid and smartctl utilities
# usage in template via zabbix agent
# additional info: 
# https://globalroot.wordpress.com/2013/06/18/megacli-raid-levels/
# http://serverfault.com/questions/381177/megacli-get-the-dev-sd-device-name-for-a-logical-drive
# http://www.snia.org/sites/default/files/SNIA_DDF_Technical_Position_v2.0.pdf
# ex
export LC_ALL=""
export LANG="en_US.UTF-8"
export PATH=$PATH:/sbin:/usr/sbin:$HOME/bin:/opt/MegaRAID/MegaCli

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

# MegaCli utility
ARCH_TYPE=$(uname -p)
MEGACLI=/opt/MegaRAID/MegaCli/MegaCli
[[ $ARCH_TYPE == "x86_64" ]] && MEGACLI=/opt/MegaRAID/MegaCli/MegaCli64
[[ -f $MEGACLI ]] || exit 1
MEGACLI="sudo $MEGACLI"

print_usage(){
  code=$1
  echo "Usage: $PROGNAME [-hv] -t ad|ld|pd|smart -m metric -a adapter_id -d device_id"
  echo "Discovery MegaRAID adapater IDs:"
  echo " $PROGNAME -t ad -m discovery"
  echo "Get metrics for the adapter:"
  echo " $PROGNAME -t ad -m battery_state|battery_temperature -a adapter_id]"
  echo
  echo "Discovery MegarRAID logical device IDs:"
  echo " $PROGNAME -t ld -m discovery"
  echo "Get metrics for the LD:"
  echo " $PROGNAME -t ld -m cache_policy|state|size|raid_level -a adapter_id -d ld_id"
  echo
  echo "Discovery MegarRAID physical device IDs:"
  echo " $PROGNAME -t pd -m discovery"
  echo "Get metrics for the PD:"
  echo " $PROGNAME -t pd -m other_error|media_error|temperature|type|size -a adapter_id -d pd_id"
  echo 
  echo "Discovery SMART physical device IDs and device names:"
  echo " $PROGNAME -t smart -m discovery"
  echo "Get SMART metrics for the PD:"
  echo " $PROGNAME -t smart -m health|protocol|temperature|defect_list|non_medium_error|uncorrect_read|uncorrect_write|uncorrect_verify -a device_name -d device_id"

  exit $code
}

# discovery installed adapters IDs
adapters_discovery(){
  print=$1  # if not defined zabbix discovery usage, else fill out variable adapters_list
 
  adapters_list=$($MEGACLI -AdpAllInfo -aALL -NoLog | \
   awk '/Adapter #[0-9]+/{print $2}' | sed -e 's/#//')

  print_debug "$adapters_list"

  if [[ -z $print ]]; then 
    echo_simple_json "$adapters_list" "ADAPTER_ID"
    exit 0
  fi
}

# discovery installed/configured logical devices
# get adapter+ld list
# ex. { "data":[{"{#LD_ADAPTER_ID}":"0","{#LD_ID}":"0"}]}
ld_discovery(){
  adapters_discovery "not_print"
  [[ -z $adapters_list ]] && exit 1

  ld_list=

  for adapter in $adapters_list; do
    lds_list=$($MEGACLI -LDInfo -LAll -a$adapter -NoLog | \
     awk '/^Virtual Drive: [0-9]+/{print $3}')
    if [[ -n $lds_list ]]; then
      for ld in $lds_list; do
        ld_list=$ld_list"LD_ADAPTER_ID=$adapter;LD_ID=$ld "
      done
      ld_list=$(echo "$ld_list" | sed -e 's/\s\+$//')
    fi
  done

  echo_multi_json "$ld_list"
  exit 0
}

# discovery installed physical devices
pd_discovery(){
  adapters_discovery "not_print"
  [[ -z $adapters_list ]] && exit 1

  pd_list=
  for adapater in $adapters_list; do
    pds_list=$($MEGACLI -pdList -a$adapater -NoLog | \
     grep '\(Enclosure Device ID:\|Slot Number\)' | \
     sed -e 's/\s\+//g' | \
     awk -F':' '{if ($1 ~ /EnclosureDeviceID/) device=$2; \
      if ($1 ~ /SlotNumber/) {device=device":"$2; print device}}')
    if [[ -n $pds_list ]]; then
      for pd in $pds_list; do
        pd_list=$pd_list"PD_ADAPTER_ID=$adapater;PD_ID=$pd "
      done
      pd_list=$(echo "$pd_list" | sed -e 's/\s\+$//')
    fi
  done

  echo_multi_json "$pd_list"
  exit 0
}

# discovery installed physical devices and linux drive for them
# ex.
# {#PD_ADAPTER}   - Adpater number for logical device
# {#PD_TARGET_ID} - Target ID for Logical Drive
# {#PD_TARGET_DEV} - Target Name (ex. /dev/sda)
# {#PD_DEVICE_ID} - physical device ID 
# function usage smartctl util:
# smartctl -a /dev/sda -d megaraid,10
smart_discovery(){
  smart_list=

  megacli_grep='\(Adapter\|Virtual Drive\|Device Id\|Enclosure Device ID\|Slot Number\)'
  megacli_cache=${TMPFILE}_megacli
  metric_ttl=3599

  # test if cache file is valid
  use_cache=$(test_cache $megacli_cache $metric_ttl)
  if [[ $use_cache -eq 1 ]]; then
    $MEGACLI -LDPDInfo -aALL -NoLog | \
     grep "$megacli_grep" | sed -e 's/#/:/' 1>$megacli_cache 2>&1
    [[ $? -gt 0 ]] && exit 1
  fi

  # exit if file is empty 
  [[ ! -s $megacli_cache ]] && exit 1

  # process file
  IFS_BAK=$IFS
  IFS=$'\n'

  adapter_id=
  target_id=
  target_dev=
  device_id=
  for line in $(cat $megacli_cache); do
    if [[ $(echo "$line" | grep -wc "Adapter") -gt 0 ]]; then
      adapter_id=$(echo "$line" | awk -F':' '{print $2}' | \
       sed -e 's/\s\+//g')
      [[ $VERBOSE -gt 0 ]] && echo "Adapter: $adapter_id"
    fi

    # exclude CacheCade Virtual Drive from output 
    [[ $(echo "$line" | grep -wc "CacheCade") -gt 0 ]] && target_id= && target_dev=

    # virtual drive found
    if [[ $(echo "$line" | grep -c '^Virtual Drive:') -gt 0 ]]; then
      target_id=$(echo "$line" | egrep -o 'Target Id:\s+[0-9]+' | awk '{print $3}')
      [[ $VERBOSE -gt 0 ]] && echo "LD Target ID: $target_id"
      if [[ -n "$target_id" ]]; then
        target_dev=$(ls -l /dev/disk/by-path/ | \
         grep -E "scsi-[0-9]:[0-9]:${target_id}:[0-9] " | awk '{print $11}')
        if [[ -n "$target_dev" ]]; then
          target_dev="/dev/"$(basename $target_dev)
        else
          target_id=
        fi
        [[ $VERBOSE -gt 0 ]] && echo "LD Target Dev: $target_dev"
      fi
    fi

    # physical drive
    if [[ $(echo "$line" | grep -c '^Device Id:') -gt 0 ]]; then
      device_id=$(echo "$line" | awk '{print $3}')
      [[ $VERBOSE -gt 0 ]] && echo "PD ID: $device_id"

      # test if logical device is found too
      if [[ ( -n $target_id ) && ( -n $target_dev ) && ( -b $target_dev ) ]]; then
        smart_list=$smart_list"PD_ADAPTER=$adapter_id;PD_TARGET_ID=$target_id;PD_TARGET_DEV=$target_dev;PD_DEVICE_ID=$device_id "
      fi
    fi
  done
  IFS=$IFS_BAK
  IFS_BAK=

  smart_list=$(echo "$smart_list" | sed -e 's/\s\+$//')

  echo_multi_json "$smart_list"
  exit 0

}

# get metric about adapter
# battery_state, battery_temperature
ametric(){
  metric=$1
  adapter=$2

  [[ "$metric" == "discovery" ]] && adapters_discovery
  [[ -z $adapter ]] && exit 1

  metric_cache=${TMPFILE}_${adapter}_ad
  metric_ttl=299
  metric_keys='\(Battery State\|Temperature\):'

  # test if cache file is valid
  use_cache=$(test_cache $metric_cache $metric_ttl)

  if [[ $use_cache -eq 1 ]]; then
    BBU_INFO=$($MEGACLI -AdpBbuCmd -a$adapter -NoLog | \
      grep "^$metric_keys")
    [[ -z $BBU_INFO ]] && exit 1

    battery_temperature=$(echo "$BBU_INFO" | awk -F':' '/^Temperature:/{print $2}' | \
     awk '{print $1}')
    battery_state=$(echo "$BBU_INFO" | awk -F':' '/^Battery State:/{print $2}' | \
     sed -e 's/\s\+//g')
    battery_state_code=0
    [[ $battery_state == "Optimal" ]] && battery_state_code=1

    echo "battery_state:$battery_state_code" > $metric_cache
    echo "battery_temperature:$battery_temperature" >> $metric_cache

  fi

  egrep -o "^$metric:[0-9\+]+" $metric_cache | awk -F':' '{print $2}'
}

# get metric about logical device
# /opt/MegaRAID/MegaCli/MegaCli64 -LDInfo -L0 -a0 -NoLog
# state,cache_policy
lmetric(){
  metric=$1
  adapter=$2
  device=$3

  [[ "$metric" == "discovery" ]] && ld_discovery
  [[ ( -z $adapter ) || ( -z $device ) ]] && exit 1

  metric_cache=${TMPFILE}_${adapter}_ld_${device}
  metric_ttl=299
  metric_keys='\(Current Cache Policy\|State\|RAID Level\|Size\)\s*:'

  # test if cache file is valid
  use_cache=$(test_cache $metric_cache $metric_ttl)
  if [[ $use_cache -eq 1 ]]; then
    LD_INFO=$($MEGACLI -LDInfo -L$device -a$adapter -NoLog | \
     grep "^$metric_keys")
    [[ -z $LD_INFO ]] && exit 1

    # metric=cache_policy
    ld_cache_policy=$(echo "$LD_INFO" | awk -F':' '/Current Cache Policy/{print $2}' | \
     awk -F',' '{print $1}' | sed -e 's/\s\+//g')
    ld_cache_policy_code=255
    [[ "$ld_cache_policy" == "WriteBack" ]] && ld_cache_policy_code=1
    [[ "$ld_cache_policy" == "WriteThrough" ]] && ld_cache_policy_code=2

    # metric=status 
    ld_state=$(echo "$LD_INFO" | awk -F':' '/State/{print $2}' | grep -wc 'Optimal')

    # metric=type
    ld_raid_level=$(echo "$LD_INFO" | \
     awk -F':' '/RAID Level/{print $2}' | \
     sed -e 's/\s\+//g;')

    # metric=size
    ld_size_number=$(echo "$LD_INFO" | awk -F':' '/Size/{print $2}' | \
     awk '{print $1}')
    ld_size_multi=$(echo "$LD_INFO" | awk -F':' '/Size/{print $2}' | \
     awk '{print $2}' | sed -e 's/^TB$/1048576/;s/^GB$/1024/;s/^MB$/1/;')
    ld_size_mbytes=$(echo "$ld_size_number * $ld_size_multi" | bc)
    ld_size_mbytes=$(printf "%.2f" $ld_size_mbytes)

    # save cache
    echo "status:$ld_state" > $metric_cache
    echo "cache_policy:$ld_cache_policy_code" >> $metric_cache
    echo "size:$ld_size_mbytes" >> $metric_cache
    echo "raid_level:$ld_raid_level" >> $metric_cache

  fi

  egrep -o "^$metric:\S+" $metric_cache | awk -F':' '{print $2}'
}

# get metric about physical device
# /opt/MegaRAID/MegaCli/MegaCli64 -pdInfo -PhysDrv\[8:11\] -a0 -NoLog
pmetric(){
  metric=$1
  adapter=$2
  device=$3

  [[ "$metric" == "discovery" ]] && pd_discovery
  [[ ( -z $adapter ) || ( -z $device ) ]] && exit 1

  metric_device=$(echo "$device" | sed -e 's/:/-/g')
  metric_cache=${TMPFILE}_${adapter}_pd_${metric_device}
  metric_ttl=55
  metric_keys='\(Other Error Count\|Media Error Count\|Drive Temperature\|PD Type\|Raw Size\)\s*:'

  # test if cache file is valid
  use_cache=$(test_cache $metric_cache $metric_ttl)
  if [[ $use_cache -eq 1 ]]; then
    PD_INFO=$($MEGACLI -pdInfo -PhysDrv\[$device\] -a$adapter -NoLog | \
     grep "^$metric_keys")
    [[ -z $PD_INFO ]] && exit 1

    # metric=other_error
    pd_o_errors=$(echo "$PD_INFO" | \
     awk -F':' '/Other Error Count/{print $2}' | sed -e 's/\s\+//g')

    # metric=media_error
    pd_m_error=$(echo "$PD_INFO" | \
     awk -F':' '/Media Error Count/{print $2}' | sed -e 's/\s\+//g')

    # metric=temperature
    pd_temperature=$(echo "$PD_INFO" | \
     awk -F':' '/Drive Temperature/{print $2}' | \
     awk '{print $1}' | sed -e 's/\s\+//g;s/C$//')

    # metric=type
    pd_type=$(echo "$PD_INFO" | \
     awk -F':' '/PD Type/{print $2}' | sed -e 's/\s\+//g')
    pd_type_code=255
    [[ "$pd_type" == "SAS" ]] && pd_type_code=1
    [[ "$pd_type" == "SATA" ]] && pd_type_code=2

    # metric=size
    pd_size_number=$(echo "$PD_INFO" | awk -F':' '/Raw Size/{print $2}' | \
     awk '{print $1}')
    pd_size_multi=$(echo "$PD_INFO" | awk -F':' '/Raw Size/{print $2}' | \
     awk '{print $2}' | sed -e 's/^TB$/1048576/;s/^GB$/1024/;s/^MB$/1/;')
    pd_size_mbytes=$(echo "$pd_size_number * $pd_size_multi" | bc)
    pd_size_mbytes=$(printf "%.2f" $pd_size_mbytes)

    # save to cache
    echo "other_error:$pd_o_errors" > $metric_cache
    echo "media_error:$pd_m_error" >> $metric_cache
    echo "temperature:$pd_temperature" >> $metric_cache
    echo "type:$pd_type_code" >> $metric_cache
    echo "size:$pd_size_mbytes" >> $metric_cache
  fi
  egrep -o "^$metric:[0-9\+]+" $metric_cache | awk -F':' '{print $2}'
}

# smartctl metrics
smetric(){
  metric=$1
  device_name=$2
  device_id=$3

  [[ "$metric" == "discovery" ]] && smart_discovery
  [[ ( -z $device_name ) || ( -z $device_id ) ]] && exit 1

  metric_cache=${TMPFILE}_$(basename ${device_name})_smart_${device_id}
  metric_ttl=55
  # test if cache file is valid
  use_cache=$(test_cache $metric_cache $metric_ttl)
  if [[ $use_cache -eq 1 ]]; then
    smart_attributes=$(${SMARTCLI} --all ${device_name} -d megaraid,${device_id})
    [[ -z $smart_attributes ]] && exit 1
    [[ $VERBOSE -gt 0 ]] && echo "$smart_attributes"

    smart_protocol=$(echo "$smart_attributes" | \
     awk -F':' '/Transport protocol:/{print $2}' | sed -e 's/\s\+//g')
    smart_protocol_code=0
    [[ "$smart_protocol" == "SAS" ]] && smart_protocol_code=1 

    smart_health=$(echo "$smart_attributes" | \
     awk -F':' '/SMART Health Status:/{print $2}' | sed -e 's/\s\+//g')
    smart_health_code=0
    [[ "$smart_health" == "OK" ]] && smart_health_code=1

    smart_temperature=$(echo "$smart_attributes" | \
     awk -F':' '/Current Drive Temperature:/{print $2}' | awk '{print $1}')

    smart_defect_list=$(echo "$smart_attributes" | \
     awk -F':' '/Elements in grown defect list:/{print $2}' | sed -e 's/\s\+//g')

    smart_non_medium_error=$(echo "$smart_attributes" | \
     awk -F':' '/Non-medium error count:/{print $2}' | sed -e 's/\s\+//g')

    smart_uncorrect_read=$(echo "$smart_attributes" | \
     awk -F':' '/read:/{print $2}' | awk '{print $7}')

    smart_uncorrect_write=$(echo "$smart_attributes" | \
     awk -F':' '/write:/{print $2}' | awk '{print $7}')

    smart_uncorrect_verify=$(echo "$smart_attributes" | \
     awk -F':' '/verify:/{print $2}' | awk '{print $7}')

    echo "protocol:$smart_protocol_code" > $metric_cache
    echo "health:$smart_health_code" >> $metric_cache
    echo "temperature:$smart_temperature" >> $metric_cache
    echo "defect_list:$smart_defect_list" >> $metric_cache
    echo "non_medium_error:$smart_non_medium_error" >> $metric_cache
    echo "uncorrect_read:$smart_uncorrect_read" >> $metric_cache
    echo "uncorrect_write:$smart_uncorrect_write" >> $metric_cache
    echo "uncorrect_verify:$smart_uncorrect_verify" >> $metric_cache
  fi 
  egrep -o "^$metric:[0-9\+]+" $metric_cache | awk -F':' '{print $2}'
}

# get command line options
# PROGNAME [-hv] -t ad|ld|pd -m metric -a adapter_id -d device_id"
while getopts ":t:m:a:d:n:vh" opt; do
  case $opt in
    "t")
      TYPE=$OPTARG            #device type: ad, ld or pd
      ;;
    "m")
      METRIC=$OPTARG          # requested metric
      ;;
    "a")
      ADAPTER=$OPTARG         # adapter id
      ;;
    "d")
      DEVICE=$OPTARG          # device id
      ;;
    "n")
      DEVICE_NAME=$OPTARG     # device_name
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
case $TYPE in
  'ad')
    ametric "$METRIC" "$ADAPTER"
  ;;
  'ld')
    lmetric "$METRIC" "$ADAPTER" "$DEVICE"
  ;;
  'pd')
    pmetric "$METRIC" "$ADAPTER" "$DEVICE"
  ;;
  'smart')
    smetric "$METRIC" "$ADAPTER" "$DEVICE" 
  ;;
  *)
  print_usage 1
  ;;
esac

