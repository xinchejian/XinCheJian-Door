#!/bin/sh
# To be setup as a cron job to check network connectivity and reboot the server when necessary.
touch /root/heartbeat.lastrun

REBOOTLOG=/root/reboot.log

GATEWAY=`route|grep 'default'|sed 's/  */ /g'|cut -d ' ' -f 2`
NETWORKDOWN=`ping -c 3 10.0.10.5 | grep '64 bytes' | wc -l`

#if network is down, reboot the router.
if [ $NETWORKDOWN -lt 1 ]; then

  # trim the reboot log file if it is getting big
  if [ `wc -l < $REBOOTLOG` -ge 3 ]; then
    /bin/sed -i '1d' $REBOOTLOG
  fi
  
  # log the rebooting event
  echo "Lost connection at " `date` >> $REBOOTLOG
  
  # Reboot the router
  /sbin/reboot
fi
