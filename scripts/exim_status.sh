#!/bin/bash
# discovery proftpd service
# usage in template via zabbix agent
# basic from:
# https://www.zabbix.com/forum/showthread.php?t=21471(Egor Minko. Synchron LLC. May.2012)
# need add zabbix to exim group or create sudo for exipick
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

PGREP="sudo /usr/bin/pgrep -x"

. $PROGPATH/zabbix_utils.sh || exit 1

# script sudo usage
SUDO_USAGE=0

# exim options
DEFAULT_EXIMLOG=/var/log/exim/main.log
TEMP_EXIMDIR=$WORKDIR/tmp
[[ ! -d $TEMP_EXIMDIR ]] && mkdir -m 700 $TEMP_EXIMDIR

# exipick - get info from exim queue
EXIPICK_CMD=$(which exipick 2>/dev/null)
[[ -z $EXIPICK_CMD ]] && exit 1
# exim searched date in log file
EXIM_DATE=$(date +"%Y-%m-%d %H:%M" -d '-1 minutes')
# exim tail lines
EXIM_TAIL=2000

print_usage(){
  code=$1
  echo "Usage: $PROGNAME [-v] -m queue_frozen|queue_urecipients|queue_recipients|queue_total"
  echo
  echo "Usage: $PROGNAME [-v] -m <name> [-l /path/to/exim/log] [-s]"
  echo " deliver   -- Delivered Messages"
  echo " error     -- Errors Total for Messages"
  echo " defer     -- Error status: Defered Messages"
  echo " unroute   -- Error status: Unroutable address"
  echo " local     -- Local/Virtual delivery of Messages"
  echo " arrive    -- Submited Pakets"
  echo " complete  -- Finished Packets"
  echo " reject    -- Rejects Total for Packets"
  echo " badrelay  -- Reject status: Relay not permited"
  echo " blacklist -- Reject status: Rejected because IP is in a black list at .."
  echo 
  echo "Additional options:"
  echo " -l        -- path to exim log file"
  echo " -s        -- enable or disable sudo usage (default: disabled)"
  echo
  echo "Get uniq recipients number in the exim queue:"
  echo " $PROGNAME -m queue_urecipients"
  echo
  exit $code
}

exim_status(){
  metric=$1
  log=$2

  [[ ( -z $metric ) || ( -z $log ) ]] && exit 1

  metric_cache=${TMPFILE}_$(echo "$log" | md5sum | awk '{print $1}')
  logtmp=$TEMP_EXIMDIR/exim_$(basename $log)
  metric_ttl=56

  # test if cache file is valid
  use_cache=$(test_cache $metric_cache $metric_ttl)

  # create cache
  if [[ $use_cache -eq 1 ]]; then
    # queue options:
    queue_frozen=$($EXIPICK_CMD -zi | wc -l)
    queue_total=$($EXIPICK_CMD -bpc)
    queue_recipients_list=$($EXIPICK_CMD -bpu | grep -vE "^$" | \
     awk '{if ($2 == "") print $1}')
    queue_recipients=$(echo "$queue_recipients_list" | wc -l)
    queue_urecipients=$(echo "$queue_recipients_list" | sort | uniq | wc -l)

    echo "queue_frozen:$queue_frozen"           > $metric_cache
    echo "queue_urecipients:$queue_urecipients" >> $metric_cache
    echo "queue_recipients:$queue_recipients"   >> $metric_cache
    echo "queue_total:$queue_total"             >> $metric_cache

    # exim log options:
    if [[ -f $log ]]; then
      log_message="deliver:0
error:0
defer:0
unroute:0
local:0
arrive:0
complete:0
reject:0
badrelay:0
blacklist:0"

      # stat time
      logtmp_mtime=0
      [[ -f $logtmp ]] && logtmp_mtime=$(stat -c %Y $logtmp)
      log_mtime=$(stat -c %Y $log)

      # main log was changed from last update temp file
      if [[ $log_mtime -gt $logtmp_mtime ]]; then

        log_bn=$(basename $log)
        log_dir=$(dirname $log)

        #  create TMP file
        tail -n $EXIM_TAIL $log | grep "$EXIM_DATE" | \
         awk '{sub(/\]/,""); sub(/\[/,""); sub(/\)/,""); sub(/\(/,""); print}' > $logtmp


        log_list=$(find $log_dir -name "${log_bn}*" -mmin -2 -type f ! -name "$log_bn")
        if [[ -n $log_list ]]; then
          for opt_log in $log_list; do
            opt_ext_gz=$(echo $opt_log | awk -F'.' '{print $NF}' | grep -wci "gz")
            if [[ $opt_ext_gz -gt 0 ]]; then
              zcat $opt_log | tail -n $EXIM_TAIL | grep "$EXIM_DATE" | \
               awk '{sub(/\]/,""); sub(/\[/,""); sub(/\)/,""); sub(/\(/,""); print}' >> $logtmp
            else
              tail -n $EXIM_TAIL $opt_log | grep "$EXIM_DATE" | \
               awk '{sub(/\]/,""); sub(/\[/,""); sub(/\)/,""); sub(/\(/,""); print}' >> $logtmp
            fi
          done
        fi

        # process TMP file
        log_message=$(cat $logtmp | awk '\
         BEGIN {deliver=0; arrive=0; error=0; local=0; complete=0; reject=0; badrelay=0; defer=0; unroute=0; blacklist=0}\
         /[-=]>/ { deliver++ }\
         /<=/ {arrive++}\
         / \*\* / {error++}\
         /[=][=]/ {defer++}\
         /al_delivery/ {local++}\
         /Completed/ {complete++}\
         /rejected/ {reject++}\
         /relay not permitted/ {badrelay++}\
         /Unrouteable address/ {unroute++}\
         / is in a black list at/ {blacklist++}\
        END {printf "error:%d\n",error;\
         printf "deliver:%d\n",deliver;\
         printf "arrive:%d\n",arrive;\
         printf "defer:%d\n",defer;\
         printf "local:%d\n",local;\
         printf "complete:%d\n",complete;\
         printf "reject:%d\n",reject;\
         printf "badrelay:%d\n",badrelay;\
         printf "unroute:%d\n",unroute;\
         printf "blacklist:%d\n",blacklist;\
      }')
      fi
      echo "$log_message" >> $metric_cache
    fi

  fi

  # get metric
  grep "^$metric:" $metric_cache | awk -F':' '{print $2}'
}

while getopts ":l:m:vhs" opt; do
  case $opt in
    "m")
      METRIC=$OPTARG          # requested metric
      ;;
    "l")
      EXIMLOG=$OPTARG         # exim main log file
      ;;
    "s")
      SUDO_USAGE=1
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

[[ -z $EXIMLOG ]] && EXIMLOG=$DEFAULT_EXIMLOG
if [[ $SUDO_USAGE -eq 1 ]]; then 
  EXIPICK_CMD="sudo $EXIPICK_CMD"
fi

if [[ "$METRIC" == "process" ]]; then
  $PGREP "exim" | wc -l
else
  exim_status "$METRIC" "$EXIMLOG"
fi
