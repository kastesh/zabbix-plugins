#!/bin/bash
# discovery proftpd service
# usage in template via zabbix agent
# need to create sudo for view dovecot logs
# dovecot examples log: http://ossec-docs.readthedocs.org/en/latest/log_samples/email/dovecot.html
#
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

# script sudo usage
SUDO_USAGE=0

# exim options
DEFAULT_DVLOG=/var/log/maillog
TEMP_LOGDIR=$WORKDIR/tmp
[[ ! -d $TEMP_LOGDIR ]] && mkdir -m 700 $TEMP_LOGDIR

# syslog searched date in log file
LOG_DATE=$(date +"%b %e %H:%M:" -d '-1 minutes')
# tail lines
LOG_TAIL=200

# sudo tail
TAIL_CMD=$(which tail 2>/dev/null)
[[ -z $TAIL_CMD ]] && exit 1
TAIL_CMD="sudo $TAIL_CMD -n $LOG_TAIL"

print_usage(){
  code=$1
  echo "Get number process for Dovecot (usage sudo for CloudLinux case):"
  echo " $PROGNAME [-v] -m process -n dovecot-auth|pop3-login|imap-login"
  echo 
  echo "Get number login/logout and errors for imap/pop3 process:"
  echo " $PROGNAME [-v] -n imap -m login|logout|error"
  echo " $PROGNAME [-v] -n pop3 -m login|logout|error -l /var/log/maillog"
  echo
  exit $code
}

dovecot_status(){
  pname=$1
  metric=$2
  log=$3

  [[ ( -z $metric ) || ( -z $pname ) || ( -z $log ) ]] && exit 1
  [[ ! -f $log ]] && exit 1

  metric_cache=${TMPFILE}_$(echo "$log" | md5sum | awk '{print $1}')
  logtmp=$TEMP_LOGDIR/dovecot_$(basename $log)
  metric_ttl=56

  # test if cache file is valid
  use_cache=$(test_cache $metric_cache $metric_ttl)

  # create cache
  # process_name:metric_name:metric_value
  if [[ $use_cache -eq 1 ]]; then
    log_message="imap_login:0
imap_logout:0
imap_error:0
pop3_login:0
pop3_logout:0
pop3_error:0"
    # test logs modify times; run only if main log has changes from last check
    logtmp_mtime=0
    [[ -f $logtmp ]] && logtmp_mtime=$(stat -c %Y $logtmp)
    log_mtime=$(stat -c %Y $log)

    # 
    if [[ $log_mtime -gt $logtmp_mtime ]]; then
      
      # get info from current log file
      $TAIL_CMD $log | grep "$LOG_DATE" | \
       grep -w dovecot | awk -F':' '{print $4,$5}' > $logtmp

      # test recently rotate logs
      log_bn=$(basename $log)
      log_dir=$(dirname $log)
      log_list=$(find $log_dir -name "${log_bn}*" -mmin -2 -type f ! -name "$log_bn" 2>/dev/null)
      if [[ -n $log_list ]]; then
        for opt_log in $log_list; do
          opt_ext_gz=$(echo $opt_log | awk -F'.' '{print $NF}' | grep -wci "gz")
          opt_ext_cmd="$TAIL_CMD $opt_log"
          [[ $opt_ext_gz -gt 0 ]] && opt_ext_cmd="sudo /bin/zcat $opt_log | tail -n $LOG_TAIL"
          $opt_ext_cmd | grep "$LOG_DATE" | \
           grep -w dovecot | awk -F':' '{print $4,$5}' >> $logtmp
        done
      fi

      # create statistics
      log_message=$(cat $logtmp | awk '\
       BEGIN{imap_logout=0; imap_login=0; imap_error=0;\
       pop3_logout=0; pop3_login=0; pop3_error=0}\
       /pop3-login  Login/          { pop3_login++ }\
       /POP3\([^\)]+\)/             { pop3_logout++ }\
       /pop3-login  Aborted login/  { pop3_error++ }\
       /pop3-login  Disconnected/   { pop3_error++ }\
       /pop3-login  Maximum number of connections/ { pop3_error++ }\
       /imap-login  Login/          { imap_login++ }\
       /IMAP\([^\)]+\)/             { imap_logout++ }\
       /imap-login  Aborted login/  { imap_error++ }\
       /imap-login  Disconnected/   { imap_error++ }\
       /imap-login  Maximum number of connections/ { imap_error++ }\
       END{\
       printf "imap_login:%d\nimap_logout:%d\nimap_error:%d\n", imap_login,imap_logout,imap_error;\
       printf "pop3_login:%d\npop3_logout:%d\npop3_error:%d\n", pop3_login,pop3_logout,pop3_error;}')
    fi
    echo "$log_message" > $metric_cache
  fi

  grep "^${pname}_${metric}:" $metric_cache | awk -F':' '{print $2}'
}

while getopts ":l:n:m:vh" opt; do
  case $opt in
    "m")
      METRIC=$OPTARG          # requested metric
      ;;
    "l")
      LOG=$OPTARG         # log file
      ;;
    "n")
      PNAME=$OPTARG
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

[[ -z $LOG ]] && LOG=$DEFAULT_DVLOG

if [[ "$METRIC" == "process" ]]; then
  sudo /etc/init.d/$PNAME status 2>/dev/null | grep -c 'is running'
else
  dovecot_status "$PNAME" "$METRIC" "$LOG"
fi
