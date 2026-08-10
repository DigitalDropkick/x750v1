-- Digital Dropkick conservative USB identity classifier.
-- This module reads sysfs metadata only. It never opens a device node or runs
-- a device-management, recovery, debug, or programming utility.

local fs = require "nixio.fs"

local M = {}

local android_vendors = {
	["04e8"] = true, -- Samsung
	["05c6"] = true, -- Qualcomm reference / bootloader devices
	["0bb4"] = true, -- HTC
	["0e8d"] = true, -- MediaTek reference / bootloader devices
	["0fce"] = true, -- Sony Mobile
	["1004"] = true, -- LG
	["12d1"] = true, -- Huawei
	["18d1"] = true, -- Google
	["1949"] = true, -- Amazon
	["22b8"] = true, -- Motorola
	["22d9"] = true, -- OPPO / Realme
	["2717"] = true, -- Xiaomi
	["2a70"] = true, -- OnePlus
	["2ae5"] = true, -- Fairphone
	["2d95"] = true, -- vivo
	["2e04"] = true  -- HMD / Nokia
}

local programmer_ids = {
	["03eb:2103"] = "Atmel JTAGICE mkII",
	["03eb:2104"] = "Atmel AVRISP mkII",
	["03eb:2107"] = "Atmel AVR Dragon",
	["03eb:2141"] = "Atmel-ICE",
	["03eb:2145"] = "Atmel EDBG",
	["0483:3744"] = "ST-LINK/V1",
	["0483:3748"] = "ST-LINK/V2",
	["0483:374b"] = "ST-LINK/V2.1",
	["0483:374d"] = "ST-LINK/V3",
	["0483:374e"] = "ST-LINK/V3",
	["0483:3752"] = "ST-LINK/V3",
	["0483:3753"] = "ST-LINK/V3",
	["0483:3754"] = "ST-LINK/V3",
	["09fb:6001"] = "Altera USB-Blaster",
	["09fb:6002"] = "Altera USB-Blaster",
	["09fb:6003"] = "Altera USB-Blaster",
	["0d28:0204"] = "CMSIS-DAP / DAPLink",
	["15ba:0003"] = "Olimex ARM-USB-OCD",
	["15ba:0004"] = "Olimex ARM-USB-TINY",
	["15ba:002a"] = "Olimex ARM-USB-TINY-H",
	["15ba:002b"] = "Olimex ARM-USB-OCD-H",
	["1d50:6008"] = "Bus Pirate",
	["1d50:6018"] = "Black Magic Probe",
	["2e8a:000c"] = "Raspberry Pi Debug Probe"
}

local programmer_tokens = {
	{ "j-link", "SEGGER J-Link" },
	{ "jlink", "SEGGER J-Link" },
	{ "st-link", "ST-LINK" },
	{ "stlink", "ST-LINK" },
	{ "cmsis-dap", "CMSIS-DAP" },
	{ "cmsis dap", "CMSIS-DAP" },
	{ "daplink", "DAPLink" },
	{ "picoprobe", "PicoProbe" },
	{ "debug probe", "Debug Probe" },
	{ "black magic probe", "Black Magic Probe" },
	{ "usb-blaster", "USB-Blaster" },
	{ "usb blaster", "USB-Blaster" },
	{ "atmel-ice", "Atmel-ICE" },
	{ "atmel ice", "Atmel-ICE" },
	{ "avr dragon", "AVR Dragon" },
	{ "jtagice", "Atmel JTAGICE" },
	{ "avrisp", "Atmel AVRISP" },
	{ "pickit", "Microchip PICkit" },
	{ "bus pirate", "Bus Pirate" },
	{ "tigard", "Tigard" },
	{ "ft232h", "FT232H debug adapter" }
}

local android_tokens = {
	"android", "pixel", "nexus", "galaxy", "samsung mobile",
	"motorola phone", "oneplus", "fairphone", "android composite"
}

local apple_mobile_tokens = {
	"iphone", "ipad", "ipod", "apple mobile device", "dfu mode", "recovery mode"
}

local function trim(value)
	return (tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function safe_text(value, limit)
	value = tostring(value or "")
	value = value:gsub("[%z\1-\31\127]", " ")
	value = value:gsub("[^A-Za-z0-9 _%.%-%+%:/%(%),#%[%]]", "?")
	value = trim(value:gsub("%s+", " "))
	return value:sub(1, limit or 96)
end

local function read_text(path, limit)
	return safe_text(fs.readfile(path) or "", limit)
end

local function valid_hex4(value)
	return type(value) == "string" and value:match("^[0-9a-f][0-9a-f][0-9a-f][0-9a-f]$") ~= nil
end

local function has_token(value, tokens)
	for _, token in ipairs(tokens) do
		if value:find(token, 1, true) then return true end
	end
	return false
end

local function has_signature(device, wanted)
	for _, interface in ipairs(device.interfaces) do
		if interface.signature == wanted then return true end
	end
	return false
end

local function classify_android(device)
	local adb = has_signature(device, "ff:42:01")
	local fastboot = has_signature(device, "ff:42:03")
	local mtp = has_signature(device, "06:01:01")
	local descriptor_match = has_token(device.descriptor, android_tokens)
	if not android_vendors[device.vendor_id] or not (adb or fastboot or mtp or descriptor_match) then
		return nil
	end
	if fastboot then return "FASTBOOT USB INTERFACE" end
	if adb then return "ADB USB INTERFACE" end
	if mtp then return "MTP MOBILE INTERFACE" end
	return "ANDROID MOBILE DESCRIPTOR"
end

local function classify_apple(device)
	if device.vendor_id ~= "05ac" or not has_token(device.descriptor, apple_mobile_tokens) then
		return nil
	end
	if device.descriptor:find("dfu", 1, true) then return "DFU MODE DESCRIPTOR" end
	if device.descriptor:find("recovery", 1, true) then return "RECOVERY MODE DESCRIPTOR" end
	return "APPLE MOBILE DESCRIPTOR"
end

local function classify_programmer(device)
	if has_signature(device, "fe:01:01") then return "USB DFU RUNTIME INTERFACE" end
	if has_signature(device, "fe:01:02") then return "USB DFU MODE INTERFACE" end
	if device.vendor_id == "1366" then return "SEGGER J-Link" end
	local exact = programmer_ids[device.usb_id]
	if exact then return exact end
	for _, entry in ipairs(programmer_tokens) do
		if device.descriptor:find(entry[1], 1, true) then return entry[2] end
	end
	return nil
end

local function scan_names(root)
	local names = {}
	local iterator = fs.dir(root)
	if iterator then
		for name in iterator do
			if name:match("^[A-Za-z0-9_.:%-]+$") then names[#names + 1] = name end
		end
	end
	table.sort(names)
	return names
end

function M.scan(root)
	root = root or "/sys/bus/usb/devices"
	if type(root) ~= "string" or root:sub(1, 1) ~= "/" or #root > 256 or root:find("..", 1, true) then
		return { android = {}, apple_mobile = {}, programmer = {}, inspected_count = 0 }
	end

	local result = { android = {}, apple_mobile = {}, programmer = {}, inspected_count = 0 }
	local names = scan_names(root)
	for _, name in ipairs(names) do
		if result.inspected_count >= 64 then break end
		local base = root .. "/" .. name
		local vendor_id = trim(fs.readfile(base .. "/idVendor")):lower()
		local product_id = trim(fs.readfile(base .. "/idProduct")):lower()
		if valid_hex4(vendor_id) and valid_hex4(product_id) then
			result.inspected_count = result.inspected_count + 1
			local device = {
				topology = safe_text(name, 32),
				vendor_id = vendor_id,
				product_id = product_id,
				usb_id = vendor_id .. ":" .. product_id,
				manufacturer = read_text(base .. "/manufacturer", 96),
				product = read_text(base .. "/product", 96),
				serial = read_text(base .. "/serial", 128),
				busnum = read_text(base .. "/busnum", 4),
				devnum = read_text(base .. "/devnum", 4),
				speed = read_text(base .. "/speed", 16),
				interfaces = {}
			}
			device.descriptor = (device.manufacturer .. " " .. device.product):lower()

			for _, interface_name in ipairs(names) do
				if #device.interfaces >= 16 then break end
				if interface_name:sub(1, #name + 1) == name .. ":" then
					local interface_base = root .. "/" .. interface_name
					local class = trim(fs.readfile(interface_base .. "/bInterfaceClass")):lower()
					local subclass = trim(fs.readfile(interface_base .. "/bInterfaceSubClass")):lower()
					local protocol = trim(fs.readfile(interface_base .. "/bInterfaceProtocol")):lower()
					local driver_link = fs.readlink(interface_base .. "/driver") or ""
					local driver = safe_text(driver_link:match("([^/]+)$") or "", 48)
					if class:match("^[0-9a-f][0-9a-f]$") and subclass:match("^[0-9a-f][0-9a-f]$") and
					   protocol:match("^[0-9a-f][0-9a-f]$") then
						device.interfaces[#device.interfaces + 1] = {
							number = read_text(interface_base .. "/bInterfaceNumber", 4),
							signature = class .. ":" .. subclass .. ":" .. protocol,
							driver = driver
						}
					end
				end
			end

			local android_match = classify_android(device)
			if android_match then
				device.identity = android_match
				result.android[#result.android + 1] = device
			end
			local apple_match = classify_apple(device)
			if apple_match then
				local apple_device = {}
				for key, value in pairs(device) do apple_device[key] = value end
				apple_device.identity = apple_match
				result.apple_mobile[#result.apple_mobile + 1] = apple_device
			end
			local programmer_match = classify_programmer(device)
			if programmer_match then
				local programmer_device = {}
				for key, value in pairs(device) do programmer_device[key] = value end
				programmer_device.identity = programmer_match
				result.programmer[#result.programmer + 1] = programmer_device
			end
		end
	end
	return result
end

return M
