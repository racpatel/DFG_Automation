#!/bin/bash
#
# POLL.sh
#   Polls ceph and logs stats and writes to LOGFILE
#

# Bring in other script files
myPath="${BASH_SOURCE%/*}"
if [[ ! -d "$myPath" ]]; then
    myPath="$PWD"
fi

# Variables
source "$myPath/../vars.shinc"

# Functions
# defines: 'get_' routines
source "$myPath/../Utils/functions.shinc"

# check for passed arguments
[ $# -ne 2 ] && error_exit "POLL.sh failed - wrong number of args"
[ -z "$1" ] && error_exit "POLL.sh failed - empty first arg"
[ -z "$2" ] && error_exit "POLL.sh failed - empty second arg"

interval=$1          # how long to sleep between polling
log=$2               # the logfile to write to
DATE='date +%Y/%m/%d-%H:%M:%S'

# update log file  
updatelog "** POLL started" $log

###########################################################
echo -e "\nceph versions:" >> $log
ceph versions >> $log

echo -e "\nceph config dump:" >> $log
ceph config dump >> $log

echo -e "\nceph balancer status" >> $log
ceph balancer status >> $log

echo -e "\nulimits:" >> $log
ulimit -a >> $log

echo -e "\nsysctl tuning:" >> $log
sysctl -a|egrep 'fs.aio-max-nr|vm.max_map_count|kernel.threads-max|vm.min_free_kbytes' >> $log

# log current RGW/OSD tunings
get_tuning
updatelog "OSD Settings:  ${osdtuning}" $log
updatelog "RGW Settings:  ${rgwtuning}" $log

# verify necessary 5.0 changes
#echo -e "\nTCMALLOC checks:" >> $log
#if [[ $cephadmshell == "true" ]]; then
#    ansible -i /rootfs/etc/ansible -m shell -a '/root/check-osd-hacks.sh' osds >> $log
#    ansible -i /rootfs/etc/ansible -m shell -a '/root/check-mon-hacks.sh' mons >> $log
#else
#    ansible -i /etc/ansible -m shell -a '/root/check-osd-hacks.sh' osds >> $log
#    ansible -i /etc/ansible -m shell -a '/root/check-mon-hacks.sh' mons >> $log
#fi

# collect daemon diffs
#case $CEPHVER in
#  luminous|nautilus)
#    ssh $RGWhostname 'ceph daemon `ls /var/run/ceph/ceph-osd.*.asok|head -1` config diff' > $OSDDIFF
#    ssh $RGWhostname 'ceph daemon `ls /var/run/ceph/ceph-client.rgw.*.asok|tail -1` config diff' > $RGWDIFF
#    ssh $MONhostname 'ceph daemon `ls /var/run/ceph/ceph-mgr.*.asok|head -1` config diff' > $MGRDIFF
#    ssh $MONhostname 'ceph daemon `ls /var/run/ceph/ceph-mon.*.asok|head -1` config diff' > $MONDIFF
#    ;;
#  pacific|quincy)
#    fsid=`ceph status |grep id: |awk '{print$2}'`
#    osd=`ceph osd tree|grep -A2 $RGWhostname |tail -1|awk '{print$1}'`
#    ssh $RGWhostname "cd /var/run/ceph/$fsid && ceph --admin-daemon ceph-client.rgw.rgws.*.asok config diff"  > $RGWDIFF
#    ssh $RGWhostname "cd /var/run/ceph/$fsid && ceph --admin-daemon ceph-osd.${osd}.asok config diff" > $OSDDIFF
#    ssh $MONhostname "cd /var/run/ceph/$fsid && ceph --admin-daemon ceph-mgr.*.asok config diff"  > $MGRDIFF
#    ssh $MONhostname "cd /var/run/ceph/$fsid && ceph --admin-daemon ceph-mon.*.asok config diff"  > $MONDIFF
#    ;;
#  *)
#    echo "unable to gather daemon config diffs stats, exit..."
#    ;;
#esac

echo -e "\nOSD swapon -s ..." >> $log
if [[ $cephadmshell == "true" ]]; then
    ansible -i /rootfs/etc/ansible -o -m command -a "swapon -s" osds >> $log
else
    ansible -i /etc/ansible -o -m command -a "swapon -s" osds >> $log
fi

# add %RAW USED and GC status to LOGFILE
#get_pendingGC   # this call can be expensive
#echo -en "\nGC: " >> $log   # prefix line with GC label for parsing
get_rawUsed
echo "" >> $log
updatelog "%RAW USED ${rawUsed}; Pending GCs ${pendingGC}" $log
threshold="80.0"

# reset site2 sync counters
if [[ $multisite == "true" ]]; then
    if [[ $syncPolling == "true" ]]; then
	echo "" >> $log
        updatelog "Resetting data-sync-from-site1 counters on site2 RGWs" $log
	case $CEPHVER in
            luminous|nautilus)
                for rgw in $RGWhosts2 ; do
                    ssh ${rgw} 'ceph daemon `ls /var/run/ceph/ceph-client.rgw*.asok|tail -1` perf reset data-sync-from-site1' >> $log
                done
	        ;;
	    pacific|quincy)
                fsid2=`ssh $RGWhostname2 "ceph status |grep id:" |awk '{print$2}'`
                for rgw in $RGWhosts2 ; do
                    ssh ${rgw} "cd /var/run/ceph/$fsid2 && ceph --admin-daemon ceph-client.rgw.rgws.*.asok perf reset data-sync-from-site1"
                done
	        ;;
	    *)
                echo "unable to reset site2 sync counters, exit..."
                ;;
        esac
    fi
fi

# keep polling until cluster reaches 'threshold' % fill mark
#while (( $(awk 'BEGIN {print ("'$rawUsed'" < "'$threshold'")}') )); do
#while [ true ]; do
while (( $(echo "${rawUsed} < ${threshold}" | bc -l) )); do
    echo -e "\n--------------------------------------------------------\n" >> $log
    # RESHARD activity
    #echo -n "RESHARD: " >> $log
    get_pendingRESHARD
    updatelog "RESHARD Queue Length ${pendingRESHARD}" $log
    updatelog "RESHARD List ${reshardList}" $log
    
    # RGW radosgw PROCESS, MEM stats and load avgs
    echo -e "\n`date +%Y/%m/%d-%H:%M:%S`\nRGW stats:          proc   %cpu %mem  vsz    rss      memused        memlimit               load avg" >> $log        # stats titles
    for rgw in $RGWhosts1 ; do
        rgwMem=`ssh $rgw ps -eo comm,pcpu,pmem,vsz,rss | grep -w 'radosgw '` &> /dev/null
        rgwMemUsed=`ssh $rgw cat /sys/fs/cgroup/memory/memory.usage_in_bytes` &> /dev/null
        rgwMemLimit=`ssh $rgw cat /sys/fs/cgroup/memory/memory.limit_in_bytes` &> /dev/null
        loadAvg=`ssh $rgw uptime | awk -F'[a-z]:' '{print $2}'`
        echo $rgw"   "$rgwMem"   "$rgwMemUsed"   "$rgwMemLimit"   "$loadAvg >> $log
    done

    # ceph-osd PROCESS and MEM stats
    echo -e "\nOSD: " >> $log        # prefix line with stats label
    for rgw in $RGWhosts1 ; do
        osdMem=`ssh $rgw ps -eo comm,pcpu,pmem,vsz,rss,args | grep -w 'ceph-osd '|egrep -v 'init|grep'|awk '{print $8"   "$2"   "$3"   "$4"   "$5}'`
        updatelog "${rgw} ${osdMem}" $log
    done

# get bucket stats
    get_bucketStats
    #echo -e "\nSite1 buckets (swift):" >> $log
    #echo -e "\nSite1 buckets (swift):"
    #updatelog "${site1bucketsswift}" $log
    echo -e "\nSite1 buckets (rgw):" >> $log
    echo -e "\nSite1 buckets (rgw):"
    updatelog "${site1bucketsrgw}" $log

    if [[ $multisite == "true" ]]; then
        #echo -e "\nSite2 buckets (swift):" >> $log 
        #echo -e "\nSite2 buckets (swift):"
        #updatelog "${site2bucketsswift}" $log
        echo -e "\nSite2 buckets (rgw):" >> $log 
        updatelog "${site2bucketsrgw}" $log
        get_syncStatus
        echo -e "\nSite2 sync status:" >> $log       
        echo -e "\nSite2 sync status:" 
        updatelog "${syncStatus}" $log
        echo -e "\nSite2 buckets sync status:" >> $log
        echo -e "\nSite2 buckets sync status:"
        updatelog "${bucketSyncStatus}" $log
    fi

    if [[ $syncPolling == "true" ]]; then
#        cmdStart=$SECONDS
#        get_dataLog
#        dataLog_duration=$(($SECONDS - $cmdStart))
#        echo -e "\nsite1 data log list ---------------------------------------------------- " >> $DATALOG
#        echo "dataLog response time: $dataLog_duration" >> $DATALOG
#        updatelog "${dataLog}" $DATALOG
        # multisite sync status
        get_SyncStats
        echo -en "\nCeph Client I/O\nsite1: " >> $log
        updatelog "site1:  ${site1io}" $log
        echo -n "site2: " >> $log
        updatelog "site2:  ${site2io}" $log
        echo -en "\nSite2 Sync Counters:\n">> $log
        cat /tmp/syncCtrs >> $log
    fi

    echo -e "\nCluster status" >> $log
    ceph status >> $log

    get_df-detail
    updatelog "ceph df detail \n${dfdetail}" $log

    # Record specific pool stats
    echo -e "\nSite1 pool details:"
    echo -e "\nSite1 pool details:" >> $log
    ceph osd pool ls detail >> $log
    get_buckets_df
    echo -e "\nSite1 buckets df"
    echo -e "\nSite1 buckets df" >> $log
    updatelog "${buckets_df}" $log
    if [[ $multisite == "true" ]]; then
        echo -e "\nSite2 buckets df"
        echo -e "\nSite2 buckets df" >> $log
        updatelog "${buckets_df2}" $log
    fi

    output=`get_free`
    updatelog "\n${output}" $log

    get_osddf
    echo -e "\nCeph osd df:" >> $log
    updatelog "${osddf}" $log

#    get_osd_memory_targets
#    echo -e "\nosd_memory_targets:" >> $log
#    updatelog "${targets}" $log

    # Record the %RAW USED and pending GC count
# NOTE: this may need to be $7 rather than $4 <<<<<<<<
#    get_rawUsed
#    get_pendingGC
#    echo -en "\nGC: " >> $log
#    updatelog "%RAW USED ${rawUsed}; Pending GCs ${pendingGC}" $log

    # monitor for large omap objs 
#    echo "" >> $log
#    site1omapCount=`ceph health detail |grep 'large obj'`
#    updatelog "Large omap objs (site1): $site1omapCount" $log
#    if [[ $multisite == "true" ]]; then
#        site2omapCount=`ssh $MONhostname2 ceph health detail |grep 'large obj'`
#        updatelog "Large omap objs (site2): $site2omapCount" $log
#    fi

    echo -e "\nPG Autoscale:" >> $log
    ceph osd pool autoscale-status >> $log

    # poll for RGW debug info &&& remove later
    echo -e "\nRGW netstat & qlen/qactive ..." >> $log
    for rgw in $RGWhosts1 ; do
        echo ${rgw} >> $log
        ssh $rgw "netstat -tnlp |egrep 'PID|rados'" >> $log
        case $CEPHVER in
            luminous|nautilus)
                ssh $rgw "ceph --admin-daemon /var/run/ceph/ceph-client.rgw.*.asok perf dump | egrep 'qlen|qactive'" >> $log
                ;;
            pacific|quincy)
                fsid=`ceph status |grep id: |awk '{print$2}'`
                ssh $rgw "cd /var/run/ceph/$fsid && ceph --admin-daemon ceph-client.rgw.rgws.*.asok perf dump | egrep 'qlen|qactive'" >> $log
                ;;
            *)
                echo "unable to collect RGW netstat & qlen/qactive"
                ;;
        esac
    done

    # Sleep for the poll interval
    sleep "${interval}"
done

# verify any rgw lifecycle policies ... &&& one-off testing, remove later
#echo -e "\nCheck buckets for LC policies ..." >> $log
#for i in `seq 6` ; do echo mycontainers$i >> $log ; s3cmd getlifecycle s3://mycontainers$i >> $log ; done

echo -n "POLL.sh: " >> $log   # prefix line with label for parsing
updatelog "** ${threshold}% fill mark hit: POLL ending" $log

# DONE
