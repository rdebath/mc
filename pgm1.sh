#!/bin/bash -
mkdir -p zip

for i in texpack/*.zip
do j=$(unzip -c "$i" | md5sum | awk '{print substr($1,1,8);}' )
ln -f "$i" zip/"$j".zip
done
