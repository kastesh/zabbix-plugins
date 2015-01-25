# list of supported urls
# GET methods
FRANKFURT_LEASEWEB="http://leasewebnoc.com/lg/lg.cgi?router=dtb-sr3&query=ping&protocol=IPv4&addr="
MOSCOW_COMCOR="http://master.comcor.ru/lg/?router=Comcor%20%28AS%208732%29&query=ping&protocol=IPv4&addr="
MOSCOW_MEGAFON="http://lg.megafon.ru/lg/lg.cgi?router=MSK-BGW-T4000-1%20Moscow&query=ping&protocol=IPv4&addr="
MOSCOW_MTS="http://lg.mtu.ru/cgi-bin/lg.cgi?router=ss-cr01.msk:cisco&query=ping&args="
MOSCOW_RETN_NET="http://lg.retn.net/cgi-bin/LG.cgi?r=5&q=p&a="
MOSCOW_TTK="http://lg.ttk.ru/?query=ping&protocol=IPv4&router=mska06rb&addr="
RIGA_TELIA="http://looking-glass.telia.net/?router=Riga&query=ping&protocol=IPv4&addr="
SPB_RUNNET="http://noc.runnet.ru/lg/?router=spb-b57-2-gw.runnet.ru&query=ping&addr="
STOCKHOLM_TELIA="http://looking-glass.telia.net/?router=Stockholm&query=ping&protocol=IPv4&addr="
WASHINGTON_LEASEWEB="http://leasewebnoc.com/lg/lg.cgi?router=wdc1-cr2&query=ping&protocol=IPv4&addr="
AMSTERDAM_TELIA="http://looking-glass.telia.net/?router=Amsterdam&query=ping&protocol=IPv4&addr="
KIEV_RETN_NET="http://lg.retn.net/cgi-bin/LG.cgi?r=65&q=p&a="
MOSCOW_FIORD="http://fiord.ru/cgi-bin/lg/lg.cgi?protocol=IPv4&query=ping&router=m9-b1&addr="
# POST methods
MOSCOW_ROSTELECOM="http://lg.rtcomm.ru/lg.php"
MOSCOW_ROSTELECOM_REQUEST="action=ping&address="
AMSTERDAM_LEVEL3="http://lookingglass.level3.net/ping/lg_ping_output.php"
AMSTERDAM_LEVEL3_REQUEST="sitename=ear1.ams1&size=64&count=5&address="

# Cron providers list
# GET
PROVIDERS="MOSCOW_COMCOR
MOSCOW_MTS
MOSCOW_RETN_NET
MOSCOW_TTK
MOSCOW_MEGAFON
RIGA_TELIA
SPB_RUNNET
STOCKHOLM_TELIA
WASHINGTON_LEASEWEB
AMSTERDAM_TELIA
KIEV_RETN_NET
MOSCOW_FIORD"

# POST
PROVIDERS_POST="MOSCOW_ROSTELECOM=MOSCOW_ROSTELECOM_REQUEST
AMSTERDAM_LEVEL3=AMSTERDAM_LEVEL3_REQUEST"
