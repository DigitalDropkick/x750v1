local previous=package.loaded["nixio.fs"]
local files={}
local root="/sys/fixture"
package.loaded["nixio.fs"]={
	readfile=function(path)return files[path]end,
	readlink=function()return nil end,
	dir=function()local names={"1-9","1-9:1.0"};local i=0;return function()i=i+1;return names[i]end end
}
local usb=dofile("files/usr/share/ddk-field-console/usb-identity.lua")
files[root.."/1-9/idVendor"]="f00d";files[root.."/1-9/idProduct"]="9876"
files[root.."/1-9:1.0/bInterfaceClass"]="ff";files[root.."/1-9:1.0/bInterfaceSubClass"]="42"
files[root.."/1-9:1.0/bInterfaceProtocol"]="01"
local result=usb.scan(root)
assert(#result.android==1 and result.android[1].identity=="ADB USB INTERFACE")
files[root.."/1-9:1.0/bInterfaceProtocol"]="03"
assert(usb.scan(root).android[1].identity=="FASTBOOT USB INTERFACE")
files[root.."/1-9:1.0/bInterfaceClass"]="06";files[root.."/1-9:1.0/bInterfaceSubClass"]="01"
files[root.."/1-9:1.0/bInterfaceProtocol"]="01"
assert(#usb.scan(root).android==0,"An unknown MTP camera must not be silently classified as Android")
assert(usb.scan("/sys/../etc").inspected_count==0)
package.loaded["nixio.fs"]=previous
print("DDK_USB_IDENTITY_OK: unfamiliar ADB/fastboot vendors, MTP distinction, path rejection")
