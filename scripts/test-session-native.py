#!/usr/bin/env python3
"""Native helper tests using owned pseudo-devices and public synthetic data."""
import json,os,pathlib,pty,select,signal,subprocess,time
root=pathlib.Path('/tmp/ddk-v3-full')
helper=root/'usr/libexec/ddk-device-session'
master,slave=pty.openpty();device=os.ttyname(slave)
process=subprocess.Popen([str(helper),'gps',device,'9600','passive'],stdout=subprocess.PIPE,stderr=subprocess.PIPE,start_new_session=True)
def sentence(payload):
 value=0
 for byte in payload.encode(): value^=byte
 return ('$'+payload+'*'+format(value,'02X')+'\r\n').encode()
try:
 observed=b''
 for index in range(150):
  if process.poll() is not None: break
  stamp='12'+format(index//60,'02d')+format(index%60,'02d')+'.00'
  os.write(master,sentence('GPRMC,'+stamp+',A,0000.0000,N,00000.0000,E,0.0,0.0,130926,,,A')+sentence('GPGGA,'+stamp+',0000.0000,N,00000.0000,E,1,08,0.9,10.0,M,0.0,M,,'))
  ready,_,_=select.select([process.stdout],[],[],.2)
  if ready: observed+=os.read(process.stdout.fileno(),8192)
  if b'"class":"TPV"' in observed and b'"mode":3' in observed: break
 process.terminate()
 output,error=process.communicate(timeout=5)
 output=observed+output
 assert process.returncode==0,'helper exit '+str(process.returncode)+': '+error.decode()[:400]
 records=[]
 for line in output.splitlines():
  try: records.append(json.loads(line))
  except ValueError: pass
 assert any(record.get('class')=='TPV' and record.get('mode',0)>=2 for record in records),'No fix from synthetic NMEA stream: '+error.decode()[:400]
 print('DDK_GPSD_NATIVE_OK: selected pseudo-receiver, real gpsd/gpspipe, public NMEA fix, owned cleanup')
finally:
 if process.poll() is None: os.killpg(process.pid,signal.SIGKILL);process.wait()
 os.close(master);os.close(slave)
# flashrom's dummy programmer exercises the installed binary without touching USB hardware.
image=root/'dummy-flash.bin'
result=subprocess.run(['/usr/sbin/flashrom-usb','-p','dummy:emulate=M25P10.RES','-r',str(image)],capture_output=True,timeout=30)
assert result.returncode==0 and image.stat().st_size==131072,'Native flashrom dummy read failed'
assert image.read_bytes()==b'\xff'*131072
image.unlink()
print('DDK_FLASHROM_NATIVE_OK: installed flashrom-usb, emulated 128 KiB chip read, expected bytes')
# RTKLIB must start its real local console without opening a telnet listener.
master,slave=pty.openpty();device=os.ttyname(slave)
configuration=root/'rtk-native.cfg';solution=root/'rtk-native.pos'
configuration.write_text('\n'.join(['inpstr1-type=1','inpstr1-path='+device.removeprefix('/dev/')+':115200:8:n:1:off','inpstr1-format=4','inpstr2-type=0','inpstr3-type=0','outstr1-type=2','outstr1-path='+str(solution),'outstr1-format=0','outstr2-type=0','logstr1-type=0','logstr2-type=0','logstr3-type=0','pos1-posmode=0','pos1-frequency=1','file-tempdir='+str(root)])+'\n')
configuration.chmod(0o600)
process=subprocess.Popen([str(helper),'rtk',str(configuration),str(solution)],stdout=subprocess.PIPE,stderr=subprocess.PIPE,start_new_session=True)
try:
 observed=b''
 for _ in range(100):
  if process.poll() is not None: break
  ready,_,_=select.select([process.stdout],[],[],.2)
  if ready: observed+=os.read(process.stdout.fileno(),8192)
  if b'rtk server start' in observed.lower(): break
 if process.poll() is not None:
  remainder,error=process.communicate();raise AssertionError('RTK exit '+str(process.returncode)+': '+error.decode()[:400]+(observed+remainder)[-1200:].decode(errors='replace'))
 process.terminate();output,error=process.communicate(timeout=5)
 output=observed+output
 assert process.returncode==0,'helper exit '+str(process.returncode)+': '+error.decode()[:400]
 assert b'rtk server start' in output.lower() and b'rtk server start error' not in output.lower(),output[-1200:].decode(errors='replace')
 print('DDK_RTK_NATIVE_OK: generated configuration, owned pseudo-receiver, real RTKLIB server startup, local PTY, cleanup; no positioning fix asserted')
finally:
 if process.poll() is None: os.killpg(process.pid,signal.SIGKILL);process.wait()
 os.close(master);os.close(slave)
 configuration.unlink(missing_ok=True);solution.unlink(missing_ok=True)
