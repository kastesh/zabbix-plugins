#!/bin/bash
# create cache for external ping check
# /usr/lib/zabbix/externalscripts/external_ping_status.sh -u MOSCOW_COMCOR -i 8.8.8.8 -c 2 -m status

script=/usr/lib/zabbix/externalscripts/external_ping_status.sh

PROVIDERS="MOSCOW_COMCOR
MOSCOW_MTS
MOSCOW_RETN_NET
MOSCOW_TTK
MOSCOW_MEGAFON
RIGA_TELIA
SPB_RUNNET
STOCKHOLM_TELIA
WASHINGTON_LEASEWEB
AMSTERDAM_TELIA"

IP=$1
[[ -z $IP ]] && exit 1
VERBOSE=$2

for provider in $PROVIDERS; do
  $script $VERBOSE -u $provider -i $IP -c 1 -m status
done
