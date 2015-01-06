#!/bin/bash
 
### Автор скрипта - sirkonst@gmail.com
### Сайт поддержки - http://wiki.enchtex.info/howto/zabbix/nginx_monitoring
 
### DESCRIPTION
# $1 - имя узла сети в zabbix'е (не используется)
# $2 - измеряемая метрика
# $3 - http ссылка на станицу статистику nginx
 
### OPTIONS VERIFICATION
if [[ -z "$1" || -z "$2" ]]; then
    exit 1
fi
 
### PARAMETERS
METRIC="$1"  # измеряемая метрика
STATURL="$2" # адрес nginx статистики
 
CURL="/usr/bin/curl -k"
 
CACHETTL="55" # Время действия кеша в секундах (чуть меньше чем период опроса элементов)
CACHE="/tmp/nginxstat-`echo $STATURL | md5sum | cut -d" " -f1`.cache"
 
### RUN
 
## Проверка кеша:
# время создание кеша (или 0 есть файл кеша отсутствует или имеет нулевой размер)
if [ -s "$CACHE" ]; then
    TIMECACHE=`stat -c"%Z" "$CACHE"`
else
    TIMECACHE=0
fi
# текущее время
TIMENOW=`date '+%s'`
# Если кеш неактуален, то обновить его (выход при ошибке)
if [ "$(($TIMENOW - $TIMECACHE))" -gt "$CACHETTL" ]; then
    $CURL -s "$STATURL" > $CACHE || exit 1
fi
 
 
## Извлечение метрики:
 
if [ "$METRIC" = "active" ]; then
    cat $CACHE | grep "Active connections" | cut -d':' -f2
fi
if [ "$METRIC" = "accepts" ]; then
    cat $CACHE | sed -n '3p' | cut -d" " -f2
fi
if [ "$METRIC" = "handled" ]; then
    cat $CACHE | sed -n '3p' | cut -d" " -f3
fi
if [ "$METRIC" = "requests" ]; then
    cat $CACHE | sed -n '3p' | cut -d" " -f4
fi
if [ "$METRIC" = "reading" ]; then
    cat $CACHE | grep "Reading" | cut -d':' -f2 | cut -d' ' -f2
fi
if [ "$METRIC" = "writing" ]; then
    cat $CACHE | grep "Writing" | cut -d':' -f3 | cut -d' ' -f2
fi
if [ "$METRIC" = "waiting" ]; then
    cat $CACHE | grep "Waiting" | cut -d':' -f4 | cut -d' ' -f2
fi

