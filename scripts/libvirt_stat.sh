#!/bin/bash
# get information about libvirt hosts via smtp aget
# http://wiki.libvirt.org/page/Libvirt-snmp
# ex
export LC_ALL=""
export LANG="en_US.UTF-8"
export PATH=$PATH:/sbin:/usr/sbin:$HOME/bin

PROGNAME=$(basename $0)
PROGPATH=$(dirname $0)
VERBOSE=0
TEST=$(echo $PROGNAME| sed -e 's/\.sh$//')
CACHESEC=298
DATE_TM=$(date +%s)

TMPDIR=/dev/shm
[[ ! -d $TMPDIR ]] && TMPDIR=/tmp

WORKDIR=/home/zabbix
[[ ! -d $WORKDIR ]] && WORKDIR=/var/lib/zabbix/local

LOGDIR=$WORKDIR/log
[[ ! -d $LOGDIR ]]  && mkdir $LOGDIR
LOGFILE=$LOGDIR/$TEST.log
TMPFILE=$TMPDIR/${TEST}
COMMUNITY_DEFAULT=public

PGREP="sudo /usr/bin/pgrep -x -P 1"

. $PROGPATH/zabbix_utils.sh || exit 1

print_usage(){
  code=$1
  echo "Usage: $PROGNAME [-hv] -m discovery|State|CpuCount|MemoryCurrent|MemoryLimit|CpuTime|RowStatus [-g guest_id] -c community_string"
  echo "Discovery existen hosts:"
  echo " $PROGNAME -m discovery -c community_string"
  echo
  echo "Get host status options:"
  echo " $PROGNAME -m State -g c0f43637-4b60-7f40-26a-81c81eacb32b"
  echo
  exit $code
}


# return 
# GUEST_NAME
# GUEST_ID
libvirt_discovery(){
  community_string=$1

  [[ -z $community_string ]] && exit

  guests_info=$(snmpwalk -m ALL -v 2c -c $community_string \
   -OX localhost libvirtGuestName)

  [[ -z $guests_info ]] && exit

  # create guest list
  guests_list=
  IFS_BAK=$IFS
  IFS=$'\n'

  for guest_data in $guests_info; do
    guest_id=$(echo "$guest_data" | awk -F'=' '{print $1}' | \
     sed -e 's/^LIBVIRT-MIB::libvirtGuestName\[STRING:\s\+//; s/\]\s\+$//;' )
    guest_name=$(echo "$guest_data" | awk -F'=' '{print $2}' | \
     sed -e 's/^\s\+STRING:\s\+//; s/\"//g')

    guests_list=$guests_list"GUEST_ID=$guest_id;GUEST_NAME=$guest_name "
  done
  IFS=$IFS_BAK
  IFS_BAK=

  guests_list=$(echo "$guests_list" | sed -e 's/\s\+$//')
  echo_multi_json "$guests_list"
}

guest_status(){
  guest_id=$1
  metric=$2
  community_string=$3

  [[ ( -z $guest_id ) || ( -z $metric ) || ( -z $community_string ) ]] && exit 1

  # create socat connection string
  metric_cache=${TMPFILE}_${guest_id}
  metric_ttl=299

  # test if cache file is valid
  use_cache=$(test_cache $metric_cache $metric_ttl)

  # create cache
  if [[ $use_cache -eq 1 ]]; then
    snmpwalk -m ALL -Oe -v 2c -c $community_string \
     -OX localhost libvirtMIB | \
     grep " $guest_id\]" | \
     sed -e "s/^LIBVIRT-MIB::libvirtGuest//;s/\[STRING: $guest_id\]//;s/\"//g" | \
     awk '{printf "%s:%s\n",$1,$NF}' >$metric_cache 2>&1

    if [[ $? -gt 0 ]]; then
      print_debug "cmd=snmpwalk return error: $(head -1 $metric_cache)"
      rm -f $metric_cache
      exit 1
    fi
  fi

  # get metric
  grep "^$metric:" $metric_cache | awk -F':' '{print $2}'
}

while getopts ":m:g:c:vh" opt; do
  case $opt in
    "m")
      METRIC=$OPTARG          # requested metric
      ;;
    "c")
      COMMUNITY=$OPTARG       # community string
      ;;
    "g")
      GUEST_ID=$OPTARG
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

[[ -z $COMMUNITY ]] && COMMUNITY=$COMMUNITY_DEFAULT

if [[ -z "$METRIC" ]]; then
  print_usage
elif [[ "$METRIC" == "discovery" ]]; then
  libvirt_discovery "$COMMUNITY"
elif [[ "$METRIC" == "process" ]]; then
  $PGREP "$guest_id" | wc -l 
else
  # try get guest status
  guest_status "$GUEST_ID" "$METRIC" "$COMMUNITY"
fi
