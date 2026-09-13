#!/usr/bin/env python3
"""Build an isolated on-router validation tree without replacing deployed files."""
from pathlib import Path
import shutil
import tarfile
root=Path(__file__).resolve().parents[1]
stage=Path('/tmp/ddk-v3-full')
for original in (root/'files').rglob('*'):
 if not original.is_file() or '__pycache__' in original.parts: continue
 relative=original.relative_to(root/'files'); target=stage/relative
 target.parent.mkdir(parents=True,exist_ok=True)
 data=original.read_bytes()
 if original.suffix in {'.lua','.json','.js','.htm'} or original.name.startswith('ddk-'):
  try:
   text=data.decode()
   for before,after in [('/usr/share/ddk-field-console',str(stage)+'/usr/share/ddk-field-console'),('/usr/libexec/ddk-',str(stage)+'/usr/libexec/ddk-'),('/tmp/ddk/',str(stage)+'/state/'),('/overlay/ddk-field-console',str(stage)+'/persist')]: text=text.replace(before,after)
   # Lua patterns escape the hyphens in the project-owned path.
   text=text.replace('/overlay/ddk%-field%-console',str(stage).replace('-','%-')+'/persist')
   data=text.encode()
  except UnicodeDecodeError: pass
 target.write_bytes(data);target.chmod(original.stat().st_mode&0o777)
for name in ['scripts/test-v3-backend.py','scripts/test-session-native.py','scripts/test-v3-native.sh','scripts/test-capture-native.py']:
 source=root/name
 if source.exists(): shutil.copyfile(source,stage/source.name)
with tarfile.open('/tmp/ddk-v3-full.tar','w') as archive: archive.add(stage,arcname='ddk-v3-full')
print('Created isolated /tmp/ddk-v3-full.tar')
