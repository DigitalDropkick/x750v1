-- Digital Dropkick Field Console Phase 3 Operator Mode schemas.
--
-- This pure module validates typed browser values and constructs reviewed
-- literal argv plans. It never executes a command or accepts an executable or
-- router path from the browser.

local M = {}

local function trim(value)
	return (tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function copy(value)
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
	for _, item in ipairs(schema.fields or {}) do allowed[item.name] = true; result[item.name] = item.default end
	for key, value in pairs(options) do
		if type(key) ~= "string" or not allowed[key] then return nil, "Unknown " .. label .. " option: " .. tostring(key) end
		result[key] = value
	end
	return result
end

local function enum(value, choices, label)
	if type(value) ~= "string" then return nil, label .. " must be a string" end
	for _, choice in ipairs(choices or {}) do
		local candidate = type(choice) == "table" and choice.value or choice
		if value == candidate then return value end
	end
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
	if (required and value == "") or #value > maximum or value:find("[%z\1-\31\127]") or
	   (value ~= "" and pattern and not value:match(pattern)) then
		return nil, label .. " is empty, too long, or contains unsupported characters"
	end
	return value
end

local function dense_paths(value, label)
	if type(value) ~= "table" then return nil, label .. " must be a JSON array" end
	local result, seen = {}, {}
	for index, item in ipairs(value) do
		if index > 64 then return nil, label .. " exceeds 64 entries" end
		local path, err = text(item, label .. " item", 240, "^[A-Za-z0-9_./ +,@%%=-]+$", true)
		if not path then return nil, err end
		if path:sub(1, 1) == "/" or path:find("..", 1, true) or path == "." then return nil, label .. " must contain relative non-traversing paths" end
		if seen[path] then return nil, label .. " contains a duplicate" end
		seen[path], result[#result + 1] = true, path
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

local function upload_choices(context, kind)
	local choices, records = { { value = "", label = "Select a sealed DDK input" } }, {}
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
	value = tostring(value):gsub("@UPLOAD@/[^: ]+", "[SEALED_DDK_UPLOAD]")
	value = value:gsub("@ARTIFACT@/", "[DDK_EXTROOT_ARTIFACT]/"):gsub("@WORK@/", "[DDK_EXTROOT_WORKSPACE]/")
	if value:match("^[A-Za-z0-9_./:@%%+=,%[%]-]+$") then return value end
	return "'" .. value:gsub("'", "'\\''") .. "'"
end

local function preview(argv)
	local result = {}
	for _, item in ipairs(argv or {}) do result[#result + 1] = preview_arg(item) end
	return table.concat(result, " ")
end

local function upload_binding(id, kind)
	return { { id = id, kind = kind } }
end

local function selected_device(items, value, label)
	local _, records = choice_map(items)
	if type(value) ~= "string" or not records[value] then return nil, label .. " is not in the reviewed live inventory" end
	return records[value]
end

local function hex_address(value, label, required)
	return text(value, label, 18, "^0[xX][0-9A-Fa-f]+$", required)
end

-- OpenOCD ------------------------------------------------------------------

local openocd_operations = { "probe", "program" }

local function openocd_schema(context)
	local devices = choice_map(context.programmer_devices)
	local boards = copy(context.openocd_board_configs)
	local interfaces = copy(context.openocd_interface_configs)
	local targets = copy(context.openocd_target_configs)
	local uploads = upload_choices(context, "firmware_image")
	return {
		action_id = "firmware.openocd", label = "OpenOCD Target Operator", class = "DISRUPTIVE",
		native = { executable = "/usr/bin/openocd", version = "OpenOCD 0.11.0-v0.11.0-1-OpenWrt" },
		fields = {
			field("device", "Reviewed USB debug adapter", "enum", devices[1] and devices[1].value or "", { options = devices }),
			field("config_mode", "Configuration selection", "enum", "interface_target", { options = { "interface_target", "board" } }),
			field("interface_config", "Installed interface config", "enum", interfaces[1] and interfaces[1].value or "", { options = interfaces, show_when = { field = "config_mode", equals = "interface_target" } }),
			field("target_config", "Installed target config", "enum", targets[1] and targets[1].value or "", { options = targets, show_when = { field = "config_mode", equals = "interface_target" } }),
			field("board_config", "Installed board config", "enum", boards[1] and boards[1].value or "", { options = boards, show_when = { field = "config_mode", equals = "board" } }),
			field("operation", "Operation", "enum", "probe", { options = copy(openocd_operations) }),
			field("upload", "Firmware image", "enum", "", { options = uploads, show_when = { field = "operation", equals = "program" } }),
			field("address", "Binary load address (optional)", "text", "", { placeholder = "0x08000000", show_when = { field = "operation", equals = "program" } }),
			field("adapter_speed", "Adapter speed (kHz; 0 = config default)", "integer", 0, { min = 0, max = 50000, advanced = true }),
			field("verify", "Verify programmed image", "boolean", true, { show_when = { field = "operation", equals = "program" } }),
			field("reset", "Reset target after programming", "boolean", true, { show_when = { field = "operation", equals = "program" } }),
			field("wall_timeout", "Wall timeout (seconds)", "integer", 900, { min = 10, max = 7200, advanced = true })
		}
	}
end

local function build_openocd(options, context)
	local schema = openocd_schema(context)
	local normalized, err = defaults(schema, options, "OpenOCD")
	if not normalized then return nil, err end
	local device = selected_device(context.programmer_devices, normalized.device, "Selected OpenOCD adapter"); if not device then return nil, "Selected OpenOCD adapter is not in the reviewed live inventory" end
	normalized.config_mode, err = enum(normalized.config_mode, { "interface_target", "board" }, "Configuration selection"); if not normalized.config_mode then return nil, err end
	normalized.operation, err = enum(normalized.operation, openocd_operations, "OpenOCD operation"); if not normalized.operation then return nil, err end
	normalized.adapter_speed, err = integer(normalized.adapter_speed, 0, 50000, "Adapter speed"); if not normalized.adapter_speed then return nil, err end
	normalized.verify, err = boolean(normalized.verify, "Verify"); if normalized.verify == nil then return nil, err end
	normalized.reset, err = boolean(normalized.reset, "Reset"); if normalized.reset == nil then return nil, err end
	normalized.wall_timeout, err = integer(normalized.wall_timeout, 10, 7200, "Wall timeout"); if not normalized.wall_timeout then return nil, err end
	normalized.address, err = hex_address(normalized.address, "Load address", false); if normalized.address == nil then return nil, err end
	local argv = { "/usr/bin/openocd" }
	if normalized.config_mode == "board" then
		normalized.board_config, err = enum(normalized.board_config, context.openocd_board_configs, "Board config"); if not normalized.board_config then return nil, err end
		add(argv, "-f"); add(argv, "/usr/share/openocd/scripts/" .. normalized.board_config)
	else
		normalized.interface_config, err = enum(normalized.interface_config, context.openocd_interface_configs, "Interface config"); if not normalized.interface_config then return nil, err end
		normalized.target_config, err = enum(normalized.target_config, context.openocd_target_configs, "Target config"); if not normalized.target_config then return nil, err end
		add(argv, "-f"); add(argv, "/usr/share/openocd/scripts/" .. normalized.interface_config)
		add(argv, "-f"); add(argv, "/usr/share/openocd/scripts/" .. normalized.target_config)
	end
	normalized.device_topology, normalized.device_usb_id, normalized.device_serial = device.topology, device.usb_id, device.serial or ""
	local input_uploads, confirmation = {}, { required = false }
	if normalized.operation == "program" then
		local _, uploads = upload_choices(context, "firmware_image")
		local upload = uploads[normalized.upload]
		if not upload then return nil, "OpenOCD programming requires a sealed firmware_image upload" end
		input_uploads = upload_binding(normalized.upload, "firmware_image")
		local phrase = "PROGRAM OPENOCD " .. normalized.device .. " " .. normalized.upload
		confirmation = { required = true, phrase = phrase, reason = "This will program the selected target through the exact adapter/config combination. Confirm voltage, pinout, target identity, backup, and recovery path." }
	elseif normalized.upload ~= "" or normalized.address ~= "" or normalized.verify ~= true or normalized.reset ~= true then
		return nil, "Programming-only OpenOCD fields must remain at defaults during probe"
	end
	local shown = copy(argv)
	shown[#shown + 1] = "-f"; shown[#shown + 1] = "[DDK_GENERATED_OPENOCD_COMMANDS]"
	return { action_id = schema.action_id, worker = "phase3_openocd", label = "OpenOCD " .. normalized.operation, class = "DISRUPTIVE", resource = "firmware", singleton = true,
		options = normalized, argv = argv, argv_preview = preview(shown), target_summary = normalized.device .. " / " .. normalized.operation,
		wall_timeout = normalized.wall_timeout, artifacts = {}, input_uploads = input_uploads, confirmation = confirmation }
end

-- AVRDUDE ------------------------------------------------------------------

local avrdude_operations = { "probe", "read_flash", "read_eeprom", "verify_flash", "verify_eeprom", "write_flash", "write_eeprom", "chip_erase" }
local avrdude_input_formats = { "a", "i", "r", "e" }
local avrdude_output_formats = { "i", "r" }

local function avrdude_schema(context)
	local devices = choice_map(context.firmware_connection_devices)
	local uploads = upload_choices(context, "firmware_image")
	return {
		action_id = "firmware.avrdude", label = "AVRDUDE Programmer", class = "DISRUPTIVE",
		native = { executable = "/usr/bin/avrdude", version = "AVRDUDE 6.3" },
		fields = {
			field("device", "Reviewed programmer/serial connection", "enum", devices[1] and devices[1].value or "", { options = devices }),
			field("programmer", "Installed programmer type", "enum", context.avrdude_programmers[1] and context.avrdude_programmers[1].value or "", { options = copy(context.avrdude_programmers) }),
			field("part", "Installed AVR part", "enum", context.avrdude_parts[1] and context.avrdude_parts[1].value or "", { options = copy(context.avrdude_parts) }),
			field("operation", "Memory operation", "enum", "probe", { options = copy(avrdude_operations) }),
			field("upload", "Firmware input", "enum", "", { options = uploads }),
			field("input_format", "Input format", "enum", "a", { options = copy(avrdude_input_formats), advanced = true }),
			field("output_format", "Backup format", "enum", "r", { options = copy(avrdude_output_formats), advanced = true }),
			field("baud", "Serial baud (0 = programmer default)", "integer", 0, { min = 0, max = 2000000, advanced = true }),
			field("bitclock", "JTAG/ISP bit clock period µs (0 = default)", "number", 0, { min = 0, max = 1000, step = 0.1, advanced = true }),
			field("disable_auto_erase", "Disable automatic flash erase", "boolean", false, { advanced = true }),
			field("no_verify", "Skip automatic write verification", "boolean", false, { advanced = true }),
			field("force_signature", "Override signature mismatch", "boolean", false, { advanced = true }),
			field("verbose", "Verbosity", "integer", 1, { min = 0, max = 4, advanced = true }),
			field("wall_timeout", "Wall timeout (seconds)", "integer", 900, { min = 10, max = 14400, advanced = true })
		}
	}
end

local function build_avrdude(options, context)
	local schema = avrdude_schema(context)
	local normalized, err = defaults(schema, options, "AVRDUDE")
	if not normalized then return nil, err end
	local device = selected_device(context.firmware_connection_devices, normalized.device, "Selected AVRDUDE connection"); if not device then return nil, "Selected AVRDUDE connection is not in the reviewed live inventory" end
	normalized.programmer, err = enum(normalized.programmer, context.avrdude_programmers, "Programmer type"); if not normalized.programmer then return nil, err end
	normalized.part, err = enum(normalized.part, context.avrdude_parts, "AVR part"); if not normalized.part then return nil, err end
	normalized.operation, err = enum(normalized.operation, avrdude_operations, "AVRDUDE operation"); if not normalized.operation then return nil, err end
	normalized.input_format, err = enum(normalized.input_format, avrdude_input_formats, "Input format"); if not normalized.input_format then return nil, err end
	normalized.output_format, err = enum(normalized.output_format, avrdude_output_formats, "Output format"); if not normalized.output_format then return nil, err end
	normalized.baud, err = integer(normalized.baud, 0, 2000000, "Baud"); if not normalized.baud then return nil, err end
	normalized.bitclock, err = number(normalized.bitclock, 0, 1000, "Bit clock"); if normalized.bitclock == nil then return nil, err end
	for _, name in ipairs({ "disable_auto_erase", "no_verify", "force_signature" }) do normalized[name], err = boolean(normalized[name], name); if normalized[name] == nil then return nil, err end end
	normalized.verbose, err = integer(normalized.verbose, 0, 4, "Verbosity"); if normalized.verbose == nil then return nil, err end
	normalized.wall_timeout, err = integer(normalized.wall_timeout, 10, 14400, "Wall timeout"); if not normalized.wall_timeout then return nil, err end
	normalized.device_kind, normalized.device_topology, normalized.device_usb_id = device.kind, device.topology or "", device.usb_id or ""
	local device_serial = type(device.serial) == "string" and device.serial:match("^[A-Za-z0-9._-]+$") and #device.serial <= 128 and device.serial or ""
	normalized.device_serial = device_serial
	local usb_connections = 0
	for _, candidate in ipairs(context.firmware_connection_devices or {}) do if candidate.kind == "usb" then usb_connections = usb_connections + 1 end end
	if device.kind == "usb" and device_serial == "" and usb_connections > 1 then return nil, "Multiple USB programmers require a stable serial descriptor for exact AVRDUDE selection" end
	local port = device.kind == "usb" and (device_serial ~= "" and ("usb:" .. device_serial) or "usb") or device.node
	local argv = { "/usr/bin/avrdude", "-p", normalized.part, "-c", normalized.programmer, "-P", port }
	if normalized.baud > 0 then add(argv, "-b"); add(argv, normalized.baud) end
	if normalized.bitclock > 0 then add(argv, "-B"); add(argv, normalized.bitclock) end
	if normalized.disable_auto_erase then add(argv, "-D") end
	if normalized.no_verify then add(argv, "-V") end
	if normalized.force_signature then add(argv, "-F") end
	for _ = 1, normalized.verbose do add(argv, "-v") end
	local artifacts, input_uploads, confirmation = {}, {}, { required = false }
	local operation, memory = normalized.operation, normalized.operation:find("eeprom", 1, true) and "eeprom" or "flash"
	if operation == "probe" then
		add(argv, "-n")
	elseif operation == "chip_erase" then
		add(argv, "-e")
		confirmation = { required = true, phrase = "ERASE AVR " .. normalized.device .. " " .. normalized.part, reason = "This will erase the selected AVR target." }
	elseif operation:match("^read_") then
		local name = normalized.output_format == "i" and "firmware-read.hex" or "firmware-read.bin"
		add(argv, "-U"); add(argv, memory .. ":r:@ARTIFACT@/" .. name .. ":" .. normalized.output_format)
		artifacts = { { name = name, kind = "firmware_backup", content_type = "application/octet-stream", max_size = 268435456, storage = "extroot" } }
	else
		local _, uploads = upload_choices(context, "firmware_image")
		local upload = uploads[normalized.upload]
		if not upload then return nil, "AVRDUDE verify/write requires a sealed firmware_image upload" end
		local mode = operation:match("^verify_") and "v" or "w"
		add(argv, "-U"); add(argv, memory .. ":" .. mode .. ":@UPLOAD@/" .. normalized.upload .. ":" .. normalized.input_format)
		input_uploads = upload_binding(normalized.upload, "firmware_image")
		if mode == "w" then confirmation = { required = true, phrase = "WRITE AVR " .. normalized.device .. " " .. normalized.part .. " " .. normalized.upload, reason = "This will write the selected AVR memory using the sealed input hash shown in review." } end
	end
	if not (operation:match("^verify_") or operation:match("^write_")) and normalized.upload ~= "" then return nil, "Firmware input is accepted only for AVRDUDE verify/write" end
	return { action_id = schema.action_id, worker = "phase3_avrdude", label = "AVRDUDE " .. operation, class = "DISRUPTIVE", resource = "firmware", singleton = true,
		options = normalized, argv = argv, argv_preview = preview(argv), target_summary = normalized.device .. " / " .. normalized.part .. " / " .. operation,
		wall_timeout = normalized.wall_timeout, artifacts = artifacts, input_uploads = input_uploads, confirmation = confirmation }
end

-- DFU ----------------------------------------------------------------------

local dfu_operations = { "read", "write", "erase", "detach", "launch", "get_info" }
local dfu_memories = { "flash", "user", "eeprom" }
local dfu_get_fields = { "bootloader-version", "ID1", "ID2", "manufacturer", "family", "product-name", "product-revision" }

local function dfu_schema(context)
	local devices = choice_map(context.dfu_devices)
	local uploads = upload_choices(context, "firmware_image")
	return {
		action_id = "firmware.dfu", label = "USB DFU Operator", class = "DISRUPTIVE",
		native = { executable = "/usr/bin/dfu-util", executables = { "/usr/bin/dfu-util", "/usr/bin/dfu-programmer" }, version = "dfu-util 0.11 / dfu-programmer 0.7.2" },
		fields = {
			field("tool", "Native DFU tool", "enum", "dfu-util", { options = { "dfu-util", "dfu-programmer" } }),
			field("device", "Reviewed live DFU device", "enum", devices[1] and devices[1].value or "", { options = devices }),
			field("operation", "Operation", "enum", "read", { options = copy(dfu_operations) }),
			field("target", "dfu-programmer controller", "enum", context.dfu_programmer_targets[1] and context.dfu_programmer_targets[1].value or "", { options = copy(context.dfu_programmer_targets), show_when = { field = "tool", equals = "dfu-programmer" } }),
			field("memory", "dfu-programmer memory", "enum", "flash", { options = copy(dfu_memories), show_when = { field = "tool", equals = "dfu-programmer" } }),
			field("get_field", "dfu-programmer information field", "enum", "product-name", { options = copy(dfu_get_fields), show_when = { field = "operation", equals = "get_info" } }),
			field("upload", "Firmware input", "enum", "", { options = uploads, show_when = { field = "operation", equals = "write" } }),
			field("alt", "dfu-util alternate setting", "text", "0", { advanced = true }),
			field("address", "DfuSe start address (optional)", "text", "", { placeholder = "0x08000000", advanced = true }),
			field("read_size", "Read size (bytes)", "integer", 1048576, { min = 1, max = 268435456, advanced = true }),
			field("transfer_size", "USB transfer size (0 = default)", "integer", 0, { min = 0, max = 1048576, advanced = true }),
			field("force", "Force operation where native tool supports it", "boolean", false, { advanced = true }),
			field("reset", "Reset/leave after dfu-util transfer", "boolean", false, { advanced = true }),
			field("wall_timeout", "Wall timeout (seconds)", "integer", 900, { min = 10, max = 14400, advanced = true })
		}
	}
end

local function build_dfu(options, context)
	local schema = dfu_schema(context)
	local normalized, err = defaults(schema, options, "DFU")
	if not normalized then return nil, err end
	local device = selected_device(context.dfu_devices, normalized.device, "Selected DFU device"); if not device then return nil, "Selected DFU device is not in the reviewed live inventory" end
	normalized.tool, err = enum(normalized.tool, { "dfu-util", "dfu-programmer" }, "DFU tool"); if not normalized.tool then return nil, err end
	normalized.operation, err = enum(normalized.operation, dfu_operations, "DFU operation"); if not normalized.operation then return nil, err end
	normalized.memory, err = enum(normalized.memory, dfu_memories, "DFU memory"); if not normalized.memory then return nil, err end
	normalized.get_field, err = enum(normalized.get_field, dfu_get_fields, "Information field"); if not normalized.get_field then return nil, err end
	normalized.alt, err = text(normalized.alt, "DFU alternate setting", 128, "^[A-Za-z0-9_. +%-]+$", true); if not normalized.alt then return nil, err end
	normalized.address, err = hex_address(normalized.address, "DfuSe address", false); if normalized.address == nil then return nil, err end
	normalized.read_size, err = integer(normalized.read_size, 1, 268435456, "Read size"); if not normalized.read_size then return nil, err end
	normalized.transfer_size, err = integer(normalized.transfer_size, 0, 1048576, "Transfer size"); if normalized.transfer_size == nil then return nil, err end
	normalized.force, err = boolean(normalized.force, "Force"); if normalized.force == nil then return nil, err end
	normalized.reset, err = boolean(normalized.reset, "Reset"); if normalized.reset == nil then return nil, err end
	normalized.wall_timeout, err = integer(normalized.wall_timeout, 10, 14400, "Wall timeout"); if not normalized.wall_timeout then return nil, err end
	normalized.device_topology, normalized.device_usb_id, normalized.device_serial, normalized.busnum, normalized.devnum = device.topology, device.usb_id, device.serial or "", device.busnum, device.devnum
	local argv, artifacts, input_uploads, confirmation = {}, {}, {}, { required = false }
	if normalized.tool == "dfu-util" then
		if normalized.operation == "erase" or normalized.operation == "launch" or normalized.operation == "get_info" then return nil, "The selected operation belongs to dfu-programmer, not dfu-util" end
		argv = { "/usr/bin/dfu-util", "-d", device.usb_id, "-p", device.topology, "-a", normalized.alt }
		if device.serial and device.serial ~= "" then add(argv, "-S"); add(argv, device.serial) end
		if normalized.transfer_size > 0 then add(argv, "-t"); add(argv, normalized.transfer_size) end
		if normalized.operation == "read" then
			if normalized.address ~= "" then add(argv, "-s"); add(argv, normalized.address .. ":" .. normalized.read_size) end
			add(argv, "-U"); add(argv, "@ARTIFACT@/firmware-dfu-read.bin"); add(argv, "-Z"); add(argv, normalized.read_size)
			artifacts = { { name = "firmware-dfu-read.bin", kind = "firmware_backup", content_type = "application/octet-stream", max_size = normalized.read_size, storage = "extroot" } }
		elseif normalized.operation == "write" then
			local _, uploads = upload_choices(context, "firmware_image"); if not uploads[normalized.upload] then return nil, "DFU download requires a sealed firmware_image upload" end
			if normalized.address ~= "" then add(argv, "-s"); add(argv, normalized.address) end
			add(argv, "-D"); add(argv, "@UPLOAD@/" .. normalized.upload); if normalized.reset then add(argv, "-R") end
			input_uploads = upload_binding(normalized.upload, "firmware_image")
			confirmation = { required = true, phrase = "WRITE DFU " .. normalized.device .. " " .. normalized.upload, reason = "This will download firmware to the exact selected DFU topology/serial." }
		else
			add(argv, "-e")
			confirmation = { required = true, phrase = "DETACH DFU " .. normalized.device, reason = "This may transition or reset the selected DFU device." }
		end
	else
		if normalized.operation == "detach" then return nil, "Detach belongs to dfu-util, not dfu-programmer" end
		normalized.target, err = enum(normalized.target, context.dfu_programmer_targets, "DFU controller"); if not normalized.target then return nil, err end
		local selector = normalized.target .. ":" .. tostring(device.busnum) .. "," .. tostring(device.devnum)
		argv = { "/usr/bin/dfu-programmer", selector }
		if normalized.operation == "read" then
			add(argv, "read"); if normalized.force then add(argv, "--force") end; add(argv, "--bin"); if normalized.memory ~= "flash" then add(argv, "--" .. normalized.memory) end
			artifacts = { { name = "firmware-dfu-read.bin", kind = "firmware_backup", content_type = "application/octet-stream", max_size = 268435456, storage = "extroot" } }
		elseif normalized.operation == "write" then
			local _, uploads = upload_choices(context, "firmware_image"); if not uploads[normalized.upload] then return nil, "dfu-programmer flash requires a sealed firmware_image upload" end
			add(argv, "flash"); if normalized.force then add(argv, "--force") end; if normalized.memory ~= "flash" then add(argv, "--" .. normalized.memory) end; add(argv, "@UPLOAD@/" .. normalized.upload)
			input_uploads = upload_binding(normalized.upload, "firmware_image")
			confirmation = { required = true, phrase = "FLASH DFU " .. normalized.device .. " " .. normalized.target .. " " .. normalized.upload, reason = "This will flash the selected DFU controller and memory." }
		elseif normalized.operation == "erase" then
			add(argv, "erase"); if normalized.force then add(argv, "--force") end
			confirmation = { required = true, phrase = "ERASE DFU " .. normalized.device .. " " .. normalized.target, reason = "This will erase the selected DFU controller." }
		elseif normalized.operation == "launch" then
			add(argv, "launch")
			confirmation = { required = true, phrase = "LAUNCH DFU " .. normalized.device .. " " .. normalized.target, reason = "This will leave the bootloader and launch the selected controller." }
		else add(argv, "get"); add(argv, normalized.get_field) end
	end
	if normalized.operation ~= "write" and normalized.upload ~= "" then return nil, "Firmware input is accepted only for DFU write" end
	return { action_id = schema.action_id, worker = "phase3_dfu", label = normalized.tool .. " " .. normalized.operation, class = "DISRUPTIVE", resource = "firmware", singleton = true,
		options = normalized, argv = argv, argv_preview = preview(argv), target_summary = normalized.device .. " / " .. normalized.tool .. " / " .. normalized.operation,
		wall_timeout = normalized.wall_timeout, artifacts = artifacts, input_uploads = input_uploads, confirmation = confirmation }
end

-- Serial bootloaders -------------------------------------------------------

local serial_tools = { "stm32flash", "bossac", "lpc21isp" }
local serial_operations = { "info", "read", "write", "verify", "erase", "crc", "go", "reset", "security", "boot_flash", "boot_rom" }

local function firmware_serial_schema(context)
	local devices = choice_map(context.firmware_serial_devices)
	local uploads = upload_choices(context, "firmware_image")
	return {
		action_id = "firmware.serial", label = "Serial Bootloader Programmer", class = "DISRUPTIVE",
		native = { executable = "/usr/bin/stm32flash", executables = { "/usr/bin/stm32flash", "/usr/bin/bossac", "/usr/sbin/lpc21isp" }, version = "STM32Flash 0.6 / BOSSA 1.9.1 / LPC21ISP 1.97" },
		fields = {
			field("tool", "Native programmer", "enum", "stm32flash", { options = copy(serial_tools) }),
			field("device", "Reviewed non-EC25 serial port", "enum", devices[1] and devices[1].value or "", { options = devices }),
			field("operation", "Operation", "enum", "info", { options = copy(serial_operations) }),
			field("upload", "Firmware input", "enum", "", { options = uploads }),
			field("baud", "Baud rate", "integer", 115200, { min = 1200, max = 2000000 }),
			field("serial_mode", "STM32 serial mode", "enum", "8e1", { options = { "8e1", "8n1", "8o1" }, advanced = true }),
			field("offset", "Flash offset/address", "text", "0x0", { advanced = true }),
			field("length", "Read length (bytes)", "integer", 1048576, { min = 1, max = 268435456, advanced = true }),
			field("oscillator_khz", "LPC oscillator (kHz)", "integer", 12000, { min = 100, max = 100000, advanced = true }),
			field("input_format", "LPC input format", "enum", "hex", { options = { "hex", "bin" }, advanced = true }),
			field("erase_before_write", "Erase before write", "boolean", true, { advanced = true }),
			field("verify_write", "Verify write", "boolean", true, { advanced = true }),
			field("reset_after", "Reset/start after operation", "boolean", false, { advanced = true }),
			field("control_lines", "Use LPC DTR/RTS boot control", "boolean", false, { advanced = true }),
			field("wall_timeout", "Wall timeout (seconds)", "integer", 900, { min = 10, max = 14400, advanced = true })
		}
	}
end

local function build_firmware_serial(options, context)
	local schema = firmware_serial_schema(context)
	local normalized, err = defaults(schema, options, "serial programmer")
	if not normalized then return nil, err end
	local device = selected_device(context.firmware_serial_devices, normalized.device, "Selected serial programming port"); if not device then return nil, "Selected serial programming port is not in the reviewed live inventory" end
	normalized.tool, err = enum(normalized.tool, serial_tools, "Serial programmer"); if not normalized.tool then return nil, err end
	normalized.operation, err = enum(normalized.operation, serial_operations, "Serial programming operation"); if not normalized.operation then return nil, err end
	normalized.baud, err = integer(normalized.baud, 1200, 2000000, "Baud"); if not normalized.baud then return nil, err end
	normalized.serial_mode, err = enum(normalized.serial_mode, { "8e1", "8n1", "8o1" }, "Serial mode"); if not normalized.serial_mode then return nil, err end
	normalized.offset, err = hex_address(normalized.offset, "Flash offset", true); if not normalized.offset then return nil, err end
	normalized.length, err = integer(normalized.length, 1, 268435456, "Read length"); if not normalized.length then return nil, err end
	normalized.oscillator_khz, err = integer(normalized.oscillator_khz, 100, 100000, "Oscillator"); if not normalized.oscillator_khz then return nil, err end
	normalized.input_format, err = enum(normalized.input_format, { "hex", "bin" }, "Input format"); if not normalized.input_format then return nil, err end
	for _, name in ipairs({ "erase_before_write", "verify_write", "reset_after", "control_lines" }) do normalized[name], err = boolean(normalized[name], name); if normalized[name] == nil then return nil, err end end
	normalized.wall_timeout, err = integer(normalized.wall_timeout, 10, 14400, "Wall timeout"); if not normalized.wall_timeout then return nil, err end
	normalized.device_topology, normalized.device_usb_id = device.topology or "", device.usb_id or ""
	local argv, artifacts, input_uploads, confirmation = {}, {}, {}, { required = false }
	local op = normalized.operation
	if normalized.tool == "stm32flash" then
		if not ({ info=true, read=true, write=true, erase=true, crc=true, go=true })[op] then return nil, "STM32Flash does not provide the selected operation" end
		argv = { "/usr/bin/stm32flash", "-b", tostring(normalized.baud), "-m", normalized.serial_mode }
		if op == "read" then add(argv, "-r"); add(argv, "@ARTIFACT@/firmware-serial-read.bin"); add(argv, "-S"); add(argv, normalized.offset .. ":" .. normalized.length); artifacts = { { name = "firmware-serial-read.bin", kind = "firmware_backup", content_type = "application/octet-stream", max_size = normalized.length, storage = "extroot" } }
		elseif op == "write" then
			local _, uploads = upload_choices(context, "firmware_image"); if not uploads[normalized.upload] then return nil, "STM32Flash write requires a sealed firmware_image upload" end
			add(argv, "-w"); add(argv, "@UPLOAD@/" .. normalized.upload); add(argv, "-S"); add(argv, normalized.offset); if normalized.verify_write then add(argv, "-v") end; if normalized.reset_after then add(argv, "-R") end
			input_uploads = upload_binding(normalized.upload, "firmware_image")
		elseif op == "erase" then add(argv, "-o")
		elseif op == "crc" then add(argv, "-C")
		elseif op == "go" then add(argv, "-g"); add(argv, normalized.offset) end
		add(argv, normalized.device)
	elseif normalized.tool == "bossac" then
		if not ({ info=true, read=true, write=true, verify=true, erase=true, reset=true, security=true, boot_flash=true, boot_rom=true })[op] then return nil, "BOSSA does not provide the selected operation" end
		argv = { "/usr/bin/bossac", "--port=" .. normalized.device }
		if op == "info" then add(argv, "--info")
		elseif op == "read" then add(argv, "--read=" .. normalized.length); add(argv, "--offset=" .. normalized.offset); add(argv, "@ARTIFACT@/firmware-serial-read.bin"); artifacts = { { name = "firmware-serial-read.bin", kind = "firmware_backup", content_type = "application/octet-stream", max_size = normalized.length, storage = "extroot" } }
		elseif op == "write" or op == "verify" then
			local _, uploads = upload_choices(context, "firmware_image"); if not uploads[normalized.upload] then return nil, "BOSSA write/verify requires a sealed firmware_image upload" end
			if op == "write" and normalized.erase_before_write then add(argv, "--erase") end; if op == "write" then add(argv, "--write") end; if op == "verify" or normalized.verify_write then add(argv, "--verify") end; add(argv, "--offset=" .. normalized.offset); if normalized.reset_after then add(argv, "--reset") end; add(argv, "@UPLOAD@/" .. normalized.upload)
			input_uploads = upload_binding(normalized.upload, "firmware_image")
		elseif op == "erase" then add(argv, "--erase")
		elseif op == "reset" then add(argv, "--reset")
		elseif op == "security" then add(argv, "--security")
		elseif op == "boot_flash" then add(argv, "--boot=1")
		elseif op == "boot_rom" then add(argv, "--boot=0") end
	else
		if op ~= "write" then return nil, "LPC21ISP 1.97 exposes programming but no safe readback operation" end
		local _, uploads = upload_choices(context, "firmware_image"); if not uploads[normalized.upload] then return nil, "LPC21ISP write requires a sealed firmware_image upload" end
		argv = { "/usr/sbin/lpc21isp", normalized.input_format == "bin" and "-bin" or "-hex" }
		if normalized.erase_before_write then add(argv, "-wipe") end; if normalized.verify_write then add(argv, "-verify") end; if not normalized.reset_after then add(argv, "-donotstart") end; if normalized.control_lines then add(argv, "-control") end
		add(argv, "@UPLOAD@/" .. normalized.upload); add(argv, normalized.device); add(argv, normalized.baud); add(argv, normalized.oscillator_khz)
		input_uploads = upload_binding(normalized.upload, "firmware_image")
	end
	local consequential = ({ write=true, erase=true, go=true, reset=true, security=true, boot_flash=true, boot_rom=true })[op]
	if consequential then confirmation = { required = true, phrase = string.upper(op) .. " SERIAL TARGET " .. normalized.device .. (normalized.upload ~= "" and (" " .. normalized.upload) or ""), reason = "This operation can alter, erase, start, reset, secure, or change boot behavior on the exact selected serial target." } end
	if op ~= "write" and op ~= "verify" and normalized.upload ~= "" then return nil, "Firmware input is accepted only for serial write/verify" end
	return { action_id = schema.action_id, worker = "phase3_serial", label = normalized.tool .. " " .. op, class = "DISRUPTIVE", resource = "firmware", singleton = true,
		options = normalized, argv = argv, argv_preview = preview(argv), target_summary = normalized.device .. " / " .. normalized.tool .. " / " .. op,
		wall_timeout = normalized.wall_timeout, artifacts = artifacts, input_uploads = input_uploads, confirmation = confirmation }
end

-- Storage ------------------------------------------------------------------

local inspect_operations = { "smart_info", "smart_health", "smart_all", "smart_attributes", "smart_short_test", "smart_long_test", "smart_abort", "fsck_check", "badblocks_read" }
local smart_device_types = { "auto", "ata", "scsi", "sat", "sat,12", "sat,16", "nvme" }

local function storage_inspect_schema(context)
	local devices = choice_map(context.storage_devices)
	return {
		action_id = "storage.inspect", label = "Storage Health & Read-Only Checks", class = "ACTION",
		native = { executable = "/usr/sbin/smartctl", executables = { "/usr/sbin/smartctl", "/usr/sbin/e2fsck", "/usr/sbin/badblocks" }, version = "smartctl 7.2 / e2fsprogs 1.46.5" },
		fields = {
			field("device", "Non-system block target", "enum", devices[1] and devices[1].value or "", { options = devices }),
			field("operation", "Operation", "enum", "smart_info", { options = copy(inspect_operations) }),
			field("smart_type", "SMART device transport", "enum", "auto", { options = copy(smart_device_types), advanced = true }),
			field("force_fsck", "Force filesystem check", "boolean", false, { advanced = true }),
			field("block_size", "Badblocks block size", "integer", 4096, { min = 512, max = 1048576, advanced = true }),
			field("max_bad_blocks", "Stop after bad blocks", "integer", 1000, { min = 1, max = 1000000, advanced = true }),
			field("wall_timeout", "Wall timeout (seconds)", "integer", 3600, { min = 10, max = 86400, advanced = true })
		}
	}
end

local function storage_record(context, value)
	return selected_device(context.storage_devices, value, "Selected storage target")
end

local function validate_storage_common(normalized, context)
	local record = storage_record(context, normalized.device)
	if not record then return nil, "Selected storage target is not an unprotected server-attributed block device" end
	return record
end

local function build_storage_inspect(options, context)
	local schema = storage_inspect_schema(context)
	local normalized, err = defaults(schema, options, "storage inspection")
	if not normalized then return nil, err end
	local device, device_err = validate_storage_common(normalized, context); if not device then return nil, device_err end
	normalized.operation, err = enum(normalized.operation, inspect_operations, "Storage operation"); if not normalized.operation then return nil, err end
	normalized.smart_type, err = enum(normalized.smart_type, smart_device_types, "SMART device type"); if not normalized.smart_type then return nil, err end
	normalized.force_fsck, err = boolean(normalized.force_fsck, "Force filesystem check"); if normalized.force_fsck == nil then return nil, err end
	normalized.block_size, err = integer(normalized.block_size, 512, 1048576, "Block size"); if not normalized.block_size then return nil, err end
	normalized.max_bad_blocks, err = integer(normalized.max_bad_blocks, 1, 1000000, "Maximum bad blocks"); if not normalized.max_bad_blocks then return nil, err end
	normalized.wall_timeout, err = integer(normalized.wall_timeout, 10, 86400, "Wall timeout"); if not normalized.wall_timeout then return nil, err end
	normalized.device_size, normalized.device_kind, normalized.fs_type, normalized.mounted = device.size, device.kind, device.fs_type or "", device.mounted and true or false
	local argv, artifacts, op = {}, {}, normalized.operation
	if op:match("^smart_") then
		if device.kind ~= "disk" then return nil, "SMART operations require a whole non-system disk target" end
		argv = { "/usr/sbin/smartctl" }; if normalized.smart_type ~= "auto" then add(argv, "-d"); add(argv, normalized.smart_type) end
		local smart_flag = ({ smart_info="-i", smart_health="-H", smart_all="-x", smart_attributes="-A", smart_short_test="-t", smart_long_test="-t", smart_abort="-X" })[op]
		add(argv, smart_flag); if op == "smart_short_test" then add(argv, "short") elseif op == "smart_long_test" then add(argv, "long") end; add(argv, normalized.device)
	elseif op == "fsck_check" then
		if device.mounted then return nil, "Filesystem checks require an unmounted target" end
		if not ({ ext2=true, ext3=true, ext4=true })[device.fs_type or ""] then return nil, "e2fsck requires an ext2/ext3/ext4 target" end
		argv = { "/usr/sbin/e2fsck", "-n", "-v" }; if normalized.force_fsck then add(argv, "-f") end; add(argv, normalized.device)
	else
		if device.mounted then return nil, "Bad-block scans require an unmounted target" end
		argv = { "/usr/sbin/badblocks", "-s", "-v", "-b", tostring(normalized.block_size), "-e", tostring(normalized.max_bad_blocks), "-o", "@ARTIFACT@/storage-badblocks.txt", normalized.device }
		artifacts = { { name = "storage-badblocks.txt", kind = "badblocks_list", content_type = "text/plain", max_size = 1048576, storage = "extroot" } }
	end
	return { action_id = schema.action_id, worker = "phase3_storage", label = "Storage " .. op, class = "ACTION", resource = "storage-" .. device.disk, singleton = true,
		options = normalized, argv = argv, argv_preview = preview(argv), target_summary = normalized.device .. " / " .. op .. " / " .. tostring(device.size) .. " bytes",
		wall_timeout = normalized.wall_timeout, artifacts = artifacts, confirmation = { required = false } }
end

local repair_operations = { "fsck_preen", "fsck_assume_yes", "badblocks_nondestructive" }

local function storage_repair_schema(context)
	local devices = choice_map(context.storage_devices)
	return {
		action_id = "storage.repair", label = "Storage Repair Operator", class = "DISRUPTIVE",
		native = { executable = "/usr/sbin/e2fsck", executables = { "/usr/sbin/e2fsck", "/usr/sbin/badblocks" }, version = "e2fsprogs 1.46.5" },
		fields = {
			field("device", "Unmounted non-system target", "enum", devices[1] and devices[1].value or "", { options = devices }),
			field("operation", "Repair operation", "enum", "fsck_preen", { options = copy(repair_operations) }),
			field("force_fsck", "Force filesystem check", "boolean", true, { advanced = true }),
			field("block_size", "Badblocks block size", "integer", 4096, { min = 512, max = 1048576, advanced = true }),
			field("passes", "Badblocks non-destructive passes", "integer", 1, { min = 1, max = 4, advanced = true }),
			field("max_bad_blocks", "Stop after bad blocks", "integer", 1000, { min = 1, max = 1000000, advanced = true }),
			field("wall_timeout", "Wall timeout (seconds)", "integer", 14400, { min = 10, max = 86400, advanced = true })
		}
	}
end

local function build_storage_repair(options, context)
	local schema = storage_repair_schema(context)
	local normalized, err = defaults(schema, options, "storage repair")
	if not normalized then return nil, err end
	local device, device_err = validate_storage_common(normalized, context); if not device then return nil, device_err end
	if device.mounted then return nil, "Repair operations require an unmounted target" end
	normalized.operation, err = enum(normalized.operation, repair_operations, "Repair operation"); if not normalized.operation then return nil, err end
	normalized.force_fsck, err = boolean(normalized.force_fsck, "Force filesystem check"); if normalized.force_fsck == nil then return nil, err end
	normalized.block_size, err = integer(normalized.block_size, 512, 1048576, "Block size"); if not normalized.block_size then return nil, err end
	normalized.passes, err = integer(normalized.passes, 1, 4, "Passes"); if not normalized.passes then return nil, err end
	normalized.max_bad_blocks, err = integer(normalized.max_bad_blocks, 1, 1000000, "Maximum bad blocks"); if not normalized.max_bad_blocks then return nil, err end
	normalized.wall_timeout, err = integer(normalized.wall_timeout, 10, 86400, "Wall timeout"); if not normalized.wall_timeout then return nil, err end
	normalized.device_size, normalized.device_kind, normalized.fs_type, normalized.mounted = device.size, device.kind, device.fs_type or "", false
	local argv, artifacts = {}, {}
	if normalized.operation:match("^fsck_") then
		if not ({ ext2=true, ext3=true, ext4=true })[device.fs_type or ""] then return nil, "e2fsck repair requires an ext2/ext3/ext4 target" end
		argv = { "/usr/sbin/e2fsck", normalized.operation == "fsck_preen" and "-p" or "-y", "-v" }; if normalized.force_fsck then add(argv, "-f") end; add(argv, normalized.device)
	else
		argv = { "/usr/sbin/badblocks", "-n", "-s", "-v", "-b", tostring(normalized.block_size), "-p", tostring(normalized.passes), "-e", tostring(normalized.max_bad_blocks), "-o", "@ARTIFACT@/storage-badblocks.txt", normalized.device }
		artifacts = { { name = "storage-badblocks.txt", kind = "badblocks_list", content_type = "text/plain", max_size = 1048576, storage = "extroot" } }
	end
	local phrase = "REPAIR STORAGE " .. normalized.device .. " " .. normalized.operation .. " " .. tostring(device.size)
	return { action_id = schema.action_id, worker = "phase3_storage", label = "Storage " .. normalized.operation, class = "DISRUPTIVE", resource = "storage-" .. device.disk, singleton = true,
		options = normalized, argv = argv, argv_preview = preview(argv), target_summary = normalized.device .. " / " .. normalized.operation .. " / " .. tostring(device.size) .. " bytes",
		wall_timeout = normalized.wall_timeout, artifacts = artifacts, confirmation = { required = true, phrase = phrase, reason = "This operation writes filesystem metadata or performs a non-destructive read/write media test. Confirm the exact unmounted target and backup state." } }
end

local function storage_image_schema(context)
	local devices = choice_map(context.storage_devices)
	local first_size = context.storage_devices[1] and context.storage_devices[1].size or 1048576
	return {
		action_id = "storage.image", label = "Raw Storage Image / Recovery", class = "ACTION",
		native = { executable = "/bin/dd", version = "BusyBox 1.35.0 dd" },
		fields = {
			field("device", "Unmounted non-system source", "enum", devices[1] and devices[1].value or "", { options = devices }),
			field("offset", "Source byte offset", "integer", 0, { min = 0, max = 34359738368, advanced = true }),
			field("length", "Bytes to image", "integer", math.min(first_size, 17179869184), { min = 1, max = 17179869184 }),
			field("block_size", "Copy block size", "enum", "1M", { options = { "64K", "256K", "1M", "4M" }, advanced = true }),
			field("continue_errors", "Continue after read errors with zero padding", "boolean", true, { advanced = true }),
			field("direct", "Use direct input I/O", "boolean", false, { advanced = true }),
			field("sha256", "Create SHA-256 companion artifact", "boolean", true, { advanced = true }),
			field("wall_timeout", "Wall timeout (seconds)", "integer", 14400, { min = 10, max = 86400, advanced = true })
		}
	}
end

local function build_storage_image(options, context)
	local schema = storage_image_schema(context)
	local normalized, err = defaults(schema, options, "storage image")
	if not normalized then return nil, err end
	local device, device_err = validate_storage_common(normalized, context); if not device then return nil, device_err end
	if device.mounted then return nil, "Raw imaging requires an unmounted source" end
	normalized.offset, err = integer(normalized.offset, 0, 34359738368, "Source offset"); if normalized.offset == nil then return nil, err end
	normalized.length, err = integer(normalized.length, 1, 17179869184, "Image length"); if not normalized.length then return nil, err end
	if normalized.offset + normalized.length > device.size then return nil, "Image offset plus length exceeds the selected target size" end
	normalized.block_size, err = enum(normalized.block_size, { "64K", "256K", "1M", "4M" }, "Block size"); if not normalized.block_size then return nil, err end
	for _, name in ipairs({ "continue_errors", "direct", "sha256" }) do normalized[name], err = boolean(normalized[name], name); if normalized[name] == nil then return nil, err end end
	normalized.wall_timeout, err = integer(normalized.wall_timeout, 10, 86400, "Wall timeout"); if not normalized.wall_timeout then return nil, err end
	normalized.device_size, normalized.device_kind, normalized.fs_type, normalized.mounted = device.size, device.kind, device.fs_type or "", false
	local input_flags = "skip_bytes,count_bytes,fullblock" .. (normalized.direct and ",direct" or "")
	local argv = { "/bin/dd", "if=" .. normalized.device, "of=@ARTIFACT@/storage-image.raw", "bs=" .. normalized.block_size, "skip=" .. normalized.offset, "count=" .. normalized.length, "iflag=" .. input_flags }
	if normalized.continue_errors then add(argv, "conv=noerror,sync") end
	local artifacts = { { name = "storage-image.raw", kind = "storage_image", content_type = "application/octet-stream", max_size = normalized.length, storage = "extroot" } }
	if normalized.sha256 then artifacts[#artifacts + 1] = { name = "storage-image.sha256", kind = "checksum", content_type = "text/plain", max_size = 256, storage = "tmp" } end
	return { action_id = schema.action_id, worker = "phase3_storage", label = "Raw image read", class = "ACTION", resource = "storage-" .. device.disk, singleton = true,
		options = normalized, argv = argv, argv_preview = preview(argv), target_summary = normalized.device .. " / offset " .. normalized.offset .. " / " .. normalized.length .. " bytes",
		wall_timeout = normalized.wall_timeout, artifacts = artifacts, confirmation = { required = false } }
end

local function storage_restore_schema(context)
	local devices = choice_map(context.storage_devices)
	local uploads = upload_choices(context, "storage_image")
	return {
		action_id = "storage.restore", label = "Raw Storage Restore", class = "DISRUPTIVE",
		native = { executable = "/bin/dd", version = "BusyBox 1.35.0 dd" },
		fields = {
			field("device", "Unmounted non-system destination", "enum", devices[1] and devices[1].value or "", { options = devices }),
			field("upload", "Sealed raw image", "enum", "", { options = uploads }),
			field("offset", "Destination byte offset", "integer", 0, { min = 0, max = 34359738368, advanced = true }),
			field("block_size", "Copy block size", "enum", "1M", { options = { "64K", "256K", "1M", "4M" }, advanced = true }),
			field("direct", "Use direct output I/O", "boolean", false, { advanced = true }),
			field("verify", "Compare written bytes (offset must be zero)", "boolean", true, { advanced = true }),
			field("wall_timeout", "Wall timeout (seconds)", "integer", 14400, { min = 10, max = 86400, advanced = true })
		}
	}
end

local function build_storage_restore(options, context)
	local schema = storage_restore_schema(context)
	local normalized, err = defaults(schema, options, "storage restore")
	if not normalized then return nil, err end
	local device, device_err = validate_storage_common(normalized, context); if not device then return nil, device_err end
	if device.mounted then return nil, "Raw restore requires an unmounted destination" end
	local _, uploads = upload_choices(context, "storage_image")
	local upload = uploads[normalized.upload]; if not upload then return nil, "Raw restore requires a sealed storage_image upload" end
	normalized.offset, err = integer(normalized.offset, 0, 34359738368, "Destination offset"); if normalized.offset == nil then return nil, err end
	if normalized.offset + upload.size > device.size then return nil, "Image plus destination offset exceeds the selected target size" end
	normalized.block_size, err = enum(normalized.block_size, { "64K", "256K", "1M", "4M" }, "Block size"); if not normalized.block_size then return nil, err end
	normalized.direct, err = boolean(normalized.direct, "Direct I/O"); if normalized.direct == nil then return nil, err end
	normalized.verify, err = boolean(normalized.verify, "Verify"); if normalized.verify == nil then return nil, err end
	if normalized.verify and normalized.offset ~= 0 then return nil, "Native bounded cmp verification is available only for offset zero" end
	normalized.wall_timeout, err = integer(normalized.wall_timeout, 10, 86400, "Wall timeout"); if not normalized.wall_timeout then return nil, err end
	normalized.device_size, normalized.image_size, normalized.image_sha256, normalized.device_kind, normalized.mounted = device.size, upload.size, upload.sha256, device.kind, false
	local output_flags = "seek_bytes" .. (normalized.direct and ",direct" or "")
	local argv = { "/bin/dd", "if=@UPLOAD@/" .. normalized.upload, "of=" .. normalized.device, "bs=" .. normalized.block_size, "seek=" .. normalized.offset, "oflag=" .. output_flags, "conv=notrunc,fsync" }
	local phrase = "RESTORE STORAGE " .. normalized.device .. " " .. tostring(device.size) .. " " .. normalized.upload .. " " .. upload.sha256
	return { action_id = schema.action_id, worker = "phase3_storage", label = "Raw storage restore", class = "DISRUPTIVE", resource = "storage-" .. device.disk, singleton = true,
		options = normalized, argv = argv, argv_preview = preview(argv), target_summary = normalized.device .. " / " .. tostring(device.size) .. " bytes / image " .. tostring(upload.size),
		wall_timeout = normalized.wall_timeout, artifacts = {}, input_uploads = upload_binding(normalized.upload, "storage_image"),
		confirmation = { required = true, phrase = phrase, reason = "This will overwrite bytes on the exact selected unmounted destination. The phrase binds device size, upload ID, and SHA-256." } }
end

local function squashfs_schema(context)
	local uploads = upload_choices(context, "storage_image")
	return {
		action_id = "storage.squashfs", label = "SquashFS Recovery", class = "ACTION",
		native = { executable = "/usr/sbin/unsquashfs", version = "unsquashfs 4.5" },
		fields = {
			field("upload", "Sealed SquashFS image", "enum", "", { options = uploads }),
			field("operation", "Operation", "enum", "stat", { options = { "stat", "list", "extract" } }),
			field("paths", "Exact relative paths (empty = all)", "target_list", {}, { rows = 5, placeholder = "etc/config/network\nwww/index.html", show_when = { field = "operation", equals = "extract" } }),
			field("max_depth", "Listing/extraction maximum depth (0 = unlimited)", "integer", 0, { min = 0, max = 64, advanced = true }),
			field("output_limit_mib", "Extraction/archive ceiling (MiB)", "integer", 512, { min = 1, max = 8192, advanced = true }),
			field("wall_timeout", "Wall timeout (seconds)", "integer", 1800, { min = 10, max = 28800, advanced = true })
		}
	}
end

local function build_squashfs(options, context)
	local schema = squashfs_schema(context)
	local normalized, err = defaults(schema, options, "SquashFS recovery")
	if not normalized then return nil, err end
	local _, uploads = upload_choices(context, "storage_image")
	if not uploads[normalized.upload] then return nil, "SquashFS recovery requires a sealed storage_image upload" end
	normalized.operation, err = enum(normalized.operation, { "stat", "list", "extract" }, "SquashFS operation"); if not normalized.operation then return nil, err end
	normalized.paths, err = dense_paths(normalized.paths, "Recovery paths"); if not normalized.paths then return nil, err end
	normalized.max_depth, err = integer(normalized.max_depth, 0, 64, "Maximum depth"); if normalized.max_depth == nil then return nil, err end
	normalized.output_limit_mib, err = integer(normalized.output_limit_mib, 1, 8192, "Output limit"); if not normalized.output_limit_mib then return nil, err end
	normalized.wall_timeout, err = integer(normalized.wall_timeout, 10, 28800, "Wall timeout"); if not normalized.wall_timeout then return nil, err end
	if normalized.operation ~= "extract" and #normalized.paths > 0 then return nil, "Exact recovery paths are accepted only for extraction" end
	local argv = { "/usr/sbin/unsquashfs", "-no-xattrs", "-no-progress", "-strict-errors", "-processors", "1", "-data-queue", "4", "-frag-queue", "4" }
	if normalized.max_depth > 0 then add(argv, "-max-depth"); add(argv, normalized.max_depth) end
	local artifacts, workspaces = {}, {}
	if normalized.operation == "stat" then add(argv, "-stat")
	elseif normalized.operation == "list" then add(argv, "-lln")
	else add(argv, "-no-wildcards"); add(argv, "-d"); add(argv, "@WORK@/squashfs-recovery") end
	add(argv, "@UPLOAD@/" .. normalized.upload)
	if normalized.operation == "extract" then
		for _, path in ipairs(normalized.paths) do add(argv, path) end
		local maximum = normalized.output_limit_mib * 1048576
		artifacts = { { name = "recovered-files.tar", kind = "recovered_files", content_type = "application/x-tar", max_size = maximum, storage = "extroot" } }
		workspaces = { { name = "squashfs-recovery", storage = "extroot", reserve_size = maximum } }
	end
	return { action_id = schema.action_id, worker = "phase3_squashfs", label = "SquashFS " .. normalized.operation, class = "ACTION", resource = "storage-recovery", singleton = true,
		options = normalized, argv = argv, argv_preview = preview(argv), target_summary = normalized.upload .. " / " .. normalized.operation,
		wall_timeout = normalized.wall_timeout, artifacts = artifacts, workspaces = workspaces, input_uploads = upload_binding(normalized.upload, "storage_image"), confirmation = { required = false } }
end

local schemas = {
	["firmware.openocd"] = openocd_schema,
	["firmware.avrdude"] = avrdude_schema,
	["firmware.dfu"] = dfu_schema,
	["firmware.serial"] = firmware_serial_schema,
	["storage.inspect"] = storage_inspect_schema,
	["storage.repair"] = storage_repair_schema,
	["storage.image"] = storage_image_schema,
	["storage.restore"] = storage_restore_schema,
	["storage.squashfs"] = squashfs_schema
}

local builders = {
	["firmware.openocd"] = build_openocd,
	["firmware.avrdude"] = build_avrdude,
	["firmware.dfu"] = build_dfu,
	["firmware.serial"] = build_firmware_serial,
	["storage.inspect"] = build_storage_inspect,
	["storage.repair"] = build_storage_repair,
	["storage.image"] = build_storage_image,
	["storage.restore"] = build_storage_restore,
	["storage.squashfs"] = build_squashfs
}

function M.describe(action_id, context)
	local builder = schemas[action_id]
	if not builder then return nil, "Unknown Phase 3 Operator Mode action" end
	return builder(context or {})
end

function M.prepare(action_id, options, context)
	local builder = builders[action_id]
	if not builder then return nil, "Unknown Phase 3 Operator Mode action" end
	return builder(options, context or {})
end

return M
