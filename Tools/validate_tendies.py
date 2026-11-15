#!/usr/bin/env python3
"""Structural validator for .tendies files, derived from real community files.

Mirrors TendiesValidator.swift. Usage: validate_tendies.py a.tendies [b.tendies ...]
Exit status 1 if any file has errors. Warnings do not fail.
Checks what we can verify offline; it cannot prove PosterBoard will accept a file.
"""
import plistlib, re, sys, zipfile
import xml.dom.minidom as minidom

def validate(path):
    errors, warns, info = [], [], {}
    try:
        z = zipfile.ZipFile(path)
    except Exception as e:
        return [f"not a zip: {e}"], [], info
    names = [n for n in z.namelist() if 'DS_Store' not in n and '__MACOSX' not in n]
    if any('com.apple.mercuryposter' in n.lower() for n in names):
        errors.append("Mercury poster container (unsupported by CAPlayground and this app)")
    pl = [n for n in names if n.endswith('/Wallpaper.plist')]
    if len(pl) != 1:
        return errors + [f"expected exactly one Wallpaper.plist, found {len(pl)}"], warns, info
    wp = pl[0]
    base = wp.rsplit('/', 1)[0] + '/'
    if not re.match(r'descriptors/[^/]+/versions/\d+/contents/[^/]+\.wallpaper/Wallpaper\.plist$', wp):
        errors.append(f"Wallpaper.plist at unexpected path: {wp}")
    root = wp.split('/contents/')[0]
    for must in ('com.apple.posterkit.provider.descriptor.identifier',
                 'com.apple.posterkit.role.identifier', 'providerInfo.plist'):
        if f"{wp.split('/versions/')[0]}/{must}" not in names:
            errors.append(f"missing descriptor file {must}")
    for must in ('com.apple.posterkit.provider.contents.userInfo',):
        if f"{root}/contents/{must}" not in names:
            errors.append(f"missing contents file {must}")
    try:
        p = plistlib.loads(z.read(wp))
        d = p['assets']['lockAndHome']['default']
        info['name'] = p.get('name'); info['screen'] = p.get('logicalScreenClass')
        refs = [d.get('foregroundAnimationFileName'), d.get('backgroundAnimationFileName'),
                d.get('floatingAnimationFileNameKey')]
        if d.get('type') != 'LayeredAnimation':
            errors.append(f"Wallpaper.plist type is {d.get('type')!r}, expected LayeredAnimation")
    except Exception as e:
        return errors + [f"Wallpaper.plist unreadable/unexpected shape: {e}"], warns, info
    ui = f"{root}/contents/com.apple.posterkit.provider.contents.userInfo"
    if ui in names:
        try:
            u = plistlib.loads(z.read(ui))
            if u.get('wallpaperRepresentingFileName') != wp.split('/')[-2]:
                errors.append("userInfo.wallpaperRepresentingFileName != .wallpaper folder name")
        except Exception as e:
            errors.append(f"userInfo unreadable: {e}")
    total = 0
    for ref in refs:
        if not ref:
            warns.append("a plane is not referenced in Wallpaper.plist"); continue
        ca = base + ref + '/'
        if not any(n.startswith(ca) for n in names):
            errors.append(f"Wallpaper.plist references missing package {ref}"); continue
        idx = ca + 'index.xml'
        if idx not in names:
            errors.append(f"{ref}: missing index.xml"); continue
        try:
            ip = plistlib.loads(z.read(idx)); rootdoc = ip['rootDocument']
        except Exception as e:
            errors.append(f"{ref}: index.xml invalid: {e}"); continue
        if ca + rootdoc not in names:
            errors.append(f"{ref}: rootDocument {rootdoc} missing"); continue
        if ca + 'assetManifest.caml' not in names:
            warns.append(f"{ref}: no assetManifest.caml (all real samples have one)")
        try:
            doc = minidom.parseString(z.read(ca + rootdoc))
        except Exception as e:
            errors.append(f"{ref}: {rootdoc} is not well-formed XML: {e}"); continue
        if doc.documentElement.tagName != 'caml' or doc.documentElement.getAttribute('xmlns') != 'http://www.apple.com/CoreAnimation/1.0':
            errors.append(f"{ref}: root element must be <caml xmlns=http://www.apple.com/CoreAnimation/1.0>")
        for el in doc.getElementsByTagName('CGImage'):
            src = el.getAttribute('src')
            if src and not src.startswith('data:') and ca + src not in names:
                errors.append(f"{ref}: image {src} missing from package")
        n_anim = len(doc.getElementsByTagName('animation'))
        n_layers = len(doc.getElementsByTagName('CALayer'))
        info[ref.split('_')[-1].split('-')[0]] = f"{n_layers} layers, {n_anim} animations"
        total += sum(z.getinfo(n).file_size for n in names if n.startswith(ca))
    if total > 200 * 1024 * 1024:
        warns.append("package larger than 200 MB")
    return errors, warns, info

if __name__ == '__main__':
    bad = 0
    for f in sys.argv[1:]:
        e, w, i = validate(f)
        print(('FAIL ' if e else 'ok   ') + f, i)
        for x in e: print('   error:', x)
        for x in w: print('   warn: ', x)
        bad += bool(e)
    sys.exit(1 if bad else 0)
