#!/bin/zsh
# Pasting and dropping a picture into the editor (LR-39, legacy ENH-108). Background run on a
# scratch workspace: a synthetic paste event (a DataTransfer holding a PNG File; the real
# pasteboard is never touched), then the file on disk, the text, and an editor snapshot.
#   scripts/check-paste-image.sh [out-dir]
set -u
cd "${0:A:h}/.."
out=${1:-build/paste-image}; mkdir -p "$out"; out=${out:A}
ws=/private/tmp/pcf-editor-1/ws; rm -rf $ws /private/tmp/pcf-editor-1/cc /private/tmp/pcf-editor-1/sup
mkdir -p $ws/Home $ws/work/garden /private/tmp/pcf-editor-1/cc /private/tmp/pcf-editor-1/sup
printf -- '---\ngoal: "Home"\n---\n\n# Home\n' > $ws/Home/HOME.md
printf -- '---\ngoal: "Plan"\n---\n\n# garden\n' > $ws/work/garden/PROJECT.md
doc="$ws/work/garden/My Note.md"
printf '# Trip notes\n\nFirst paragraph.\n\nSecond paragraph.\n' > "$doc"
png=$(python3 - <<'PY'
import zlib,struct,base64
w=h=48
raw=b''.join(b'\x00'+bytes([220,60,60]*(w//2)+[60,60,220]*(w//2)) for _ in range(h))
def ch(t,d): c=struct.pack('>I',len(d))+t+d; return c+struct.pack('>I',zlib.crc32(t+d)&0xffffffff)
print(base64.b64encode(b'\x89PNG\r\n\x1a\n'+ch(b'IHDR',struct.pack('>IIBBBBB',w,h,8,2,0,0,0))+ch(b'IDAT',zlib.compress(raw))+ch(b'IEND',b'')).decode())
PY
)
# mk(): build a File, put it in a DataTransfer; `,` is written ⸴ because --then splits on commas.
mk="const b=atob('$png');const u=new Uint8Array(b.length);for(let i=0;i<b.length;i++)u[i]=b.charCodeAt(i);const dt=new DataTransfer();dt.items.add(new File([u]⸴'x.png'⸴{type:'image/png'}));const c=document.querySelector('.cm-content');"
paste="${mk}duo.select(30);const ev=new ClipboardEvent('paste'⸴{clipboardData:dt⸴bubbles:true⸴cancelable:true});c.dispatchEvent(ev);return 'paste prevented='+ev.defaultPrevented"
drop="${mk}const r=c.getBoundingClientRect();const ev=new DragEvent('drop'⸴{dataTransfer:dt⸴bubbles:true⸴cancelable:true⸴clientX:r.left+20⸴clientY:r.bottom-4});c.dispatchEvent(ev);return 'drop prevented='+ev.defaultPrevented"
acts="open:garden,open-file:$doc,freeze:2,editor-js:$paste,freeze:2,editor-js:$drop,freeze:2,editor-js:return 1,freeze:2,editor-js:return 1,freeze:1,editor-js:duo.select(0)⸴1,freeze:2,editor-js:return 1,freeze:2,editor-js:return 1,freeze:2,editor-snapshot:$out/editor.png,freeze:3,editor-js:return 1,freeze:2,editor-js:return 1,freeze:2,editor-js:return 1,freeze:2,editor-state"
env -u DUO_SUPPORT_DIR DUO_EXTRA_ENV="DUO_SUPPORT_DIR=/private/tmp/pcf-editor-1/sup CLAUDE_CONFIG_DIR=/private/tmp/pcf-editor-1/cc" DUO_TIMEOUT=60 \
  scripts/run-live.sh $ws "$out/window.png" "$acts" "$out/run.log" >/dev/null
grep -E "editor-js|editor-state|buffer|disk" "$out/run.log"
sleep 2; echo "--- on disk:"; cat "$doc"; ls -l "${doc:h}"
