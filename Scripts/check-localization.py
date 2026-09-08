#!/usr/bin/env python3
"""Fail on missing/duplicate keys, broken strings, or untranslated dynamic keys."""
import pathlib,re,json,sys
root=pathlib.Path(__file__).resolve().parents[1]
localized={}
for lang in ('en','zh-Hans','ja'):
    values={}
    for line in (root/f'Sources/Arcora/Resources/{lang}.lproj/Localizable.strings').read_text().splitlines():
        if not line.strip() or line.startswith('//'):continue
        m=re.fullmatch(r'("(?:[^"\\]|\\.)*")\s*=\s*("(?:[^"\\]|\\.)*");',line)
        if not m:raise SystemExit('Invalid .strings line: '+line)
        key,value=map(json.loads,m.groups())
        if key in values:raise SystemExit('Duplicate key: '+lang+' '+key)
        if not value:raise SystemExit('Empty value: '+lang+' '+key)
        values[key]=value
    localized[lang]=values
keys=set(localized['en'])
for lang,values in localized.items():
    if set(values)!=keys:raise SystemExit('Mismatched language keys: '+lang)
prefixes={key.split('.')[0] for key in keys}
source='\n'.join(p.read_text() for p in (root/'Sources/Arcora').glob('*.swift'))
required=set(k for k in re.findall(r'"([A-Za-z]+\.[A-Za-z0-9.]+)"',source) if k.split('.')[0] in prefixes)
required|={'guide.'+s+'.'+v for s in ['start','formats','rar','parts','password','threads','safety','build'] for v in ['title','body']}
required|={'state.'+s for s in ['queued','running','paused','succeeded','failed','cancelled','interrupted']}
required|={'level.'+str(v) for v in [0,1,3,5,7,9]}
missing=required-keys
if missing:raise SystemExit('Missing UI translations: '+', '.join(sorted(missing)))
print(f'PASS: {len(keys)} keys × 3 languages; all referenced UI keys covered.')
