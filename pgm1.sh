for i in *.zip
do j=$(md5sum $i| awk '{print substr($1,1,8);}' )
echo "$(echo "$i"|sed 's/texpack-//')" https://raw.githubusercontent.com/rdebath/mc/zip/"$j".zip
done |
sort |
column -t > README.txt
