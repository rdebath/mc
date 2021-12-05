for i in *.zip
do j=$(md5sum $i| awk '{print substr($1,1,8);}' )
ln -f "$i" "$j".zip
done
