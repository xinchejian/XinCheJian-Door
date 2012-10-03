echo 'Copying the door http program ...'
chmod a+x serve.lua
scp serve.lua root@10.0.10.9:/usr/bin/

echo 'Copying arp ...'
chmod a+x arp
scp arp root@10.0.10.9:/usr/bin/

echo 'Copying tts-token ...'
scp tts-token root@10.0.10.9:/root/

echo 'Copy the door init service script ..'
chmod a+x door
scp door root@10.0.10.9:/etc/init.d/

echo 'Copy the startup LED lock script ..'
chmod a+x ledoff
scp ledoff root@10.0.10.9:/etc/init.d/

echo 'Copy the heartbeat script ..'
chmod a+x heartbeat.sh
scp ledoff root@10.0.10.9:/usr/bin/
