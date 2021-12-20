
rm README.txt
rm mcscript/*.mc
rm texpack/*.zip
rm zip/*.zip
rm png/texpack-*.png

cp -p ../terrain/Texpacks/*.mc mcscript/.
cp -p ../terrain/Texpacks/texpack-*.zip texpack/.
cp -p ../terrain/Texpacks/texpack-*.png png/.

rm texpack/texpack-none-*
rm png/texpack-none-*
