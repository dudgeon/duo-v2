#!/bin/bash
# Build deck.md with pandoc 3.13 (arm64 release zip in the scratch dir) and list which layout each slide uses.
set -e
D=${SCRATCH:-/tmp/duo-decks}/formats
P=$D/dl/pandoc-3.13-arm64/bin/pandoc
cd $D/pandoc
$P --version | head -1
python3 -c '
import struct,zlib
w,h=40,30
raw=b"".join(b"\x00"+b"\x80\x80\xff"*w for _ in range(h))
c=lambda t,d: struct.pack(">I",len(d))+t+d+struct.pack(">I",zlib.crc32(t+d)&0xffffffff)
open("pic.png","wb").write(b"\x89PNG\r\n\x1a\n"+c(b"IHDR",struct.pack(">IIBBBBB",w,h,8,2,0,0,0))+c(b"IDAT",zlib.compress(raw))+c(b"IEND",b""))'
REF=${REF:-}
OUT=${OUT:-deck.pptx}
if [ -n "$REF" ]; then $P deck.md -o $OUT --reference-doc=$REF; else $P deck.md -o $OUT; fi
n=$(unzip -l $OUT | grep -c 'ppt/slides/slide[0-9]*.xml')
for i in $(seq 1 $n); do
  f=$(unzip -p $OUT ppt/slides/_rels/slide$i.xml.rels | grep -o 'slideLayout[0-9]*.xml')
  name=$(unzip -p $OUT ppt/slideLayouts/$f | grep -o '<p:cSld name="[^"]*"')
  ph=$(unzip -p $OUT ppt/slides/slide$i.xml | grep -o '<p:ph[^>]*>' | tr '\n' ' ')
  echo "slide$i -> $f $name | $ph"
done
