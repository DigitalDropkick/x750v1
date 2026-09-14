#!/usr/bin/env python3
"""Native rotated-PCAP reuse regression in an isolated v4 staging tree."""
import base64, hashlib, json, pathlib, socket, subprocess, time
ROOT=pathlib.Path('/tmp/ddk-v4-validation')
def call(*args):
    result=subprocess.run(['/usr/bin/lua',str(ROOT/'usr/libexec/ddk-console'),*args],text=True,capture_output=True,timeout=45)
    value=json.loads(result.stdout)
    assert value['ok'],value.get('message')
    return value['data']
def envelope(value):
    return base64.urlsafe_b64encode(json.dumps({'version':1,'options':value}).encode()).decode().rstrip('=')
plan=call('action','prepare','capture.ring',envelope({'interface':'lo','filter':'udp port 49999','segment_mb':1,'segments':3,'snaplen':0,'duration':4,'output_mib':1,'promiscuous':False}))
args=['job','start',plan['prepared_id']]
if plan['confirmation']['required']: args.append(base64.urlsafe_b64encode(plan['confirmation']['phrase'].encode()).decode().rstrip('='))
job=call(*args)
time.sleep(1)
with socket.socket(socket.AF_INET,socket.SOCK_DGRAM) as sender:
    for _ in range(20): sender.sendto(b'DDK public v4 GUI input fixture',('127.0.0.1',49999))
for _ in range(80):
    state=call('job','status',job['id'])
    if state['status'] not in ['running','queued','stopping']: break
    time.sleep(.2)
assert state['status']=='complete',state['stderr']
artifact=next(a for a in state['artifacts'] if a['name']=='capture.pcap0')
source=ROOT/'persist/artifacts'/job['id']/artifact['name']
original=hashlib.sha256(source.read_bytes()).hexdigest()
reused=call('job','reuse',job['id'],artifact['name'],'capture_input')
while reused['phase']=='sealing':
    time.sleep(.2);reused=call('upload','finalize',reused['id'])
assert reused['original_name']=='capture.pcap0.pcap'
assert reused['sha256']==original
assert hashlib.sha256(source.read_bytes()).hexdigest()==original
for action in ['capture.inspect','capture.replay','wireless.file_analysis']:
    schema=call('action','describe',action)
    field=next(f for f in schema['fields'] if f['name']=='input')
    assert any(isinstance(o,dict) and o['value']==reused['id'] for o in field['options'])
call('job','delete',job['id']);call('upload','delete',reused['id'])
print('DDK_V4_INPUT_NATIVE_OK: native ring capture reused, identical SHA-256, unchanged source, selected by all three capture tools, fixtures removed')
