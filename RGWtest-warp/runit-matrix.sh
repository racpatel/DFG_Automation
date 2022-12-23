#!/bin/bash
cd /root/RGWtest-warp

egrep 'duration=|concurrent|objsize' vars.shinc
time ./runit-fill.sh 7h-256K-con5

radosgw-admin gc process --include-all &
radosgw-admin gc process --include-all &
radosgw-admin gc process --include-all &
sleep 5m

sed -i -e 's/concurrent=5/concurrent=10/' vars.shinc
egrep 'duration=|concurrent|objsize' vars.shinc
./resetRGW.sh ; sleep 8m ; time ./runit-fill.sh 7h-256K-con10


#sed -i -e 's/duration=7h/duration=5h/' vars.shinc
#egrep 'duration=|concurrent|objsize' vars.shinc
#./resetRGW.sh ; sleep 8m ; time ./runit-fill.sh 5h-1G-con1

#sed -i -e 's/objsize=1GiB/objsize=512MiB/' vars.shinc
#egrep 'duration=|concurrent|objsize' vars.shinc
#./resetRGW.sh ; sleep 8m ; time ./runit-fill.sh 5h-512M-con1

#ceph config set global rgw_max_concurrent_requests 1024

#sed -i -e 's/duration=5h/duration=7h/' vars.shinc
#sed -i -e 's/objsize=512MiB/objsize=1GiB/' vars.shinc
#egrep 'duration=|concurrent|objsize' vars.shinc
#./resetRGW.sh ; sleep 8m ; time ./runit-fill.sh 7h-1G-con1-1024req

#sed -i -e 's/concurrent=1/concurrent=5/' vars.shinc
#egrep 'duration=|concurrent|objsize' vars.shinc
#./resetRGW.sh ; sleep 8m ; time ./runit-fill.sh 7h-1G-con5-1024req

