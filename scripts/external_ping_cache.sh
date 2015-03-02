#!/bin/bash
# create cache for external ping check
# /usr/lib/zabbix/externalscripts/external_ping_status.sh -u MOSCOW_COMCOR -i 8.8.8.8 -c 2 -m status

PROGNAME=$(basename $0)
PROGPATH=$(dirname $0)
script=$PROGPATH/external_ping_status.sh

# URL for providers with external pings
. $PROGPATH/external_ping_vars.sh || exit 1

IP=$1
[[ -z $IP ]] && exit 1
VERBOSE=$2

# providers with GET method
for provider in $PROVIDERS; do
  $script $VERBOSE -u $provider -i $IP -c 1 -m status
done

# providers with POST method
for provider_def in $PROVIDERS_POST; do
  provider=$(echo "$provider_def" | awk -F'=' '{print $1}')
  provider_post=$(echo "$provider_def" | awk -F'=' '{print $2}')

  $script $VERBOSE -u $provider -d $provider_post -i $IP -c 1 -m status
done
