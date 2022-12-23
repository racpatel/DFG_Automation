#!/bin/bash
EXPECTED_ARGS=1
if [ $# -eq $EXPECTED_ARGS ] ; then
  comment=$1
else
  echo "Usage: $(basename $0) <test_comment>"
  exit 1
fi

# use NFS mount for file markers
rm -f /rdu-nfs/site2.*
i=1

for xml in fill hybrid hybrid-48hr hybrid delWrite ; do

  # wait for GCs to process
  while [ `radosgw-admin gc list --include-all | wc -l` != 1 ] ; do sleep 10 ; done

  # wait until site1 is ready 
  touch /rdu-nfs/site2.$i
  echo "Wait until site1 is ready ..."
  while [[ ! -f /rdu-nfs/site1.$i || ! -f /rdu-nfs/site2.$i ]]; do sleep 5 ; done

  ./runit_generic-${xml}.sh $comment
  radosgw-admin gc process --include-all &
  radosgw-admin gc process --include-all &
  radosgw-admin gc process --include-all &

  i=$(($i+1))
  sleep 5m

done
