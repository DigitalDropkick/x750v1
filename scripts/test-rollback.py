#!/usr/bin/env python3
"""Exercise the real rollback script against a disposable filesystem fixture."""
import pathlib, subprocess, tempfile
source=pathlib.Path(__file__).with_name('router-rollback.sh').read_text()
with tempfile.TemporaryDirectory(prefix='ddk-rollback-') as directory:
 root=pathlib.Path(directory)
 # Rewrite only absolute infrastructure roots for this isolated fixture.
 script=source
 for path in ['/root/ddk-backups','/usr/libexec','/usr/share','/usr/lib/lua','/www','/tmp/luci-indexcache','/etc/init.d/rpcd']:
  script=script.replace(path,str(root)+path)
 rpcd=root/'etc/init.d/rpcd';rpcd.parent.mkdir(parents=True);rpcd.write_text('#!/bin/sh\n[ "$1" = reload ]\n');rpcd.chmod(0o755)
 for version in ['1','3','4']:
  backup=root/('root/ddk-backups/20260913T220000Z-field-console-v'+version)
  old=root/'usr/libexec/ddk-console';new=root/'usr/libexec/ddk-v3-worker'
  old.parent.mkdir(parents=True,exist_ok=True);old.write_text('replacement');new.write_text('new helper')
  archived=backup/'files'/str(old).lstrip('/');archived.parent.mkdir(parents=True);archived.write_text('previous release');archived.chmod(0o755)
  (backup/'existing.list').write_text(str(old)+'\n');(backup/'new.list').write_text(str(new)+'\n')
  result=subprocess.run(['sh','-s','--',str(backup)],input=script,text=True,capture_output=True)
  assert result.returncode==0,result.stderr
  assert old.read_text()=='previous release' and old.stat().st_mode&0o777==0o755
  assert not new.exists()
 print('DDK_ROLLBACK_OK: v1/v3/v4 snapshots, prior bytes and executable mode restored, new helper removed')
