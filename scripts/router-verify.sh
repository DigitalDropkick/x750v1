#!/bin/sh
# Functional v4 acceptance on the installed appliance. Only owned loopback jobs.
set -eu
[ "$(ubus call system board | jsonfilter -e '@.model')" = 'GL.iNet GL-X750' ]
[ "$(cat /usr/share/ddk-field-console/VERSION)" = '4.1.0-beta.1' ]
printf '%s\n' 'PASS Field Console version 4.1.0-beta.1 and target identity'
mount | grep -q '^/dev/sda1 on /overlay type ext4 '
grep -q '^/overlay/ddk-install.swap[[:space:]]' /proc/swaps
for worker in ddk-console ddk-job-worker ddk-apple-worker ddk-phase3-worker ddk-phase4-worker ddk-v3-worker ddk-device-session ddk-modbus-client ddk-usbip-client ddk-compare-range ddk-input-sealer; do
 [ -x "/usr/libexec/$worker" ]
done
python3 - <<'PYTHON_VERIFY'
import base64,hashlib,json,pathlib,subprocess,time
backend='/usr/libexec/ddk-console'
protected=['network','wireless','firewall','uhttpd','rpcd','gpsd','rtl_tcp','motion','mjpg-streamer']
def hashes():return {name:hashlib.sha256(pathlib.Path('/etc/config',name).read_bytes()).digest() for name in protected}
before=hashes()
def call(*args,ok=True):
 result=subprocess.run([backend,*args],capture_output=True,text=True,timeout=60)
 value=json.loads(result.stdout)
 assert value['ok']==ok,(args[:2],value.get('message'))
 return value.get('data')
def encode(options):return base64.urlsafe_b64encode(json.dumps({'version':1,'options':options}).encode()).decode().rstrip('=')
def finish(job):
 for _ in range(60):
  state=call('job','status',job['id'])
  if state['status'] in ['complete','stopped','failed']:return state
  time.sleep(.25)
 raise AssertionError('Owned loopback job did not finish')
call('status');modules=call('capabilities');call('packages');call('settings','get')
actions=[]
for path in pathlib.Path('/usr/share/ddk-field-console/tools').glob('*.json'):
 module=json.loads(path.read_text())
 for action in module['actions']:
  if action.get('enabled') and action.get('parameter_schema')=='operator-v1':actions.append(action['id'])
for index,action in enumerate(sorted(actions)):
 schema=call('action','describe',action)
 assert schema['action_id']==action and schema['fields'],action
 if (index+1)%10==0:print('PASS opened %s structured schemas'%(index+1),flush=True)
print('PASS all %s live structured schemas remain accessible'%len(actions),flush=True)
call('action','describe','not.a.real.action',ok=False)
call('job','stop','1',ok=False)
call('action','prepare','network.fping',encode({'targets':['127.0.0.1;id']}),ok=False)
created=[]
try:
 plan=call('action','prepare','network.fping',encode({'targets':['127.0.0.1'],'interface':'lo','count':2,'period_ms':100,'duration':10,'output_mib':1}))
 job=call('job','start',plan['prepared_id']);created.append(job)
 result=finish(job);assert result['status']=='complete' and result['artifacts'],result.get('stderr')
 assert '127.0.0.1' in result['stdout']
 call('job','save',job['id']);assert call('job','status',job['id'])['saved']
 plan=call('action','prepare','network.fping',encode({'targets':['127.0.0.1'],'interface':'lo','count':0,'period_ms':100,'duration':0,'output_mib':1}))
 job=call('job','start',plan['prepared_id']);created.append(job);time.sleep(2)
 call('job','stop',job['id']);result=finish(job)
 assert result['status']=='stopped' and result['artifacts']
 print('PASS native loopback, unlimited duration, stop, partial artifacts and case save',flush=True)
finally:
 for job in created:
  state=call('job','status',job['id'])
  if state['status'] in ['queued','running','stopping']:call('job','stop',job['id']);finish(job)
  call('job','delete',job['id'])
assert hashes()==before,'Protected router configuration changed'
print('PASS owned test cleanup and protected configuration preservation',flush=True)
PYTHON_VERIFY
for route in / /ddk /luci-static/resources/ddk/console-app.js /luci-static/resources/ddk/console-guide.js /luci-static/resources/ddk/console.css; do
 code="$(curl -sSL -o /dev/null -w '%{http_code}' --max-time 10 "http://127.0.0.1$route")"
 [ "$code" = 200 ] || { printf 'HTTP check failed: %s %s\n' "$route" "$code"; exit 1; }
done
printf '%s\n' 'DDK_ROUTER_V4_OK: installed runtime, all schemas, native jobs, results, cleanup and web services'
