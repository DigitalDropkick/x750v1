local m = dofile("files/usr/share/ddk-field-console/operator-v3.lua")
local validators = dofile("files/usr/share/ddk-field-console/operator-actions.lua")
local c = {clone_jobs={{value="new"}},saved_cases={{value="job-1-2",files={{name="capture.pcap",size=64}},archive_size=1048576}},usb_policy=dofile("files/usr/share/ddk-field-console/usb-topology.lua"),usb_hubs={},usb_inventory={hubs={},protected={}},usbip_ports={},validators=validators, processes={{value="100",name="test",exe="/bin/sleep",starttime="123"}}, service_addresses={{value="127.0.0.1"}},interfaces={{name="lo"}}, bluetooth_all={"hci0"}, can_devices={"vcan0"},
	ftdi_devices={{value="1-9",busnum=1,devnum=9,usb_id="0403:6001",serial="TEST"}},flashrom_devices={{value="1-10",busnum=1,devnum=10,usb_id="1a86:5512",serial=""}},wireless_phys={{value="phy0",active=true}},modem_at_node="/dev/ttyUSB2",serial_devices={"/dev/ttyUSB9"},camera_devices={"/dev/video0"},rtl_devices={":TEST"},gps_devices={"/dev/ttyUSB9"},
	storage_devices={{value="/dev/sdb",node="/dev/sdb",disk="sdb",size=2147483648,mounted=false},{value="/dev/sdc",node="/dev/sdc",disk="sdc",size=4294967296,mounted=false}},recovery_jobs={{value="new",label="New"}},
	cellular_interface="modem", uploads={{id="upload-1-2-3",kind="forensics",original_name="evidence.bin",size=8192}}}
local overrides = { ["storage.clone"]={target="/dev/sdc"}, ["cellular.profile"]={apn="test.example"}, ["auth.otp"]={key="3132333435363738393031323334353637383930",base32=false,mode="hotp",counter=0},
	["firmware.flashrom"]={device="1-10"},["auth.stoken"]={token="synthetic-fixture-not-a-real-token"},["forensics.hex"]={input="upload-1-2-3"},["android.operator"]={transport="tcp"} }
local count = 0
for id, spec in pairs(m.actions) do
	local schema = assert(m.describe(id,c)); assert(schema.action_id==id)
	local opts=overrides[id] or {}
	local plan,err=m.prepare(id,opts,c); assert(plan,id..": "..tostring(err))
	assert(plan.worker=="v3_native" and plan.action_id==id and plan.wall_timeout>=0)
	local match=false;for _,exe in ipairs(spec.executables) do if plan.argv[1]==exe then match=true end end;assert(match)
	local bad={};for k,v in pairs(opts) do bad[k]=v end;bad.executable="/bin/sh";assert(not m.prepare(id,bad,c))
	for _,f in ipairs(schema.fields) do
		local invalid={};for k,v in pairs(opts) do invalid[k]=v end
		if f.type=="integer" then invalid[f.name]=f.max+1
		elseif f.type=="boolean" then invalid[f.name]="true"
		elseif f.type=="enum" then invalid[f.name]="__missing__"
		elseif f.type=="target_list" or f.type=="upload_list" or f.type=="integer_list" then invalid[f.name]="wrong type"
		else invalid[f.name]="invalid\ntext" end
		assert(not m.prepare(id,invalid,c),id.." accepted invalid "..f.name)
	end
	count=count+1
end
local dns=assert(m.prepare("network.dns",{server="2001:db8::1",name="_ldap._tcp.example.com",record="SRV"},c))
assert(dns.argv[2]=="@2001:db8::1")
assert(not m.prepare("network.dns",{server="-f/etc/passwd"},c))
assert(not m.prepare("network.arp_scan",{localnet=false,targets={"example.com"}},c))
assert(m.prepare("network.arp_scan",{localnet=false,targets={"192.0.2.0/24"}},c))
local mqtt=assert(m.prepare("automation.mqtt_subscribe",{password="sample-test-password",topics={"shop/+/state","shop/#"}},c))
assert(not mqtt.argv_preview:find("sample-test-password",1,true) and mqtt.options.password=="[REDACTED]")
assert(#mqtt.private_inputs==1 and mqtt.window)
assert(m.prepare("automation.mqtt_subscribe",{remove_retained=true},c).confirmation.required)
local otp=assert(m.prepare("auth.otp",overrides["auth.otp"],c))
assert(otp.sensitive and #otp.artifacts==0 and otp.stdin=="@PRIVATE@/otp-key")
local b=assert(m.prepare("bluetooth.services",{operation="write",value="0102"},c))
assert(b.confirmation.required and table.concat(b.argv," "):find("--char-write-req",1,true))
assert(not m.prepare("can.transmit",{frame="123#001"},c))
assert(not m.prepare("can.capture",{interface="eth0"},c))
assert(not m.prepare("cellular.control",{operation="reconnect"},{validators=validators}))
print("DDK_V3_TEST_OK: "..count.." workflows plus field, argv, secret, and target validation")
local apk_context={};for k,v in pairs(c) do apk_context[k]=v end
apk_context.uploads={{id="upload-1-2-4",kind="android_package",original_name="base.apk"},{id="upload-1-2-5",kind="android_package",original_name="split_config.apk"}}
apk_context.apk_uploads={{value="upload-1-2-4"},{value="upload-1-2-5"}}
local apks=assert(m.prepare("android.operator",{transport="tcp",host="2001:db8::42",operation="install_multiple",packages={"upload-1-2-4","upload-1-2-5"}},apk_context))
assert(apks.adb_connect=="[2001:db8::42]:5555" and apks.apk_inputs and #apks.input_uploads==2 and apks.confirmation.required)
local pulling=assert(m.prepare("android.operator",{transport="tcp",operation="pull_directory",remote_path="/sdcard/Download/Field notes"},c))
assert(pulling.wall_timeout==0 and pulling.archive_directory and #pulling.workspaces==1)
assert(not m.prepare("android.operator",{transport="tcp",remote_path="/sdcard/';reboot;#"},c))
assert(not m.prepare("wireless.monitor",{channel=6},c))
assert(m.prepare("wireless.monitor",{channel=0},c))
assert(not m.prepare("can.transmit",{frame="FFF#01"},c))
assert(not m.prepare("can.transmit",{frame="FFFFFFFF#01"},c))
local ring=assert(m.prepare("capture.ring",{segments=16,segment_mb=64},c))
assert(ring.wall_timeout==0 and #ring.artifacts==18 and ring.artifacts[2].name=="capture.pcap00" and ring.artifacts[17].name=="capture.pcap15")
local serial=assert(m.prepare("serial.transfer",{direction="send_receive",input="upload-1-2-3"},c))
assert(serial.stdin_upload=="upload-1-2-3" and serial.stdout_artifact=="serial-transfer.bin" and serial.confirmation.required)

local clone=assert(m.prepare("storage.clone",{target="/dev/sdc"},c))
assert(clone.options.length==2147483648 and clone.confirmation.required and clone.clone_target.disk=="sdc")
assert(not m.prepare("storage.clone",{target="/dev/sdb"},c))
assert(not m.prepare("storage.clone",{target="/dev/sdc",target_offset=4294967296},c))
