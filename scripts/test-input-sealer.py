#!/usr/bin/env python3
"""Verify complete streaming hashes and retained failed inputs with the actual worker."""
import hashlib,json,pathlib,subprocess,tempfile
source=(pathlib.Path(__file__).resolve().parents[1]/'files/usr/libexec/ddk-input-sealer').read_text()
with tempfile.TemporaryDirectory(prefix='ddk-sealer-') as temporary:
 root=pathlib.Path(temporary);identifier='upload-1789330000-123-1';directory=root/identifier;directory.mkdir()
 worker=root/'worker.py';worker.write_text(source.replace('/overlay/ddk-field-console/uploads',str(root)))
 payload=b'DDK public streaming hash fixture\n'*262144;(directory/'sealed.bin').write_bytes(payload)
 record={'id':identifier,'phase':'sealing','declared_size':len(payload),'retention_seconds':3600}
 (directory/'metadata.json').write_text(json.dumps(record))
 subprocess.run(['python3',str(worker),identifier],check=True)
 result=json.loads((directory/'metadata.json').read_text());assert result['phase']=='sealed' and result['sha256']==hashlib.sha256(payload).hexdigest()
 assert result['expires_at']-result['sealed_at']==3600
 record['declared_size']+=1;(directory/'metadata.json').write_text(json.dumps(record))
 subprocess.run(['python3',str(worker),identifier],check=True)
 assert json.loads((directory/'metadata.json').read_text())['phase']=='failed'
 assert (directory/'sealed.bin').read_bytes()==payload
 print('DDK_INPUT_SEALER_OK: streaming SHA-256, retention, size mismatch, failed input preserved')
