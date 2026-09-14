#!/usr/bin/python3
"""Install the checksum-pinned MSP userspace closure on the matching appliance.

Run on the router: python3 install-msp-tools.py PACKAGE_DIRECTORY LOCK_JSON
Only missing packages are installed. Existing versions must match the lock.
No feed refresh, dependency download, daemon enablement or core upgrade occurs.
"""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time


def installed():
    result={}
    for paragraph in Path('/usr/lib/opkg/status').read_text().split('\n\n'):
        fields=dict(line.split(': ',1) for line in paragraph.splitlines() if ': ' in line and not line.startswith(' '))
        if 'installed' in fields.get('Status','').split():result[fields['Package']]=fields
    return result


def main():
    os.umask(0o077)
    assert os.geteuid()==0,'Run only on the router as root'
    board=json.loads(subprocess.check_output(['ubus','call','system','board']))
    assert board['model']=='GL.iNet GL-X750' and board['release']['version']=='22.03.4','Unexpected appliance'
    package_dir=Path(sys.argv[1]).resolve();lock=json.loads(Path(sys.argv[2]).read_text())
    assert lock['firmware']=='22.03.4' and lock['architecture']=='mips_24kc'
    before=installed();missing=[]
    providers=set(before)
    for record in before.values():providers.update(x.strip().split(' ')[0] for x in record.get('Provides','').split(',') if x.strip())
    for package in lock['packages']:
        assert package['architecture']=='mips_24kc'
        assert package['package'] not in ['libc','kernel','libgcc','libpthread','libopenssl1.1']
        if package['package'] in before:
            assert before[package['package']]['Version']==package['version'],'Installed version differs: '+package['package']
        else:missing.append(package)
        path=package_dir/package['filename']
        assert path.parent==package_dir and path.is_file() and not path.is_symlink()
        assert path.stat().st_size==package['bytes']
        assert hashlib.sha256(path.read_bytes()).hexdigest()==package['sha256'],'Checksum mismatch: '+package['package']
    closure=providers | {p['package'] for p in missing}
    for package in missing:
        for dep in package['depends'].split(','):
            assert dep.strip().split(' ')[0] in closure,'Unresolved dependency: '+dep
    if not missing:
        print('All eight pinned MSP packages are already installed.');return
    assert os.statvfs('/overlay').f_bavail*os.statvfs('/overlay').f_frsize>150*1048576,'Insufficient extroot space'
    backup=Path('/root/ddk-backups')/('msp-packages-'+time.strftime('%Y%m%dT%H%M%SZ',time.gmtime()))
    backup.mkdir(mode=0o700)
    (backup/'before.json').write_text(json.dumps({n:p['Version'] for n,p in before.items()},indent=2))
    (backup/'added.txt').write_text('\n'.join(p['package'] for p in missing)+'\n')
    print('Package rollback record: '+str(backup),flush=True)
    # Offline local archives for the entire dependency closure: opkg has no reason
    # to fetch/upgrade anything. The post-install audit enforces that invariant.
    empty_lists=backup/'empty-package-lists';empty_lists.mkdir(mode=0o700)
    config=backup/'offline-opkg.conf'
    config.write_text('dest root /\nlists_dir ext '+str(empty_lists)+'\narch all 1\narch noarch 1\narch mips_24kc 10\n')
    offline_env=dict(os.environ,OPKG_CONF_DIR=str(empty_lists))
    subprocess.run(['opkg','--conf',str(config),'--noaction','install']+[str(package_dir/p['filename']) for p in missing],check=True,env=offline_env,timeout=180)
    subprocess.run(['opkg','--conf',str(config),'install']+[str(package_dir/p['filename']) for p in missing],check=True,env=offline_env)
    after=installed()
    assert all(after.get(n,{}).get('Version')==p['Version'] for n,p in before.items()),'An existing package changed'
    assert set(after)-set(before)=={p['package'] for p in missing},'Unexpected added package'
    assert all(after[p['package']]['Version']==p['version'] for p in lock['packages'])
    (backup/'verified.json').write_text(json.dumps({n:p['Version'] for n,p in after.items()},indent=2))
    print('Verified: '+str(len(missing))+' userspace packages added; every existing package version preserved.')


if __name__=='__main__':main()
