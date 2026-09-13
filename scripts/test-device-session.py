#!/usr/bin/env python3
"""Recovery tests with deterministic API failures, without changing live network state."""
import importlib.machinery,importlib.util,json,pathlib,tempfile,sys,unittest,io,ctypes
from unittest.mock import patch,MagicMock
sys.dont_write_bytecode=True
loader=importlib.machinery.SourceFileLoader('session',str(pathlib.Path(__file__).resolve().parents[1]/'files/usr/libexec/ddk-device-session'))
spec=importlib.util.spec_from_loader(loader.name,loader);m=importlib.util.module_from_spec(spec);loader.exec_module(m)
class Recovery(unittest.TestCase):
 def test_can_first_configuration(self):
  commands=[]
  def run(argv):
   commands.append(argv)
   if '-json' in argv: return json.dumps([{'flags':[],'linkinfo':{'info_kind':'can','info_data':{}}}])
   return ''
  with patch.object(m,'run',run): m.configure_can('can0','500000','100')
  self.assertIn(['/sbin/ip','link','set','dev','can0','type','can','bitrate','500000','restart-ms','100'],commands)
 def test_can_failure_restores(self):
  commands=[]
  def run(argv):
   commands.append(argv)
   if '-json' in argv: return json.dumps([{'flags':['UP'],'linkinfo':{'info_kind':'can','info_data':{'bittiming':{'bitrate':125000},'restart_ms':50}}}])
   if '500000' in argv: raise RuntimeError('simulated driver failure')
   return ''
  with patch.object(m,'run',run),patch.object(m.signal,'signal'):
   with self.assertRaises(RuntimeError): m.configure_can('can0','500000','100')
  self.assertIn(['/sbin/ip','link','set','dev','can0','type','can','bitrate','125000','restart-ms','50'],commands)
  self.assertEqual(commands[-1][-1],'up')
 def cellular(self,confirm):
  calls=[]
  with tempfile.TemporaryDirectory() as directory:
   if confirm: pathlib.Path(directory,'confirm-network').write_text('confirm')
   def ubus(obj,method,payload):
    calls.append((obj,method,payload))
    if (obj,method)==('uci','get'): return {'values':{'proto':'qmi','device':'/dev/cdc-wdm0'}}
    if (obj,method)==('session','create'): return {'ubus_rpc_session':'fixture'}
    return {}
   with patch.object(m,'ubus',ubus),patch.object(m.signal,'signal'),patch.object(m.time,'monotonic',side_effect=[0,0 if confirm else 1000]):
    if confirm: m.cellular_session('modem','test.example','ipv4v6','none','@EMPTY@','-',directory,'60')
    else:
     with self.assertRaises(RuntimeError): m.cellular_session('modem','test.example','ipv4v6','none','@EMPTY@','-',directory,'60')
   methods=[method for obj,method,_ in calls]
   self.assertTrue(calls[4][2]['rollback']);self.assertEqual(methods[-1],'destroy')
   self.assertIn('confirm' if confirm else 'rollback',methods)
   self.assertNotIn('rollback' if confirm else 'confirm',methods)
   self.assertFalse(pathlib.Path(directory,'network-confirm-ready').exists())
   self.assertNotIn('password',calls[3][2]['values'])
 def test_cellular_confirm(self): self.cellular(True)
 def test_cellular_timeout(self): self.cellular(False)
 def test_cellular_exact_target(self):
  with patch.object(m,'ubus',return_value={'values':{'proto':'dhcp','device':'eth0'}}):
   with self.assertRaises(RuntimeError): m.cellular_session('wan','test.example','ipv4','none','@EMPTY@','-','/tmp','60')
class Selection(unittest.TestCase):
 def bluetooth(self,selected):
  adapter='00:11:22:33:44:55';address='00:00:00:00:00:01';sent=[]
  replies=[b'[bluetooth]# ',b'[bluetooth]# ',('Controller '+selected+' (public)\r\n[bluetooth]# ').encode(),b'Connection successful\r\n']
  process=MagicMock();process.poll.return_value=None
  with patch.object(m.select,'select',return_value=([17],[],[])),patch.object(m.os,'read',side_effect=replies),patch.object(m.os,'write',side_effect=lambda fd,value:sent.append(value)),patch.object(m.sys,'stdout',io.StringIO()):
   if selected==adapter: m.bluetooth_dialogue(17,process,adapter,address,'connect','')
   else:
    with self.assertRaisesRegex(RuntimeError,'selection was not confirmed'): m.bluetooth_dialogue(17,process,adapter,address,'connect','')
  return sent
 def test_already_selected_bluetooth_controller(self):
  self.assertEqual(self.bluetooth('00:11:22:33:44:55'),[b'select 00:11:22:33:44:55\r',b'show\r',b'connect 00:00:00:00:00:01\r'])
 def test_wrong_bluetooth_controller_never_receives_operation(self):
  self.assertEqual(len(self.bluetooth('00:11:22:33:44:66')),2)
 def rtl(self,serials,requested):
  library=MagicMock();library.rtlsdr_get_device_count.return_value=len(serials)
  def strings(index,manufacturer,product,value): value.value=serials[index].encode();return 0
  library.rtlsdr_get_device_usb_strings.side_effect=strings
  output=io.StringIO()
  with patch.object(ctypes,'CDLL',return_value=library),patch.object(m.sys,'stdout',output): m.rtl_index(requested)
  return output.getvalue().strip()
 def test_rtl_numeric_serial_is_resolved_to_native_index(self): self.assertEqual(self.rtl(['00000002','00000001'],'00000001'),'1')
 def test_rtl_duplicate_serial_is_rejected(self):
  with self.assertRaisesRegex(RuntimeError,'one exact serial'): self.rtl(['00000001','00000001'],'00000001')
 def test_rtl_disconnected_serial_is_rejected(self):
  with self.assertRaisesRegex(RuntimeError,'one exact serial'): self.rtl(['00000002'],'00000001')
if __name__=='__main__': unittest.main()
