#!/usr/bin/python3
"""Installed-router acceptance. Only owned loopback jobs and synthetic fixtures.

Optional SMB fixture: forward router 127.0.0.1:2445 to the isolated laptop test
server, then supply --smb-port 2445. No customer targets or credentials are used.
"""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import socket
import subprocess
import threading
import time

created=[]


def call(*args, ok=True):
    r=subprocess.run(['/usr/libexec/ddk-console',*args],capture_output=True,text=True,timeout=60)
    value=json.loads(r.stdout)
    assert value['ok']==ok,(args[:2],value.get('message'))
    return value.get('data')


def b64(value):return base64.urlsafe_b64encode(value.encode()).decode().rstrip('=')
def envelope(options):return b64(json.dumps({'version':1,'options':options}))


def start(action,options):
    plan=call('action','prepare',action,envelope(options))
    argv=['job','start',plan['prepared_id']]
    if plan.get('confirmation',{}).get('required'):argv.append(b64(plan['confirmation']['phrase']))
    job=call(*argv);created.append(job['id']);return job


def finish(job,expected='complete'):
    for _ in range(240):
        state=call('job','status',job['id'])
        if state['status'] in ('complete','failed','stopped'):
            assert state['status']==expected,(state['status'],state['stderr'])
            return state
        time.sleep(.25)
    raise AssertionError('Owned fixture job did not finish')


def tlv(tag,data):
    length=len(data)
    if length<128:prefix=bytes([length])
    else:
        raw=length.to_bytes((length.bit_length()+7)//8,'big');prefix=bytes([128+len(raw)])+raw
    return bytes([tag])+prefix+data


def unpack(data):
    tag,length=data[0],data[1];offset=2
    if length&128:
        size=length&127;length=int.from_bytes(data[offset:offset+size],'big');offset+=size
    return tag,data[offset:offset+length],data[offset+length:]


class SNMPFixture:
    def __init__(self):
        self.socket=socket.socket(socket.AF_INET,socket.SOCK_DGRAM);self.socket.bind(('127.0.0.1',0));self.socket.settimeout(.2)
        self.port=self.socket.getsockname()[1];self.running=True;self.matches=0
        # Synthetic parser fixture, not a device credential.
        self.community='orbit-fixture "quoted" \\ value'
        self.thread=threading.Thread(target=self.serve,daemon=True);self.thread.start()

    def serve(self):
        while self.running:
            try:data,peer=self.socket.recvfrom(65535)
            except socket.timeout:continue
            _,body,_=unpack(data);_,version,body=unpack(body);_,community,body=unpack(body)
            if community!=self.community.encode():continue
            self.matches+=1
            kind,pdu,_=unpack(body);_,request,pdu=unpack(pdu);_,_,pdu=unpack(pdu);_,_,pdu=unpack(pdu);_,bindings,_=unpack(pdu)
            values=[]
            while bindings:
                _,binding,bindings=unpack(bindings);_,oid,_=unpack(binding)
                # Custom GETNEXT walks stop honestly at the end of our tiny MIB.
                value=tlv(0x82,b'') if kind==0xa1 else tlv(4,b'Orbit synthetic equipment')
                values.append(tlv(0x30,tlv(6,oid)+value))
            response=tlv(0xa2,tlv(2,request)+tlv(2,b'\0')+tlv(2,b'\0')+tlv(0x30,b''.join(values)))
            self.socket.sendto(tlv(0x30,tlv(2,version)+tlv(4,community)+response),peer)

    def close(self):self.running=False;self.thread.join(1);self.socket.close()


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--smb-port',type=int);args=parser.parse_args()
    assert Path('/usr/share/ddk-field-console/VERSION').read_text().strip()=='4.2.1'
    protected=['network','wireless','firewall','uhttpd','rpcd','gpsd','rtl_tcp','motion','mjpg-streamer']
    def hashes():return {n:hashlib.sha256(Path('/etc/config',n).read_bytes()).hexdigest() for n in protected}
    before=hashes();fixture=SNMPFixture();listener=socket.socket();listener.bind(('127.0.0.1',0));listener.listen(2)
    try:
        for action in ['network.lldp','network.tracepath','network.snmp','network.compare_scans','network.smb']:
            schema=call('action','describe',action);assert schema['fields'];assert not schema['availability']['missing'],schema['availability']
        print('PASS five installed native tool schemas',flush=True)
        lldp=finish(start('network.lldp',{'duration':15,'output_mib':1}));assert isinstance(json.loads(lldp['stdout'])['lldp'],dict)
        print('PASS LLDP JSON response (neighbor content depends on connected equipment)',flush=True)
        for family,host in [('ipv4','127.0.0.1'),('ipv6','::1')]:
            state=finish(start('network.tracepath',{'host':host,'family':family,'duration':15,'output_mib':1}));assert 'reached' in state['stdout']
        print('PASS IPv4 and IPv6 tracepath loopback',flush=True)
        options={'host':'127.0.0.1','port':fixture.port,'community':fixture.community,'timeout':1,'retries':0,'duration':10,'output_mib':1}
        for profile in ['system','walk']:
            state=finish(start('network.snmp',dict(options,profile=profile)));assert fixture.community not in json.dumps(state)
            assert not Path('/tmp/ddk/jobs',state['id'],'private-msp').exists()
        assert fixture.matches>=2
        state=finish(start('network.snmp',dict(options,community='deliberately-wrong-fixture')),expected='failed')
        assert 'Timeout' in state['stderr']
        print('PASS native SNMP GET/walk, quoted credential parsing, timeout and RAM-file cleanup',flush=True)
        port=listener.getsockname()[1]
        opts={'targets':['127.0.0.1'],'interface':'lo','scan_type':'connect','ports':str(port),'service_detection':False,'os_detection':False,'script_profile':'none','output_format':'xml','output_mib':1,'wall_timeout':30}
        earlier=finish(start('network.nmap_lan_discovery',opts));call('job','save',earlier['id']);listener.close()
        later=finish(start('network.nmap_lan_discovery',opts));call('job','save',later['id'])
        state=finish(start('network.compare_scans',{'baseline':earlier['id'],'current':later['id'],'duration':30,'output_mib':1}))
        assert str(port) in state['stdout'] and 'Differences reported' in state['stdout']
        assert call('job','save',state['id'])['saved']
        print('PASS real saved Nmap open/closed port comparison and case preservation',flush=True)
        if args.smb_port:
            options={'host':'127.0.0.1','port':args.smb_port,'share':'Orbit-Test','guest':True,'timeout':30,'duration':180,'output_mib':1}
            for operation in ['shares','directory','transfer']:
                state=finish(start('network.smb',dict(options,operation=operation,transfer_mib=2)))
                if operation=='transfer':assert 'Transfer verified: PASS' in state['stdout'] and 'Transfer test file removed:' in state['stdout']
                assert not Path('/tmp/ddk/jobs',state['id'],'private-msp').exists()
                assert not Path('/overlay/ddk-field-console/artifacts',state['id'],'workspace-msp').exists()
            print('PASS installed SMB list/browse, transfer larger than log budget, SHA256 and deletion',flush=True)
        assert hashes()==before
        print('PASS all protected configuration hashes preserved',flush=True)
    finally:
        fixture.close();listener.close()
        for identifier in reversed(created):
            state=call('job','status',identifier)
            if state['status'] not in ['complete','stopped','failed']:call('job','stop',identifier);finish({'id':identifier},expected='stopped')
            call('job','delete',identifier)
        print('Owned acceptance jobs and saved fixture cases removed.',flush=True)


if __name__=='__main__':main()
