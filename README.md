## Monitoring scripts for Zabbix

### Template - 3Ware Controller
Allow monitoring 3ware controllers.

File  | Desc
------------- | -------------
scripts/3ware.sh  | monitoring scripts (zabbix agent)
include/3ware.conf | config file
templates/3ware_template.xml | template

The script uses [tw_cli util](http://www.cyberciti.biz/files/tw_cli.8.html "tw_cli").

The utility requires root access, so the script has sudo usage.

You can use next command alias in the sudoers file:

`
Cmnd_Alias TWCTRL  =  /usr/local/bin/tw_cli info *, \

 /usr/local/bin/tw_cli info, \
 
 /usr/local/bin/tw_cli * show *
`

There are several value mappings in the template. 

#### 3ware BBU statuses
0. Not Present
1. Testing
2. Charging
3. OK
4. WeakBat
5. Failed
6. Error
7. Fault
255. Unknown

#### 3ware opts statuses
1. OK
2. HIGH
3. LOW
4. TOO-HIGH
5. TOO-LOW
255. UNKNOWN

#### 3ware statuses
1. OK
2. VERIFYING
3. INITIALIZING
4. INIT-PAUSED
5. REBUILDING
6. REBUILD-PAUSED
7. DEGRADED
8. MIGRATING
9. MIGRATE-PAUSED
10. RECOVERY
11. INOPERABLE
255. UNKNOWN

### Template - External DNS checks
Allows to monitor the mapping DNS names to IP addresses on the selected NS.

File  | Desc
------------- | -------------
scripts/dig_status.sh  | monitoring script; it uses zabbix trapper and discovery options
include/dig_status.conf | config file for zabbix agent
templates/dig_status_template.xml | template
etc/google.ini | configuration option; it contains list of DNS, IP address and NS

The monitoring script uses dig and zabbix_sender utilities, you need to install them.

#### Description

##### Configuration files
Configuration files (etc/*.ini) contain next settings:

```
# Tested DNS names and expected IP addresses
[requests]
smtp.yandex.ru=87.250.250.38,213.180.193.38
smtp.mail.ru=94.100.180.160 

# Used name servers
[dns]
dns1=8.8.8.8
dns2=8.8.8.4
```

**Notice**: You should replace values in the [requests] on appropriate 
 and copy files to /etc/zabbix.

##### Monitoring utility
Monitoring utility can be used as follows:
1. Testing DNS names which is defined in the configuration file.
  It sends the results to the server using the zabbix_sender utility.
2. Return discovery information which is used in the zabbix template.

```
# test DNS names in config
scripts/dig_status.sh -m test -c /etc/zabbix/google.ini

# discovery settings from config file for zabbix server
scripts/dig_status.sh -m discovery -c /etc/zabbix/google.ini
```

**Notice**: You need to add this script as a cron task to a monitoring server.
For example, add the following lines to the /etc/crontab file
```
# dns monitoring
*/10  * * * * zabbix /var/lib/zabbix/local/scripts/dig_status.sh -m test -c /etc/zabbix/google.ini
```

##### Zabbix agent config
Zabbix agent config contains the definition for the check,
 which is used in discovery rules of the zabbix template.

**Notice**: You should replace path of monitoring script dig_status.sh in it 
 and copy this config file to zabbix_agent's include directory.

##### Zabbix template
Zabbix template contains next discovery rules:
1. Discovery FQDN names and NS servers - google
2. Discovery FQDN names and NS servers - opendns
This tests use UserParameter dig_status, which defined in the zabbix agent config file.

The discovery rule:
1. get next information from script's config file:
  * REQ_FQDN - tested DNS name
  * REQ_DNS  - selected NS server
  * RTN_IP   - expected IP address
2. create two checks (Zabbix trapper) on each triple:
  * Request status for REQ_FQDN 
  * IP address for REQ_FQDN

Template uses value mapping for statuses.

###### DNS request status
0. NS: OK
1. NS: Found additional IP in a reply
3. NS: Not all test IP found in a reply
4. NS: Not found records
5. NS: Return totally different IPs
101. dig util: Usage error
108. dig util: Couldn't open batch file
109. dig util: No reply from server
110. dig util: Internal error










