#!/bin/bash
# Export deck.md with marp-cli: default pptx (images) and --pptx-editable; inspect slide1 XML.
D=${SCRATCH:-/tmp/duo-decks}/formats
cd $D/marp
M=$D/node/node_modules/.bin/marp
$M --version
export PATH=/opt/homebrew/bin:$PATH
$M deck.md --pptx -o img.pptx --allow-local-files 2>&1 | tail -3
$M deck.md --pptx --pptx-editable -o edit.pptx --allow-local-files 2>&1 | tail -5
for f in img.pptx edit.pptx; do
  [ -f $f ] || { echo "$f missing"; continue; }
  echo "== $f $(stat -f %z $f) bytes"
  unzip -l $f | grep -E 'slides/slide|media|slideLayouts/slideLayout' | awk '{print $4}' | tr '\n' ' '; echo
  unzip -p $f ppt/slides/slide2.xml | grep -o -E '<p:ph[^>]*>|<a:t>[^<]*</a:t>|<p:pic>|<a:off [^>]*>' | head -20 | tr '\n' ' '; echo
  unzip -p $f ppt/notesSlides/notesSlide2.xml 2>/dev/null | grep -o '<a:t>[^<]*</a:t>' | tr '\n' ' '; echo
done
