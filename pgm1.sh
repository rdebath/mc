#!/bin/bash -
mkdir -p zip
echo '*' > zip/.gitignore

for i in texpack/*.zip
do j=$(md5sum $i| awk '{print substr($1,1,8);}' )
ln -f "$i" zip/"$j".zip
done
