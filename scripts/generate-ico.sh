#!/bin/sh

# The ImageMagick conversion tool doesn't seem to always generate
# ICO files with background transparency properly. Please validate
# that the output has a transparent background.

convert -density 256 -background none -define icon:auto-resize ../app/res/stand-in.svg ../app/stand-in.ico
convert -density 256 -background none -size 64x64 ../app/res/stand-in.svg ../app/stand-in_wix.png

echo IMPORTANT: Validate the icon has a transparent background before committing!
