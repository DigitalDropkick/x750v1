local m=dofile("files/usr/share/ddk-field-console/usb-topology.lua")
assert(m.affects("1-2","1-2") and m.affects("1-2","1-2.3"))
assert(not m.affects("1-2","1-20") and not m.affects("1-2.1","1-2.10"))
assert(m.port_target("1",2)=="1-2" and m.port_target("1-2",3)=="1-2.3")
local inventory={hubs={{value="1",ports=4},{value="1-2",ports=4}},protected={["1-2.3"]="Mounted storage",["1-4"]="EC25"}}
assert(not m.check_port(inventory,"1",2))
assert(not m.check_port(inventory,"1-2",3))
assert(m.check_port(inventory,"1-2",1)=="1-2.1")
assert(not m.check_port(inventory,"1-2",5))
assert(not m.check_port(inventory,"9",1))
local files={['/proc/mounts']='/dev/sda1 /overlay ext4 rw 0 0\n'}
for name,values in pairs({usb1={idVendor='1d6b',idProduct='0002',maxchild='4',busnum='1',devnum='1'},['1-2']={idVendor='1234',idProduct='5678',maxchild='0',busnum='1',devnum='12',serial='fixture'},['1-4']={idVendor='2c7c',idProduct='0125',maxchild='0',busnum='1',devnum='9'}}) do
	for key,value in pairs(values) do files['/sys/bus/usb/devices/'..name..'/'..key]=value..'\n' end
end
local native=m.inventory({readfile=function(path)local value=files[path];return value,value and #value or 2 end,realpath=function(path)if path=='/sys/class/block/sda1' then return '/sys/devices/usb1/1-2/block/sda/sda1' end end,dir=function()local names={'usb1','1-2','1-4'};local i=0;return function()i=i+1;return names[i]end end})
assert(native.hubs[1].ports==4 and native.devices[1].busnum==1 and native.devices[1].devnum==12)
assert(native.protected['1-2']=='Mounted storage at /overlay' and native.protected['1-4']=='EC25 cellular modem')
print("DDK_USB_TOPOLOGY_OK: ancestor ports, sibling isolation, mounted storage, modem, stale hubs")
