-- Current USB topology, shared by preparation and execution. No device is opened.
local M={}
local function trim(value) return (tostring(value or ""):gsub("^%s+",""):gsub("%s+$","")) end
local function physical(path)
	local result
	for name in tostring(path or ""):gmatch("[^/]+") do if name:match("^%d+%-%d+[%.%d]*$") then result=name end end
	return result
end
function M.affects(target,device)
	return target==device or device:sub(1,#target+1)==target.."."
end
function M.port_target(hub,port)
	if type(hub)~="string" or not hub:match("^%d+[%d.-]*$") or type(port)~="number" or port~=math.floor(port) or port<1 or port>255 then return nil end
	return hub..(hub:find("-",1,true) and "." or "-")..port
end
function M.inventory(fs)
	local result={hubs={},devices={},protected={}}
	local function protect(path,reason)
		local node=physical(path);if node then result.protected[node]=reason end
	end
	for line in (fs.readfile("/proc/mounts") or ""):gmatch("[^\n]+") do
		local device,mountpoint=line:match("^/dev/([^%s]+)%s+(%S+)")
		if device then protect(fs.realpath("/sys/class/block/"..device),"Mounted storage at "..mountpoint) end
	end
	for line in (fs.readfile("/proc/swaps") or ""):gmatch("[^\n]+") do
		local device=line:match("^/dev/([^%s]+)");if device then protect(fs.realpath("/sys/class/block/"..device),"Active swap") end
	end
	for line in (fs.readfile("/proc/net/route") or ""):gmatch("[^\n]+") do
		local interface,destination=line:match("^(%S+)%s+(%x+)")
		if destination=="00000000" and interface:match("^[A-Za-z0-9_.-]+$") then protect(fs.realpath("/sys/class/net/"..interface.."/device"),"Default network uplink") end
	end
	for name in (fs.dir("/sys/bus/usb/devices") or function() end) do
		if name:match("^%d+%-%d+[%.%d]*$") or name:match("^usb%d+$") then
			local path="/sys/bus/usb/devices/"..name
			local vendor=trim(fs.readfile(path.."/idVendor"));local product=trim(fs.readfile(path.."/idProduct"))
			local description=trim(fs.readfile(path.."/product")):gsub("[%z\1-\31]"," "):sub(1,80)
			if vendor=="2c7c" and product=="0125" then result.protected[name]="EC25 cellular modem" end
			local ports=tonumber(trim(fs.readfile(path.."/maxchild"))) or 0
			if ports>0 then
				result.hubs[#result.hubs+1]={value=name:gsub("^usb",""),node=name,ports=ports,label=name.." / "..ports.." ports / "..description}
			else result.devices[#result.devices+1]={value=name,label=name.." / "..vendor..":"..product.." / "..description,usb_id=vendor..":"..product,serial=trim(fs.readfile(path.."/serial")),busnum=tonumber(trim(fs.readfile(path.."/busnum"))),devnum=tonumber(trim(fs.readfile(path.."/devnum")))} end
		end
	end
	table.sort(result.hubs,function(a,b)return a.value<b.value end);table.sort(result.devices,function(a,b)return a.value<b.value end)
	return result
end
function M.check_port(inventory,hub,port)
	local found
	for _,candidate in ipairs(inventory.hubs) do if candidate.value==hub then found=candidate end end
	if not found or port>found.ports then return nil,"Selected hub or port is no longer present" end
	local target=M.port_target(hub,port);if not target then return nil,"Invalid USB port" end
	for device,reason in pairs(inventory.protected) do if M.affects(target,device) then return nil,reason end end
	return target
end
return M
