#!/bin/sh
# To be setup as a cron job to check network connectivity and reboot the server when necessary.
touch /root/heartbeat.lastrun
                             
REBOOTLOG=/root/reboot.log
                                                              
GATEWAY=`route|grep 'default'|sed 's/  */ /g'|cut -d ' ' -f 2`
                                                                  
NETWORKDOWN=`ping -qc 3 $GATEWAY |grep '0 packets received'|wc -l`
                             
                                        
# if network is down, reboot the router.
if [ $NETWORKDOWN == 1 ]; then
                                                 
  # trim the reboot log file if it is getting big
  if [ `wc -l < $REBOOTLOG` -ge 3 ]; then
    sed -i '1d' $REBOOTLOG
  fi
                           
  # log the rebooting event                      
  echo "Lost connection at " `date` >> $REBOOTLOG
                     
  # Reboot the router
  reboot
fi

