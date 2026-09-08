#!/usr/bin/env python3
"""Deterministic, tiny test archives. No user data, downloads or executable payloads."""
import io, pathlib, tarfile, zipfile, gzip, bz2, lzma, json, subprocess, tempfile
root=pathlib.Path(__file__).resolve().parents[1]/'Tests/ArcoraCoreTests/Fixtures'
root.mkdir(parents=True,exist_ok=True)
entries={'hello.txt':b'Hello from Arcora.\n','资料/日本語.txt':'中文・日本語・English\n'.encode(),'empty.txt':b'','nested/deep/value.bin':bytes(range(256))*4}
def tar_data(items):
    out=io.BytesIO()
    with tarfile.open(fileobj=out,mode='w',format=tarfile.PAX_FORMAT) as archive:
        for name,data in items.items():
            info=tarfile.TarInfo(name);info.size=len(data);info.mtime=1700000000;info.mode=0o644
            archive.addfile(info,io.BytesIO(data))
    return out.getvalue()
def zip_data(items):
    out=io.BytesIO()
    with zipfile.ZipFile(out,'w',compression=zipfile.ZIP_DEFLATED) as archive:
        for name,data in items.items():
            info=zipfile.ZipInfo(name,(2023,11,14,22,13,20));info.compress_type=zipfile.ZIP_DEFLATED;info.external_attr=(0o100644<<16)
            archive.writestr(info,data)
    return out.getvalue()
raw=tar_data(entries)
for name,data in [('normal.tar',raw),('normal.tar.gz',gzip.compress(raw,mtime=0)),('normal.tar.bz2',bz2.compress(raw)),('normal.tar.xz',lzma.compress(raw)),('normal.zip',zip_data(entries)),('traversal.zip',zip_data({'../escaped.txt':b'not allowed'})),('absolute.tar',tar_data({'/tmp/arcora-escape.txt':b'not allowed'})),('case-collision.zip',zip_data({'Report.txt':b'one','report.txt':b'two'})),('parent-conflict.tar',tar_data({'node':b'file','node/child.txt':b'child'})),('expansion-limit.zip',zip_data({'large.txt':b'A'*1_048_576})),('invalid.bin',b'This is not an archive.\x00\x03')]:
    (root/name).write_bytes(data)
for kind in ['symlink','hardlink','fifo']:
    out=io.BytesIO()
    with tarfile.open(fileobj=out,mode='w') as archive:
        info=tarfile.TarInfo('unsafe');info.mtime=1700000000
        info.type={'symlink':tarfile.SYMTYPE,'hardlink':tarfile.LNKTYPE,'fifo':tarfile.FIFOTYPE}[kind]
        info.linkname='../../escape';archive.addfile(info)
    (root/(kind+'.tar')).write_bytes(out.getvalue())
(root/'truncated.tar').write_bytes(raw[:520])
(root/'expected.json').write_text(json.dumps({k:v.hex() for k,v in entries.items()},ensure_ascii=False,indent=2)+'\n')
print('Generated fixtures in',root)
