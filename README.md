## Monitoring scripts for Zabbix

### Template - 3Ware Controller
Allow monitoring 3ware controllers.

File  | Desc
------------- | -------------
scripts/3ware.sh  | monitoring scripts (zabbix agent)
include/3ware.conf | config file
templates/3ware_template.xml | template

The script usages [tw_cli util](http://www.cyberciti.biz/files/tw_cli.8.html "tw_cli").

The utility requires root access, so the script has sudo usage.

You can use next command alias in the sudoers file:

`
Cmnd_Alias TWCTRL  =  /usr/local/bin/tw_cli info *, \
 /usr/local/bin/tw_cli info, \
 /usr/local/bin/tw_cli * show *
`

There are several value mappings in the template. 

### 3ware BBU statuses
0. Not Present
1. Testing
2. Charging
3. OK
4. WeakBat
5. Failed
6. Error
7. Fault
255. Unknown

### 3ware opts statuses
1. OK
2. HIGH
3. LOW
4. TOO-HIGH
5. TOO-LOW
255. UNKNOWN

### 3ware statuses
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
