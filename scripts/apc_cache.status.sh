#!/bin/sh

### apc stats
### uses a php script that returns a value, third argument passed to url

### DESCRIPTION
# $1 -  uri to apc.stat.php
# $2 - type of value
# cache - cache data
# files - file/system cache information
# user - user cache information
# memory - memory information
# $3 - name of requested value
# cache:
#       uptime - uptime for cache - information trigger if changed ( uptime.current < uptime.last )
# file/user:
#       mem_size     - memory size usage by files/user cache ( in Bytes )
#       num_hits     - number of hits for cache ( counter )
#       num_misses   - number of misses for cache ( counter )
#       num_entries  - number of entries in the cache
#       num_inserts  - number of inserts ( counter )
# memory
#       mem_total    - amount of available memory
#       mem_free     - amount of free memory    - avg trigger if mem_free = 0 
#       mem_frg      - amount of fragmented memory
# return value, can be used for active or routine zabbix checks
DEBUG=0
PROGNAME=`basename $0`

## functions
#### help message
function help_message {
    exit_code=$1

    if [[ $DEBUG -gt 0 ]]; then
        printf "%s - %s\n" "Usage script \`$PROGNAME\`" " to obtain the information about APC cache status"
        printf "%s\n" "Usage:"
        printf "%5s %s\n" "*" "Get information about cache"
        printf "%-5s %s\n" " " "$PROGNAME cache uptime [uri]"
        printf "%5s %s\n" " " "Example: $PROGNAME cache uptime http://192.168.0.4/admin/zabbix_apc.php"
        printf "\n"

        printf "%5s %s\n" "*" "Get information about system or user cache"
        printf "%-5s %s\n" " " "$PROGNAME user|file mem_size|num_hits|num_misses|num_entries|num_inserts [uri]"
        printf "\n"

        printf "%5s %s\n" "*" "Get information about memory status"
        printf "%-5s %s\n" " " "$PROGNAME memory mem_total|mem_free|mem_frg"
        printf "\n"

    fi

    exit $exit_code;
}


typ=$1
par=$2
uri=$3
curl=/usr/bin/curl

if [[ ( -z $typ ) || ( -z $uri ) ]]; then
    help_message 1
fi

### OPTIONS VERIFICATION
if [[ -z "$uri" ]]; then
    URL="http://127.0.0.1/admin/zabbix_apc.php"
fi

# page test
head=`$curl -I $uri 2> /dev/null`
is_exist=`echo "$head" | grep "200 OK" -c`
[[ $is_exist -eq 0 ]] && exit 1

# get data
data=`$curl $uri 2> /dev/null`
[[ $DEBUG -gt 0 ]] && echo $data


# get data
if [[ $par = "mem_frg" ]] ; then
    vars_mem_size=`echo "$data" | grep '^user: mem_size:'   | awk '{print $3}'`
    memo_tot_size=`echo "$data" | grep '^memory: mem_total:' | awk '{print $3}'`
    memo_mem_aval=`echo "$data" | grep '^memory: mem_free:' | awk '{print $3}'`
    file_mem_size=`echo "$data" | grep '^file: mem_size:'   | awk '{print $3}'`
    
    echo_data=`echo "$memo_tot_size-$memo_mem_aval-$vars_mem_size-$file_mem_size"|bc`
    
else

    echo_data=`echo "$data" | grep -i "^$typ: $par:" | awk '{print $3}'`
    
fi

echo -n "$echo_data"

exit 0
