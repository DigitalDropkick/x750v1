-- Digital Dropkick Field Console Apple Operator Mode schemas and argv builders.
--
-- Browser values are validated here and become literal argv elements only.
-- This module never executes a command and never accepts an executable path.

local M = {}

local function trim(value)
	return (tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function copy_array(value)
	local result = {}
	for index, item in ipairs(value or {}) do result[index] = item end
	return result
end

local function field(name, label, kind, default, extra)
	local result = { name = name, label = label, type = kind, default = default }
	for key, value in pairs(extra or {}) do result[key] = value end
	return result
end

local function defaults(schema, options, label)
	if type(options) ~= "table" then return nil, "Options must be a JSON object" end
	local result, allowed = {}, {}
	for _, item in ipairs(schema.fields or {}) do
		allowed[item.name] = true
		result[item.name] = item.default
	end
	for key, value in pairs(options) do
		if type(key) ~= "string" or not allowed[key] then return nil, "Unknown " .. label .. " option: " .. tostring(key) end
		result[key] = value
	end
	return result
end

local function enum(value, choices, label)
	if type(value) ~= "string" then return nil, label .. " must be a string" end
	for _, choice in ipairs(choices) do if value == choice then return value end end
	return nil, label .. " is not an allowed value"
end

local function integer(value, minimum, maximum, label)
	if type(value) ~= "number" or value ~= math.floor(value) or value < minimum or value > maximum then
		return nil, string.format("%s must be an integer from %d to %d", label, minimum, maximum)
	end
	return value
end

local function number(value, minimum, maximum, label)
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge or value < minimum or value > maximum then
		return nil, string.format("%s must be a number from %s to %s", label, tostring(minimum), tostring(maximum))
	end
	return value
end

local function boolean(value, label)
	if type(value) ~= "boolean" then return nil, label .. " must be true or false" end
	return value
end

local function text(value, label, maximum, pattern, required)
	if type(value) ~= "string" then return nil, label .. " must be a string" end
	value = trim(value)
	if (required and value == "") or #value > maximum or value:find("[%z\1-\31\127]") or (value ~= "" and pattern and not value:match(pattern)) then
		return nil, label .. " is empty, too long, or contains unsupported characters"
	end
	return value
end

local function dense_text_list(value, label, maximum_items, maximum_length, pattern)
	if type(value) ~= "table" then return nil, label .. " must be a JSON array" end
	local result, seen = {}, {}
	for index, item in ipairs(value) do
		if index > maximum_items then return nil, label .. " exceeds its item limit" end
		local normalized, err = text(item, label .. " item", maximum_length, pattern, true)
		if not normalized then return nil, err end
		if seen[normalized] then return nil, label .. " contains a duplicate" end
		seen[normalized], result[#result + 1] = true, normalized
	end
	for key in pairs(value) do
		if type(key) ~= "number" or key < 1 or key > #result or key ~= math.floor(key) then return nil, label .. " must be a dense JSON array" end
	end
	return result
end

local function choice_map(items)
	local choices, records = {}, {}
	for _, item in ipairs(items or {}) do
		if type(item) == "table" and type(item.value) == "string" and type(item.label) == "string" and not records[item.value] then
			choices[#choices + 1] = { value = item.value, label = item.label }
			records[item.value] = item
		end
	end
	return choices, records
end

local function upload_choices(context, kind, include_empty)
	local choices, records = {}, {}
	if include_empty then choices[#choices + 1] = { value = "", label = "None" } end
	for _, upload in ipairs(context.uploads or {}) do
		if type(upload) == "table" and upload.kind == kind and type(upload.id) == "string" then
			choices[#choices + 1] = { value = upload.id, label = upload.original_name .. " / " .. tostring(upload.size) .. " bytes / " .. upload.id }
			records[upload.id] = upload
		end
	end
	return choices, records
end

local function add(argv, value) argv[#argv + 1] = tostring(value) end

local function preview_arg(value)
	value = tostring(value)
	if value:match("^[A-Za-z0-9_./:@%%+=,-]+$") then return value end
	return "'" .. value:gsub("'", "'\\''") .. "'"
end

local function preview(argv)
	local result = {}
	for _, item in ipairs(argv) do
		item = item:gsub("^@UPLOAD@/", "[SEALED_DDK_UPLOAD]/"):gsub("^@ARTIFACT@/", "[DDK_EXTROOT_ARTIFACT]/"):gsub("^@WORK@/", "[DDK_EXTROOT_WORKSPACE]/")
		result[#result + 1] = preview_arg(item)
	end
	return table.concat(result, " ")
end

local mobile_diagnostic_operations = {
	"info", "name", "date", "pair_validate", "pair_hostid", "pair_systembuid",
	"diagnostics", "mobilegestalt", "ioreg", "ioregentry"
}
local info_domains = {
	"", "com.apple.disk_usage", "com.apple.disk_usage.factory", "com.apple.mobile.battery",
	"com.apple.iqagent", "com.apple.purplebuddy", "com.apple.PurpleBuddy", "com.apple.mobile.chaperone",
	"com.apple.mobile.third_party_termination", "com.apple.mobile.lockdownd", "com.apple.mobile.lockdown_cache",
	"com.apple.xcode.developerdomain", "com.apple.international", "com.apple.mobile.data_sync",
	"com.apple.mobile.tethered_sync", "com.apple.mobile.mobile_application_usage", "com.apple.mobile.backup",
	"com.apple.mobile.nikita", "com.apple.mobile.restriction", "com.apple.mobile.user_preferences",
	"com.apple.mobile.sync_data_class", "com.apple.mobile.software_behavior",
	"com.apple.mobile.iTunes.SQLMusicLibraryPostProcessCommands", "com.apple.mobile.iTunes.accessories",
	"com.apple.mobile.internal", "com.apple.mobile.wireless_lockdown", "com.apple.fairplay", "com.apple.iTunes",
	"com.apple.mobile.iTunes.store", "com.apple.mobile.iTunes"
}
local diagnostic_types = { "All", "WiFi", "GasGauge", "NAND" }
local ioreg_planes = { "", "IODeviceTree", "IOPower", "IOService" }

local function mobile_diagnostics_schema(context)
	local devices = choice_map(context.apple_normal_devices)
	return {
		action_id = "apple.mobile_diagnostics", label = "Apple Mobile Diagnostics", class = "ACTION",
		native = { executable = "/usr/bin/ideviceinfo", executables = {
			"/usr/bin/ideviceinfo", "/usr/bin/idevicename", "/usr/bin/idevicedate", "/usr/bin/idevicepair", "/usr/bin/idevicediagnostics"
		}, version = "libimobiledevice 1.3.0", helper = "/usr/sbin/usbmuxd 1.1.1" },
		fields = {
			field("device", "Normal-mode Apple device", "enum", devices[1] and devices[1].value or "", { options = devices, help = "Only sysfs-reviewed normal-mode Apple identities are offered; the worker requires an exact usbmuxd UDID match again." }),
			field("operation", "Native operation", "enum", "info", { options = copy_array(mobile_diagnostic_operations) }),
			field("wall_timeout", "Wall timeout (seconds)", "integer", 60, { min = 10, max = 900 }),
			field("info_domain", "ideviceinfo domain", "enum", "", { options = copy_array(info_domains), show_when = { field = "operation", equals = "info" } }),
			field("info_key", "ideviceinfo key (empty = all)", "text", "", { show_when = { field = "operation", equals = "info" }, placeholder = "ProductType" }),
			field("info_simple", "Avoid automatic pairing", "boolean", false, { show_when = { field = "operation", equals = "info" } }),
			field("info_xml", "XML plist output", "boolean", false, { show_when = { field = "operation", equals = "info" } }),
			field("diagnostic_type", "Diagnostics type", "enum", "All", { options = copy_array(diagnostic_types), show_when = { field = "operation", equals = "diagnostics" } }),
			field("gestalt_keys", "MobileGestalt keys", "target_list", {}, { rows = 4, show_when = { field = "operation", equals = "mobilegestalt" }, placeholder = "ProductType\nProductVersion" }),
			field("ioreg_plane", "IORegistry plane", "enum", "", { options = copy_array(ioreg_planes), show_when = { field = "operation", equals = "ioreg" } }),
			field("ioreg_key", "IORegistry entry key (empty = default)", "text", "", { show_when = { field = "operation", equals = "ioregentry" }, placeholder = "AppleARMPMUCharger" })
		}
	}
end

local function build_mobile_diagnostics(options, context)
	local schema = mobile_diagnostics_schema(context)
	local normalized, err = defaults(schema, options, "Apple diagnostics")
	if not normalized then return nil, err end
	local _, devices = choice_map(context.apple_normal_devices)
	if type(normalized.device) ~= "string" or not devices[normalized.device] then return nil, "Selected normal-mode Apple device is not in the reviewed live inventory" end
	normalized.operation, err = enum(normalized.operation, mobile_diagnostic_operations, "Apple diagnostics operation"); if not normalized.operation then return nil, err end
	normalized.wall_timeout, err = integer(normalized.wall_timeout, 10, 900, "Wall timeout"); if not normalized.wall_timeout then return nil, err end
	normalized.info_domain, err = enum(normalized.info_domain, info_domains, "ideviceinfo domain"); if normalized.info_domain == nil then return nil, err end
	normalized.info_key, err = text(normalized.info_key, "ideviceinfo key", 128, "^[A-Za-z0-9_.-]+$", false); if normalized.info_key == nil then return nil, err end
	normalized.info_simple, err = boolean(normalized.info_simple, "Avoid automatic pairing"); if normalized.info_simple == nil then return nil, err end
	normalized.info_xml, err = boolean(normalized.info_xml, "XML output"); if normalized.info_xml == nil then return nil, err end
	normalized.diagnostic_type, err = enum(normalized.diagnostic_type, diagnostic_types, "Diagnostics type"); if not normalized.diagnostic_type then return nil, err end
	normalized.gestalt_keys, err = dense_text_list(normalized.gestalt_keys, "MobileGestalt keys", 32, 128, "^[A-Za-z0-9_.-]+$"); if not normalized.gestalt_keys then return nil, err end
	normalized.ioreg_plane, err = enum(normalized.ioreg_plane, ioreg_planes, "IORegistry plane"); if normalized.ioreg_plane == nil then return nil, err end
	normalized.ioreg_key, err = text(normalized.ioreg_key, "IORegistry key", 128, "^[A-Za-z0-9_.-]+$", false); if normalized.ioreg_key == nil then return nil, err end
	if normalized.operation ~= "info" and (normalized.info_domain ~= "" or normalized.info_key ~= "" or normalized.info_simple or normalized.info_xml) then return nil, "ideviceinfo fields are accepted only for info" end
	if normalized.operation ~= "diagnostics" and normalized.diagnostic_type ~= "All" then return nil, "Diagnostics type is accepted only for diagnostics" end
	if normalized.operation == "mobilegestalt" and #normalized.gestalt_keys == 0 then return nil, "MobileGestalt requires at least one key" end
	if normalized.operation ~= "mobilegestalt" and #normalized.gestalt_keys > 0 then return nil, "MobileGestalt keys are accepted only for mobilegestalt" end
	if normalized.operation ~= "ioreg" and normalized.ioreg_plane ~= "" then return nil, "IORegistry plane is accepted only for ioreg" end
	if normalized.operation ~= "ioregentry" and normalized.ioreg_key ~= "" then return nil, "IORegistry key is accepted only for ioregentry" end
	local op, argv = normalized.operation, {}
	if op == "info" then
		argv = { "/usr/bin/ideviceinfo", "-u", normalized.device }
		if normalized.info_simple then add(argv, "-s") end
		if normalized.info_domain ~= "" then add(argv, "-q"); add(argv, normalized.info_domain) end
		if normalized.info_key ~= "" then add(argv, "-k"); add(argv, normalized.info_key) end
		if normalized.info_xml then add(argv, "-x") end
	elseif op == "name" then argv = { "/usr/bin/idevicename", "-u", normalized.device }
	elseif op == "date" then argv = { "/usr/bin/idevicedate", "-u", normalized.device }
	elseif op:match("^pair_") then argv = { "/usr/bin/idevicepair", "-u", normalized.device, op:gsub("^pair_", "") }
	else
		argv = { "/usr/bin/idevicediagnostics", "-u", normalized.device, op }
		if op == "diagnostics" then add(argv, normalized.diagnostic_type)
		elseif op == "mobilegestalt" then for _, key in ipairs(normalized.gestalt_keys) do add(argv, key) end
		elseif op == "ioreg" and normalized.ioreg_plane ~= "" then add(argv, normalized.ioreg_plane)
		elseif op == "ioregentry" and normalized.ioreg_key ~= "" then add(argv, normalized.ioreg_key) end
	end
	return { action_id = schema.action_id, worker = "apple_mobile", label = "Apple " .. op, class = "ACTION", resource = "apple_mobile", singleton = true,
		options = normalized, argv = argv, argv_preview = preview(argv), target_summary = normalized.device .. " / " .. op,
		wall_timeout = normalized.wall_timeout, artifacts = {}, confirmation = { required = false } }
end

local mobile_manage_operations = { "pair", "unpair", "set_name", "set_timestamp", "set_current_time", "shutdown", "restart", "sleep", "enter_recovery", "set_location", "reset_location" }

local function mobile_manage_schema(context)
	local devices = choice_map(context.apple_normal_devices)
	return {
		action_id = "apple.mobile_manage", label = "Apple Mobile Device Management", class = "DISRUPTIVE",
		native = { executable = "/usr/bin/idevicepair", executables = {
			"/usr/bin/idevicepair", "/usr/bin/idevicename", "/usr/bin/idevicedate", "/usr/bin/idevicediagnostics", "/usr/bin/ideviceenterrecovery", "/usr/bin/idevicesetlocation"
		}, version = "libimobiledevice 1.3.0", helper = "/usr/sbin/usbmuxd 1.1.1" },
		fields = {
			field("device", "Normal-mode Apple device", "enum", devices[1] and devices[1].value or "", { options = devices }),
			field("operation", "Device-changing operation", "enum", "pair", { options = copy_array(mobile_manage_operations) }),
			field("wall_timeout", "Wall timeout (seconds)", "integer", 120, { min = 10, max = 1800 }),
			field("device_name", "New device name", "text", "", { show_when = { field = "operation", equals = "set_name" } }),
			field("timestamp", "Unix timestamp", "integer", 0, { min = 0, max = 4102444800, show_when = { field = "operation", equals = "set_timestamp" } }),
			field("latitude", "Latitude", "number", 0, { min = -90, max = 90, step = 0.000001, show_when = { field = "operation", equals = "set_location" } }),
			field("longitude", "Longitude", "number", 0, { min = -180, max = 180, step = 0.000001, show_when = { field = "operation", equals = "set_location" } })
		}
	}
end

local function build_mobile_manage(options, context)
	local schema = mobile_manage_schema(context)
	local normalized, err = defaults(schema, options, "Apple management")
	if not normalized then return nil, err end
	local _, devices = choice_map(context.apple_normal_devices)
	if type(normalized.device) ~= "string" or not devices[normalized.device] then return nil, "Selected normal-mode Apple device is not in the reviewed live inventory" end
	normalized.operation, err = enum(normalized.operation, mobile_manage_operations, "Apple management operation"); if not normalized.operation then return nil, err end
	normalized.wall_timeout, err = integer(normalized.wall_timeout, 10, 1800, "Wall timeout"); if not normalized.wall_timeout then return nil, err end
	normalized.device_name, err = text(normalized.device_name, "Device name", 255, nil, normalized.operation == "set_name"); if normalized.device_name == nil then return nil, err end
	normalized.timestamp, err = integer(normalized.timestamp, 0, 4102444800, "Unix timestamp"); if normalized.timestamp == nil then return nil, err end
	normalized.latitude, err = number(normalized.latitude, -90, 90, "Latitude"); if normalized.latitude == nil then return nil, err end
	normalized.longitude, err = number(normalized.longitude, -180, 180, "Longitude"); if normalized.longitude == nil then return nil, err end
	if normalized.operation ~= "set_name" and normalized.device_name ~= "" then return nil, "Device name is accepted only for set_name" end
	if normalized.operation ~= "set_timestamp" and normalized.timestamp ~= 0 then return nil, "Timestamp is accepted only for set_timestamp" end
	if normalized.operation ~= "set_location" and (normalized.latitude ~= 0 or normalized.longitude ~= 0) then return nil, "Coordinates are accepted only for set_location" end
	local op, argv = normalized.operation, {}
	if op == "pair" or op == "unpair" then argv = { "/usr/bin/idevicepair", "-u", normalized.device, op }
	elseif op == "set_name" then argv = { "/usr/bin/idevicename", "-u", normalized.device, normalized.device_name }
	elseif op == "set_timestamp" then argv = { "/usr/bin/idevicedate", "-u", normalized.device, "-s", tostring(normalized.timestamp) }
	elseif op == "set_current_time" then argv = { "/usr/bin/idevicedate", "-u", normalized.device, "-c" }
	elseif op == "shutdown" or op == "restart" or op == "sleep" then argv = { "/usr/bin/idevicediagnostics", "-u", normalized.device, op }
	elseif op == "enter_recovery" then argv = { "/usr/bin/ideviceenterrecovery", normalized.device }
	elseif op == "set_location" then argv = { "/usr/bin/idevicesetlocation", "-u", normalized.device, "--", tostring(normalized.latitude), tostring(normalized.longitude) }
	else argv = { "/usr/bin/idevicesetlocation", "-u", normalized.device, "reset" } end
	local phrase = "RUN APPLE " .. op:upper() .. " ON " .. normalized.device
	return { action_id = schema.action_id, worker = "apple_mobile", label = "Apple " .. op, class = "DISRUPTIVE", resource = "apple_mobile", singleton = true,
		options = normalized, argv = argv, argv_preview = preview(argv), target_summary = normalized.device .. " / " .. op,
		wall_timeout = normalized.wall_timeout, artifacts = {},
		confirmation = { required = true, phrase = phrase, reason = "This native operation can change pairing records, device settings, power state, location override, or boot mode. Confirm the exact UDID and operation." } }
end

local capture_operations = { "screenshot", "syslog" }
local kernel_filters = { "all", "kernel_only", "no_kernel" }

local function mobile_capture_schema(context)
	local devices = choice_map(context.apple_normal_devices)
	return {
		action_id = "apple.mobile_capture", label = "Apple Screenshot & Syslog Capture", class = "ACTION",
		native = { executable = "/usr/bin/idevicescreenshot", executables = { "/usr/bin/idevicescreenshot", "/usr/bin/idevicesyslog" }, version = "libimobiledevice 1.3.0", helper = "/usr/sbin/usbmuxd 1.1.1" },
		fields = {
			field("device", "Normal-mode Apple device", "enum", devices[1] and devices[1].value or "", { options = devices }),
			field("operation", "Capture operation", "enum", "screenshot", { options = copy_array(capture_operations) }),
			field("duration", "Syslog duration (seconds)", "integer", 60, { min = 5, max = 3600, show_when = { field = "operation", equals = "syslog" } }),
			field("match", "Message substring", "text", "", { show_when = { field = "operation", equals = "syslog" } }),
			field("trigger", "Start trigger substring", "text", "", { show_when = { field = "operation", equals = "syslog" } }),
			field("untrigger", "Stop trigger substring", "text", "", { show_when = { field = "operation", equals = "syslog" } }),
			field("processes", "Only processes (name|name)", "text", "", { show_when = { field = "operation", equals = "syslog" }, placeholder = "SpringBoard|backboardd" }),
			field("exclude_processes", "Exclude processes (name|name)", "text", "", { show_when = { field = "operation", equals = "syslog" } }),
			field("quiet", "Exclude common noisy processes", "boolean", false, { show_when = { field = "operation", equals = "syslog" } }),
			field("kernel_filter", "Kernel messages", "enum", "all", { options = copy_array(kernel_filters), show_when = { field = "operation", equals = "syslog" } })
		}
	}
end

local function build_mobile_capture(options, context)
	local schema = mobile_capture_schema(context)
	local normalized, err = defaults(schema, options, "Apple capture")
	if not normalized then return nil, err end
	local _, devices = choice_map(context.apple_normal_devices)
	if type(normalized.device) ~= "string" or not devices[normalized.device] then return nil, "Selected normal-mode Apple device is not in the reviewed live inventory" end
	normalized.operation, err = enum(normalized.operation, capture_operations, "Capture operation"); if not normalized.operation then return nil, err end
	normalized.duration, err = integer(normalized.duration, 5, 3600, "Syslog duration"); if not normalized.duration then return nil, err end
	for _, name in ipairs({ "match", "trigger", "untrigger" }) do normalized[name], err = text(normalized[name], name, 128, nil, false); if normalized[name] == nil then return nil, err end end
	for _, name in ipairs({ "processes", "exclude_processes" }) do normalized[name], err = text(normalized[name], name, 256, "^[A-Za-z0-9_.+%-]+[|A-Za-z0-9_.+%-]*$", false); if normalized[name] == nil then return nil, err end end
	normalized.quiet, err = boolean(normalized.quiet, "Quiet filter"); if normalized.quiet == nil then return nil, err end
	normalized.kernel_filter, err = enum(normalized.kernel_filter, kernel_filters, "Kernel filter"); if not normalized.kernel_filter then return nil, err end
	if normalized.operation ~= "syslog" and (normalized.duration ~= 60 or normalized.match ~= "" or normalized.trigger ~= "" or normalized.untrigger ~= "" or normalized.processes ~= "" or normalized.exclude_processes ~= "" or normalized.quiet or normalized.kernel_filter ~= "all") then return nil, "Syslog fields are accepted only for syslog" end
	local argv, artifacts, timeout
	if normalized.operation == "screenshot" then
		argv = { "/usr/bin/idevicescreenshot", "-u", normalized.device, "@ARTIFACT@/apple-screenshot.tiff" }
		artifacts = { { name = "apple-screenshot.tiff", kind = "apple_screenshot", content_type = "image/tiff", max_size = 67108864, storage = "extroot" } }
		timeout = 120
	else
		argv = { "/usr/bin/idevicesyslog", "-u", normalized.device, "-x", "--no-colors" }
		if normalized.match ~= "" then add(argv, "-m"); add(argv, normalized.match) end
		if normalized.trigger ~= "" then add(argv, "-t"); add(argv, normalized.trigger) end
		if normalized.untrigger ~= "" then add(argv, "-T"); add(argv, normalized.untrigger) end
		if normalized.processes ~= "" then add(argv, "-p"); add(argv, normalized.processes) end
		if normalized.exclude_processes ~= "" then add(argv, "-e"); add(argv, normalized.exclude_processes) end
		if normalized.quiet then add(argv, "-q") end
		if normalized.kernel_filter == "kernel_only" then add(argv, "-k") elseif normalized.kernel_filter == "no_kernel" then add(argv, "-K") end
		artifacts = { { name = "apple-syslog.txt", kind = "apple_syslog", content_type = "text/plain", max_size = 33554432, storage = "extroot" } }
		timeout = normalized.duration + 10
	end
	return { action_id = schema.action_id, worker = "apple_mobile", label = "Apple " .. normalized.operation, class = "ACTION", resource = "apple_mobile", singleton = true,
		options = normalized, argv = argv, argv_preview = preview(argv), target_summary = normalized.device .. " / " .. normalized.operation,
		wall_timeout = timeout, artifacts = artifacts, confirmation = { required = false } }
end

local recovery_operations = { "query", "mode", "send_command", "send_file", "send_payload", "run_script", "reset", "normal" }

local function recovery_schema(context)
	local devices = choice_map(context.apple_recovery_devices)
	local inputs = upload_choices(context, "apple_recovery_input", true)
	return {
		action_id = "apple.recovery", label = "Apple Recovery / DFU Operator", class = "DISRUPTIVE",
		native = { executable = "/usr/bin/irecovery", executables = { "/usr/bin/irecovery" }, version = "1.0.0" },
		fields = {
			field("device", "Recovery / DFU target", "enum", devices[1] and devices[1].value or "", { options = devices, help = "A parseable ECID from one reviewed Apple recovery/DFU USB identity is required." }),
			field("operation", "Native operation", "enum", "query", { options = copy_array(recovery_operations) }),
			field("wall_timeout", "Wall timeout (seconds)", "integer", 120, { min = 10, max = 1800 }),
			field("verbosity", "Native verbosity", "integer", 0, { min = 0, max = 3, advanced = true }),
			field("recovery_command", "Recovery command", "text", "", { show_when = { field = "operation", equals = "send_command" }, help = "Sent as one literal irecovery protocol argument; it is never interpreted by the router shell." }),
			field("input_upload_id", "Sealed recovery input (file/payload/script)", "enum", "", { options = inputs, help = "Used only by send_file, send_payload, and run_script." })
		}
	}
end

local function build_recovery(options, context)
	local schema = recovery_schema(context)
	local normalized, err = defaults(schema, options, "Apple recovery")
	if not normalized then return nil, err end
	local _, devices = choice_map(context.apple_recovery_devices)
	local _, uploads = upload_choices(context, "apple_recovery_input")
	if type(normalized.device) ~= "string" or not devices[normalized.device] then return nil, "Selected Apple recovery/DFU ECID is not in the reviewed live inventory" end
	normalized.operation, err = enum(normalized.operation, recovery_operations, "Recovery operation"); if not normalized.operation then return nil, err end
	normalized.wall_timeout, err = integer(normalized.wall_timeout, 10, 1800, "Wall timeout"); if not normalized.wall_timeout then return nil, err end
	normalized.verbosity, err = integer(normalized.verbosity, 0, 3, "Verbosity"); if normalized.verbosity == nil then return nil, err end
	normalized.recovery_command, err = text(normalized.recovery_command, "Recovery command", 256, "^[A-Za-z0-9_.,:=+/%@%-%s]+$", normalized.operation == "send_command"); if normalized.recovery_command == nil then return nil, err end
	if normalized.operation ~= "send_command" and normalized.recovery_command ~= "" then return nil, "Recovery command is accepted only for send_command" end
	local requires_input = normalized.operation == "send_file" or normalized.operation == "send_payload" or normalized.operation == "run_script"
	if requires_input and not uploads[normalized.input_upload_id] then return nil, "This recovery operation requires one sealed recovery input" end
	if not requires_input and normalized.input_upload_id ~= "" then return nil, "Recovery input is accepted only for file, payload, or script operations" end
	local argv = { "/usr/bin/irecovery", "-i", devices[normalized.device].ecid }
	for _ = 1, normalized.verbosity do add(argv, "-v") end
	local op = normalized.operation
	if op == "query" then add(argv, "-q") elseif op == "mode" then add(argv, "-m")
	elseif op == "send_command" then add(argv, "-c"); add(argv, normalized.recovery_command)
	elseif op == "send_file" then add(argv, "-f"); add(argv, "@UPLOAD@/" .. normalized.input_upload_id)
	elseif op == "send_payload" then add(argv, "-k"); add(argv, "@UPLOAD@/" .. normalized.input_upload_id)
	elseif op == "run_script" then add(argv, "-e"); add(argv, "@UPLOAD@/" .. normalized.input_upload_id)
	elseif op == "reset" then add(argv, "-r") else add(argv, "-n") end
	local confirmation = { required = false }
	if op ~= "query" and op ~= "mode" then
		confirmation = { required = true, phrase = "RUN IRECOVERY " .. op:upper() .. " ON " .. devices[normalized.device].ecid,
			reason = "This native recovery/DFU operation can transmit data, execute a device recovery command, reset the connection, or change boot mode. Confirm the exact ECID and operation." }
	end
	return { action_id = schema.action_id, worker = "apple_recovery", label = "irecovery " .. op, class = "DISRUPTIVE", resource = "apple_mobile", singleton = true,
		options = normalized, argv = argv, argv_preview = preview(argv), target_summary = devices[normalized.device].ecid .. " / " .. devices[normalized.device].mode .. " / " .. op,
		wall_timeout = normalized.wall_timeout, artifacts = {}, input_uploads = requires_input and { { id = normalized.input_upload_id, kind = "apple_recovery_input" } } or {}, confirmation = confirmation }
end

local restore_modes = { "update", "erase", "no_action" }
local restore_sources = { "sealed_ipsw", "latest_signed" }

local function restore_schema(context)
	local devices = choice_map(context.apple_restore_devices)
	local restores = upload_choices(context, "apple_restore")
	local tickets = upload_choices(context, "apple_ticket", true)
	return {
		action_id = "apple.restore", label = "Apple IPSW Restore Operator", class = "DISRUPTIVE",
		native = { executable = "/usr/bin/idevicerestore", executables = { "/usr/bin/idevicerestore" }, version = "1.0.0", helper = "/usr/sbin/usbmuxd 1.1.1 for normal-mode targets" },
		fields = {
			field("device", "Exact restore target", "enum", devices[1] and devices[1].value or "", { options = devices }),
			field("source", "Firmware source", "enum", "sealed_ipsw", { options = copy_array(restore_sources) }),
			field("restore_upload_id", "Sealed IPSW", "enum", "", { options = restores, show_when = { field = "source", equals = "sealed_ipsw" } }),
			field("mode", "Restore mode", "enum", "update", { options = copy_array(restore_modes), help = "Update attempts to preserve data; erase explicitly requests a full data-erasing restore; no_action performs no restore action." }),
			field("wall_timeout", "Wall timeout (seconds)", "integer", 7200, { min = 600, max = 28800 }),
			field("plain_progress", "Plain progress output", "boolean", true),
			field("debug", "Communication debugging", "boolean", false, { advanced = true }),
			field("custom", "Custom firmware", "boolean", false, { advanced = true }),
			field("cydia", "Use Cydia signature service", "boolean", false, { advanced = true }),
			field("exclude_baseband", "Exclude NOR/baseband upgrade", "boolean", false, { advanced = true }),
			field("fetch_shsh", "Fetch TSS record and exit", "boolean", false, { advanced = true }),
			field("no_restore", "Stop after booting restore ramdisk", "boolean", false, { advanced = true }),
			field("keep_personalized", "Keep personalized components", "boolean", false, { advanced = true }),
			field("pwn_dfu", "Put supported device in pwned DFU", "boolean", false, { advanced = true }),
			field("allow_restore_mode", "Allow Restore-mode target", "boolean", false, { advanced = true }),
			field("ticket_upload_id", "Optional AP ticket", "enum", "", { options = tickets, advanced = true })
		}
	}
end

local function build_restore(options, context)
	local schema = restore_schema(context)
	local normalized, err = defaults(schema, options, "Apple restore")
	if not normalized then return nil, err end
	local _, devices = choice_map(context.apple_restore_devices)
	local _, restores = upload_choices(context, "apple_restore")
	local _, tickets = upload_choices(context, "apple_ticket")
	local target = type(normalized.device) == "string" and devices[normalized.device] or nil
	if not target then return nil, "Selected Apple restore target is not in the reviewed live inventory" end
	normalized.source, err = enum(normalized.source, restore_sources, "Firmware source"); if not normalized.source then return nil, err end
	normalized.mode, err = enum(normalized.mode, restore_modes, "Restore mode"); if not normalized.mode then return nil, err end
	normalized.wall_timeout, err = integer(normalized.wall_timeout, 600, 28800, "Wall timeout"); if not normalized.wall_timeout then return nil, err end
	for _, name in ipairs({ "plain_progress", "debug", "custom", "cydia", "exclude_baseband", "fetch_shsh", "no_restore", "keep_personalized", "pwn_dfu", "allow_restore_mode" }) do normalized[name], err = boolean(normalized[name], name); if normalized[name] == nil then return nil, err end end
	if normalized.source == "sealed_ipsw" then if not restores[normalized.restore_upload_id] then return nil, "Sealed IPSW source requires one live Apple restore upload" end
	elseif normalized.restore_upload_id ~= "" then return nil, "Restore upload is accepted only for the sealed IPSW source" end
	if normalized.ticket_upload_id ~= "" and not tickets[normalized.ticket_upload_id] then return nil, "AP ticket selection is not a live sealed Apple ticket upload" end
	local argv = { "/usr/bin/idevicerestore" }
	if target.selector == "udid" then add(argv, "-u"); add(argv, target.identifier) else add(argv, "-i"); add(argv, target.identifier) end
	add(argv, "-y"); add(argv, "-C"); add(argv, "@WORK@/restore-cache")
	if normalized.mode == "erase" then add(argv, "-e") elseif normalized.mode == "no_action" then add(argv, "-n") end
	if normalized.plain_progress then add(argv, "-P") end
	if normalized.debug then add(argv, "-d") end
	if normalized.custom then add(argv, "-c") end
	if normalized.cydia then add(argv, "-s") end
	if normalized.exclude_baseband then add(argv, "-x") end
	if normalized.fetch_shsh then add(argv, "-t") end
	if normalized.no_restore then add(argv, "-z") end
	if normalized.keep_personalized then add(argv, "-k") end
	if normalized.pwn_dfu then add(argv, "-p") end
	if normalized.allow_restore_mode then add(argv, "-R") end
	local input_uploads, reserve_size = {}, 12884901888
	if normalized.ticket_upload_id ~= "" then add(argv, "-T"); add(argv, "@UPLOAD@/" .. normalized.ticket_upload_id); input_uploads[#input_uploads + 1] = { id = normalized.ticket_upload_id, kind = "apple_ticket" } end
	if normalized.source == "latest_signed" then add(argv, "-l")
	else
		add(argv, "@UPLOAD@/" .. normalized.restore_upload_id)
		input_uploads[#input_uploads + 1] = { id = normalized.restore_upload_id, kind = "apple_restore" }
		reserve_size = math.max(2147483648, math.min(12884901888, restores[normalized.restore_upload_id].size * 2))
	end
	local phrase = "RESTORE APPLE TARGET " .. target.identifier .. " MODE " .. normalized.mode:upper()
	return { action_id = schema.action_id, worker = "apple_restore", label = "Apple restore " .. normalized.mode, class = "DISRUPTIVE", resource = "apple_mobile", singleton = true,
		options = normalized, argv = argv, argv_preview = preview(argv), target_summary = target.identifier .. " / " .. target.mode .. " / " .. normalized.mode .. " / " .. normalized.source,
		wall_timeout = normalized.wall_timeout,
		artifacts = { { name = "apple-restore.log", kind = "apple_restore_log", content_type = "text/plain", max_size = 16777216, storage = "extroot" } },
		workspaces = { { name = "restore-cache", storage = "extroot", reserve_size = reserve_size } }, input_uploads = input_uploads,
		confirmation = { required = true, phrase = phrase, reason = "idevicerestore will run non-interactively against this exact UDID/ECID. Update may still cause data loss; erase explicitly erases the device. Verify backup, power, signed firmware, authorization, and recovery path." } }
end

function M.describe(action_id, context)
	if action_id == "apple.mobile_diagnostics" then return mobile_diagnostics_schema(context or {}) end
	if action_id == "apple.mobile_manage" then return mobile_manage_schema(context or {}) end
	if action_id == "apple.mobile_capture" then return mobile_capture_schema(context or {}) end
	if action_id == "apple.recovery" then return recovery_schema(context or {}) end
	if action_id == "apple.restore" then return restore_schema(context or {}) end
	return nil, "Action does not expose an Apple Operator Mode schema"
end

function M.prepare(action_id, options, context)
	if action_id == "apple.mobile_diagnostics" then return build_mobile_diagnostics(options, context or {}) end
	if action_id == "apple.mobile_manage" then return build_mobile_manage(options, context or {}) end
	if action_id == "apple.mobile_capture" then return build_mobile_capture(options, context or {}) end
	if action_id == "apple.recovery" then return build_recovery(options, context or {}) end
	if action_id == "apple.restore" then return build_restore(options, context or {}) end
	return nil, "Action does not accept structured Apple Operator Mode parameters"
end

return M
