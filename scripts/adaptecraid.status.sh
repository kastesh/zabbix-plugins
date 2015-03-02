#!/bin/sh
### DESCRIPTION:
### The script obtain the information about Adaptec RAID for zabbix server
### It can be used to obtain information through active checks, and by sending values ​​through a trapper mechanism.
###
### COMMANDLINE OPTIONS:
### $1 - type of device
###     ad - RAID controller info
###     ld - Logical Device info
###     pd - Physical Device info
### $2 - requested option name
### ad:
###     model 		- model name + serial number ( ex. "model: Adaptec 2405; serial: 2D0611E50B9; bios: 5.2-0 (18948)" )
###		status		- status of RAID controller ( ex. 0 - Optimal, 1 - Failed, 2 - Degraded, 255 - Unknown/Other )
###		temperature	- current temperature of RAID controller
###		all			-  send all previously defined options to zabbix server by zabbix trapper
### ld:
###		level		- RAID level for logical device
###		status		- RAID status
###		size		- RAID size (Byte)
###		rc_mode		- Read-cache mode (ex. 0 - Enabled, 1 -Disabled, 255 -Unknown/Other )
###		wc_mode		- Write-cache mode (ex. 0 - Enabled, 1 -Disabled, 255 -Unknown/Other )
###		wc_setting	- Write-cache Settings (ex. 0 - Enabled, 1 -Disabled, 255 -Unknown/Other )
###		all			-  send all previously defined options to zabbix server by zabbix trapper
### pd:
###		model		- vendor name + model name + serial number + transfer speed ( ex. "vendor: SEAGATE; model: ST3450856SS; serial: 3QQ0J217; transfer_speed: SAS 3.0 Gb/s" )
###		size		- size of physical device (Byte)
###		status		- physical device status ( 0 - Online, 1 - Offline, 255 - Unknown )
###		all			-  send all previously defined options to zabbix server by zabbix trapper
### $3 - RAID controller number (default = 1 )
### $4 - logical or physical device number ( default = 0 )
DEBUG=1
PROGNAME=`basename $0`
WORK=/home/zabbix20
TMP=$WORK/tmp
ZCONF=$WORK/etc/zabbix_agentd.conf
ZBIN=$WORK/bin/zabbix_sender
ARCCONF_BIN="sudo /opt/manage/bin/arcconf getconfig"

# get server IP
SERVER=""

# get hostname
HOST=""

### FUNCTIONS:
#### set variables for all check
function set_all_variables {
	type_check=$1

	case $type_check in
	"ad")
		AD_MODEL=0
		AD_STATUS=1
		AD_TEMPERATURE=1
	;;
	"ld")
		LD_LEVEL=0
		LD_STATUS=1
		LD_SIZE=0
		LD_RC_MODE=1
		LD_WC_MODE=1
		LD_WC_SETTING=1
	;;
	"pd")
		PD_MODEL=0
		PD_SIZE=0
		PD_STATUS=1
	;;
	esac

	DATE=`date '+%s'`
	PREFIX="adaptecraid.status"
	CACHE_DIR=${TMP}/${PREFIX}
	CACHE_FILE=${CACHE_DIR}/${DATE}_${type_check}
	
	[[ ! -d $CACHE_DIR ]] && mkdir -p $CACHE_DIR
}
#### get server and host options for zabbix_sender command
function get_agent_info {

    # get zabbix server name or address
    if [[ "$SERVER" = "" ]]; then
        SERVER=`grep -v "^$\|^#" $ZCONF | grep "Server=" | awk -F'=' '{print $2}'`
        IF_SEVERAL=`echo "$SERVER" | grep -c ','`
        if [[ $IF_SEVERAL -gt 0 ]]; then
            SERVER=`echo "$SERVER" | awk -F',' '{print $1}'`
        fi
    fi
    [[ $DEBUG -gt 0 ]] && printf "%-15s: %s\n" "Send data to" "$SERVER"

    # get hostname
    if [[ "$HOST" = "" ]]; then
        HOST=`grep -v "^$\|^#" $ZCONF | grep "Hostname=" | awk -F'=' '{print $2}'`
        if [[ -z $HOST ]]; then
            HOST=`hostname`
        fi
    fi
    [[ $DEBUG -gt 0 ]] && printf "%-15s: %s\n" "Hostname" "$HOST"
}

#### help message
function help_message {
    exit_code=$1

    if [[ $DEBUG -gt 0 ]]; then
		printf "%s - %s\n" "Usage script \`$PROGNAME\`" " obtain the information about Adaptec RAID for zabbix server"
		printf "%s\n" "Usage:"
		printf "%5s %s\n" "*" "Get information about RAID controller"
		printf "%-5s %s\n" " " "$PROGNAME ad model|status|temperature|all [controller_number]"
		printf "%5s %s\n" " " "Example: $PROGNAME ad model 1"
		printf "\n"

		printf "%5s %s\n" "*" "Get information about RAID Logical device"
		printf "%-5s %s\n" " " "$PROGNAME ld level|size|status|rc_mode|wc_mode|wc_setting|all [controller_number] [logical_device_number]"
		printf "\n"

		printf "%5s %s\n" "*" "Get information about RAID Physical device"
		printf "%-5s %s\n" " " "$PROGNAME pd model|size|status|all [controller_number] [physical_device_number]"
		printf "\n"

		printf "%5s %s\n" "*" "Get help"
		printf "%-5s %s\n" " " "$PROGNAME help|-h|--help"
		printf "\n"
    fi

    exit $exit_code;
}

#### send data to zabbix server by sender
function send_by_sender {
	sender_server=$1
	sender_host=$2
	sender_file=$3

	SENDER_DATA=`$ZBIN --zabbix-server $sender_server -s $sender_host -i $sender_file  --with-timestamps`
	SENDER_FAILED=`echo $SENDER_DATA | egrep -o 'Failed [0-9]+' | awk '{print $2}'`

	[[ $DEBUG -gt 0 ]] && printf "%-15s: %s\n" "Temp file" "$sender_file"
	[[ $DEBUG -gt 0 ]] && printf "%-15s: %s\n" "Failed" "$SENDER_FAILED"

	# check is data send or not
    if [[ $SENDER_FAILED -eq 0 ]]; then
		rm -f $sender_file
        exit 0
    fi

    exit 1
}

device_type=$1

# 01 check commandline options
if [[ "$#" -ne 4  &&  "$#" -ne 3 && "$#" -ne 2  ]]; then
    help_message 1
fi


case "$device_type" in
"ad")
	
	controller_o=$2
	controller_n=$3

	# define controller number
	[[ -z $controller_n ]] && controller_n=1

	# processing of the specified parameter check
	case $controller_o in
	"model")
		# model: Adaptec 2405; serial: 2D0611E50B9; bios: 5.2-0 (18948)
		controller_data=`$ARCCONF_BIN $controller_n AD | grep "\(Controller Model\|Controller Serial Number\|BIOS\|Firmware\|Driver\|Boot Flash\)"`
		controller_model=` echo "$controller_data" | grep "Controller Model"         | awk -F':' '{print $2}' | sed -e 's/^\s\+//'`
		controller_serial=`echo "$controller_data" | grep "Controller Serial Number" | awk -F':' '{print $2}' | sed -e 's/^\s\+//'`
		controller_bios=`  echo "$controller_data" | grep "BIOS"                     | awk -F':' '{print $2}' | sed -e 's/^\s\+//'`
		controller_firm=`  echo "$controller_data" | grep "Firmware"                 | awk -F':' '{print $2}' | sed -e 's/^\s\+//'`
		controller_driver=`echo "$controller_data" | grep "Driver"                   | awk -F':' '{print $2}' | sed -e 's/^\s\+//'`
		controller_bflash=`echo "$controller_data" | grep "Boot Flash"               | awk -F':' '{print $2}' | sed -e 's/^\s\+//'`

		echo -n "model: $controller_model; serial: $controller_serial; bios/firmware/driver/boot_flash: $controller_bios/$controller_firm/$controller_driver/$controller_bflash"
	;;
	"status")
		controller_status=`$ARCCONF_BIN $controller_n AD | grep "Controller Status" | awk -F':' '{print $2}' | sed -e 's/^\s\+//'`

		controller_status_info=255
		[[ "$controller_status" = "Optimal"  ]]  && controller_status_info=0
		[[ "$controller_status" = "Failed"   ]]  && controller_status_info=1
		[[ "$controller_status" = "Degraded" ]]  && controller_status_info=2
	;;
	"temperature")
		controller_temp=`$ARCCONF_BIN $controller_n AD | grep "Temperature" | awk -F':' '{print $2}' | awk -F'/' '{print $1}' | sed -e 's/^\s\+//' | awk '{print $1}'`
		echo -n $controller_temp
	;;
	"all")
		send_options_number=0
		
		set_all_variables "ad"

		get_agent_info

		controller_data=`$ARCCONF_BIN $controller_n AD | grep "\(Controller Model\|Controller Serial Number\|BIOS\|Firmware\|Driver\|Boot Flash\|Controller Status\|Temperature\)"`
		controller_model=` echo "$controller_data" | grep "Controller Model"         | awk -F':' '{print $2}' | sed -e 's/^\s\+//'`
		controller_serial=`echo "$controller_data" | grep "Controller Serial Number" | awk -F':' '{print $2}' | sed -e 's/^\s\+//'`
		controller_bios=`  echo "$controller_data" | grep "BIOS"                     | awk -F':' '{print $2}' | sed -e 's/^\s\+//'`
		controller_firm=`  echo "$controller_data" | grep "Firmware"                 | awk -F':' '{print $2}' | sed -e 's/^\s\+//'`
		controller_driver=`echo "$controller_data" | grep "Driver"                   | awk -F':' '{print $2}' | sed -e 's/^\s\+//'`
		controller_bflash=`echo "$controller_data" | grep "Boot Flash"               | awk -F':' '{print $2}' | sed -e 's/^\s\+//'`
		controller_status=`echo "$controller_data" | grep "Controller Status"        | awk -F':' '{print $2}' | sed -e 's/^\s\+//'`
		controller_temp=`  echo "$controller_data" | grep "Temperature"		         | awk -F':' '{print $2}' | awk -F'/' '{print $1}' | sed -e 's/^\s\+//' | awk '{print $1}'`

		controller_model_info=`echo -n "model: $controller_model; serial: $controller_serial; bios/firmware/driver/boot_flash: $controller_bios/$controller_firm/$controller_driver/$controller_bflash"`
		
		controller_status_info=255
		[[ "$controller_status" = "Optimal"  ]]  && controller_status_info=0
		[[ "$controller_status" = "Failed"   ]]  && controller_status_info=1
		[[ "$controller_status" = "Degraded" ]]  && controller_status_info=2


		[[ $AD_MODEL  -gt 0 ]]      && printf "%-20s %-40s %-20s %-100s\n" "${HOST}" "${PREFIX}[ad,model,$controller_n]"       "$DATE"  "$controller_model_info"  >> $CACHE_FILE && send_options_number=1
		[[ $AD_STATUS -gt 0 ]]      && printf "%-20s %-40s %-20s %-100d\n" "${HOST}" "${PREFIX}[ad,status,$controller_n]"      "$DATE"  "$controller_status_info" >> $CACHE_FILE && send_options_number=1
		[[ $AD_TEMPERATURE -gt 0 ]] && printf "%-20s %-40s %-20s %-100d\n" "${HOST}" "${PREFIX}[ad,temperature,$controller_n]" "$DATE"  "$controller_temp"        >> $CACHE_FILE && send_options_number=1
		 
		[[ $send_options_number -gt 0 ]] && send_by_sender "$SERVER" "$HOST" "$CACHE_FILE"
	;;
	*)
		help_message 1
	;;
	esac
;;
"ld")
	# level|size|status|rc_mode|wc_mode|wc_setting|all [controller_number] [logical_device_number]
	logicaldev_o=$2
	controller_n=$3
	logicaldev_n=$4

	# define controller number
	[[ -z $controller_n ]] && controller_n=1

	case $logicaldev_o in
	"level")
		logicaldev_raid=`$ARCCONF_BIN $controller_n LD$logicaldev_n | grep "RAID level" | awk -F':' '{print $2}' | sed -e 's/^\s\+//'`
		echo -n $logicaldev_raid
	;;
	"size")
		logicaldev_size=`$ARCCONF_BIN $controller_n LD$logicaldev_n | grep "Size"       | awk -F':' '{print $2}' | sed -e 's/^\s\+//'`
		
		l_size=`echo "$logicaldev_size" | awk '{print $1}'`
		l_dime=`echo "$logicaldev_size" | awk '{print $2}'`

		lsize_info=$l_size
		
		[[ "$l_dime" = "GB" ]] && lsize_info=`echo "$l_size*1073741824" |bc`
		[[ "$l_dime" = "MB" ]] && lsize_info=`echo "$l_size*1048576"    |bc`
		[[ "$l_dime" = "KB" ]] && lsize_info=`echo "$l_size*1024"       |bc`
		echo -n $lsize_info
	;;
	"status")
		logicaldev_status=`$ARCCONF_BIN $controller_n LD$logicaldev_n | grep "Status of logical device" | awk -F':' '{print $2}' | sed -e 's/^\s\+//'`

		logicaldev_status_info=255
		[[ "$logicaldev_status" = "Optimal"  ]] &&  logicaldev_status_info=0
		[[ "$logicaldev_status" = "Failed"   ]] &&  logicaldev_status_info=1
		[[ "$logicaldev_status" = "Degraded" ]] &&  logicaldev_status_info=2

		echo -n $logicaldev_status_info

	;;
	rc_mode|wc_mode|wc_setting)
		search_string="Read-cache mode"
		[[ "$logicaldev_o" = "wc_mode" ]] && search_string="Write-cache mode"
		[[ "$logicaldev_o" = "wc_setting" ]] && search_string="Write-cache setting"

		logicaldev_cache=`$ARCCONF_BIN $controller_n LD$logicaldev_n | grep "$search_string" | grep -c 'Enabled'`
		echo -n $logicaldev_cache
	;;
	"all")

		send_options_number=0
		set_all_variables "ld"

		get_agent_info
		
		# RAID level
		if [[ $LD_LEVEL -gt  0 ]]; then
			logicaldev_raid=`$ARCCONF_BIN $controller_n LD$logicaldev_n | grep "RAID level" | awk -F':' '{print $2}' | sed -e 's/^\s\+//'`
			printf "%-20s %-40s %-20s %-100d\n" "${HOST}" "${PREFIX}[ld,level,$controller_n]"  "$DATE"  "$logicaldev_raid"  >> $CACHE_FILE

			send_options_number=1
		fi

		# RAID size
		if [[ $LD_SIZE -gt 0 ]]; then

			logicaldev_size=`$ARCCONF_BIN $controller_n LD$logicaldev_n | grep "Size" | awk -F':' '{print $2}' | sed -e 's/^\s\+//'`
			l_size=`echo "$logicaldev_size" | awk '{print $1}'`
			l_dime=`echo "$logicaldev_size" | awk '{print $2}'`

			lsize_info=$l_size

			[[ "$l_dime" = "GB" ]] && lsize_info=`echo "$l_size*1073741824" |bc`
			[[ "$l_dime" = "MB" ]] && lsize_info=`echo "$l_size*1048576"    |bc`
			[[ "$l_dime" = "KB" ]] && lsize_info=`echo "$l_size*1024"       |bc`
			
			printf "%-20s %-40s %-20s %-100d\n" "${HOST}" "${PREFIX}[ld,size,$controller_n]"  "$DATE"  "$l_size_info"  >> $CACHE_FILE

			send_options_number=1
		fi

		if [[ $LD_STATUS -gt 0 ]]; then
			logicaldev_status=`$ARCCONF_BIN $controller_n LD$logicaldev_n | grep "Status of logical device" | awk -F':' '{print $2}' | sed -e 's/^\s\+//'`
			logicaldev_status_info=255
			[[ "$logicaldev_status" = "Optimal"  ]] &&  logicaldev_status_info=0
			[[ "$logicaldev_status" = "Failed"   ]] &&  logicaldev_status_info=1
			[[ "$logicaldev_status" = "Degraded" ]] &&  logicaldev_status_info=2

			printf "%-20s %-40s %-20s %-100d\n" "${HOST}" "${PREFIX}[ld,status,$controller_n]"  "$DATE"  "$logicaldev_status_info"  >> $CACHE_FILE

			send_options_number=1
		fi

		if [[ $LD_RC_MODE -gt 0 ]]; then
			logicaldev_cache=`$ARCCONF_BIN $controller_n LD$logicaldev_n | grep "Read-cache mode" | grep -c 'Enabled'`
			printf "%-20s %-40s %-20s %-100d\n" "${HOST}" "${PREFIX}[ld,rc_mode,$controller_n]"  "$DATE"  "$logicaldev_cache"  >> $CACHE_FILE

			send_options_number=1
		fi

		if [[ $LD_WC_MODE -gt 0 ]]; then
			logicaldev_cache=`$ARCCONF_BIN $controller_n LD$logicaldev_n | grep "Write-cache mode" | grep -c 'Enabled'`
			printf "%-20s %-40s %-20s %-100d\n" "${HOST}" "${PREFIX}[ld,wc_mode,$controller_n]"  "$DATE"  "$logicaldev_cache"  >> $CACHE_FILE

			send_options_number=1
		fi

		if [[ $LD_RC_MODE -gt 0 ]]; then
			logicaldev_cache=`$ARCCONF_BIN $controller_n LD$logicaldev_n | grep "Write-cache setting" | grep -c 'Enabled'`
			printf "%-20s %-40s %-20s %-100d\n" "${HOST}" "${PREFIX}[ld,wc_setting,$controller_n]"  "$DATE"  "$logicaldev_cache"  >> $CACHE_FILE

			send_options_number=1
		fi

		[[ $send_options_number -gt 0 ]] && send_by_sender "$SERVER" "$HOST" "$CACHE_FILE"
	;;
	*)
		help_message 1
	;;
	esac
;;
"pd")
	physicaldev_o=$2
	controller_n=$3
	physicaldev_n=$4

	# define controller number
	[[ -z $controller_n ]]  && controller_n=1
	[[ -z $physicaldev_n ]] && physicaldev_n=0

	search_string='\(Device \#[0-9]\|State\|Transfer Speed\|Vendor\|Model\|Serial number\|Size\)'

	pdev_cache=`$ARCCONF_BIN $controller_n PD | grep "$search_string" | sed -e 's/\s\+/_/g' | sed -e 's/^_//'`
	pdev_numb=0
	pdev_state=""
	pdev_speed=""
	pdev_vendor=""
	pdev_model=""
	pdev_serial=""
	pdev_size=""

	for data_str in $pdev_cache; do
		
		is_device_string=`echo "$data_str" | grep -c "Device_\#"`

		if [[ $is_device_string -gt 0 ]]; then
			is_wanted_device=`echo "$data_str" | grep -c "Device_\#$physicaldev_n"`

            if [[ $is_wanted_device -gt 0  ]]; then
				pdev_numb=1
			else
				pdev_numb=0
			fi
		fi

		if [[ $pdev_numb -eq 1 ]]; then
			pdev_key=`echo "$data_str" | cut -d':' -f1 | sed -e 's/_$//' | sed -e 's/_/ /g'`
			pdev_val=`echo "$data_str" | cut -d':' -f2 | sed -e 's/^_//' | sed -e 's/_/ /g'`

			if [[ "$pdev_key" = "State" ]]; then

				if [[ "$physicaldev_o" = "status" || "$physicaldev_o" = "all"  ]] ; then
					pdev_state=255

					[[ $pdev_val = "Online" ]]  && pdev_state=0
					[[ $pdev_val = "Offline" ]] && pdev_state=1
				fi
			fi

			if [[ "$pdev_key" = "Transfer Speed" ]]; then
				if [[ "$physicaldev_o" = "model" || "$physicaldev_o" = "all" ]]; then
					pdev_speed=$pdev_val
				fi
			fi

			if [[ "$pdev_key" = "Vendor" ]]; then
				if [[  "$physicaldev_o" = "model" || "$physicaldev_o" = "all" ]]; then
					pdev_vendor=$pdev_val
				fi
			fi

			if [[ "$pdev_key" = "Model" ]]; then
				if [[ "$physicaldev_o" = "model" || "$physicaldev_o" = "all" ]]; then
					pdev_model=$pdev_val
				fi
			fi

			if [[ "$pdev_key" = "Serial number" ]]; then
				if [[ "$physicaldev_o" = "model" || "$physicaldev_o" = "all" ]]; then
					pdev_serial=$pdev_val
				fi
			fi

			if [[ "$pdev_key" = "Size" ]]; then
				if [[ "$physicaldev_o" = "size"  || "$physicaldev_o" = "all" ]] ; then
					size_n=`echo $pdev_val | awk '{print $1}'`
                    size_d=`echo $pdev_val | awk '{print $2}'`

                    pdev_size=$size_n
                    [[ $size_d = "GB" ]] && pdev_size=`echo "$size_n*1073741824" |bc`
                    [[ $size_d = "MB" ]] && pdev_size=`echo "$size_n*1048576"    |bc`
                    [[ $size_d = "KB" ]] && pdev_size=`echo "$size_n*1024"       |bc`

				fi
			fi
		fi

	done

	#model|size|status|all [controller_number] [physical_device_number]
	[[ "$physicaldev_o" = "model" ]]   && echo -n "vendor: $pdev_vendor; model: $pdev_model; serial: $pdev_serial; transfer_speed: $pdev_speed"
	[[ "$physicaldev_o" = "size"  ]]   && echo -n "$pdev_size"
	[[ "$physicaldev_o" = "status"  ]] && echo -n "$pdev_state"

	if [[ "$physicaldev_o" = "all" ]]; then
		send_options_number=0
		set_all_variables "pd"

		get_agent_info

		CACHE_FILE=${CACHE_FILE}${physicaldev_n}

		[[ $PD_MODEL  -gt 0 ]] && printf "%-20s %-40s %-20s %-100s\n" "${HOST}" "${PREFIX}[pd,model,$controller_n,$physicaldev_n]" "$DATE" \
		 "vendor: $pdev_vendor; model: $pdev_model; serial: $pdev_serial; transfer_speed: $pdev_speed"  >> $CACHE_FILE &&  send_options_number=1
		

		[[ $PD_SIZE -gt 0 ]]   && printf "%-20s %-40s %-20s %-100d\n" "${HOST}" "${PREFIX}[pd,size,$controller_n,$physicaldev_n]" "$DATE" \
		 "$pdev_size" >> $CACHE_FILE &&  send_options_number=1

		[[ $PD_STATUS -gt 0 ]] && printf "%-20s %-40s %-20s %-100d\n" "${HOST}" "${PREFIX}[pd,status,$controller_n,$physicaldev_n]" "$DATE" \
		 "$pdev_state" >> $CACHE_FILE &&  send_options_number=1

		[[ $send_options_number -gt 0 ]] && send_by_sender "$SERVER" "$HOST" "$CACHE_FILE"
	fi

;;
*)
	help_message 1
;;
esac

