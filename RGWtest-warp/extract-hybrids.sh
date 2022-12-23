# stuff the output of each warp run into log
#echo -e "\nWarp output:"
#for i in `seq 5` ; do
#   echo -e "\n---------\n\nBucket${i}\n"
#   warp analyze hybrid${i}.csv.zst --no-color
#done

# aggregate the individual run totals and append to log
echo -e "\n==========================\nOperation Totals:" 
grep -A1 DELETE test.log |grep Thro | awk 'BEGIN {printf("%s","DELETE: ")}{sum+=$3}END{print sum" "$4}' 
grep -A1 GET test.log | grep Thro | awk 'BEGIN {printf("%s", "GET: ")}{sum+=$3;sum1+=$5}END{print sum" "$4sum1" "$6}' 
grep -A1 STAT test.log | grep Thro | awk 'BEGIN {printf("%s","STAT: ")}{sum+=$3}END{print sum" "$4}'
grep -A1 PUT test.log | grep Thro | awk 'BEGIN {printf("%s","PUT: ")}{sum+=$3;sum1+=$5}END{print sum" "$4sum1" "$6}' 
grep Total test.log | awk 'BEGIN {printf("%s","Cluster Totals: ")}{sum+=$3;sum1+=$5}END{print sum" "$4sum1" "$6}' 
echo -e "==========================\n" 
