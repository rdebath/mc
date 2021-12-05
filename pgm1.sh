for i in *.zip
do j=$(md5sum $i| awk '{print substr($1,1,8);}' )
echo "$j".zip  "$i"
done |
sort -k2 > README.txt
