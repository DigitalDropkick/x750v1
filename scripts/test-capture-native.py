#!/usr/bin/env python3
"""Staged native monitor ownership and loopback ring rotation regression."""
import base64, hashlib, json, pathlib, socket, subprocess, time
root = pathlib.Path('/tmp/ddk-v3-full')
def call(*args):
    result = subprocess.run(['/usr/bin/lua', str(root/'usr/libexec/ddk-console'), *args], capture_output=True, text=True, timeout=45)
    value = json.loads(result.stdout)
    assert value['ok'], value.get('message')
    return value['data']
def encode(value):
    return base64.urlsafe_b64encode(value.encode()).decode().rstrip('=')
def start(action, options):
    plan = call('action', 'prepare', action, encode(json.dumps({'version':1, 'options':options})))
    args = ['job', 'start', plan['prepared_id']]
    if plan['confirmation']['required']:
        args.append(encode(plan['confirmation']['phrase']))
    return call(*args)
def finish(job, stop=False):
    if stop: call('job', 'stop', job['id'])
    for _ in range(100):
        state = call('job', 'status', job['id'])
        if state['status'] in ['complete', 'failed', 'stopped']: return state
        time.sleep(.2)
    raise AssertionError('Capture did not terminate')
def config_hashes():
    return [hashlib.sha256(pathlib.Path('/etc/config', name).read_bytes()).digest() for name in ['network','wireless','firewall']]
before = config_hashes()
interfaces = set(pathlib.Path('/sys/class/net').iterdir())
# Shares the current AP channel. The filter excludes ordinary client frames.
monitor = start('wireless.monitor', {'phy':'phy1', 'channel':0, 'duration':3, 'capture_mib':1, 'output_mib':1, 'filter':'wlan addr2 00:00:00:00:00:00'})
try:
    result = finish(monitor)
    assert result['status']=='complete', result.get('stderr')
    assert any(a['name']=='wireless.pcap' for a in result['artifacts'])
finally:
    if call('job','status',monitor['id'])['status'] in ['queued','running']: finish(monitor, True)
assert set(pathlib.Path('/sys/class/net').iterdir()) == interfaces, 'Monitor interface leaked'
assert config_hashes() == before, 'Router configuration changed'
print('DDK_NATIVE_MONITOR_OK: concurrent interface, native PCAP, current channel, cleanup, configuration preserved', flush=True)
ring = start('capture.ring', {'interface':'lo', 'filter':'udp port 49999', 'segment_mb':1, 'segments':3, 'snaplen':0, 'duration':0, 'output_mib':1, 'promiscuous':False})
try:
    time.sleep(2)
    sender = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    for i in range(6000):
        sender.sendto(b'DDK public loopback fixture ' + bytes(1372), ('127.0.0.1',49999))
        time.sleep(.001)
    sender.close()
    result = finish(ring, True)
    assert result['status']=='stopped', result.get('stderr')
    captures = [a for a in result['artifacts'] if a['name'].startswith('capture.pcap')]
    assert {a['name'] for a in captures} == {'capture.pcap0','capture.pcap1','capture.pcap2'}, [a['name'] for a in captures]
    for item in captures:
        path = root/'persist/artifacts'/ring['id']/item['name']
        assert 24 < path.stat().st_size <= 1262144
        assert path.read_bytes()[:4] in [bytes.fromhex('a1b2c3d4'), bytes.fromhex('d4c3b2a1')]
    print('DDK_NATIVE_RING_OK: three rotating PCAP files, bounded sizes, loopback payload only, stop preserved results', flush=True)
finally:
    if call('job','status',ring['id'])['status'] in ['queued','running']: finish(ring, True)
