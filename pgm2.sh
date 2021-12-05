

for i in $(awk '/texture/{j=$0; sub(".*/","",j); print j;}' mcscript/*.mc | sort -u)
do j=$(md5sum "texpack-$i"| awk '{print substr($1,1,8);}' )

echo "s@\\(os map texture \\).*$i@\\\\1https://raw.githubusercontent.com/rdebath/mc/zip/$j.zip@"

done > pgm2.sed

for i in mcscript/*.mc
do sed -i -f pgm2.sed "$i"
done
