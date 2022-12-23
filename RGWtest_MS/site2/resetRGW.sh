#!/bin/bash
# RESETRGW.sh

myPath="${BASH_SOURCE%/*}"
if [[ ! -d "$myPath" ]]; then
    myPath="$PWD" 
fi

# Variables
source "$myPath/vars.shinc"

#------------------------
# BEGIN FUNCTIONS
function delete_pools {
  if [[ $multisite == "true" ]]; then
      poolroot=site2
  else
      poolroot=default
  fi
  for pl in ${pool_list[@]}; do
      if [ $pl != "rbd" ]; then
          $execMON ceph osd pool delete $pl $pl --yes-i-really-really-mean-it
      fi
  done

  sleep 5
  $execMON ceph osd crush rule rm ${poolroot}.rgw.buckets.data
}

function create_pools {
  if [[ $multisite == "true" ]]; then
      poolroot=site2
  else
      poolroot=default
  fi
  if [ "$1" == "rep" ]; then
      cmdtail="replicated"
  elif [ "$1" == "ec" ]; then
      cmdtail="erasure myprofile"
      $execMON ceph osd erasure-code-profile rm myprofile
      $execMON ceph osd erasure-code-profile set myprofile k=$k m=$m
      $execMON ceph osd crush rule create-erasure ${poolroot}.rgw.buckets.data myprofile
  else
      echo "unknown value for REPLICATION in create_pools"; exit
  fi

  for pl in ${pool_list[@]}; do
      if [ $pl == "${poolroot}.rgw.buckets.data" ]; then
          $execMON ceph osd pool create $pl --pg_num_min $pg_data $cmdtail
          if [ "$1" == "rep" ]; then
              $execMON ceph osd pool set $pl size "${numREPLICAS}"
          fi
      elif [ $pl == "${poolroot}.rgw.buckets.index" ]; then
          $execMON ceph osd pool create $pl --pg_num_min $pg_index replicated
          $execMON ceph osd pool set $pl size "${numREPLICAS}"
      else
          $execMON ceph osd pool create $pl --pg_num_min $pg replicated
          $execMON ceph osd pool set $pl size "${numREPLICAS}"
      fi
  done

  # enable RGW on the pools for RHCS 3.x builds
  if echo $CEPH_VERSION | grep -q "10.2." ; then
    echo "Skip pool enable for 2.5 versions"
  else
    for pool in $(rados lspools); do
       $execMON ceph osd pool application enable $pool rgw --yes-i-really-mean-it
    done
  fi
}

# END FUNCTIONS
#------------------------

echo "$PROGNAME: Running with these values:"
echo "RGWhostname=$RGWhostname r=$REPLICATION k=$k m=$m pgdata=$pg_data pgindex=$pg_index \
      pg=$pg f=$fast_read"

echo "runmode=$runmode"
if [ $runmode == "containerized" ]; then
    nt_start=$(ssh $RGWhostname 'bash -s' < Utils/thr_time.sh)
    echo -e $nt_start
fi

echo "Stopping RGWs, and echoing status"
case $CEPHVER in
  luminous|nautilus)
    ansible -o -m shell -a 'systemctl stop ceph-radosgw.target' rgws
    sleep 5
    ansible -o -m shell -a 'systemctl status ceph-radosgw.target |grep Act' rgws
    ;;
  pacific|quincy)
    ceph orch stop rgw.rgws
    ;;
  *)
    echo "unable to stop RGWs, exit..."
    ;;
esac
# ensure RGWs are stopped
while [[ `ceph status |grep rgw: |grep active` ]] ; do sleep 5 ; done

# ensure that pool deletion is enabled
$execMON ceph tell mon.\* injectargs '--mon-allow-pool-delete=true'
sleep 2

echo "Removing existing/old pools"
delete_pools

echo "Creating new pools"
create_pools $REPLICATION

# echo "sleeping for $longPAUSE seconds..."; sleep "${longPAUSE}"
echo "sleeping for 30 seconds..."; sleep 30

echo "Starting RGWs, and echoing status"
case $CEPHVER in
  luminous|nautilus)
    ansible -o -m shell -a 'systemctl start ceph-radosgw.target' rgws
    sleep 5
    ansible -o -m shell -a 'systemctl status ceph-radosgw.target |grep Act' rgws
    ;;
  pacific|quincy)
    ceph orch start rgw.rgws
    sleep 10
    ;;
  *)
    echo "unable to start RGWs, exit..."
    ;;
esac
# ensure at least one of the RGWs are started
while [[ ! `ceph status |grep rgw: |grep active` ]] ; do sleep 5 ; done

#echo "disabling PG autoscaler"
#for i in `rados lspools` ; do echo -ne $i"\t" ; ceph osd pool set $i pg_autoscale_mode off ; done

# Create user and put password(s) into XML files
echo "Creating user and inserting new password into XML files"
case $storagetype in
  swift)
    $execRGW 'radosgw-admin user create --uid=johndoe --display-name="John Doe" --email=john@example.com' &&
    newswift=$($execRGW 'radosgw-admin subuser create --uid=johndoe --subuser=johndoe:swift --access=full' |jq .swift_keys[].secret_key | tr -d '"')
    sed -i "s/password=.*;/password=$newswift;/g" *.xml
    ;;
  s3)
    newaccess=$(radosgw-admin user create --uid=johndoe --display-name="John Doe" |jq .keys[].access_key | tr -d '"')
    newsecret=$(radosgw-admin user info --uid=johndoe |jq .keys[].secret_key | tr -d '"')
    sed -i -e "s/accesskey=[A-Za-z0-9]*/accesskey=$newaccess/g" -e "s/secretkey=[A-Za-z0-9]*/secretkey=$newsecret/g" *.xml
    ;;
  *)
    echo "$storagetype not defined, exit..."
    ;;
esac

#if [ $runmode == "containerized" ]; then
#    nt_end=$(ssh $RGWhostname 'bash -s' < Utils/thr_time.sh)
#    echo -e $nt_end
#fi

echo "$PROGNAME: Done"

# DONE
