import json, sys
E = '\x1b'
C = E + '['
def u(code, mod=1): return f'{C}{code};{mod}u' if mod != 1 else f'{C}{code}u'
def ctrl(ch): return chr(ord(ch) & 0x1f)
cases = []
def add(name, *bytes_, gap=None):
    c = {'name': name, 'bytes': list(bytes_)}
    if gap: c['gap'] = gap
    cases.append(c)
add('none')
add('left', C + 'D'); add('right', C + 'C'); add('up', C + 'A'); add('down', C + 'B')
add('home CSI H', C + 'H'); add('end CSI F', C + 'F'); add('home CSI 1~', C + '1~'); add('end CSI 4~', C + '4~')
add('home SS3 H', E + 'OH'); add('end SS3 F', E + 'OF')
for ch in 'aebfnptodhkuwy':
    add(f'ctrl+{ch} raw', ctrl(ch)); add(f'ctrl+{ch} csi-u', u(ord(ch), 5))
add('ctrl+k then ctrl+y raw', ctrl('k'), ctrl('y')); add('ctrl+k then ctrl+y csi-u', u(ord('k'), 5), u(ord('y'), 5))
add('ctrl+_ undo raw (after ctrl+w)', ctrl('w'), '\x1f'); add('ctrl+_ undo csi-u (after ctrl+w)', u(ord('w'), 5), u(ord('-'), 5))
add('esc b', E + 'b'); add('esc f', E + 'f'); add('esc d', E + 'd'); add('esc DEL', E + '\x7f')
add('alt+b csi-u', u(98, 3)); add('alt+f csi-u', u(102, 3)); add('alt+backspace csi-u', u(127, 3))
add('alt+left CSI 1;3D', C + '1;3D'); add('alt+right CSI 1;3C', C + '1;3C')
add('super+left CSI 1;9D', C + '1;9D'); add('super+right CSI 1;9C', C + '1;9C')
add('super+up CSI 1;9A', C + '1;9A'); add('super+down CSI 1;9B', C + '1;9B')
add('super+shift+left CSI 1;10D', C + '1;10D'); add('super+shift+right CSI 1;10C', C + '1;10C')
add('shift+left CSI 1;2D', C + '1;2D'); add('shift+right CSI 1;2C', C + '1;2C')
add('shift+up CSI 1;2A', C + '1;2A'); add('shift+down CSI 1;2B', C + '1;2B')
add('shift+home CSI 1;2H', C + '1;2H'); add('shift+end CSI 1;2F', C + '1;2F')
add('alt+shift+left CSI 1;4D', C + '1;4D')
add('ctrl+home CSI 1;5H', C + '1;5H'); add('ctrl+end CSI 1;5F', C + '1;5F')
add('ctrl+left CSI 1;5D', C + '1;5D'); add('ctrl+right CSI 1;5C', C + '1;5C')
add('fwd delete CSI 3~', C + '3~'); add('alt+fwd delete CSI 3;3~', C + '3;3~')
add('backspace DEL', '\x7f'); add('backspace csi-u 127', u(127))
add('super+backspace csi-u', u(127, 9)); add('super+a csi-u', u(97, 9)); add('super+z csi-u', u(122, 9))
add('super+shift+z csi-u', u(122, 10)); add('super+c csi-u', u(99, 9)); add('super+x csi-u', u(120, 9))
add('pageup CSI 5~', C + '5~'); add('pagedown CSI 6~', C + '6~')
json.dump(cases, open(sys.argv[1], 'w'), indent=0)
print(len(cases))
