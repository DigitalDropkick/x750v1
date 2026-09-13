local p = assert(dofile('files/usr/share/ddk-field-console/operator-phase4.lua'))
local u1='upload-1700000000-100-1'; local u2='upload-1700000000-100-2'; local cap='upload-1700000000-100-3'
local context = {
	interfaces={{value='lo',label='loopback'}}, wireless_interfaces={{value='wlan0',label='synthetic'}},
	usb_devices={{value='001:002',label='synthetic USB',usb_id='1234:5678'}},
	rtl_devices={{value=':DDKTEST',label='synthetic RTL',serial='DDKTEST',topology='9-9',usb_id='0bda:2838'}},
	bluetooth_devices={{value='hci0',label='synthetic HCI'}}, relay_devices={{value='RELAY123',label='synthetic relay',relays=8}},
	serial_devices={{value='/dev/ttyACM9',label='synthetic serial',topology='9-8',usb_id='1234:5678'}},
	gps_devices={{value='/dev/ttyACM8',label='synthetic GNSS',topology='9-7',usb_id='1546:01a7'}},
	camera_devices={{value='/dev/video9',label='synthetic camera',usb_id='046d:0825'}},
	local_addresses={{value='127.0.0.1',address='127.0.0.1',label='loopback',family='inet'},{value='::1',address='::1',label='loopback6',family='inet6'}},
	uploads={{id=u1,kind='forensics_input',original_name='sample.bin',size=4,sha256=string.rep('a',64)},{id=u2,kind='forensics_input',original_name='rules.yar',size=4,sha256=string.rep('b',64)},{id=cap,kind='capture_input',original_name='replay.pcap',size=64,sha256=string.rep('c',64)}}
}
local cases = {
	{'monitoring.snapshot',{mode='history',interface='lo'}}, {'wireless.survey',{interface='wlan0'}}, {'usb.inventory',{}},
	{'forensics.inspect_file',{input=u1,operation='yara',rules=u2}}, {'capture.replay',{input=cap,interface='lo'}},
	{'adsb.receive',{device=':DDKTEST'}}, {'radio.ais',{device=':DDKTEST'}}, {'bluetooth.scan',{controller='hci0'}},
	{'automation.mqtt_publish',{host='127.0.0.1',topic='ddk/test',payload='private payload'}},
	{'automation.relay',{device='RELAY123',operation='on'}}, {'industrial.modbus_read',{transport='tcp',host='127.0.0.1'}},
	{'auth.inventory',{mode='yubikey'}}, {'auth.program',{operation='configure_hmac',secret=string.rep('a',40),commit=true}},
	{'camera.stream',{device='/dev/video9',bind_address='127.0.0.1',password='StrongPass1234'}},
	{'gps.ntrip',{device='/dev/ttyACM8',server='caster.example.net',mountpoint='MOUNT',username='tech',password='private'}}
}
for _, case in ipairs(cases) do
	local schema=assert(p.describe(case[1],context)); assert(schema.action_id==case[1])
	local plan,err=p.prepare(case[1],case[2],context); assert(plan,case[1]..': '..tostring(err))
	assert(plan.action_id==case[1] and plan.argv[1]:match('^/'))
end
local mqtt=assert(p.prepare('automation.mqtt_publish',{host='127.0.0.1',topic='ddk/test',payload='private payload',username='tech',password='secret'},context))
assert(not mqtt.argv_preview:find('secret',1,true) and mqtt.options.password=='[REDACTED]' and #mqtt.private_inputs==2)
local camera=assert(p.describe('camera.stream',context)); for _, field in ipairs(camera.fields) do if field.name=='bind_address' then assert(#field.options==1 and field.options[1].value=='127.0.0.1') end end
assert(not p.prepare('automation.mqtt_publish',{host='127.0.0.1',topic='ddk/test',payload='x',shell='id'},context))
assert(not p.prepare('camera.stream',{device='/dev/video9',bind_address='::1',password='StrongPass1234'},context))
assert(not p.prepare('capture.replay',{input=cap,interface='eth9'},context))
assert(not p.prepare('gps.ntrip',{device='/dev/ttyUSB0',server='caster.example',mountpoint='M',username='u',password='p'},context))
print("DDK_OPERATOR_PHASE4_OK")
