#!/bin/bash
# automatic recognition of various system parameters
# input: get subsystem type
# script for centos
export LANG=en_US.UTF-8
export TERM=linux

DEBUG=1
WORK=/home/zabbix20
[[ ! -d $WORK ]] && WORK=/home/zabbix
option_name=$1

if [[ -z $option_name ]]; then
	[[ $DEBUG -eq 1 ]] && echo Usage $0 option_name
	exit 1
fi

# get software raid names
function get_md_opt {
	md_proc=/proc/mdstat
	md_list=`grep '^md' $md_proc | awk -F':' '{print $1}'`

	if [[ -n "$md_list" ]]; then
		first=1
		printf "{\n"
		printf "\t\"%s\":[\n\n" 'data'

		for md_name in $md_list
		do
			[[ $first -eq 0 ]] && printf "\t,\n"
			first=0;

			printf "\t{\n"
			printf "\t\t\"%s\":\"%s\"\n" '{#MDNAME}' "$md_name"
			printf "\t}\n"
			
		done
		
		printf "\n\t]\n"
		printf "}\n"
	fi
}

# get information for network interfaces and its ip addresses
function get_network_opt {
	net_proc=/proc/net/dev
	net_cmd=/sbin/ip

	only_interfaces='^\(eth\|tun\|bridge\)'
	
	link_list=`cat $net_proc | sed 's/^\s\+//' | grep "$only_interfaces" | cut -d':' -f1 | sort | uniq`
	link_num=`echo "$link_list" | wc -l`

	if [[ $link_num -gt 0 ]]; then
		first=1
		printf "{\n"
		printf "\t\"%s\":[\n\n" 'data'
		for link in $link_list
		do
			link_addr=`$net_cmd addr show dev $link | grep -v 'secondary' | grep -v 'bridge[0-9]\+:' | grep -v 'eth[0-9]\+:' | egrep -o 'inet +[0-9\.]+' | awk '{print $2}'`
			
			if [[ -n "$link_addr" ]]; then
				if [[ $first -eq 0 ]]; then
					printf "\t,\n"
				fi
				first=0;

				printf "\t{\n"
				printf "\t\t\"%s\":\"%s\",\n" '{#INTNAME}' "$link"
				printf "\t\t\"%s\":\"%s\"\n"  '{#INTIP}'   "$link_addr"
				printf "\t}\n"
			fi
		done
		printf "\n\t]\n"
		printf "}\n"
	fi
}

# get hostnames for BackupPC
function get_backuppc_hosts {
	host_file=/etc/BackupPC/hosts
	host_list=`cat $host_file | grep -v "^#\|^$" | grep -v '^host ' | awk '{print $1}'`
	host_numb=`echo "$host_list" | wc -l`

	if [[ $host_numb -gt 0 ]]; then
		first=1
		printf "{\n"
		printf "\t\"%s\":[\n\n" 'data'
		for host in $host_list
		do
			
			if [[ $first -eq 0 ]]; then
				printf "\t,\n"
			fi
			first=0;

			printf "\t{\n"
			printf "\t\t\"%s\":\"%s\"\n" '{#BPCHOST}' "$host"
			printf "\t}\n"
			
		done
		printf "\n\t]\n"
		printf "}\n"
	fi
}

# mysql discovery variables
function get_mysql_services {
	mysql_option=$1
	mysql_conf=$WORK/etc/mysqld

	#get file list with .cnf
	if [[ $mysql_option = "names" ]]; then
		mysql_conf_files=`find $mysql_conf -type f -name "*.cnf" -exec basename '{}' ';' | sed -e 's/\.cnf$//'`
		
		if [[ -n "$mysql_conf_files" ]]; then
			first=1
			printf "{\n"
			printf "\t\"%s\":[\n\n" 'data'

			for mysql_name in $mysql_conf_files
			do
				if [[ $first -eq 0 ]]; then
					printf "\t,\n"
				fi
				first=0;

				printf "\t{\n"
				printf "\t\t\"%s\":\"%s\"\n" '{#MYSQLNAME}' "$mysql_name"
				printf "\t}\n"
			done
			
			printf "\n\t]\n"
			printf "}\n"
		fi
		exit 0
	fi
	
	if [[ $mysql_option = "db" ]]; then
		mysql_exclude_dbs='^\(Database\|performance_schema\|test\|information_schema\|phpmyadmin\|replica_monitor\)$'
		mysql_exclude_pat='^\(monitor\|monitor\)\[0-9\]\+$'

		mysql_conf_files=`find $mysql_conf -type f -name "*.cnf"`
		#mysql_conf_number=`echo "$mysql_conf_files" | wc -l`
		if [[ -n "$mysql_conf_files" ]]; then
			first=1
			printf "{\n"
			printf "\t\"%s\":[\n\n" 'data'

			for mysql_file in $mysql_conf_files
			do
				[[ $first -eq 0 ]] && printf "\t,\n"
				first=0;
				
				mysql_name=`basename $mysql_file | sed -e 's/\.cnf$//'`
				mysql_dbs=`mysql --defaults-file="$mysql_file" -e "show databases;" | grep -v "$mysql_exclude_dbs" | grep -v "$mysql_exclude_pat"`
				
				if [[ -n "$mysql_dbs" ]]; then
					first=1;

					for db_name in $mysql_dbs
					do
						[[ $first -eq 0 ]] && printf "\t,\n"
						first=0;
						printf "\t{\n"
						printf "\t\t\"%s\":\"%s\",\n" '{#MYSQLDB}'    "$db_name"
						printf "\t\t\"%s\":\"%s\"\n"  '{#MYSQLDBSRV}' "$mysql_name"
						printf "\t}\n"
					done
				fi
			done

			printf "\n\t]\n"
			printf "}\n"
		fi
		exit 0
	fi

	if [[ $mysql_option = "replica" ]]; then
		replica_conf_files=`find $mysql_conf -type f  -exec basename '{}' ';' | grep -v '\.cnf$'`
		
		if [[ -n  "$replica_conf_files" ]]; then
			first=1
			printf "{\n"
			printf "\t\"%s\":[\n\n" 'data'

			for replica_name in $replica_conf_files
			do
				if [[ $first -eq 0 ]]; then
					printf "\t,\n"
				fi
				first=0;

				printf "\t{\n"
				printf "\t\t\"%s\":\"%s\"\n" '{#MYSQLREPLICA}' "$replica_name"
				printf "\t}\n"
			done

			printf "\n\t]\n"
			printf "}\n"
		fi
		exit 0	
	fi

	exit 1
	
}

# get UPS defined on the host
function get_ups_names {
	ups_conf=/etc/ups/upsmon.conf
	ups_names=`grep -v '^$\|^#' $ups_conf | grep MONITOR | awk '{print $2}' | sed -e 's/\@localhost//'`
	if [[ -n $ups_names ]]; then
		first=1
		printf "{\n"
		printf "\t\"%s\":[\n\n" 'data'
		for ups in $ups_names
		do
			if [[ $first -eq 0 ]]; then
				printf "\t,\n"
			fi
			first=0;

			printf "\t{\n"
			printf "\t\t\"%s\":\"%s\"\n" '{#UPSNAME}' "$ups"
			printf "\t}\n"

		done
		printf "\n\t]\n"
		printf "}\n"
	fi
}

# get gluster peer names
function get_gfs_peers {
    gfs_cmd="sudo /usr/sbin/gluster peer status"
    gfs_names=`$gfs_cmd | grep "^Hostname" | awk -F':' '{print $2}' | sed -e 's/ //g'`

    if [[ -n $gfs_names ]]; then
        first=1
        printf "{\n"
        printf "\t\"%s\":[\n\n" 'data'

        for node in $gfs_names
        do
            if [[ $first -eq 0 ]]; then
                printf "\t,\n"
            fi
            first=0;

            printf "\t{\n"
            printf "\t\t\"%s\":\"%s\"\n" '{#GFSPEER}' "$node"
            printf "\t}\n"
        done

        printf "\n\t]\n"
        printf "}\n"
    fi
}

# get php slow servers
function get_php_backend {
  work_dir=/root/scripts/slow_req
  work_script=create_stats

  backend_list=`find $work_dir -name "$work_script.*.sh" | sed -e "s:$work_dir/::"| sed -e "s/$work_script\.//" | sed -e "s/\.sh//"`

  if [[ -n $backend_list ]]; then
    first=1
    printf "{\n"
    printf "\t\"%s\":[\n\n" 'data'

    for backend_server in $backend_list
    do
      if [[ $first -eq 0 ]]; then
        printf "\t,\n"
      fi

      first=0;

      printf "\t{\n"
      printf "\t\t\"%s\":\"%s\"\n" '{#PHPSERV}' "$backend_server"
      printf "\t}\n"
    done

    printf "\n\t]\n"
    printf "}\n"
  fi
}

# get php slow servers
function get_disks_info {
  disk_exclude='\(drbd\|md\)'
  disk_labels=`iostat -kxd | grep -v '^$' | grep -v '^\(Device\|Linux\)' | grep -v "$disk_exclude" | awk '{print $1}' | sort | uniq`

  if [[ -n "$disk_labels" ]]; then
    first=1
    printf "{\n"
    printf "\t\"%s\":[\n\n" 'data'

    for label in $disk_labels
    do

      if [[ $first -eq 0 ]]; then
        printf "\t,\n"
      fi
      first=0;

      lname=$label
      is_lvm=`echo $label | grep -c '^dm-'`
      if [[ $is_lvm -gt 0 ]]; then
        link_name=`find /dev/mapper/ -maxdepth 1 -type l -ls | grep "$label$" | awk '{print $11}' | sed -e 's:^/dev/mapper/::'`
        [[ -n $link_name ]] && lname=$link_name
      fi

      printf "\t{\n"
      printf "\t\t\"%s\":\"%s\",\n" '{#DLABEL}'    "$label"
      printf "\t\t\"%s\":\"%s\"\n"  '{#DNAME}'     "$lname"
      printf "\t}\n"
    done

    printf "\n\t]\n"
    printf "}\n"
  
  fi
}

#get links information
function get_links_info {
  conf_file=$WORK/etc/links.conf

  [[ -f $conf_file ]] || exit 0
  # file contains:
  # /opt/data/sites/guitaretab_com/www/cache
  # /opt/data/sites/guitartabs_cc/www/tabs

  link_list=`cat $conf_file`
  if [[ -n $link_list ]]; then
    first=1
    printf "{\n"
    printf "\t\"%s\":[\n\n" 'data'

    for link in $link_list
    do
      if [[ $first -eq 0 ]]; then
        printf "\t,\n"
      fi
      first=0;

      printf "\t{\n"
      printf "\t\t\"%s\":\"%s\"\n"  '{#LFILE}'     "$link"
      printf "\t}\n"
      
    done

    printf "\n\t]\n"
    printf "}\n"
    
  fi
}

function get_cert_list {
  conf_file=/etc/zabbix/certs.conf
  
  [[ -f $conf_file ]] || exit 0
  certsrc_list=$(cat $conf_file)
  
  if [[ -n $certsrc_list ]]; then
    first=1
    printf "{\n"
    printf "\t\"%s\":[\n\n" 'data'

    for cert in $certsrc_list
    do
      if [[ $first -eq 0 ]]; then
        printf "\t,\n"
      fi
      first=0;

      printf "\t{\n"
      printf "\t\t\"%s\":\"%s\"\n"  '{#CERTSRC}'     "$cert"
      printf "\t}\n"
      
    done

    printf "\n\t]\n"
    printf "}\n"
    
  fi
}

function get_memcached {
  is_standart=1
  is_cluster=0
  memcached_services=""
  # check standart service location
  if [[ $(/sbin/chkconfig --list | grep '^memcached' | grep -c '[234]:on') -eq 0 ]] ; then
    # it is can be cluster service
    is_standart=0
  fi
  
  # check cluster configuration
  cluster_conf="$WORK/etc/cluster/cluster.conf"
  cluster_desc="$WORK/utils/cluster.pl /etc/zabbix/cluster/cluster.conf  script_internal"
  cluster_stats="sudo /usr/sbin/clustat"
  if [[ -f "$cluster_conf" ]]; then
    # check if exists memcached cluster service
    cluster_data=$( $cluster_desc )
    if [[ $( echo $cluster_data | grep -c "memcached") -gt 0 ]]; then
      # verify that the host is the owner of the resource
      for record in $cluster_data
      do
        if [[ $(echo $record | grep -c "memcached") -gt 0 ]]; then
          memcached_name=$( echo $record | cut -d":" -f1 )
          cluster_service=$(echo $record | cut -d":" -f2 )
          
          service_owner=$( $cluster_stats | egrep "service:$cluster_service" | awk '{print $2}' )
          if [[ ( -n "$service_owner" ) && ( $service_owner == $(hostname -s) ) ]]; then
            memcached_services=$memcached_services"$memcached_name "
            is_cluster=1
          fi
        fi
      done
      
    fi
    
  fi
  
  if [[ "$is_cluster$is_standart" = "00" ]]; then
    exit
  fi 
  

  #echo 1
  memcached_services=$memcached_services$(/sbin/chkconfig --list | grep '^memcached' | grep '[234]:on' | awk '{print $1}')
  header=0
  first=1
  for mc in $memcached_services
  do
    sysconf=/etc/sysconfig/$mc

    # port and ip
    # service with socket -skip
    port=$(grep -v '^$\|^#' $sysconf | grep 'PORT=' | awk -F'=' '{print $2}' | sed -e 's/"//g' | sed -e "s/'//g")
    sock=$(grep -v '^$\|^#' $sysconf | grep 'SOCKET=' | awk -F'=' '{print $2}' | sed -e 's/"//g' | sed -e "s/'//g")
    host=$(grep -v '^$\|^#' $sysconf | grep 'HOST=' | awk -F'=' '{print $2}'| sed -e 's/"//g' | sed -e "s/'//g")

    if [[ -z $sock ]]; then
      [[ -z $port ]] && port=11211
      [[ -z $host ]] && host=127.0.0.1



      if [[ $header -eq 0 ]]; then
        printf "{\n"
        printf "\t\"%s\":[\n\n" 'data'
        header=1
      fi

      
      if [[ $first -eq 0 ]]; then
        printf "\t,\n"
      fi
      first=0

      printf "\t{\n"
      printf "\t\t\"%s\":\"%s\",\n"  '{#MHOST}'     "$host"
      printf "\t\t\"%s\":\"%s\"\n"   '{#MPORT}'     "$port"
      printf "\t}\n"

    fi
  done
  if [[ $header -eq 1 ]] ; then
    printf "\n\t]\n"
    printf "}\n"
  fi
  
}

function get_searchd {
  conf=/etc/sysconfig
  base=searchd
  
  sphinx_instance=$(find $conf -type f -name "${base}-*" )
  if [[ -n "$sphinx_instance" ]]; then
    header=0
    first=1
    for file in $sphinx_instance
    do
      inst=$(basename $file)
      ison=$(  grep -v "^$\|^#" $file | grep "^ON=" | cut -d'=' -f2 )
      if [[ $ison -eq 1 ]]; then
        port=$(grep -v "^$\|^#" $file | grep "^PORT=" | cut -d'=' -f2 )
        host=$(grep -v "^$\|^#" $file | grep "^ADDRESS=" | cut -d'=' -f2 )
        #conf=$(grep -v "^$\|^#" $file | grep "^CONF=" | cut -d'=' -f2 )
        name=$(grep -v "^$\|^#" $file | grep "^NAME=" | cut -d'=' -f2 )
        
        # default values
        [[ -z "$port" ]] && port=3312
        [[ -z "$host" ]] && host=127.0.0.1
        #[[ -z "$conf" ]] && conf=/etc/sphinx/sphinx.conf
        [[ -z "$name" ]] && conf=default
        
        
        
        if [[ $header -eq 0 ]]; then
          printf "{\n"
          printf "\t\"%s\":[\n\n" 'data'
          header=1
        fi
        
        
        if [[ $first -eq 0 ]]; then
          printf "\t,\n"
        fi
        first=0

        printf "\t{\n"
        printf "\t\t\"%s\":\"%s\",\n"  '{#SPHHOST}'     "$host"
        #printf "\t\t\"%s\":\"%s\",\n"  '{#SPHCONF}'     "$conf"
        printf "\t\t\"%s\":\"%s\",\n"  '{#SPHNAME}'     "$name"
        printf "\t\t\"%s\":\"%s\"\n"   '{#SPHPORT}'     "$port"
        
        printf "\t}\n"
      fi
    done
    if [[ $header -eq 1 ]] ; then
      printf "\n\t]\n"
      printf "}\n"
    fi
  fi
}

case $option_name in
"network")
  get_network_opt
;;
"backuppc")
  get_backuppc_hosts
;;
mysql_db|mysql_names|mysql_replica)
  myopt=`echo $option_name | awk -F'_' '{print $2}'`
  get_mysql_services "$myopt"
;;
"ups")
  get_ups_names
;;
"gfs_peers")
  get_gfs_peers
;;
"php")
  get_php_backend
;;
"disks" )
  get_disks_info
;;
"links" )
  get_links_info
;;
"memcached" )
  get_memcached
;;
"searchd" )
  get_searchd
;;
"mdraid")
  get_md_opt
;;
"certs")
  get_cert_list
;;
*)
	exit 1
;;
esac

exit 0


