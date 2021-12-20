#!/bin/bash -

cat >README.txt <<\!
This is some of my extras for MCGalaxy

There are some plugins in the addins directory.


The rest is texture packs.

!

for i in texpack/*.zip
do j=$(unzip -c "$i" | md5sum | awk '{print substr($1,1,8);}' )
echo "$(echo "$i"|sed 's/.*texpack-//')" https://raw.githubusercontent.com/rdebath/mc/zip/"$j".zip
done |
sort |
column -t >> README.txt
