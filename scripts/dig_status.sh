#!/bin/bash
#set -x
# test A records on different DNS servers
# dig_status[discovery]
# return {#FQDN},{#DNS} pares
# dig_status[ip,{#FQDN},{#DNS}]
# dig_status[request,{#FQDN},{#DNS}]
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
TMPFILE=$TMPDIR/${TEST}_${DATE_TM}

SERVER="127.0.0.1"        # Zabbix Server from config file
HOST="dns_test"           # Zabbix Client Name from config file

CONFDIR=/etc/zabbix
CONFFILE_DEFAULT=$CONFDIR/dns_list.ini

. $PROGPATH/zabbix_utils.sh || exit 1

# dig utility
[[ -x /usr/bin/dig ]] || exit 1
DIG_CMD=/usr/bin/dig


print_usage(){
  code=$1
  echo "Usage: $PROGNAME [-hv] -m discovery|test [-c /path/to/config/file]"
  echo " -m discovery - return to zabbix-server list of FQDN and DNS servers"
  echo " -m test      - run check for all FQDN in config file; send it to the zabbix"
  echo " -c           - config files with list of FQDNs and DNSs (default: $CONFFILE_DEFAULT)"
  exit $code
}

dig_config(){
  config=$1
  [[ ( -z $config ) || ( ! -f $config ) ]] && exit 1

  REQUESTS=         # final list of requests
  DNS_SRVS=         # final list of dns
  NS_REQ_NAME=$(basename $config | sed -e 's/\.ini$//')

  is_request=0      # mark for requests section
  is_dns=0          # mark fro dns section
  while read line; do
    # section
    if [[ $(echo "$line" | grep -v '^#' | grep '\[[^ ]\+\]' -c) -gt 0 ]]; then
      section=$(echo "$line" | sed -e 's/\[//;s/\]//;')
      is_request=0
      is_dns=0
      [[ "$section" == "requests" ]] && is_request=1
      [[ "$section" == "dns" ]] && is_dns=1
    fi

    # option
    if [[ $(echo "$line" | grep -v '^#' | grep '=' -c) -gt 0 ]]; then
      key=$(echo "$line" | awk -F'=' '{print $1}' | sed -e 's/\s\+$//;s/^\s\+//')
      val=$(echo "$line" | awk -F'=' '{print $2}' | sed -e 's/\s\+$//;s/^\s\+//')
      if [[ $is_request -gt 0 ]]; then
        REQUESTS=$REQUESTS"$key=$val "
      fi

      if [[ $is_dns -gt 0 ]]; then
        DNS=$DNS"$val "
      fi
    fi
  done < $config
  DNS=$(echo "$DNS" | sed -e 's/\s\+$//')
  REQUESTS=$(echo "$REQUESTS" | sed -e 's/\s\+$//')

  # exit if lists are empty
  [[ ( -z $DNS ) || ( -z $REQUESTS ) ]] && exit 1
}

# test fqdn name
# return 
#       0 -  DNS server return value and it fits with value in config file
#       1 -  NS server return more IPs that me tests
#       2 -  NS server return nothing 
#       3 -  NS server return less or IPs that me tests
#       4 -  NS server return 0 IP from our list
#       101 - NS server return error: Usage error
#       108 - NS server return error: Couldn't open batch file
#       ....

dig_request(){
  dig_ns=$1
  dig_rq=$2
  dig_rs=$3

  [[ ( -z $dig_ns ) || ( -z $dig_rq ) || ( -z $dig_rs ) ]] && exit 1
  status=255
  ip=

  cache_file=${TMPFILE}.dig
  dig @${dig_ns} ${dig_rq} A >$cache_file 2>&1 
  # possible DIG error codes:
  # 0: Everything went well, including things like NXDOMAIN
  # 1: Usage error
  # 8: Couldn't open batch file
  # 9: No reply from server
  # 10: Internal error
  if [[ $? -gt 0 ]]; then
    status=$(( 100 + $? ))
  else
    regexp_rq=$(echo "$dig_rq" | sed -e 's/\./\\./g')
    # test returned result
    rtn_rs=$(grep -v '^;\|^$' $cache_file | \
     grep "^$regexp_rq[\. ]" | awk '{print $NF}')
    if [[ -z $rtn_rs ]]; then
      status=4
    else
      ip=$(echo "$rtn_rs" | awk '{printf "%s,",$1}' | sed -e 's/,$//')

      # compare value(s)
      dig_rs_count=$(echo "$dig_rs" | awk -F',' '{print NF}')      # number IP in dig_rs
      rtn_rs_count=$(echo "$rtn_rs" | wc -l)      # number IP in rtn_rs
      dig_rs_miss=0       # number IP that exiten in dig_rs and not found in rtn_rs
      dig_rs_found=0      # number found IP addrees in rtn_rs
      rtn_rs_found=0      # number found IP address in dig_rs

      # test list requested IP addrees by IP addressses returned by NS server
      for dig_ip in $(echo "$dig_rs" | sed -e 's/,/ /g'); do
        dig_ip_regexp=$(echo "$dig_ip" | sed -e 's/\./\\./g')

        # test if ip exist in rtn_rs (result returned by DNS server)
        dig_ip_existen=$(echo "$rtn_rs" | sed -e 's/^\s\+//;s/\s\+$//' | \
         grep -c "^$dig_ip_regexp$")
        if [[ $dig_ip_existen  -gt 0 ]]; then
          dig_rs_found=$(( $dig_rs_found + 1 ))
          rtn_rs_found=$(( $rtn_rs_found + 1 ))
        else
          dig_rs_miss=$(( $dig_rs_miss + 1 ))
        fi
      done
      # test result and create status code
      if [[ $dig_rs_miss -gt 0 ]]; then
        status=5                              # NS server doesn't return any IP from our list     
        [[ $dig_rs_found -gt 0 ]] && status=3 # NS server doesn't return some of IP from our list
      else
        status=0                                           # nothing extra
        [[ $rtn_rs_found -lt $rtn_rs_count ]] && status=1  # found some extra found in NS server output
      fi
    fi
  fi
  rm -f $cache_file
}

# dig_status
dig_status(){
  config=$1
  dig_config $config
  # GET HOST and SERVER options from zabbix config
  get_agent_info

  # test FQDN one by one via DNS
  for dns_srv in $DNS; do
    for req_info in $REQUESTS; do
      req_fqdn=$(echo "$req_info" | awk -F'=' '{print $1}')
      req_res=$(echo "$req_info" | awk -F'=' '{print $2}')

      # fill out status and ip adress
      dig_request "$dns_srv" "$req_fqdn" "$req_res"
      if [[ $VERBOSE -gt 0 ]]; then
        echo "$dns_srv -> $req_fqdn: $req_res"
        echo "$ip; $status"
      fi

      printf "%-20s %-40s %-20s %d\n" \
        "${HOST}" "${TEST}[status,$NS_REQ_NAME,$dns_srv,$req_fqdn]"  "$DATE_TM"  "$status"  >> $TMPFILE
      printf "%-20s %-40s %-20s %s\n" \
        "${HOST}" "${TEST}[ip,$NS_REQ_NAME,$dns_srv,$req_fqdn]"  "$DATE_TM"  "$ip"  >> $TMPFILE
      sleep 2
    done
  done

  # send data to zabbix server/proxy
  send_statuses
}

# dig_discovery
dig_discovery(){
  config=$1
  dig_config $config

  DIG_LIST=

  for dns_srv in $DNS; do
    for req_info in $REQUESTS; do
      req_fqdn=$(echo "$req_info" | awk -F'=' '{print $1}')
      req_ips=$(echo "$req_info" | awk -F'=' '{print $2}')
      DIG_LIST=$DIG_LIST"REQ_FQDN=$req_fqdn;REQ_DNS=$dns_srv;RTN_IP=$req_ips "
    done
  done
  DIG_LIST=$(echo "$DIG_LIST" | sed -e 's/\s\+$//')

  echo_multi_json "$DIG_LIST"
  exit 0
}

# get command line options
while getopts ":m:c:vh" opt; do
  case $opt in
    "m")
      METRIC=$OPTARG          # requested metric
      ;;
    "c")
      CONFFILE=$OPTARG         # config file
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

[[ -z $CONFFILE ]] && CONFFILE=$CONFFILE_DEFAULT
[[ -f $CONFFILE ]] || exit 1

case $METRIC in
  'discovery')
    dig_discovery "$CONFFILE"
  ;;
  'test')
    dig_status "$CONFFILE"
  ;;
  *)
  print_usage 1
  ;;
esac

