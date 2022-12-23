#!/bin/bash
EXPECTED_ARGS=1
if [ $# -eq $EXPECTED_ARGS ] ;then
  comment=$1
else
  echo "Usage: $(basename $0) <test_comment>"
  exit 1
fi

# Variables
source "./vars.shinc"

# Functions
source "./Utils/functions.shinc"

jobID=`cat jobID`
testname=hybrid-site1-$comment
nodelist=./cloud07.list   # local list of RGWs & MONs

echo `date +%y/%m/%d" "%H:%M` " wait for any Ceph GCs ..."
./Utils/completedGC.sh 10 /tmp/`date +'%y%m%d-%H%M'`_completedGC > /dev/null

echo `date +%y/%m/%d" "%H:%M` " sync ; drop cache ..."
if [[ $cephadmshell == "true" ]]; then
    ansible -i /rootfs/etc/ansible/ osds -m shell -a "sync ; echo 1 > /proc/sys/vm/drop_caches" > /dev/null
else
    ansible -i /etc/ansible/ osds -m shell -a "sync ; echo 1 > /proc/sys/vm/drop_caches" > /dev/null
fi

echo `date +%y/%m/%d" "%H:%M` " start vmstat.sh ..."
ansible all -i ${nodelist} -m shell -a "nohup /usr/local/bin/vmstat.sh -i 15 > /tmp/vmstat.txt &" > /dev/null

echo `date +%y/%m/%d" "%H:%M` " start warp hybrid ..."
./runIOworkload-site1.sh hybrid

# create output dir under RESULTS dir
basepath=${PWD}
outdir=RESULTS/w${jobID}_${ts}_${testname}
mkdir ${basepath}/${outdir}

# stop vmstat.sh, copy output and logfile to outdir
echo `date +%y/%m/%d" "%H:%M` " stop vmstat.sh ..."
ansible -i ${nodelist} -m command -a "/root/stop-vmstat.sh ${testname}" all > /dev/null
for host in `cat ${nodelist}` ; do
    scp ${host}:/tmp/*${testname}.log $outdir/ &> /dev/null
done

mv ${basepath}/RESULTS/*.log $outdir/
mv ${basepath}/*.{zst,out} $outdir/

if [[ $bsV2Polling == "true" ]]; then
    # rename and move debug logs and OSD logs to testdir
    mkdir $outdir/bsv2perf
    for i in $(cd ${basepath}/RESULTS/ && ls osd.*.log) ; do mv ${basepath}/RESULTS/$i $outdir/bsv2perf/${ts}_${i} ; done
    mkdir $outdir/ceph-osd
    fsid=`ceph status |grep id: |awk '{print$2}'`
    if [[ $cephadmshell == "true" ]]; then
        ansible -i /rootfs/etc/ansible/ -o -m shell -a "scp /var/log/ceph/${fsid}/ceph-osd.* ${ADMINhostname}:${outdir}/ceph-osd/" osds
        cd ${outdir}/ceph-osd/ && for j in `ls ceph-osd.*.log` ; do gzip $j ; done ; cd -
        cp /rootfs/var/log/ceph/${fsid}/ceph*{audit,mgr,mon}* ${outdir}/
        cp /rootfs/var/log/ceph/${fsid}/ceph.log* ${outdir}/
    else
        ansible -i /etc/ansible/ -o -m shell -a "scp /var/log/ceph/${fsid}/ceph-osd.* ${ADMINhostname}:${outdir}/ceph-osd/" osds
        cd ${outdir}/ceph-osd/ && for j in `ls ceph-osd.*.log` ; do gzip $j ; done ; cd -
        cp /var/log/ceph/${fsid}/ceph*{audit,mgr,mon}* ${outdir}/
        cp /var/log/ceph/${fsid}/ceph.log* ${outdir}/
    fi
fi

# increment warp job ID
jobID=$(($jobID+1))
echo $jobID > jobID

date +%y/%m/%d" "%H:%M

if [[ $cephadmshell != "true" ]]; then
    echo " " | mail -s "RGWtest-warp (${testname}) complete" twilkins@redhat.com
fi
