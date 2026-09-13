#!/usr/bin/env python3
"""Native LuCI/nixio backend lifecycle test; all job paths are staged under /tmp."""
import base64,json,pathlib,subprocess,time
root=pathlib.Path('/tmp/ddk-v3-full')
backend=root/'usr/libexec/ddk-console'
def call(*args,ok=True):
 result=subprocess.run(['/usr/bin/lua',str(backend),*args],capture_output=True,text=True,timeout=45)
 try: value=json.loads(result.stdout)
 except Exception: raise AssertionError('Backend did not return JSON: '+result.stderr[:300])
 assert value['ok']==ok,(args[:2],value.get('message'))
 return value.get('data')
def envelope(options): return base64.urlsafe_b64encode(json.dumps({'version':1,'options':options}).encode()).decode().rstrip('=')
def await_job(job):
 for _ in range(60):
  state=call('job','status',job['id'])
  if state['status'] in ['complete','failed','stopped']: return state
  time.sleep(.25)
 raise AssertionError('Job failed to reach terminal state')
settings=call('settings','get');assert settings['job_hours']>=0
modules=call('capabilities');assert len(modules)==24
for kind,name,size in [('android_package','large-fixture.apk',536870912),('android_backup','large-fixture.ab',2147483648),('firmware_image','large-fixture.bin',536870912)]:
 reserved=call('upload','reserve',kind,envelope({'name':name,'size':size}))
 call('upload','delete',reserved['id'])
print('Native large APK, backup and firmware reservations passed without allocating payloads',flush=True)
for index,action in enumerate(sorted(a['id'] for module in modules for a in module['actions'] if a.get('parameter_schema')=='operator-v1')):
 described=call('action','describe',action);assert described['fields'] and described['action_id']==action
 if (index+1)%10==0: print('Staged native schemas opened: '+str(index+1),flush=True)
call('settings','set',envelope({'job_hours':0,'job_count':0,'input_hours':0}))
assert call('settings','get')['job_hours']==0
call('settings','set',envelope({'job_hours':-1}),ok=False)
schema=call('action','describe','network.fping')
assert any(x['name']=='duration' and x['min']==0 for x in schema['fields'])
plan=call('action','prepare','network.fping',envelope({'targets':['127.0.0.1'],'interface':'lo','count':2,'period_ms':100,'duration':5,'output_mib':1}))
job=call('job','start',plan['prepared_id']);state=await_job(job)
assert state['status']=='complete',state['stderr']
assert any(a['size']>0 for a in state['artifacts'])
saved=call('job','save',job['id']);assert saved['saved']
label=call('job','label',job['id'],envelope({'label':'DDK native loopback fixture'}));assert label['metadata']['case_label']=='DDK native loopback fixture'
call('job','label',job['id'],envelope({'label':'x\n'}),ok=False)
upload=call('job','reuse',job['id'],'native-output.txt','forensics_input')
for _ in range(60):
 if upload['phase']=='sealed': break
 time.sleep(.2);upload=call('upload','finalize',upload['id'])
assert len(upload['sha256'])==64 and upload['sealed_at']>0
# A saved case remains usable when transient metadata disappears (reboot simulation).
transient=root/'state/jobs'/job['id']
transient.rename(transient.with_name(transient.name+'.reboot-fixture'))
assert call('job','status',job['id'])['saved']
export=call('action','prepare','cases.export',envelope({'case':job['id'],'output_mib':1}))
exported=await_job(call('job','start',export['prepared_id']))
assert exported['status']=='complete',exported['stderr']
archive=root/'persist/artifacts'/exported['id']/'case.tar'
names=[name.removeprefix('./') for name in subprocess.check_output(['/bin/tar','-tf',str(archive)],text=True).splitlines()]
assert {'metadata.json','status','stdout','stderr','native-output.txt'}<=set(names),names
plan=call('action','prepare','network.fping',envelope({'targets':['127.0.0.1'],'interface':'lo','count':0,'period_ms':100,'duration':0,'output_mib':1}))
running=call('job','start',plan['prepared_id']);time.sleep(1)
call('job','stop',running['id']);stopped=await_job(running)
assert stopped['status']=='stopped' and stopped['artifacts'],stopped['status']
assert call('job','save',running['id'])['saved']
call('job','delete',job['id']);call('job','status',job['id'],ok=False)
print('DDK_V3_BACKEND_OK: real prepare/start/results, save, case label, reuse, reboot survival, tar export, unlimited-duration stop, partial save, delete, retention validation')
