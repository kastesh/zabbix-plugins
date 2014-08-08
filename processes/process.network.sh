#!/bin/sh

### cpu usage by process
### 

### DESCRIPTION
# $1 -  status
#       ESTABLISHED     connection up and passing data
#       SYN_SENT        session has been requested by us;
#                       waiting for reply from remote endpoint
#       SYN_RECV        session has been requested by a remote endpoint
#                       for a socket on which we were listening
#       FIN_WAIT1       our socket has closed;
#                       we are in the process of tearing down the connection
#       FIN_WAIT2       the connection has been closed;
#                       our socket is waiting for the remote endpoint to shut down
#       TIME_WAIT       socket is waiting after closing
#                       for any packets left on the network
#       CLOSE_WAIT      remote endpoint has shut down;
#                       the kernel is waiting for the application to close the socket
#       LISTEN          accepting connections
#       TCP             tcp connections
#       UDP             udp connections
# count values:
#       total
### EXAMPLE
# if                $1 = mysqld:w2:3308,mysqld:w3:3307,mysqld:w14:3309,mysqld:w18:3310,nginx:80,searchd:tabs:3314,searchd:099rc2:3313
#                   process.network[ESTABLISHED,mysqld,w3]
#                   process.network[SYN_SENT,mysqld,master]
#                   ....
#                   process.network[TOTAL,mysqld,master]
#                   ...
#                   process.network[tcp,all]
#                   process.network[udp,all]
#                   process.network[file_socket,all]
# service string_format: service_name01:instance_name01:port_number01,service_name02:port_number02,...

### OPTIONS VERIFICATION
if [[ -z "$1" ]]; then
    exit 1
fi

# define services and instances
def_services=$1
#echo $def_services

DEBUG=0
WORK=/home/zabbix20
TMP=$WORK/tmp
CONF=$WORK/etc

export PATH=$PATH:$WORK/bin
ZABBIX_CONF=$CONF/zabbix_agentd.conf
ZABBIX_BIN=zabbix_sender

SAVE_STAT=0         # save statistics for process that not defined in command line: 0 -> not save; 1 -> save

# get server IP
SERVER=""
HOST=""

# get server and host optionf for sender
function get_agent_info {

    # get zabbix server name or address
    if [[ "$SERVER" = "" ]]; then
        SERVER=`grep -v "^$\|^#" $ZABBIX_CONF | grep "Server=" | awk -F'=' '{print $2}'`
        IF_SEVERAL=`echo "$SERVER" | grep -c ','`
        if [[ $IF_SEVERAL -gt 0 ]]; then
            SERVER=`echo "$SERVER" | awk -F',' '{print $1}'`
        fi
    fi
    [[ $DEBUG -gt 0 ]] && printf "%-15s: %s\n" "Send data to" "$SERVER"

    # get hostname
    if [[ "$HOST" = "" ]]; then
        HOST=`grep -v "^$\|^#" $ZABBIX_CONF | grep "Hostname=" | awk -F'=' '{print $2}'`
        if [[ -z $HOST ]]; then
            HOST=`hostname`
        fi
    fi
    [[ $DEBUG -gt 0 ]] && printf "%-15s: %s\n" "Hostname" "$HOST"
}

### CREATE TMP DATA
date=`date +%Y%m%d%H`
send_date=`date '+%s'`
human_date=`date +"%d/%m/%Y %H:%M:%S"`

# create directories for temporary data
CACHEDIR=${TMP}/process_network
[[ -d "$CACHEDIR" ]] || mkdir -p $CACHEDIR
SAVEDIR=${CACHEDIR}/logs
[[ $SAVE_STAT -eq 1 ]] && ( [[ -d $SAVE_STAT ]] || mkdir -p $SAVE_STAT  )


### CREATE TMP DATA
SEND=$CACHEDIR/$send_date
STATFILE=$SAVEDIR/$date.process_stats.txt
STATLINK=$SAVEDIR/process_stats.txt
ZABBIX_PREFIX='process.network'

get_agent_info

### NETWORK_ADDR
other_addrs=`/sbin/ifconfig -a | egrep -o "inet addr:[0-9.]+" | awk -F':' '{print $2}'`
addrs_regex='\(0\.0\.0\.0\|'

for addr in $other_addrs
do
    # hide dot char
    addr_regex=`echo $addr | sed -e 's/\./\\\./g'`

    addrs_regex=$addrs_regex$addr_regex"\|"
done
addrs_regex=$addrs_regex"\)\:"
#echo $addrs_regex

### CREATE DATA
connections_data=`netstat -an`

# create common statistics
udp_conns=`echo "$connections_data"    | grep "^udp" -c`
let "udp_conns += 0"
printf "%-20s %-40s %-20s %-d\n" "${HOST}" "${ZABBIX_PREFIX}[udp,all]"  "$send_date"  "$udp_conns"  > $SEND

# TCP
tcp_data=`echo "$connections_data"     | grep "^tcp"`
tcp_conns=`echo "$tcp_data"            | wc -l `
let "tcp_conns += 0"
printf "%-20s %-40s %-20s %-d\n" "${HOST}" "${ZABBIX_PREFIX}[tcp,all]"  "$send_date"  "$tcp_conns"  >> $SEND


# UNIX SOCKET
socket_conns=`echo "$connections_data" | grep "^unix" -c`
let "socket_conns += 0"
printf "%-20s %-40s %-20s %-d\n" "${HOST}" "${ZABBIX_PREFIX}[file_socket,all]"  "$send_date"  "$socket_conns"  >> $SEND

###############################################
# total TCP connection by type
###############################################
tcp_types=`echo "$tcp_data" | awk '{print $6}' | sort | uniq -c `
#echo "---------------------------------"
#echo $tcp_types
#echo "---------------------------------"
cache_conns=""
# create and save stats
function all_connections {
    connection_type=$1

    num_conns=0
    num_conns=`echo "$tcp_types" | egrep -o "[0-9]+ $connection_type" | awk '{print $1}' | sed 's/ //g'`
    let "num_conns += 0"
    printf "%-20s %-40s %-20s %-d\n" "${HOST}" "${ZABBIX_PREFIX}[$connection_type,all]"  "$send_date"  "$num_conns"  >> $SEND

    cache_conns=$cache_conns" "$connection_type"="$num_conns
    

}
# SYN_SENT 
all_connections "SYN_SENT"    "$tcp_data" "$SEND"
all_connections "SYN_RECV"    "$tcp_data" "$SEND"
all_connections "LISTEN"      "$tcp_data" "$SEND"
all_connections "ESTABLISHED" "$tcp_data" "$SEND"
all_connections "CLOSE_WAIT"  "$tcp_data" "$SEND"
all_connections "TIME_WAIT"   "$tcp_data" "$SEND"
all_connections "FIN_WAIT1"   "$tcp_data" "$SEND"
all_connections "FIN_WAIT2"   "$tcp_data" "$SEND"

#echo $cache_conns

function other_connection {
    connection_type=$1
    connection_def=$2

    for def in $cache_conns
    do
        if_found=`echo $def | grep -c "^$connection_type"`
        if [[ $if_found -gt 0 ]]; then
    #        echo found
            total_conn=`echo $def | awk -F'=' '{print $2}'`
            rest=`echo "$total_conn-$connection_def" |bc`

            cache_conns=`echo "$cache_conns" | sed "s/$connection_type\=$total_conn/$connection_type\=$rest/"`
        fi
    done
}

# create stati by service
services=`echo "$def_services" | sed 's/\;/ /g'`
#echo "$services"
total_app=0

for service_def in $services
do
    #echo $service_def
    service_name=`echo "$service_def" | awk -F':' '{print $1}'`
    service_inst=`echo "$service_def" | awk -F':' '{print $2}'`
    service_port=`echo "$service_def" | awk -F':' '{print $3}'`
    if_inst=1

    # initial values
    listen_var_val=0
    establ_var_val=0
    t_wait_var_val=0
    c_wait_var_val=0
    s_sent_var_val=0
    s_recv_var_val=0
    totals_var_val=0
    others_var_val=0

    if [[ -z "$service_port" ]]; then
        service_port=$service_inst
        if_inst=0
    fi

    item_name=$service_name
    if [[ $if_inst -eq 1 ]]; then
        item_name=$service_name','$service_inst
    fi

    if_several_ports=`echo "$service_port" | grep -c '\,'`
    service_port_regexp="\("
    if [[ $if_several_ports -gt 0 ]] ; then
        for port in `echo $service_port | sed 's/\,/ /g'`
        do
            service_port_regexp=$service_port_regexp$port'\|'
        done
        service_port_regexp=`echo $service_port_regexp | sed 's/\\\|$//'`
        service_port_regexp=$service_port_regexp"\)"
    else
        service_port_regexp=$service_port
    fi
    [[ $DEBUG -gt 0 ]] && printf "%-15s: %s\n" "Grep by" $service_port_regexp


    # get statistics data for defined port
    listen_var_val=`echo "$tcp_data"  | grep "$addrs_regex$service_port_regexp " | grep "LISTEN" -c`
    [[ $DEBUG -gt 0 ]] && printf "%-15s: %s\n" "$item_name LISTEN" $listen_var_val

    printf "%-20s %-40s %-20s %-d\n" "${HOST}" "${ZABBIX_PREFIX}[LISTEN,$item_name]"      "$send_date"  "$listen_var_val"  >> $SEND
    other_connection "LISTEN" $listen_var_val

    establ_var_val=`echo "$tcp_data"  | grep "$addrs_regex$service_port_regexp " | grep "ESTABLISHED" -c`
    [[ $DEBUG -gt 0 ]] && printf "%-15s: %s\n" "$item_name ESTABLISHED" $establ_var_val

    printf "%-20s %-40s %-20s %-d\n" "${HOST}" "${ZABBIX_PREFIX}[ESTABLISHED,$item_name]" "$send_date"  "$establ_var_val"  >> $SEND
    other_connection "ESTABLISHED" $establ_var_val

    t_wait_var_val=`echo "$tcp_data"  | grep "$addrs_regex$service_port_regexp " | grep "TIME_WAIT" -c`
    [[ $DEBUG -gt 0 ]] && printf "%-15s: %s\n" "$item_name TIME_WAIT" $t_wait_var_val

    printf "%-20s %-40s %-20s %-d\n" "${HOST}" "${ZABBIX_PREFIX}[TIME_WAIT,$item_name]"   "$send_date"  "$t_wait_var_val"  >> $SEND
    other_connection "TIME_WAIT" $t_wait_var_val

    c_wait_var_val=`echo "$tcp_data"  | grep "$addrs_regex$service_port_regexp " | grep "CLOSE_WAIT" -c`
    [[ $DEBUG -gt 0 ]] && printf "%-15s: %s\n" "$item_name CLOSE_WAIT" $c_wait_var_val

    printf "%-20s %-40s %-20s %-d\n" "${HOST}" "${ZABBIX_PREFIX}[CLOSE_WAIT,$item_name]"  "$send_date"  "$c_wait_var_val"  >> $SEND
    other_connection "CLOSE_WAIT" $c_wait_var_val

    s_sent_var_val=`echo "$tcp_data"  | grep "$addrs_regex$service_port_regexp " | grep "SYN_SENT" -c`
    [[ $DEBUG -gt 0 ]] && printf "%-15s: %s\n" "$item_name SYN_SENT" $s_sent_var_val
   
    printf "%-20s %-40s %-20s %-d\n" "${HOST}" "${ZABBIX_PREFIX}[SYN_SENT,$item_name]"    "$send_date"  "$s_sent_var_val"  >> $SEND
#    echo $s_sent_var_val
    other_connection "SYN_SENT" $s_sent_var_val

    s_recv_var_val=`echo "$tcp_data"  | grep "$addrs_regex$service_port_regexp " | grep "SYN_RECV" -c`
    [[ $DEBUG -gt 0 ]] && printf "%-15s: %s\n" "$item_name SYN_RECV" $s_recv_var_val
    printf "%-20s %-40s %-20s %-d\n" "${HOST}" "${ZABBIX_PREFIX}[SYN_RECV,$item_name]"    "$send_date"  "$s_recv_var_val"  >> $SEND
    other_connection "SYN_RECV" $s_recv_var_val


    fin_wait1_var_val=`echo "$tcp_data"  | grep "$addrs_regex$service_port_regexp " | grep "FIN_WAIT1" -c`
    fin_wait2_var_val=`echo "$tcp_data"  | grep "$addrs_regex$service_port_regexp " | grep "FIN_WAIT2" -c`
    printf "%-20s %-40s %-20s %-d\n" "${HOST}" "${ZABBIX_PREFIX}[FIN_WAIT1,$item_name]"      "$send_date"  "$fin_wait1_var_val"  >> $SEND
    printf "%-20s %-40s %-20s %-d\n" "${HOST}" "${ZABBIX_PREFIX}[FIN_WAIT2,$item_name]"      "$send_date"  "$fin_wait2_var_val"  >> $SEND
    [[ $DEBUG -gt 0 ]] && printf "%-15s: %s\n" "$item_name FIN_WAIT1" $fin_wait1_var_val
    [[ $DEBUG -gt 0 ]] && printf "%-15s: %s\n" "$item_name FIN_WAIT2" $fin_wait2_var_val

    other_connection "FIN_WAIT1" $fin_wait1_var_val
    other_connection "FIN_WAIT2" $fin_wait2_var_val
#    echo $others_var_val

    totals_var_val=`echo "$tcp_data"  | grep "$addrs_regex$service_port_regexp " -c`
    printf "%-20s %-40s %-20s %-d\n" "${HOST}" "${ZABBIX_PREFIX}[TOTAL,$item_name]"       "$send_date"  "$totals_var_val"  >> $SEND
#    echo $totals_var_val
    [[ $DEBUG -gt 0 ]] && printf "%-15s: %s\n" "$item_name TOTAL" $totals_var_val
    total_app=`echo "$total_app+$totals_var_val" | bc`

#    echo $cache_conns
done
#echo $cache_conns

# save data for ther open connections
for def_other in $cache_conns
do
    other_type=`echo $def_other | awk -F'=' '{print $1}'`
    other_val=`echo $def_other | awk -F'=' '{print $2}'`
    printf "%-20s %-40s %-20s %-d\n" "${HOST}" "${ZABBIX_PREFIX}[$other_type,others]"      "$send_date"  "$other_val"  >> $SEND
done
printf "%-20s %-40s %-20s %-d\n" "${HOST}" "${ZABBIX_PREFIX}[TOTAL,others]"      "$send_date"  `echo "$tcp_conns-$total_app"|bc`  >> $SEND

# send data to zabbix
ZABBIX_TRAP=`$ZABBIX_BIN --zabbix-server ${SERVER} --host $HOST -i $SEND --with-timestamps`
failed=`echo $ZABBIX_TRAP | egrep -o 'Failed [0-9]+' | awk '{print $2}'`

[[ $DEBUG -gt 0 ]] && printf "%-15s: %s\n" "Temp file" "$SEND"
[[ $DEBUG -gt 0 ]] && printf "%-15s: %s\n" "Failed" "$failed"


# if no failed sending => delete send file and check for old data
if [[ $failed -eq 0 ]]; then
    rm -f $SEND >> /dev/null
fi

exit 0

