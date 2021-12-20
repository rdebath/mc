
for file in texpack/*.zip
do
    cp -p "$file" default.zip
    rm -rf default ||:
    mkdir default
    (
	cd default
	unzip -jq ../default.zip
	for i in *.png
	do
	    convert "$i" tmp_1.png
	    pngcrush -brute tmp_1.png tmp_2.png
	    [ -s tmp_1.png ] && mv tmp_1.png "$i"
	    rm -f tmp_1.png tmp_2.png
	done

	mkdir mob
	for f in skinnedcube.png \
		chicken.png creeper.png pig.png pony.png sheep.png \
		sheep_fur.png skeleton.png spider.png zombie.png
	do  [ -f "$f" ] || continue
	    mv "$f" mob/.
	done

	mkdir gui
	for f in gui.png gui_classic.png default.png icons.png touch.png
	do  [ -f "$f" ] || continue
	    mv "$f" gui/.
	done

	mkdir env
	for f in particles.png rain.png snow.png clouds.png
	do  [ -f "$f" ] || continue
	    mv "$f" env/.
	done

	7z -tzip -mx9 a default-7z.zip -r '*.*'
	mv default-7z.zip ../default.zip
    )
    mv default.zip "$file"
    rm -rf default ||:
done
