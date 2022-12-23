#!/bin/bash
EXPECTED_ARGS=1
if [ $# -eq $EXPECTED_ARGS ] ; then
  comment=$1
else
  echo "Usage: $(basename $0) <test_comment>"
  exit 1
fi
./runit-fill.sh $comment
radosgw-admin gc process --include-all &
radosgw-admin gc process --include-all &
radosgw-admin gc process --include-all &
sleep 5m
./runit-hybrid-new.sh $comment
radosgw-admin gc process --include-all &
radosgw-admin gc process --include-all &
radosgw-admin gc process --include-all &
sleep 5m
./runit-hybrid-48hr.sh $comment
radosgw-admin gc process --include-all &
radosgw-admin gc process --include-all &
radosgw-admin gc process --include-all &
sleep 5m
./runit-hybrid-aged.sh $comment
radosgw-admin gc process --include-all &
radosgw-admin gc process --include-all &
radosgw-admin gc process --include-all &
sleep 5m
./runit-delWrite.sh $comment
