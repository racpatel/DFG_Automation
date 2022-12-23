#!/bin/bash
EXPECTED_ARGS=1
if [ $# -eq $EXPECTED_ARGS ] ; then
  numCONT=$1
else
  echo "Usage: $(basename $0) <number_of_containers>"
  exit 1
fi

# Start warp clients 
for i in `seq ${numCONT}` ; do
    ansible drivers -m shell -a "(hostname -I | awk '{str=$2\":800${i}\"}END{print str}'|xargs warp client )" &
done

