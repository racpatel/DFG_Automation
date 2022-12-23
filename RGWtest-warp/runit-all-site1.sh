#!/bin/bash
EXPECTED_ARGS=1
if [ $# -eq $EXPECTED_ARGS ] ; then
  comment=$1
else
  echo "Usage: $(basename $0) <test_comment>"
  exit 1
fi

i=1
for xml in fill hybrid hybrid-48hr hybrid delwrite ; do

  # set postPolling for delWrite job
#  if [ $xml = delWrite ] ; then sed -i -e "s/postPolling=false/postPolling=true/" vars.shinc ; fi

  # turn off debug levels before 48hr test
#  if [ $xml = hybrid-48hr ] ; then ansible -m shell -a "ceph --admin-daemon /var/run/ceph/ceph-client.rgw.*.asok config set debug_rgw 1/5" rgws ; fi

  # wait for GCs to process
  while [ `radosgw-admin gc list --include-all | wc -l` != 1 ] ; do sleep 10 ; done

  # use NFS mount for file markers, wait until other site is ready
  touch /rdu-nfs/twilkins/site1.$i
  echo "Wait until site2 is ready ..."
  while [[ ! -f /rdu-nfs/twilkins/site1.$i || ! -f /rdu-nfs/twilkins/site2.$i ]]; do sleep 3 ; done

  ./runit-${xml}.sh $comment
  radosgw-admin gc process --include-all &
  radosgw-admin gc process --include-all &
  radosgw-admin gc process --include-all &

  i=$(($i+1))
  sleep 5m

  # unset postPolling after delWrite job
#  if [ $xml = delWrite ] ; then sed -i -e "s/postPolling=true/postPolling=false/" vars.shinc ; fi

done
