#!/bin/bash
# discovery status for devices by hpcli
# zebbix_agent usage, create cache files
# Ex.
# get controller slot:
# /var/lib/zabbix/local/scripts/hpraid.sh -t cdiscovery
# get controller metrics:
# /var/lib/zabbix/local/scripts/hpraid.sh -t cmetric -s 3 -m battery|status|cache
#
# get ld info:
# /var/lib/zabbix/local/scripts/hpraid.sh -t ldiscovery -s 3
# metrics:
# /var/lib/zabbix/local/scripts/hpraid.sh -t lmetric -s 3 -d 1 -m type|status|size|cache
#
# get pd info:
# /var/lib/zabbix/local/scripts/hpraid.sh -t pdiscovery -s 3
# metrics
# /var/lib/zabbix/local/scripts/hpraid.sh -t pmetric -s 3 -d "1I:1:4" -m temperature|size|status
#
# get smart info
# /var/lib/zabbix/local/scripts/hpraid.sh -t sdiscovery -s 3
# metrics:
# /var/lib/zabbix/local/scripts/hpraid.sh -t smetric -D /dev/sda -I 0 -m status|Raw_Read_Error_Rate
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

[[ -f /usr/sbin/hpacucli ]] || exit 1
[[ -f /usr/sbin/smartctl ]] || exit 1
HPACUCLI="sudo /usr/sbin/hpacucli"
SMARTCLI="sudo /usr/sbin/smartctl"

[[ -z $DEBUG ]] && DEBUG=0

print_usage(){
  code=$1

  echo "Usage: $PROGNAME [-hv] [-s slot] -t cdiscovery|ldiscovery|pdiscovery|sdiscovery|cmetric|lmetric|pmetric|smart [-d device -m metric] [ -D /dev/<name> -I 0]"
  echo "Options: "
  echo " -h - print help message"
  echo " -v - print verbose info"
  echo " -t - type requested variables:"
  echo "      cdiscovery    - return slot where found controller
              ldiscovery    - return logical devices id in defined slot number
              pdiscovery    - return phisical devices id in defined slot number
              sdiscovery    - return linux disk names and physical device for smart test
              controller    - return metrics for controller,
                              possible metrics are: status, cache, battery
              ld            - return metric for logical device,
                              possible metrics are: status, size, cache, type
              pd            - return metric for physical device,
                              possible metrics are: status, size, temperature
              smart         - return status for device via smartctl util"
  echo " -d - device id that can be used in hpacucli (ex. lb - 1 or pd - 1I:1:3)"
  echo " -m - requested device metric"
  echo " -D - device name for smartctl"
  echo " -I - device id for smartct"
  echo "Ex."
  echo " $PROGNAME -t cdiscovery"
  echo

  exit $code
}

# controller discovery => return slot number
cdiscovery(){
  smart_names='\(Smart Array P410\)'
  
  SLOTS=$($HPACUCLI ctrl all show status | \
   grep "^$smart_names" | awk '{print $NF}')
  
  print_debug "$SLOTS"

  echo_simple_json "${SLOTS}" "SLOT"
  exit 0
}

# get controoler information
# cmetric "$SLOT" "$METRIC"
# possible metrics: status, cache, battery
cmetric(){
  slot=$1
  metric=$2

  metric_cache=${TMPFILE}_${slot}_controller
  metric_ttl=55
  metric_keys='\(Battery/Capacitor Status\|Cache Status\|Controller Status\)'

  # test if cache file is valid
  use_cache=$(test_cache $metric_cache $metric_ttl)
  
  # update/create cache file
  if [[ $use_cache -eq 1 ]]; then
    METRIC_INFO=$(${HPACUCLI} ctrl slot=${slot} show detail | \
     sed -e 's/^\s\+//' | grep "^$metric_keys:") 
    ctrl_status=$(echo "$METRIC_INFO" | \
     awk -F':' '/Controller Status:/ {print $2}' | sed -e 's/\s\+//g')
    ctrl_cache=$(echo "$METRIC_INFO" | \
     awk -F':' '/Cache Status:/ {print $2}' | sed -e 's/\s\+//g')
    ctrl_battery=$(echo "$METRIC_INFO" | \
     awk -F':' '/Battery\/Capacitor Status:/ {print $2}' | sed -e 's/\s\+//g')

     ctrl_status_code=0 # error
     [[ "$ctrl_status" == "OK" ]] && ctrl_status_code=1 # OK
     ctrl_cache_code=0  # error
     [[ "$ctrl_cache" == "OK" ]] && ctrl_cache_code=1   # OK
     ctrl_battery_code=0
     [[ "$ctrl_battery" == "OK" ]] && ctrl_battery_code=1

     echo "status:$ctrl_status_code"    >  $metric_cache
     echo "cache:$ctrl_cache_code"      >> $metric_cache
     echo "battery:$ctrl_battery_code"  >> $metric_cache
    
     [[ "$metric" == "status" ]]  && echo $ctrl_status_code
     [[ "$metric" == "cache"  ]]  && echo $ctrl_cache_code
     [[ "$metric" == "battery" ]] && echo $ctrl_battery_code
  else
    egrep -o "$metric:[01]" $metric_cache | awk -F':' '{print $2}'
  fi
}

# logical device discovery => return id 
ldiscovery(){
  slot=$1

  [[ -z $slot ]] && print_usage 1
  
  DRIVES=$(${HPACUCLI} ctrl slot=${slot} ld all show status | \
   awk '/logicaldrive/ {printf("%d\n", $2)}')

  echo_simple_json "${DRIVES}" "LD"
  exit 0
}

# get metrics for logical device
# lmetric "$SLOT" "$DEVICE" "$METRIC"
# possible metrics: status, size, cache, type
lmetric(){
  slot=$1
  device=$2
  metric=$3

  metric_cache=${TMPFILE}_${slot}_lb_${device}
  metric_ttl=55
  metric_keys='\(Status\|Caching\|Size\|Fault Tolerance\)'

  # test if cache file is valid
  use_cache=$(test_cache $metric_cache $metric_ttl)
  #echo "cache: |$use_cache|"
  
  # update/create cache file
  if [[ ${use_cache} -eq 1 ]]; then
    METRIC_INFO=$(${HPACUCLI} ctrl slot=${slot} ld ${device} show detail 2>/dev/null | \
     sed -e 's/^\s\+//' | grep "^$metric_keys:")

    [[ -z "$METRIC_INFO" ]] && exit 1

    lb_status=$(echo "$METRIC_INFO" | \
     awk -F':' '/^Status:/ {print $2}' | sed -e 's/\s\+//g')
    lb_caching=$(echo "$METRIC_INFO" | \
     awk -F':' '/^Caching:/ {print $2}' | sed -e 's/\s\+//g')
    lb_size_number=$(echo "$METRIC_INFO" | \
     awk -F':' '/^Size:/ {print $2}' | awk '{print $1}' | sed -e 's/\s\+//g')
    lb_size_metric=$(echo "$METRIC_INFO" | \
     awk -F':' '/^Size:/ {print $2}' | awk '{print $2}' | sed -e 's/\s\+//g')
    lb_type=$(echo "$METRIC_INFO" | \
     awk -F':' '/^Fault Tolerance:/ {print $2}' | sed -e 's/\s\+//g')

     lb_status_code=0 # error
     [[ "$lb_status" == "OK" ]] && lb_status_code=1       # OK

     lb_cache_code=0  # disabled
     [[ "$lb_caching" == "Enabled" ]] && lb_cache_code=1    # Enabled
     
     lb_size_bytes_multi=$(echo "$lb_size_metric" | \
      sed -e 's/^TB$/1048576/;s/^GB$/1024/;s/^MB$/1/;')   # convert to MB
     lb_size_mbytes=$(echo "$lb_size_number * $lb_size_bytes_multi" | bc)
     lb_size_mbytes=$(printf "%.2f" $lb_size_mbytes)

     echo "status:$lb_status_code"    >  $metric_cache
     echo "cache:$lb_cache_code"      >> $metric_cache
     echo "size:$lb_size_mbytes"      >> $metric_cache
     echo "type:$lb_type"             >> $metric_cache
    
     [[ "$metric" == "status" ]]  && echo $lb_status_code
     [[ "$metric" == "cache"  ]]  && echo $lb_cache_code
     [[ "$metric" == "size" ]]    && echo $lb_size_mbytes
     [[ "$metric" == "type" ]]    && echo $lb_type
  else
    egrep -o "^$metric:[0-9\+]+" $metric_cache | awk -F':' '{print $2}'
  fi
}


# physical device discovery => return id 
pdiscovery(){
  slot=$1

  [[ -z $slot ]] && print_usage 1
  
  DRIVES=$(${HPACUCLI} ctrl slot=${slot} pd all show status | \
   awk '/physicaldrive/ {printf("%s\n", $2)}')

  echo_simple_json "${DRIVES}" "PD"
  exit 0
}

# get metrics for physical device
# lmetric "$SLOT" "$DEVICE" "$METRIC"
# possible metrics: status, size, temperature
pmetric(){
  slot=$1
  device=$2
  metric=$3

  metric_device=$(echo "${device}" | sed -e 's/:/-/g')
  metric_cache=${TMPFILE}_${slot}_pd_${metric_device}
  metric_ttl=55
  metric_keys='\(Status:\|Size:\|Current Temperature\|Interface Type\)'

  # test if cache file is valid
  use_cache=$(test_cache $metric_cache $metric_ttl)
  
  # update/create cache file
  if [[ $use_cache -eq 1 ]]; then
    METRIC_INFO=$(${HPACUCLI} ctrl slot=${slot} pd ${device} show detail 2>/dev/null | \
     sed -e 's/^\s\+//' | grep "^$metric_keys")
    [[ -z "$METRIC_INFO" ]] && exit 1

    pd_status=$(echo "$METRIC_INFO" | \
     awk -F':' '/^Status:/ {print $2}' | sed -e 's/\s\+//g')
    pd_size_number=$(echo "$METRIC_INFO" | \
     awk -F':' '/^Size:/ {print $2}' | awk '{print $1}' | sed -e 's/\s\+//g')
    pd_size_metric=$(echo "$METRIC_INFO" | \
     awk -F':' '/^Size:/ {print $2}' | awk '{print $2}' | sed -e 's/\s\+//g')
    pd_temper=$(echo "$METRIC_INFO" | \
     awk -F':' '/^Current Temperature \(C\):/ {print $2}' | sed -e 's/\s\+//g')
    [[ -z $pd_temper ]] && pd_temper=0

    pd_interface=$(echo "$METRIC_INFO" | \
     awk -F':' '/^Interface Type:/ {print $2}' | sed -e 's/\s\+//g')

    pd_status_code=0 # error
    [[ "$pd_status" == "OK" ]] && pd_status_code=1       # OK

    pd_interface_code=255
    [[ "$pd_interface" == "SAS" ]] && pd_interface_code=1
    [[ "$pd_interface" == "SATA" ]] && pd_interface_code=2
    [[ "$pd_interface" == "SolidStateSATA" ]]  && pd_interface_code=3

    pd_size_bytes_multi=$(echo "$pd_size_metric" | \
      sed -e 's/^TB$/1048576/;s/^GB$/1024/;s/^MB$/1/;')   # convert to MB
    pd_size_mbytes=$(echo "$pd_size_number * $pd_size_bytes_multi" | bc)
    pd_size_mbytes=$(printf "%.2f" $pd_size_mbytes)

    echo "status:$pd_status_code"       >  $metric_cache
    echo "size:$pd_size_mbytes"         >> $metric_cache
    echo "temperature:$pd_temper"       >> $metric_cache
    echo "interface:$pd_interface_code" >> $metric_cache
    
     [[ "$metric" == "status" ]]        && echo $pd_status_code
     [[ "$metric" == "size" ]]          && echo $pd_size_mbytes
     [[ "$metric" == "temperature" ]]   && echo $pd_temper
     [[ "$metric" == "interface" ]]     && echo $pd_interface_code
  else
    egrep -o "^$metric:[0-9]+" $metric_cache | awk -F':' '{print $2}'
  fi
}

# device discovery
sdiscovery(){
  slot=$1

  [[ -z $slot ]] && print_usage 1
  
  LBTMP=${TMPFILE}_${slot}_disks
  ${HPACUCLI} ctrl slot=${slot} ld all show detail | \
   grep "\(Logical Drive:\|Disk Name:\|physicaldrive\)" > $LBTMP 2>&1
  
  if [[ $? -gt 0 ]]; then
    rm -f $LBTMP
    exit 0
  fi

  is_lb=0
  disk_name=""
  start_json=0
  JSON=""
  JSON_EL=0
  while read line; do
    [[ $(echo "$line" | grep -c "Logical Drive:") -gt 0 ]] && is_lb=1

    if [[ $(echo "$line" | grep -c "Disk Name:") -gt 0 ]]; then
      disk_name=$(echo "$line" | awk -F':' '/Disk Name:/ {print $2}' | sed -e 's/^\s\+//;s/\s\+$//')
      disk_id=0
      # prin json element for fisrt disk:
      [[ $JSON_EL -eq 1 ]] && JSON=${JSON}','
      [[ -z "$JSON" ]] && JSON="{ \"data\":["
      JSON=${JSON}"{\"{#HPDISK}\":\"$disk_name\",\"{#HPID}\":\"$disk_id\"}"
      JSON_EL=1
    fi
    
    if [[ $(echo "$line" | grep -c "physicaldrive") -gt 0 ]]; then
      if [[ $disk_id -gt 0 ]]; then
        [[ $JSON_EL -eq 1 ]] && JSON=${JSON}','
        JSON=${JSON}"{\"{#HPDISK}\":\"$disk_name\",\"{#HPID}\":\"$disk_id\"}"
      fi
      disk_id=$(($disk_id+1))
    fi
  done <$LBTMP

  [[ -n ${JSON} ]] && JSON=${JSON}"]}"
  echo "$JSON"

  exit 0
}

# get metrics for physical device by smartctl util
# smetric "$HPDISK" "$HPID"
# possible metrics, depends on device type:
# SATA:
# from smartctl attributes:
# Raw_Read_Error_Rate, 
# temperature => Temperature_Celsius in output
# Reallocated_Sector_Ct
# Seek_Error_Rate
# Current_Pending_Sector
# Offline_Uncorrectable
# Power_On_Hours
# errors => Raw_Read_Error_Rate+Reallocated_Sector_Ct+Seek_Error_Rate+Current_Pending_Sector+Offline_Uncorrectable
# SCSI:
# temperature => "Current Drive Temperature"
# errors      => "Elements in grown defect list"
# Power_On_Hours => "number of hours powered up"
# from smartctl health status:
# status => SATA: "SMART overall-health self-assessment test result", SCSI: "SMART Health Status"
# ex.
# smartctl --attributes /dev/sda -d cciss,0
# smartctl --health /dev/sda -d cciss,0
# Warning: you need sudo for commands that defined below
smetric(){
  sdevice=$1
  sid=$2
  metric=$3

  #echo "$sdevice $sid $metric"

  [[ ( -z "$sdevice" ) || ( -z "$sid" ) || ( -z "$metric" ) ]] && exit 1

  metric_device=$(basename "${sdevice}")
  metric_cache=${TMPFILE}_smart_${metric_device}_$sid
  metric_ttl=55

  # test if cache file is valid
  use_cache=$(test_cache $metric_cache $metric_ttl)
  
  # update/create cache file
  if [[ $use_cache -eq 1 ]]; then
    A_METRIC_DATA=$(${SMARTCLI} --attributes ${sdevice} -d cciss,${sid})
    [[ -z "$A_METRIC_DATA" ]] && exit 1

    # try defined device type
    device_type=0
    [[ $(echo "$A_METRIC_DATA" | grep -c '\[SCSI\]') -gt 0 ]] && device_type=1
    [[ $(echo "$A_METRIC_DATA" | grep -c '\[SAT\]') -gt 0 ]] && device_type=2
    
    # SATA device
    if [[ $device_type -eq 2 ]]; then
      A_METRIC_INFO=$(echo "$A_METRIC_DATA" | \
        sed -e 's/^\s\+//' | grep '^[0-9]\+' | \
        tr -s ' ' | sed "s/^[[:space:]]*\(.*\)[[:space:]]*$/\1/" | \
        awk '{printf "%s:%s\n",$2,$10}')
      [[ -z "$A_METRIC_INFO" ]] && exit 1
      temperature=$(echo "$A_METRIC_INFO" | awk -F':' '/^Temperature_Celsius:/{print $2}')


      health_status=$(${SMARTCLI} --health ${sdevice} -d cciss,${sid} | \
        grep -c "SMART overall-health self-assessment test result: PASSED" ) # 0 - ok, 1 - error

      errors=$(echo "$A_METRIC_INFO" | \
       grep '^\(Raw_Read_Error_Rate\|Reallocated_Sector_Ct\|Seek_Error_Rate\|Current_Pending_Sector\|Offline_Uncorrectable\):' | \
       awk -F':' '{total+=$2} END {print total}')

      echo "$A_METRIC_INFO"            > $metric_cache
      echo "status:$health_status"    >> $metric_cache
      echo "temperature:$temperature" >> $metric_cache
      echo "errors:$errors"           >> $metric_cache

    elif [[ $device_type -eq 1 ]]; then
      health_status=$(${SMARTCLI} --health ${sdevice} -d cciss,${sid} | \
        grep -c "SMART Health Status: OK" ) # 0 - ok, 1 - error

      errors=$(echo "$A_METRIC_DATA" | \
       awk -F':' '/^Elements in grown defect list:/{print $2}' | \
       sed -e 's/\s\+//g')
      temperature=$(echo "$A_METRIC_DATA" | \
       awk -F':' '/^Current Drive Temperature:/{print $2}' | \
       awk '{print $1}' | sed -e 's/\s\+//g')

      Power_On_Hours=$(echo "$A_METRIC_DATA" | \
       awk -F'=' '/number of hours powered up/{print $2}' | \
       sed -e 's/\s\+//g')

      echo "status:$health_status"           > $metric_cache
      echo "temperature:$temperature"       >> $metric_cache
      echo "errors:$errors"                 >> $metric_cache
      echo "Power_On_Hours:$Power_On_Hours" >> $metric_cache
    else
      exit 1
    fi
  fi
  egrep -o "^$metric:[0-9]+" $metric_cache | awk -F':' '{print $2}'
}


# get command line options
while getopts ":s:t:D:I:d:m:vh" opt; do
  case $opt in
    "t")
      TYPE=$OPTARG        # type of testing or discovery
      ;;
    "s")
      SLOT=$OPTARG        # HP controller slot
      ;;
    "d")
      DEVICE=$OPTARG      # DEVICE ID
      ;;
    "m")
      METRIC=$OPTARG      # METRIC NAME
      ;;
    "D")
      HPDISK=$OPTARG      # disk name in the system, ex. /dev/sda
      ;;
    "I")
      HPID=$OPTARG        # disk id in the system, 1,2...
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

# test
case $TYPE in 
  "cdiscovery")
    cdiscovery
  ;;
  "ldiscovery")
    ldiscovery "$SLOT"
  ;;
  "pdiscovery")
    pdiscovery "$SLOT"
  ;;
  "sdiscovery")
    sdiscovery "$SLOT"
  ;;
  cmetric|controller)
    cmetric "$SLOT" "$METRIC"
  ;;
  lmetric|ld)
    lmetric "$SLOT" "$DEVICE" "$METRIC"
  ;;
  pmetric|pd)
    pmetric "$SLOT" "$DEVICE" "$METRIC"
  ;;
  smetric|smart)
    smetric "$HPDISK" "$HPID" "$METRIC"
  ;;
  *) 
    print_usage 1 
  ;;
esac 

exit 0
