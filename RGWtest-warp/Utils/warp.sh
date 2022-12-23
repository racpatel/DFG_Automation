#!/bin/bash
EXPECTED_ARGS=2
if [ $# -eq $EXPECTED_ARGS ] ; then
  operation=$1
  log=$2
else
  echo "Usage: $(basename $0) {fill,hybrid-new,hybrid-48hr,hybrid-aged,delwrite} <logfile>"
  exit 1
fi

# Bring in other script files
myPath="${BASH_SOURCE%/*}"
if [[ ! -d "$myPath" ]]; then
    myPath="$PWD"
fi

# Variables
source "$myPath/../vars.shinc"

# Functions
source "$myPath/../Utils/functions.shinc"

# timestamp for output files
ts=`date +'%y%m%d-%H%M'`
tmplog=/tmp/${ts}_warp.out

# Start warp clients 
#./Utils/start-clients.sh ${numCONT}
#echo "Starting clients for $operation"
#sleep 10

# Execute warp job
case $operation in
    fill)
        i=1
        echo -e "\nWarp commands:\n-----------------" > $tmplog
        for driver in $drivers ; do
            if [ $i -le ${numCONT} ] ; then  #  limit warp servers to desired bucket count
                echo -e "\nwarp put --obj.size $objsize --duration=$duration --concurrent=$concurrent --warp-client=${warpClients[$(($i-1))]} --host=$warpHosts --access-key=$access --secret-key=$secret --obj.randsize --bucket bucket${i} --benchdata ${ts}_${operation}-${i} --host-select=$hostSelect --noclear --no-color --debug &> ${ts}_warp${i}.out" >> $tmplog
                ssh $driver warp put --obj.size $objsize --duration=$duration --concurrent=$concurrent --warp-client=${warpClients[$(($i-1))]} --host=$warpHosts --access-key=$access --secret-key=$secret --obj.randsize --bucket bucket${i} --benchdata ${ts}_${operation}-${i} --host-select=$hostSelect --noclear --no-color --debug &> ${ts}_warp${i}.out &
                i=$(($i+1))
            fi
        done

        # add commands syntax to log
        sleep 10
        while [[ `pgrep -a warp |grep -v "client " |grep -v warp.sh` ]] ; do sleep 30 ; done
        sleep 1m

        # add the output of each run to log
        i=1
        echo "" >> $tmplog
        for output in `ls ${ts}_warp*.out` ; do
            echo -e "-----------------------\nBucket${i}" >> $tmplog
            grep -A2 PUT $output >> $tmplog
            i=$(($i+1))
        done
        
        # aggregate the individual run totals and append to log
        echo -e "\n==============================\nOperation Totals:" >> $tmplog
        grep "* Average" $tmplog | awk 'BEGIN {printf("%s","PUT: ")}{sum+=$3;sum1+=$5}END{print sum" "$4sum1" "$6}' >> $tmplog
        echo -e "==============================\n" >> $tmplog
        cat $tmplog >> $log
        ;;

    hybrid-new|hybrid-aged)
        i=1
        echo -e "\nWarp commands:\n-----------------" > $tmplog
        for driver in $drivers ; do
            if [ $i -le ${numCONT} ] ; then  #  limit warp servers to desired bucket count
                if [ $i -le 3 ] ; then  # the first 3 drivers will do puts & deletes
                    echo -e "\nwarp mixed --duration=60m0s --concurrent=$concurrent --put-distrib $putdist --delete-distrib $deletedist --get-distrib 0 --stat-distrib 0 --warp-client=${warpClients[$(($i-1))]} --host=$warpHosts --access-key=$access --secret-key=$secret --obj.size $objsize --obj.randsize --bucket bucket${i} --benchdata ${ts}_${operation}-${i} --host-select=$hostSelect --noclear --no-color --debug &> ${ts}_warp${i}.out" >> $tmplog
                    ssh $driver warp mixed --duration=60m0s --concurrent=$concurrent --put-distrib $putdist --delete-distrib $deletedist --get-distrib 0 --stat-distrib 0 --warp-client=${warpClients[$(($i-1))]} --host=$warpHosts --access-key=$access --secret-key=$secret --obj.size $objsize --obj.randsize --bucket bucket${i} --benchdata ${ts}_${operation}-${i} --host-select=$hostSelect --noclear --no-color --debug &> ${ts}_warp${i}.out &
                else	# the remaining drivers will do gets & stats
                    echo -e "\nwarp mixed --duration=60m0s --concurrent=$concurrent --put-distrib 0 --delete-distrib 0 --get-distrib $getdist --stat-distrib $statdist --warp-client=${warpClients[$(($i-1))]} --host=$warpHosts --access-key=$access --secret-key=$secret --obj.size $objsize --obj.randsize --bucket bucket${i} --benchdata ${ts}_${operation}-${i} --host-select=$hostSelect --noclear --no-color --debug &> ${ts}_warp${i}.out" >> $tmplog
                    ssh $driver warp mixed --duration=60m0s --concurrent=$concurrent --put-distrib 0 --delete-distrib 0 --get-distrib $getdist --stat-distrib $statdist --warp-client=${warpClients[$(($i-1))]} --host=$warpHosts --access-key=$access --secret-key=$secret --obj.size $objsize --obj.randsize --bucket bucket${i} --benchdata ${ts}_${operation}-${i} --host-select=$hostSelect --noclear --no-color --debug &> ${ts}_warp${i}.out &
                fi
                i=$(($i+1))
            fi
        done

        # add commands syntax to log
        sleep 10
        while [[ `pgrep -a warp |grep -v "client " |grep -v warp.sh` ]] ; do sleep 30 ; done
        sleep 1m

        # add the output of each run to log
        i=1
        echo "" >> $tmplog
        for output in `ls ${ts}_warp*.out` ; do
            echo -e "-----------------------\nBucket${i}" >> $tmplog
            if [ $i -le 3 ] ; then  # the first 3 buckets have puts & deletes
                grep -A2 PUT $output >> $tmplog
                grep -A2 DELETE $output >> $tmplog
            else    # the remaining buckets have gets & stats
                grep -A2 GET $output >> $tmplog
                grep -A2 STAT $output >> $tmplog
            fi
            i=$(($i+1))
        done
        
        # aggregate the individual run totals and append to log
        echo -e "\n==============================\nOperation Totals:" >> $tmplog
        grep -A2 PUT $tmplog | grep Thro | awk 'BEGIN {printf("%s","PUT: ")}{sum+=$3;sum1+=$5}END{print sum" "$4sum1" "$6}' >> $tmplog
        grep -A2 DELETE $tmplog |grep Thro | awk 'BEGIN {printf("%s","DELETE: ")}{sum+=$3}END{print sum" "$4}' >> $tmplog
        grep -A2 GET $tmplog | grep Thro | awk 'BEGIN {printf("%s", "GET: ")}{sum+=$3;sum1+=$5}END{print sum" "$4sum1" "$6}' >> $tmplog
        grep -A2 STAT $tmplog | grep Thro | awk 'BEGIN {printf("%s","STAT: ")}{sum+=$3}END{print sum" "$4}' >> $tmplog
        echo -e "==============================\n" >> $tmplog
        cat $tmplog >> $log
        ;;

    hybrid-48hr)
        i=1
        echo -e "\nWarp commands:\n-----------------" > $tmplog
        for driver in $drivers ; do
            if [ $i -le ${numCONT} ] ; then  #  limit warp servers to desired bucket count
                if [ $i -le 3 ] ; then  # the first 3 drivers will do puts & deletes
                    echo -e "\nwarp mixed --duration=2880m0s --concurrent=$concurrent --put-distrib $putdist --delete-distrib $deletedist --get-distrib 0 --stat-distrib 0 --warp-client=${warpClients[$(($i-1))]} --host=$warpHosts --access-key=$access --secret-key=$secret --obj.size $objsize --obj.randsize --bucket bucket${i} --benchdata ${ts}_${operation}-${i} --host-select=$hostSelect --noclear --no-color --debug &> ${ts}_warp${i}.out" >> $tmplog
                    ssh $driver warp mixed --duration=2880m0s --concurrent=$concurrent --put-distrib $putdist --delete-distrib $deletedist --get-distrib 0 --stat-distrib 0 --warp-client=${warpClients[$(($i-1))]} --host=$warpHosts --access-key=$access --secret-key=$secret --obj.size $objsize --obj.randsize --bucket bucket${i} --benchdata ${ts}_${operation}-${i} --host-select=$hostSelect --noclear --no-color --debug &> ${ts}_warp${i}.out &
                else	# the remaining drivers will do gets & stats
                    echo -e "\nwarp mixed --duration=2880m0s --concurrent=$concurrent --put-distrib 0 --delete-distrib 0 --get-distrib $getdist --stat-distrib $statdist --warp-client=${warpClients[$(($i-1))]} --host=$warpHosts --access-key=$access --secret-key=$secret --obj.size $objsize --obj.randsize --bucket bucket${i} --benchdata ${ts}_${operation}-${i} --host-select=$hostSelect --noclear --no-color --debug &> ${ts}_warp${i}.out" >> $tmplog
                    ssh $driver warp mixed --duration=2880m0s --concurrent=$concurrent --put-distrib 0 --delete-distrib 0 --get-distrib $getdist --stat-distrib $statdist --warp-client=${warpClients[$(($i-1))]} --host=$warpHosts --access-key=$access --secret-key=$secret --obj.size $objsize --obj.randsize --bucket bucket${i} --benchdata ${ts}_${operation}-${i} --host-select=$hostSelect --noclear --no-color --debug &> ${ts}_warp${i}.out &
                fi
                i=$(($i+1))
            fi
        done

        # add commands syntax to log
        sleep 10
        while [[ `pgrep -a warp |grep -v "client " |grep -v warp.sh` ]] ; do sleep 30 ; done
        sleep 1m

        # add the output of each run to log
        i=1
        echo "" >> $tmplog
        for output in `ls ${ts}_warp*.out` ; do
            echo -e "-----------------------\nBucket${i}" >> $tmplog
            if [ $i -le 3 ] ; then  # the first 3 buckets have puts & deletes
                grep -A2 PUT $output >> $tmplog
                grep -A2 DELETE $output >> $tmplog
            else    # the remaining buckets have gets & stats
                grep -A2 GET $output >> $tmplog
                grep -A2 STAT $output >> $tmplog
            fi
            i=$(($i+1))
        done
        
        # aggregate the individual run totals and append to log
        echo -e "\n==============================\nOperation Totals:" >> $tmplog
        grep -A2 PUT $tmplog | grep Thro | awk 'BEGIN {printf("%s","PUT: ")}{sum+=$3;sum1+=$5}END{print sum" "$4sum1" "$6}' >> $tmplog
        grep -A2 DELETE $tmplog |grep Thro | awk 'BEGIN {printf("%s","DELETE: ")}{sum+=$3}END{print sum" "$4}' >> $tmplog
        grep -A2 GET $tmplog | grep Thro | awk 'BEGIN {printf("%s", "GET: ")}{sum+=$3;sum1+=$5}END{print sum" "$4sum1" "$6}' >> $tmplog
        grep -A2 STAT $tmplog | grep Thro | awk 'BEGIN {printf("%s","STAT: ")}{sum+=$3}END{print sum" "$4}' >> $tmplog
        echo -e "==============================\n" >> $tmplog
        cat $tmplog >> $log
        ;;

    delwrite)
        i=1
        echo -e "\nWarp commands:\n-----------------" > $tmplog
        for driver in $drivers ; do
            if [ $i -le ${numCONT} ] ; then  #  limit warp servers to desired bucket count
                echo -e "\nwarp mixed --duration=120m0s --concurrent=$concurrent --obj.size $objsize --put-distrib 80 --delete-distrib 20 --get-distrib 0 --stat-distrib 0 --warp-client=${warpClients[$(($i-1))]} --host=$warpHosts --access-key=$access --secret-key=$secret --obj.randsize --bucket bucket${i} --benchdata ${ts}_${operation}-${i} --host-select=$hostSelect --noclear --no-color --debug &> ${ts}_warp${i}.out" >> $tmplog
                ssh $driver warp mixed --duration=120m0s --concurrent=$concurrent --obj.size $objsize --put-distrib 80 --delete-distrib 20 --get-distrib 0 --stat-distrib 0 --warp-client=${warpClients[$(($i-1))]} --host=$warpHosts --access-key=$access --secret-key=$secret --obj.randsize --bucket bucket${i} --benchdata ${ts}_${operation}-${i} --host-select=$hostSelect --noclear --no-color --debug &> ${ts}_warp${i}.out &
                i=$(($i+1))
            fi
        done

        # add commands syntax to log
        sleep 10
        while [[ `pgrep -a warp |grep -v "client " |grep -v warp.sh` ]] ; do sleep 30 ; done
        sleep 1m

        # add the output of each run to log
        i=1
        echo "" >> $tmplog
        for output in `ls ${ts}_warp*.out` ; do
            echo -e "-----------------------\nBucket${i}" >> $tmplog
            grep -A2 PUT $output >> $tmplog
            grep -A2 DELETE $output >> $tmplog
            i=$(($i+1))
        done
        
        # aggregate the individual run totals and append to log
        echo -e "\n==============================\nOperation Totals:" >> $tmplog
        grep -A2 PUT $tmplog | grep Thro | awk 'BEGIN {printf("%s","PUT: ")}{sum+=$3;sum1+=$5}END{print sum" "$4sum1" "$6}' >> $tmplog
        grep -A2 DELETE $tmplog |grep Thro | awk 'BEGIN {printf("%s","DELETE: ")}{sum+=$3}END{print sum" "$4}' >> $tmplog
#        grep Total: $tmplog | awk 'BEGIN {printf("%s","Cluster Totals: ")}{sum+=$3;sum1+=$5}END{print sum" "$4sum1" "$6}' >> $tmplog
        echo -e "==============================\n" >> $tmplog
        cat $tmplog >> $log
        ;;

    *)
        echo "Invalid warp operation provided, exit..."
        ;;
esac

# Stop warp clients
#ansible -m command -a "killall warp &> /dev/null" drivers &> /dev/null
