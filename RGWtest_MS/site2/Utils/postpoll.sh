#!/bin/bash
#
# POSTPOLL.sh
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
updatelog "** POST POLL started" $log

sample=1
#while [ $SECONDS -lt $postpollend ]; do
while [ true ]; do

    # Sleep for the poll interval before first sample
    sleep "${interval}"

    echo -e "\nSAMPLE (post poll): ${sample}   =============================================\n"
    echo -e "\nSAMPLE (post poll): ${sample}   =============================================\n" >> $log

    # RESHARD activity
    #echo -n "RESHARD: " >> $log
    get_pendingRESHARD
    updatelog "RESHARD Queue Length ${pendingRESHARD}" $log
    updatelog "RESHARD List ${reshardList}" $log
    
    # RGW radosgw PROCESS, MEM stats and load avgs
    echo -e "\n`date +%Y/%m/%d-%H:%M:%S`\nRGW stats:          proc   %cpu %mem  vsz    rss      memused        memlimit               load avg" >> $log
    for rgw in $RGWhosts1 ; do
        rgwMem=`ssh $rgw ps -eo comm,pcpu,pmem,vsz,rss | grep -w 'radosgw '` &> /dev/null
        rgwMemUsed=`ssh $rgw cat /sys/fs/cgroup/memory/memory.usage_in_bytes` &> /dev/null
        rgwMemLimit=`ssh $rgw cat /sys/fs/cgroup/memory/memory.limit_in_bytes` &> /dev/null
        loadAvg=`ssh $rgw uptime | awk -F'[a-z]:' '{print $2}'`
        echo $rgw"   "$rgwMem"   "$rgwMemUsed"   "$rgwMemLimit"   "$loadAvg >> $log
    done

    echo -e "\n`date +%Y/%m/%d-%H:%M:%S`\nController stats:" >> $log
    loadAvg=`uptime | awk -F'[a-z]:' '{print $2}'`
    haproxyMem=`ps -eo comm,pcpu,pmem,vsz,rss | grep -v "0.0  0.0" | grep -w 'haproxy '` &> /dev/null
    monMem=`ps -eo comm,pcpu,pmem,vsz,rss | grep -w 'ceph-mon '` &> /dev/null
    echo -e `hostname -s`: "$loadAvg\n${haproxyMem}\n$monMem" >> $log

    # ceph-osd PROCESS and MEM stats
    echo -e "\nOSD stats: " >> $log        # prefix line with stats label
    for rgw in $RGWhosts1 ; do
        osdMem=`ssh $rgw ps -eo comm,pcpu,pmem,vsz,rss,args | grep -w 'ceph-osd '|egrep -v 'init|grep'|awk '{print $8"   "$2"   "$3"   "$4"   "$5}'`
        updatelog "${rgw} ${osdMem}" $log
    done

    # get bucket stats
    get_bucketStats
    echo -e "\nSite1 buckets (rgw):" >> $log
    echo -e "\nSite1 buckets (rgw):"
    updatelog "${site1bucketsrgw}" $log

    if [[ $multisite == "true" ]]; then
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
    updatelog "ceph df detail ${dfdetail}" $log

    # Record specific pool stats
    echo -e "\nSite1 pool details:"
    echo -e "\nSite1 pool details:" >> $log
    ceph osd pool ls detail >> $log
    get_buckets_df
    echo -e "\nSite1 buckets df"
    echo -e "Site1 buckets df" >> $log
    updatelog "${buckets_df}" $log
    if [[ $multisite == "true" ]]; then
        echo -e "\nSite2 buckets df"
        echo -e "\nSite2 buckets df" >> $log
        updatelog "${buckets_df2}" $log
    fi

    echo "" >> $log
    rgw_free=`get_rgwfree`
    updatelog "${rgw_free}" $log

#    get_osddf
#    echo -e "\nCeph osd df:" >> $log
#    updatelog "${osddf}" $log

#    get_osd_memory_targets
#    echo -e "\nosd_memory_targets:" >> $log
#    updatelog "${targets}" $log

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

    sample=$(($sample+1))
done

echo -n "POST POLL.sh: " >> $log   # prefix line with label for parsing
updatelog "** POST POLL ending" $log

