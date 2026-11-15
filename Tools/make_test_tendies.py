#!/usr/bin/env python3
"""Build a small reference .tendies using the same layout/CAML dialect as TendiesExporter.swift.

Purpose: (1) lets you test your install tool/iOS version with a known-good-structure file
before the app is ever built; (2) exercises the format assumptions against validate_tendies.py.
Usage: make_test_tendies.py out.tendies [width height]
Defaults to 430x932 (iPhone 14 Pro Max). Needs only the Python stdlib.
"""
import base64, re, struct, sys, zlib, io, zipfile, os, math

HERE = os.path.dirname(os.path.abspath(__file__))
TPL = open(os.path.join(HERE, '..', 'Sources', 'TendieStudio', 'Export', 'TendiesTemplate.swift')).read()
UUID = re.search(r'descriptorUUID = "([^"]+)"', TPL).group(1)
FILES = dict(re.findall(r'File\(path: "([^"]+)", base64: "([^"]+)"', TPL))
WF = "7400.WWDC_2022-390w-844h@3x~iphone.wallpaper"
def ca(p): return f"7400.WWDC_2022_{p}-390w-844h@3x~iphone.ca"

def num(v):
    if v == round(v) and abs(v) < 1e9: return str(int(round(v)))
    s = f"{v:.5f}".rstrip('0').rstrip('.'); return '0' if s == '-0' else s

def png(w, h, rgb):  # solid PNG, stdlib only
    raw = b''.join(b'\x00' + bytes(rgb + (255,)) * w for _ in range(h))
    def chunk(t, d): c = struct.pack('>I', len(d)) + t + d; return c + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b'')

STATES = """<modules/>
<states><LKState name="Locked"><elements/></LKState><LKState name="Unlock"><elements/></LKState><LKState name="Sleep"><elements/></LKState></states>
<stateTransitions>""" + ''.join(f'<LKStateTransition fromState="{a}" toState="{b}"><elements/></LKStateTransition>' for a, b in
    [("*","Unlock"),("Unlock","*"),("*","Locked"),("Locked","*"),("*","Sleep"),("Sleep","*")]) + "</stateTransitions>"

def layer(i, name, w, h, x, y, color=None, src=None, anims=''):
    a = f'id="L{i}" name="{name}" bounds="0 0 {num(w)} {num(h)}" position="{num(x)} {num(y)}" zPosition="0" opacity="1" transform.rotation.z="0" transform.rotation.x="0" transform.rotation.y="0" transform="rotate(0deg) rotate(0deg, 0, 1, 0) rotate(0deg, 1, 0, 0)"'
    if color: a += f' backgroundColor="{color}"'
    a += f' cornerRadius="{num(min(w,h)/2) if color else 0}" allowsEdgeAntialiasing="1" allowsGroupOpacity="1" contentsFormat="RGBA8" cornerCurve="circular"'
    inner = (f'<contents><CGImage src="{src}"/></contents>' if src else '') + (f'<animations>{anims}</animations>' if anims else '')
    return f'<CALayer {a}>{inner}</CALayer>' if inner else f'<CALayer {a}/>'

def anim(i, keypath, kind, values, duration, rev=False):
    v = ''.join((f'<CGPoint value="{num(a)} {num(b)}"/>' if kind == 'pt' else f'<real value="{num(a)}"/>') for a, b in values)
    return (f'<animation key="animation-{i}" type="CAKeyframeAnimation" keyPath="{keypath}" autoreverses="{int(rev)}" beginTime="1e-100" '
            f'duration="{num(duration)}" speed="1" removedOnCompletion="0" repeatCount="inf" repeatDuration="inf" calculationMode="linear"><values>{v}</values></animation>')

def doc(w, h, children):
    cx, cy = w / 2, h / 2
    attrs = f'bounds="0 0 {num(w)} {num(h)}" position="{num(cx)} {num(cy)}" zPosition="0" geometryFlipped="0" opacity="1" allowsEdgeAntialiasing="1" allowsGroupOpacity="1" contentsFormat="RGBA8" cornerCurve="circular"'
    return ('<?xml version="1.0" encoding="UTF-8"?>\n<caml xmlns="http://www.apple.com/CoreAnimation/1.0">'
            f'<CALayer id="__capRootLayer__" name="TendieStudio Root" {attrs}><sublayers><CALayer id="root" name="Root Layer" {attrs}><sublayers>'
            + children + '</sublayers></CALayer></sublayers>' + STATES + '</CALayer></caml>\n')

def build(w=430, h=932, duration=6):
    N = int(duration * 30)
    t = [duration * i / N for i in range(N + 1)]
    bg = layer(0, "Background Color", w, h, w/2, h/2, color="0.05 0.06 0.12")
    # Orbiting amber dot + spinning ember square + breathing PNG badge
    orbit = anim(0, "position", 'pt', [(w/2 + 90*math.cos(2*math.pi*s/duration), h/2 + 90*math.sin(2*math.pi*s/duration)) for s in t], duration)
    dot = layer(1, "Amber Dot", 70, 70, w/2, h/2, color="1 0.69 0.2", anims=orbit)
    spin = anim(0, "transform.rotation.z", 'r', [(2*math.pi*s/duration, 0) for s in t], duration)
    sq = layer(2, "Spinning Square", 120, 120, w/2, h*0.72, color="1 0.42 0.3", anims=spin)
    pulse = anim(0, "opacity", 'r', [(0.35 + 0.65*(0.5 - 0.5*math.cos(2*math.pi*s/duration)), 0) for s in t], duration)
    badge = layer(3, "Badge", 160, 160, w/2, h*0.22, src="assets/badge.png", anims=pulse)
    files = {}
    for p, b64 in FILES.items(): files[f"descriptors/{UUID}/{p}"] = base64.b64decode(b64)
    base = f"descriptors/{UUID}/versions/1/contents/{WF}/"
    fg = base + ca("Foreground") + "/index.xml"
    s = files[fg].decode()
    s = s.replace("<key>documentHeight</key>\n\t<real>844</real>", f"<key>documentHeight</key>\n\t<real>{num(h)}</real>")
    s = s.replace("<key>documentWidth</key>\n\t<real>390</real>", f"<key>documentWidth</key>\n\t<real>{num(w)}</real>")
    files[fg] = s.encode()
    files[base + ca("Background") + "/main.caml"] = doc(w, h, bg).encode()
    files[base + ca("Floating") + "/main.caml"] = doc(w, h, dot + sq + badge).encode()
    files[base + ca("Foreground") + "/main.caml"] = doc(w, h, '').encode()
    files[base + ca("Floating") + "/assets/badge.png"] = png(160, 160, (255, 176, 51))
    return files

def write(files, out):
    dirs = set()
    for p in files:
        parts = p.split('/')[:-1]
        for i in range(1, len(parts) + 1): dirs.add('/'.join(parts[:i]) + '/')
    with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
        for d in sorted(dirs): z.writestr(zipfile.ZipInfo(d, (2026, 1, 1, 0, 0, 0)), b'')
        for p in sorted(files): z.writestr(p, files[p])

if __name__ == '__main__':
    out = sys.argv[1]
    w, h = (float(sys.argv[2]), float(sys.argv[3])) if len(sys.argv) > 3 else (430, 932)
    write(build(w, h), out); print('wrote', out, f'({int(w)}x{int(h)})')
