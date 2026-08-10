-- Digital Dropkick Field Console Phase 4 Operator Mode schemas.
--
-- Browser values are typed and validated here. Every resulting plan selects an
-- exact installed executable and literal argv; execution and live target
-- revalidation remain in the dedicated Phase 4 worker.

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
	for _, item in ipairs(schema.fields or {}) do
		allowed[item.name] = true
		result[item.name] = type(item.default) == "table" and copy(item.default) or item.default
	end
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

local function multiline(value, label, maximum, required)
	if type(value) ~= "string" then return nil, label .. " must be a string" end
	value = value:gsub("\r\n", "\n"):gsub("\r", "\n")
	if (required and value == "") or #value > maximum or value:find("[%z\1-\8\11\12\14-\31\127]") then
		return nil, label .. " is empty, too long, or contains unsupported control characters"
	end
	return value
end

local function dense_integers(value, minimum, maximum, count, label)
	if type(value) ~= "table" then return nil, label .. " must be a JSON array" end
	local result, seen = {}, {}
	for index, item in ipairs(value) do
		if index > count then return nil, label .. " exceeds " .. tostring(count) .. " entries" end
		local normalized, err = integer(item, minimum, maximum, label .. " item")
		if not normalized then return nil, err end
		if seen[normalized] then return nil, label .. " contains a duplicate" end
		seen[normalized], result[#result + 1] = true, normalized
	end
	for key in pairs(value) do
		if type(key) ~= "number" or key < 1 or key > #result or key ~= math.floor(key) then return nil, label .. " must be a dense JSON array" end
	end
	if #result == 0 then return nil, label .. " requires at least one entry" end
	return result
end

local function choice_map(items)
	local choices, records = {}, {}
	for _, item in ipairs(items or {}) do
		local value = type(item) == "table" and (item.value or item.node or item.address or item.name or item.selector) or nil
		local label = type(item) == "table" and (item.label or value) or nil
		if type(value) == "string" and type(label) == "string" and not records[value] then
			choices[#choices + 1] = { value = value, label = label }
			records[value] = item
		end
	end
	return choices, records
end

local function selected(items, value, label)
	local _, records = choice_map(items)
	if type(value) ~= "string" or not records[value] then return nil, label .. " is not in the reviewed live inventory" end
	return records[value]
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
	value = tostring(value):gsub("@UPLOAD@/[^: ]+", "[SEALED_DDK_UPLOAD]"):gsub("@JOB@/", "[DDK_JOB]/")
	if value:match("^[A-Za-z0-9_./:@%%+=,%[%]-]+$") then return value end
	return "'" .. value:gsub("'", "'\\''") .. "'"
end

local function preview(argv)
	local result = {}
	for _, item in ipairs(argv or {}) do result[#result + 1] = preview_arg(item) end
	return table.concat(result, " ")
end

local function hex(value)
	return (value:gsub(".", function(character) return string.format("%02x", string.byte(character)) end))
end

local function private(name, value)
	return { name = name, hex = hex(value) }
end

local function text_artifact(name, kind, maximum)
	return { name = name, kind = kind, content_type = "text/plain", max_size = maximum, storage = "tmp" }
end

local function validate_host(value, label)
	local host, err = text(value, label, 253, "^[A-Za-z0-9_.:%%-]+$", true)
	if not host then return nil, err end
	if host:sub(1, 1) == "-" or host:find("..", 1, true) then return nil, label .. " is not a valid literal address or hostname" end
	return host
end

-- Monitoring --------------------------------------------------------------

local function monitoring_schema(context)
	local interfaces = choice_map(context.interfaces)
	return { action_id = "monitoring.snapshot", label = "Monitoring Snapshot", class = "INFO",
		native = { executable = "/usr/bin/vnstat", executables = { "/usr/bin/vnstat", "/usr/bin/iftop" }, version = "vnStat 2.9 / iftop 1.0pre4" },
		fields = {
			field("mode", "Snapshot mode", "enum", "history", { options = { "history", "live_flows" } }),
			field("interface", "Live interface", "enum", interfaces[1] and interfaces[1].value or "", { options = interfaces }),
			field("duration", "Live observation seconds", "integer", 10, { min = 2, max = 120, show_when = { field = "mode", equals = "live_flows" } }),
			field("lines", "Maximum flow rows", "integer", 40, { min = 10, max = 200, show_when = { field = "mode", equals = "live_flows" }, advanced = true }),
			field("show_ports", "Show ports", "boolean", true, { show_when = { field = "mode", equals = "live_flows" } })
		}
	}
end

local function build_monitoring(options, context)
	local schema = monitoring_schema(context); local normalized, err = defaults(schema, options, "monitoring")
	if not normalized then return nil, err end
	normalized.mode, err = enum(normalized.mode, { "history", "live_flows" }, "Snapshot mode"); if not normalized.mode then return nil, err end
	local interface = selected(context.interfaces, normalized.interface, "Selected interface"); if not interface then return nil, "Selected interface is not in the live inventory" end
	normalized.duration, err = integer(normalized.duration, 2, 120, "Duration"); if not normalized.duration then return nil, err end
	normalized.lines, err = integer(normalized.lines, 10, 200, "Maximum rows"); if not normalized.lines then return nil, err end
	normalized.show_ports, err = boolean(normalized.show_ports, "Show ports"); if normalized.show_ports == nil then return nil, err end
	local argv
	if normalized.mode == "history" then argv = { "/usr/bin/vnstat", "--iface", normalized.interface, "--json" }
	else
		argv = { "/usr/bin/iftop", "-n", "-N", "-t", "-s", tostring(normalized.duration), "-L", tostring(normalized.lines), "-i", normalized.interface }
		if normalized.show_ports then add(argv, "-P") end
	end
	return { action_id = schema.action_id, worker = "phase4_monitoring", label = "Monitoring " .. normalized.mode, class = "INFO", resource = "monitoring-" .. normalized.interface, singleton = true,
		options = normalized, argv = argv, argv_preview = preview(argv), target_summary = normalized.interface .. " / " .. normalized.mode,
		wall_timeout = normalized.mode == "history" and 15 or normalized.duration + 10, artifacts = { text_artifact("monitoring.txt", "monitoring_snapshot", 1048576) }, input_uploads = {}, confirmation = { required = false } }
end

-- Wireless ---------------------------------------------------------------

local function wireless_schema(context)
	local interfaces = choice_map(context.wireless_interfaces)
	return { action_id = "wireless.survey", label = "Wireless Survey", class = "INFO",
		native = { executable = "/usr/bin/iwinfo", executables = { "/usr/bin/iwinfo", "/usr/sbin/iw" }, version = "iwinfo 2022-12-15 / iw 5.16" },
		fields = {
			field("interface", "Wireless interface", "enum", interfaces[1] and interfaces[1].value or "", { options = interfaces }),
			field("operation", "Operation", "enum", "info", { options = { "info", "scan", "stations" } }),
			field("wall_timeout", "Wall timeout (seconds)", "integer", 30, { min = 5, max = 120, advanced = true })
		}
	}
end

local function build_wireless(options, context)
	local schema = wireless_schema(context); local normalized, err = defaults(schema, options, "wireless survey")
	if not normalized then return nil, err end
	if not selected(context.wireless_interfaces, normalized.interface, "Selected wireless interface") then return nil, "Selected wireless interface is not in the reviewed live inventory" end
	normalized.operation, err = enum(normalized.operation, { "info", "scan", "stations" }, "Wireless operation"); if not normalized.operation then return nil, err end
	normalized.wall_timeout, err = integer(normalized.wall_timeout, 5, 120, "Wall timeout"); if not normalized.wall_timeout then return nil, err end
	local argv = normalized.operation == "stations" and { "/usr/sbin/iw", "dev", normalized.interface, "station", "dump" } or { "/usr/bin/iwinfo", normalized.interface, normalized.operation }
	return { action_id = schema.action_id, worker = "phase4_wireless", label = "Wireless " .. normalized.operation, class = "INFO", resource = "wireless-" .. normalized.interface, singleton = true,
		options = normalized, argv = argv, argv_preview = preview(argv), target_summary = normalized.interface .. " / " .. normalized.operation,
		wall_timeout = normalized.wall_timeout, artifacts = { text_artifact("wireless-survey.txt", "wireless_survey", 1048576) }, input_uploads = {}, confirmation = { required = false } }
end

-- USB inventory -----------------------------------------------------------

local function usb_inventory_schema(context)
	local devices = choice_map(context.usb_devices)
	local with_all = { { value = "", label = "All USB devices" } }; for _, item in ipairs(devices) do with_all[#with_all + 1] = item end
	return { action_id = "usb.inventory", label = "USB Inventory", class = "INFO",
		native = { executable = "/usr/bin/lsusb", version = "usbutils 014" },
		fields = {
			field("operation", "Inventory detail", "enum", "summary", { options = { "summary", "tree", "verbose" } }),
			field("device", "USB device", "enum", "", { options = with_all, show_when = { field = "operation", equals = "verbose" } }),
			field("wall_timeout", "Wall timeout (seconds)", "integer", 20, { min = 5, max = 60, advanced = true })
		}
	}
end

local function build_usb_inventory(options, context)
	local schema = usb_inventory_schema(context); local normalized, err = defaults(schema, options, "USB inventory")
	if not normalized then return nil, err end
	normalized.operation, err = enum(normalized.operation, { "summary", "tree", "verbose" }, "Inventory detail"); if not normalized.operation then return nil, err end
	normalized.wall_timeout, err = integer(normalized.wall_timeout, 5, 60, "Wall timeout"); if not normalized.wall_timeout then return nil, err end
	local argv = { "/usr/bin/lsusb" }
	if normalized.operation == "tree" then add(argv, "-t")
	elseif normalized.operation == "verbose" then
		add(argv, "-v")
		if normalized.device ~= "" then
			local device = selected(context.usb_devices, normalized.device, "Selected USB device"); if not device then return nil, "Selected USB device is not in the reviewed inventory" end
			add(argv, "-d"); add(argv, device.usb_id)
		end
	elseif normalized.device ~= "" then return nil, "USB device selection is accepted only for verbose inventory" end
	return { action_id = schema.action_id, worker = "phase4_usb", label = "USB " .. normalized.operation, class = "INFO", resource = "usb-inventory", singleton = true,
		options = normalized, argv = argv, argv_preview = preview(argv), target_summary = normalized.device ~= "" and normalized.device or "all USB devices",
		wall_timeout = normalized.wall_timeout, artifacts = { text_artifact("usb-inventory.txt", "usb_inventory", 1048576) }, input_uploads = {}, confirmation = { required = false } }
end

-- Forensics ---------------------------------------------------------------

local function forensics_schema(context)
	local inputs = upload_choices(context, "forensics_input")
	return { action_id = "forensics.inspect_file", label = "Forensic File Inspection", class = "SECURITY",
		native = { executable = "/usr/bin/file", executables = { "/usr/bin/file", "/usr/bin/hashdeep", "/usr/bin/ssdeep", "/usr/bin/checksec", "/usr/bin/yara" }, version = "file 5.41 / hashdeep 4.4 / ssdeep 2.14.1 / checksec 2.5.0 / YARA 4.1.3" },
		fields = {
			field("input", "Sealed file", "enum", "", { options = inputs }),
			field("operation", "Analysis", "enum", "identify", { options = { "identify", "hashes", "similarity", "checksec", "yara" } }),
			field("rules", "Sealed YARA rules", "enum", "", { options = inputs, show_when = { field = "operation", equals = "yara" } }),
			field("yara_strings", "Include matching strings", "boolean", false, { show_when = { field = "operation", equals = "yara" }, advanced = true }),
			field("yara_max_rules", "Maximum YARA matches", "integer", 100, { min = 1, max = 1000, show_when = { field = "operation", equals = "yara" }, advanced = true }),
			field("wall_timeout", "Wall timeout (seconds)", "integer", 120, { min = 5, max = 1800, advanced = true })
		}
	}
end

local function build_forensics(options, context)
	local schema = forensics_schema(context); local normalized, err = defaults(schema, options, "forensics")
	if not normalized then return nil, err end
	local _, uploads = upload_choices(context, "forensics_input")
	if not uploads[normalized.input] then return nil, "Forensic inspection requires a sealed forensics_input upload" end
	normalized.operation, err = enum(normalized.operation, { "identify", "hashes", "similarity", "checksec", "yara" }, "Analysis"); if not normalized.operation then return nil, err end
	normalized.yara_strings, err = boolean(normalized.yara_strings, "YARA strings"); if normalized.yara_strings == nil then return nil, err end
	normalized.yara_max_rules, err = integer(normalized.yara_max_rules, 1, 1000, "Maximum YARA matches"); if not normalized.yara_max_rules then return nil, err end
	normalized.wall_timeout, err = integer(normalized.wall_timeout, 5, 1800, "Wall timeout"); if not normalized.wall_timeout then return nil, err end
	local target = "@UPLOAD@/" .. normalized.input
	local argv, input_uploads = {}, { { id = normalized.input, kind = "forensics_input" } }
	if normalized.operation == "identify" then argv = { "/usr/bin/file", "-b", "-k", "-i", target }
	elseif normalized.operation == "hashes" then argv = { "/usr/bin/hashdeep", "-c", "md5,sha1,sha256", "-b", target }
	elseif normalized.operation == "similarity" then argv = { "/usr/bin/ssdeep", "-b", target }
	elseif normalized.operation == "checksec" then argv = { "/usr/bin/checksec", "--format=json", "--file=" .. target }
	else
		if not uploads[normalized.rules] or normalized.rules == normalized.input then return nil, "YARA requires a separate sealed rules input" end
		input_uploads[#input_uploads + 1] = { id = normalized.rules, kind = "forensics_input" }
		argv = { "/usr/bin/yara", "--no-warnings", "--threads=1", "--timeout=" .. tostring(math.min(normalized.wall_timeout, 300)), "--max-rules=" .. tostring(normalized.yara_max_rules) }
		if normalized.yara_strings then add(argv, "--print-strings") end
		add(argv, "@UPLOAD@/" .. normalized.rules); add(argv, target)
	end
	if normalized.operation ~= "yara" and normalized.rules ~= "" then return nil, "YARA rules are accepted only for a YARA analysis" end
	return { action_id = schema.action_id, worker = "phase4_forensics", label = "Forensics " .. normalized.operation, class = "SECURITY", resource = "forensics", singleton = true,
		options = normalized, argv = argv, argv_preview = preview(argv), target_summary = normalized.input .. " / " .. normalized.operation,
		wall_timeout = normalized.wall_timeout, artifacts = { text_artifact("forensics-report.txt", "forensics_report", 2097152) }, input_uploads = input_uploads, confirmation = { required = false } }
end

-- Packet replay -----------------------------------------------------------

local function replay_schema(context)
	local interfaces = choice_map(context.interfaces); local uploads = upload_choices(context, "capture_input")
	return { action_id = "capture.replay", label = "Authenticated Packet Replay", class = "DISRUPTIVE",
		native = { executable = "/usr/bin/tcpreplay", version = "tcpreplay 4.4.1" },
		fields = {
			field("input", "Sealed PCAP", "enum", "", { options = uploads }),
			field("interface", "Output interface", "enum", interfaces[1] and interfaces[1].value or "", { options = interfaces }),
			field("loop", "Replay loops", "integer", 1, { min = 1, max = 1000 }),
			field("packet_limit", "Maximum packets (0 = native file count)", "integer", 10000, { min = 0, max = 1000000 }),
			field("duration", "Maximum replay seconds", "integer", 60, { min = 1, max = 3600 }),
			field("speed", "Replay speed", "enum", "original", { options = { "original", "multiplier", "pps", "mbps", "topspeed" } }),
			field("rate", "Speed value", "number", 1, { min = 0.001, max = 1000000, show_when = { field = "speed", not_equals = "original" } }),
			field("wall_timeout", "Wall timeout (seconds)", "integer", 120, { min = 10, max = 7200, advanced = true })
		}
	}
end

local function build_replay(options, context)
	local schema = replay_schema(context); local normalized, err = defaults(schema, options, "packet replay")
	if not normalized then return nil, err end
	local _, uploads = upload_choices(context, "capture_input"); if not uploads[normalized.input] then return nil, "Packet replay requires a sealed capture_input upload" end
	if not selected(context.interfaces, normalized.interface, "Selected output interface") then return nil, "Selected replay interface is not in the live inventory" end
	normalized.loop, err = integer(normalized.loop, 1, 1000, "Replay loops"); if not normalized.loop then return nil, err end
	normalized.packet_limit, err = integer(normalized.packet_limit, 0, 1000000, "Packet limit"); if normalized.packet_limit == nil then return nil, err end
	normalized.duration, err = integer(normalized.duration, 1, 3600, "Replay duration"); if not normalized.duration then return nil, err end
	normalized.speed, err = enum(normalized.speed, { "original", "multiplier", "pps", "mbps", "topspeed" }, "Replay speed"); if not normalized.speed then return nil, err end
	normalized.rate, err = number(normalized.rate, 0.001, 1000000, "Speed value"); if not normalized.rate then return nil, err end
	normalized.wall_timeout, err = integer(normalized.wall_timeout, 10, 7200, "Wall timeout"); if not normalized.wall_timeout then return nil, err end
	local argv = { "/usr/bin/tcpreplay", "--quiet", "--intf1=" .. normalized.interface, "--loop=" .. tostring(normalized.loop), "--duration=" .. tostring(normalized.duration) }
	if normalized.packet_limit > 0 then add(argv, "--limit=" .. tostring(normalized.packet_limit)) end
	if normalized.speed == "multiplier" then add(argv, "--multiplier=" .. tostring(normalized.rate))
	elseif normalized.speed == "pps" then add(argv, "--pps=" .. tostring(normalized.rate))
	elseif normalized.speed == "mbps" then add(argv, "--mbps=" .. tostring(normalized.rate))
	elseif normalized.speed == "topspeed" then add(argv, "--topspeed") end
	add(argv, "@UPLOAD@/" .. normalized.input)
	local phrase = "REPLAY " .. normalized.input .. " ON " .. normalized.interface
	return { action_id = schema.action_id, worker = "phase4_replay", label = "Packet Replay", class = "DISRUPTIVE", resource = "interface-" .. normalized.interface, singleton = true,
		options = normalized, argv = argv, argv_preview = preview(argv), target_summary = normalized.interface .. " / " .. normalized.input,
		wall_timeout = normalized.wall_timeout, artifacts = {}, input_uploads = { { id = normalized.input, kind = "capture_input" } },
		confirmation = { required = true, phrase = phrase, reason = "This transmits every selected PCAP packet through the exact live interface. Confirm authorization, topology, rate, packet limit, and that replay cannot affect production or management traffic." } }
end

-- ADS-B and AIS -----------------------------------------------------------

local function adsb_schema(context)
	local devices = choice_map(context.rtl_devices)
	return { action_id = "adsb.receive", label = "ADS-B Receiver", class = "ACTION",
		native = { executable = "/usr/bin/readsb", version = "readsb 3.9.0" },
		fields = {
			field("device", "Reviewed RTL-SDR", "enum", devices[1] and devices[1].value or "", { options = devices }),
			field("frequency", "Frequency (Hz)", "integer", 1090000000, { min = 24000000, max = 1766000000 }),
			field("gain", "Tuner gain dB (-10 = auto)", "number", -10, { min = -10, max = 49.6 }),
			field("ppm", "Frequency correction PPM", "integer", 0, { min = -1000, max = 1000 }),
			field("output", "Decoded output", "enum", "raw", { options = { "raw", "addresses", "stats" } }),
			field("mode_ac", "Decode Mode A/C", "boolean", false, { advanced = true }),
			field("metric", "Metric units", "boolean", true, { advanced = true }),
			field("duration", "Receive duration (seconds)", "integer", 60, { min = 10, max = 3600 })
		}
	}
end

local function build_adsb(options, context)
	local schema = adsb_schema(context); local normalized, err = defaults(schema, options, "ADS-B")
	if not normalized then return nil, err end
	local device = selected(context.rtl_devices, normalized.device, "Selected RTL-SDR"); if not device then return nil, "Selected RTL-SDR is not in the reviewed live inventory" end
	normalized.frequency, err = integer(normalized.frequency, 24000000, 1766000000, "Frequency"); if not normalized.frequency then return nil, err end
	normalized.gain, err = number(normalized.gain, -10, 49.6, "Gain"); if not normalized.gain then return nil, err end
	normalized.ppm, err = integer(normalized.ppm, -1000, 1000, "PPM correction"); if normalized.ppm == nil then return nil, err end
	normalized.output, err = enum(normalized.output, { "raw", "addresses", "stats" }, "Decoded output"); if not normalized.output then return nil, err end
	normalized.mode_ac, err = boolean(normalized.mode_ac, "Mode A/C"); if normalized.mode_ac == nil then return nil, err end
	normalized.metric, err = boolean(normalized.metric, "Metric"); if normalized.metric == nil then return nil, err end
	normalized.duration, err = integer(normalized.duration, 10, 3600, "Duration"); if not normalized.duration then return nil, err end
	normalized.device_topology, normalized.device_usb_id, normalized.device_serial = device.topology or "", device.usb_id or "", device.serial or ""
	local argv = { "/usr/bin/readsb", "--device-type=rtlsdr", "--device=" .. normalized.device, "--freq=" .. tostring(normalized.frequency), "--gain=" .. tostring(normalized.gain), "--ppm=" .. tostring(normalized.ppm), "--no-interactive" }
	if normalized.output == "raw" then add(argv, "--raw") elseif normalized.output == "addresses" then add(argv, "--onlyaddr") else add(argv, "--stats-every=" .. tostring(math.max(5, math.min(60, normalized.duration)))) end
	if normalized.mode_ac then add(argv, "--modeac") end; if normalized.metric then add(argv, "--metric") end
	return { action_id = schema.action_id, worker = "phase4_adsb", label = "ADS-B Receive", class = "ACTION", resource = "rtl-sdr", singleton = true,
		options = normalized, argv = argv, argv_preview = preview(argv), target_summary = normalized.device .. " / " .. tostring(normalized.frequency) .. " Hz",
		wall_timeout = normalized.duration, artifacts = { text_artifact("adsb.txt", "adsb_decode", 2097152) }, input_uploads = {}, confirmation = { required = false } }
end

local function ais_schema(context)
	local devices = choice_map(context.rtl_devices)
	return { action_id = "radio.ais", label = "AIS Receiver", class = "ACTION",
		native = { executable = "/usr/bin/rtl_ais", version = "rtl-ais 0.3" },
		fields = {
			field("device", "Reviewed RTL-SDR", "enum", devices[1] and devices[1].value or "", { options = devices }),
			field("left_frequency", "Left frequency (Hz)", "integer", 161975000, { min = 24000000, max = 1766000000 }),
			field("right_frequency", "Right frequency (Hz)", "integer", 162025000, { min = 24000000, max = 1766000000 }),
			field("sample_rate", "Decoder sample rate", "integer", 24000, { min = 12000, max = 192000 }),
			field("output_rate", "Output rate", "integer", 48000, { min = 24000, max = 384000 }),
			field("gain", "Tuner gain (0 = automatic)", "number", 0, { min = 0, max = 49.6 }),
			field("ppm", "Frequency correction PPM", "integer", 0, { min = -1000, max = 1000 }),
			field("duration", "Receive duration (seconds)", "integer", 60, { min = 10, max = 3600 })
		}
	}
end

local function build_ais(options, context)
	local schema = ais_schema(context); local normalized, err = defaults(schema, options, "AIS")
	if not normalized then return nil, err end
	local device = selected(context.rtl_devices, normalized.device, "Selected RTL-SDR"); if not device then return nil, "Selected RTL-SDR is not in the reviewed live inventory" end
	for _, item in ipairs({ { "left_frequency", 24000000, 1766000000, "Left frequency" }, { "right_frequency", 24000000, 1766000000, "Right frequency" }, { "sample_rate", 12000, 192000, "Sample rate" }, { "output_rate", 24000, 384000, "Output rate" }, { "ppm", -1000, 1000, "PPM correction" }, { "duration", 10, 3600, "Duration" } }) do
		normalized[item[1]], err = integer(normalized[item[1]], item[2], item[3], item[4]); if normalized[item[1]] == nil then return nil, err end
	end
	normalized.gain, err = number(normalized.gain, 0, 49.6, "Gain"); if not normalized.gain then return nil, err end
	if normalized.left_frequency >= normalized.right_frequency or normalized.right_frequency - normalized.left_frequency > 1200000 then return nil, "AIS frequencies must be ascending and within 1.2 MHz" end
	if normalized.output_rate < normalized.sample_rate * 2 then return nil, "AIS output rate must be at least twice the decoder sample rate" end
	normalized.device_topology, normalized.device_usb_id, normalized.device_serial = device.topology or "", device.usb_id or "", device.serial or ""
	local argv = { "/usr/bin/rtl_ais", "-d", normalized.device, "-l", tostring(normalized.left_frequency), "-r", tostring(normalized.right_frequency), "-s", tostring(normalized.sample_rate), "-o", tostring(normalized.output_rate), "-p", tostring(normalized.ppm), "-h", "127.0.0.1", "-P", "10110", "-n" }
	if normalized.gain > 0 then add(argv, "-g"); add(argv, normalized.gain) end
	return { action_id = schema.action_id, worker = "phase4_ais", label = "AIS Receive", class = "ACTION", resource = "rtl-sdr", singleton = true,
		options = normalized, argv = argv, argv_preview = preview(argv), target_summary = normalized.device .. " / AIS1 + AIS2",
		wall_timeout = normalized.duration, artifacts = { text_artifact("ais-nmea.txt", "ais_nmea", 2097152) }, input_uploads = {}, confirmation = { required = false } }
end

-- Bluetooth ---------------------------------------------------------------

local function bluetooth_schema(context)
	local devices = choice_map(context.bluetooth_devices)
	return { action_id = "bluetooth.scan", label = "Bluetooth Discovery", class = "SECURITY",
		native = { executable = "/usr/bin/hcitool", version = "BlueZ 5.64" },
		fields = {
			field("controller", "Active HCI controller", "enum", devices[1] and devices[1].value or "", { options = devices }),
			field("mode", "Discovery mode", "enum", "classic", { options = { "classic", "le" } }),
			field("duration", "Discovery duration (seconds)", "integer", 20, { min = 5, max = 120 })
		}
	}
end

local function build_bluetooth(options, context)
	local schema = bluetooth_schema(context); local normalized, err = defaults(schema, options, "Bluetooth")
	if not normalized then return nil, err end
	local controller = selected(context.bluetooth_devices, normalized.controller, "Selected HCI controller"); if not controller then return nil, "Selected HCI controller is not active in the reviewed inventory" end
	normalized.mode, err = enum(normalized.mode, { "classic", "le" }, "Discovery mode"); if not normalized.mode then return nil, err end
	normalized.duration, err = integer(normalized.duration, 5, 120, "Duration"); if not normalized.duration then return nil, err end
	local argv = { "/usr/bin/hcitool", "-i", normalized.controller, normalized.mode == "classic" and "scan" or "lescan" }
	return { action_id = schema.action_id, worker = "phase4_bluetooth", label = "Bluetooth " .. normalized.mode .. " discovery", class = "SECURITY", resource = "bluetooth-" .. normalized.controller, singleton = true,
		options = normalized, argv = argv, argv_preview = preview(argv), target_summary = normalized.controller .. " / " .. normalized.mode,
		wall_timeout = normalized.duration, artifacts = { text_artifact("bluetooth-scan.txt", "bluetooth_discovery", 524288) }, input_uploads = {}, confirmation = { required = false } }
end

-- MQTT and relay ----------------------------------------------------------

local function mqtt_schema()
	return { action_id = "automation.mqtt_publish", label = "MQTT Publish", class = "ACTION",
		native = { executable = "/usr/bin/mosquitto_pub", version = "mosquitto_pub 2.0.15" },
		fields = {
			field("host", "Broker host", "text", "", { required = true, placeholder = "broker.example.net" }),
			field("port", "Broker port", "integer", 1883, { min = 1, max = 65535 }),
			field("tls", "Use TLS with OS certificates", "boolean", false),
			field("topic", "Publish topic", "text", "", { required = true, placeholder = "service/device/event" }),
			field("payload", "Message payload", "multiline", "", { required = true, rows = 4 }),
			field("qos", "QoS", "enum", "0", { options = { "0", "1", "2" } }),
			field("retain", "Retain message", "boolean", false),
			field("protocol", "MQTT protocol", "enum", "mqttv311", { options = { "mqttv31", "mqttv311", "mqttv5" }, advanced = true }),
			field("username", "Username (optional)", "text", "", { advanced = true }),
			field("password", "Password (not retained)", "secret", "", { advanced = true }),
			field("repeat_count", "Publish count", "integer", 1, { min = 1, max = 100, advanced = true }),
			field("repeat_delay", "Delay between publishes (seconds)", "number", 0, { min = 0, max = 60, advanced = true }),
			field("wall_timeout", "Wall timeout (seconds)", "integer", 30, { min = 5, max = 600, advanced = true })
		}
	}
end

local function build_mqtt(options)
	local schema = mqtt_schema(); local normalized, err = defaults(schema, options, "MQTT")
	if not normalized then return nil, err end
	local password = normalized.password
	normalized.host, err = validate_host(normalized.host, "Broker host"); if not normalized.host then return nil, err end
	normalized.port, err = integer(normalized.port, 1, 65535, "Broker port"); if not normalized.port then return nil, err end
	normalized.tls, err = boolean(normalized.tls, "TLS"); if normalized.tls == nil then return nil, err end
	normalized.topic, err = text(normalized.topic, "Publish topic", 512, "^[A-Za-z0-9_./:%-]+$", true); if not normalized.topic then return nil, err end
	if normalized.topic:find("#", 1, true) or normalized.topic:find("+", 1, true) or normalized.topic:sub(1, 1) == "/" then return nil, "Publish topic must be a concrete non-root topic" end
	local payload; payload, err = multiline(normalized.payload, "Payload", 8192, true); if not payload then return nil, err end
	normalized.qos, err = enum(normalized.qos, { "0", "1", "2" }, "QoS"); if not normalized.qos then return nil, err end
	normalized.retain, err = boolean(normalized.retain, "Retain"); if normalized.retain == nil then return nil, err end
	normalized.protocol, err = enum(normalized.protocol, { "mqttv31", "mqttv311", "mqttv5" }, "MQTT protocol"); if not normalized.protocol then return nil, err end
	normalized.username, err = text(normalized.username, "Username", 256, "^[A-Za-z0-9_.@:%+/-]+$", false); if normalized.username == nil then return nil, err end
	password, err = text(password, "Password", 256, nil, false); if password == nil then return nil, err end
	if (normalized.username == "") ~= (password == "") then return nil, "MQTT username and password must be supplied together" end
	normalized.repeat_count, err = integer(normalized.repeat_count, 1, 100, "Publish count"); if not normalized.repeat_count then return nil, err end
	normalized.repeat_delay, err = number(normalized.repeat_delay, 0, 60, "Repeat delay"); if normalized.repeat_delay == nil then return nil, err end
	normalized.wall_timeout, err = integer(normalized.wall_timeout, 5, 600, "Wall timeout"); if not normalized.wall_timeout then return nil, err end
	local argv = { "/usr/bin/mosquitto_pub", "-h", normalized.host, "-p", tostring(normalized.port), "-t", normalized.topic, "-q", normalized.qos, "-V", normalized.protocol, "--repeat", tostring(normalized.repeat_count), "--repeat-delay", tostring(normalized.repeat_delay), "-s" }
	if normalized.tls then add(argv, "--tls-use-os-certs") end; if normalized.retain then add(argv, "-r") end
	if normalized.username ~= "" then add(argv, "-u"); add(argv, normalized.username) end
	local private_inputs = { private("mqtt-payload", payload) }
	if password ~= "" then private_inputs[#private_inputs + 1] = private("mqtt-password", password); add(argv, "-P"); add(argv, "[PRIVATE_MQTT_PASSWORD]") end
	normalized.payload = "[PRIVATE " .. tostring(#payload) .. " BYTES]"; normalized.password = password ~= "" and "[REDACTED]" or ""
	local shown = copy(argv); for index, item in ipairs(shown) do if item == "[PRIVATE_MQTT_PASSWORD]" then shown[index] = "[PRIVATE]" end end
	local phrase = normalized.retain and ("PUBLISH RETAINED MQTT " .. normalized.topic .. " TO " .. normalized.host .. ":" .. tostring(normalized.port)) or nil
	return { action_id = schema.action_id, worker = "phase4_mqtt", label = "MQTT Publish", class = "ACTION", resource = "mqtt", singleton = true,
		options = normalized, private_inputs = private_inputs, argv = argv, argv_preview = preview(shown) .. " < [PRIVATE_PAYLOAD]", target_summary = normalized.host .. ":" .. tostring(normalized.port) .. " / " .. normalized.topic,
		wall_timeout = normalized.wall_timeout, artifacts = {}, input_uploads = {}, confirmation = phrase and { required = true, phrase = phrase, reason = "A retained MQTT publish changes broker state and may affect subscribed automation. Confirm the exact broker and topic." } or { required = false } }
end

local function relay_schema(context)
	local devices = choice_map(context.relay_devices)
	return { action_id = "automation.relay", label = "USB Relay Control", class = "DISRUPTIVE",
		native = { executable = "/usr/bin/crelay", version = "crelay 0.14" },
		fields = {
			field("device", "Reviewed relay controller", "enum", devices[1] and devices[1].value or "", { options = devices }),
			field("relay", "Relay channel", "integer", 1, { min = 1, max = 16 }),
			field("operation", "Operation", "enum", "status", { options = { "status", "on", "off" } }),
			field("wall_timeout", "Wall timeout (seconds)", "integer", 15, { min = 5, max = 60, advanced = true })
		}
	}
end

local function build_relay(options, context)
	local schema = relay_schema(context); local normalized, err = defaults(schema, options, "relay")
	if not normalized then return nil, err end
	local device = selected(context.relay_devices, normalized.device, "Selected relay controller"); if not device then return nil, "Selected relay controller is not in the reviewed live inventory" end
	normalized.relay, err = integer(normalized.relay, 1, math.min(16, tonumber(device.relays) or 16), "Relay channel"); if not normalized.relay then return nil, err end
	normalized.operation, err = enum(normalized.operation, { "status", "on", "off" }, "Relay operation"); if not normalized.operation then return nil, err end
	normalized.wall_timeout, err = integer(normalized.wall_timeout, 5, 60, "Wall timeout"); if not normalized.wall_timeout then return nil, err end
	local argv = { "/usr/bin/crelay", "-s", normalized.device, tostring(normalized.relay) }; if normalized.operation ~= "status" then add(argv, normalized.operation:upper()) end
	local phrase = normalized.operation ~= "status" and ("SET RELAY " .. normalized.device .. " CHANNEL " .. tostring(normalized.relay) .. " " .. normalized.operation:upper()) or nil
	return { action_id = schema.action_id, worker = "phase4_relay", label = "Relay " .. normalized.operation, class = "DISRUPTIVE", resource = "relay-" .. normalized.device, singleton = true,
		options = normalized, argv = argv, argv_preview = preview(argv), target_summary = normalized.device .. " / relay " .. tostring(normalized.relay), wall_timeout = normalized.wall_timeout,
		artifacts = {}, input_uploads = {}, confirmation = phrase and { required = true, phrase = phrase, reason = "This changes a physical relay output. Confirm controller serial, channel wiring, load state, and downstream safety." } or { required = false } }
end

-- Modbus read -------------------------------------------------------------

local function modbus_schema(context)
	local serials = choice_map(context.serial_devices)
	return { action_id = "industrial.modbus_read", label = "Modbus Register Read", class = "ACTION",
		native = { executable = "/usr/bin/mbcollect", version = "mbtools 2014-10-29 / libmodbus 3.1.7" },
		fields = {
			field("transport", "Transport", "enum", "tcp", { options = { "tcp", "rtu" } }),
			field("host", "Modbus TCP host", "text", "127.0.0.1", { show_when = { field = "transport", equals = "tcp" } }),
			field("port", "Modbus TCP port", "integer", 502, { min = 1, max = 65535, show_when = { field = "transport", equals = "tcp" } }),
			field("device", "Reviewed non-EC25 serial port", "enum", serials[1] and serials[1].value or "", { options = serials, show_when = { field = "transport", equals = "rtu" } }),
			field("baud", "RTU baud", "enum", "19200", { options = { "1200", "2400", "4800", "9600", "19200", "38400", "57600", "115200" }, show_when = { field = "transport", equals = "rtu" } }),
			field("parity", "RTU parity", "enum", "E", { options = { "N", "E", "O" }, show_when = { field = "transport", equals = "rtu" } }),
			field("data_bits", "RTU data bits", "enum", "8", { options = { "7", "8" }, show_when = { field = "transport", equals = "rtu" } }),
			field("stop_bits", "RTU stop bits", "enum", "1", { options = { "1", "2" }, show_when = { field = "transport", equals = "rtu" } }),
			field("unit", "Slave / unit ID", "integer", 1, { min = 1, max = 247 }),
			field("addresses", "Holding-register addresses", "integer_list", { 0 }, { rows = 4 }),
			field("datatype", "Value type", "enum", "int", { options = { "int", "floatlsb", "floatmsb" } }),
			field("interval", "Poll interval (seconds)", "integer", 1, { min = 1, max = 60 }),
			field("duration", "Read duration (seconds)", "integer", 10, { min = 3, max = 300 })
		}
	}
end

local function build_modbus(options, context)
	local schema = modbus_schema(context); local normalized, err = defaults(schema, options, "Modbus")
	if not normalized then return nil, err end
	normalized.transport, err = enum(normalized.transport, { "tcp", "rtu" }, "Transport"); if not normalized.transport then return nil, err end
	normalized.unit, err = integer(normalized.unit, 1, 247, "Unit ID"); if not normalized.unit then return nil, err end
	normalized.addresses, err = dense_integers(normalized.addresses, 0, 65535, 32, "Register addresses"); if not normalized.addresses then return nil, err end
	normalized.datatype, err = enum(normalized.datatype, { "int", "floatlsb", "floatmsb" }, "Datatype"); if not normalized.datatype then return nil, err end
	normalized.interval, err = integer(normalized.interval, 1, 60, "Poll interval"); if not normalized.interval then return nil, err end
	normalized.duration, err = integer(normalized.duration, 3, 300, "Duration"); if not normalized.duration then return nil, err end
	if normalized.transport == "tcp" then
		normalized.host, err = validate_host(normalized.host, "Modbus host"); if not normalized.host then return nil, err end
		normalized.port, err = integer(normalized.port, 1, 65535, "Modbus port"); if not normalized.port then return nil, err end
		normalized.device = ""
	else
		local device = selected(context.serial_devices, normalized.device, "Selected Modbus serial port"); if not device then return nil, "Selected Modbus RTU port is not a reviewed non-EC25 serial target" end
		normalized.device_topology, normalized.device_usb_id = device.topology or "", device.usb_id or ""
		normalized.baud, err = enum(normalized.baud, { "1200", "2400", "4800", "9600", "19200", "38400", "57600", "115200" }, "Baud"); if not normalized.baud then return nil, err end
		normalized.parity, err = enum(normalized.parity, { "N", "E", "O" }, "Parity"); if not normalized.parity then return nil, err end
		normalized.data_bits, err = enum(normalized.data_bits, { "7", "8" }, "Data bits"); if not normalized.data_bits then return nil, err end
		normalized.stop_bits, err = enum(normalized.stop_bits, { "1", "2" }, "Stop bits"); if not normalized.stop_bits then return nil, err end
		normalized.host, normalized.port = "", 0
	end
	local argv = { "/usr/bin/mbcollect", "--mode=master", "--interval=" .. tostring(normalized.interval), "--verbose" }
	return { action_id = schema.action_id, worker = "phase4_modbus", label = "Modbus Holding Register Read", class = "ACTION", resource = normalized.transport == "rtu" and "serial" or "modbus-network", singleton = true,
		options = normalized, argv = argv, argv_preview = preview(argv) .. " --inifile=[DDK_GENERATED_MODBUS_CONFIG]", target_summary = normalized.transport == "tcp" and (normalized.host .. ":" .. tostring(normalized.port) .. " / unit " .. tostring(normalized.unit)) or (normalized.device .. " / unit " .. tostring(normalized.unit)),
		wall_timeout = normalized.duration, artifacts = { text_artifact("modbus-read.txt", "modbus_read", 1048576) }, input_uploads = {}, confirmation = { required = false } }
end

-- Smartcard and YubiKey ---------------------------------------------------

local function auth_inventory_schema()
	return { action_id = "auth.inventory", label = "Smartcard / Token Inventory", class = "INFO",
		native = { executable = "/usr/bin/pcsc_scan", executables = { "/usr/bin/pcsc_scan", "/usr/bin/ykinfo" }, version = "pcsc-tools 1.5.7 / ykpers 1.20.0 / pcscd 1.9.9" },
		fields = {
			field("mode", "Inventory mode", "enum", "readers", { options = { "readers", "yubikey" } }),
			field("device_index", "YubiKey index", "integer", 1, { min = 1, max = 16, show_when = { field = "mode", equals = "yubikey" } }),
			field("wall_timeout", "Wall timeout (seconds)", "integer", 20, { min = 5, max = 60, advanced = true })
		}
	}
end

local function build_auth_inventory(options)
	local schema = auth_inventory_schema(); local normalized, err = defaults(schema, options, "token inventory")
	if not normalized then return nil, err end
	normalized.mode, err = enum(normalized.mode, { "readers", "yubikey" }, "Inventory mode"); if not normalized.mode then return nil, err end
	normalized.device_index, err = integer(normalized.device_index, 1, 16, "Device index"); if not normalized.device_index then return nil, err end
	normalized.wall_timeout, err = integer(normalized.wall_timeout, 5, 60, "Wall timeout"); if not normalized.wall_timeout then return nil, err end
	local argv = normalized.mode == "readers" and { "/usr/bin/pcsc_scan", "-r" } or { "/usr/bin/ykinfo", "-n", tostring(normalized.device_index), "-a" }
	return { action_id = schema.action_id, worker = "phase4_auth_inventory", label = "Token " .. normalized.mode, class = "INFO", resource = "smartcard", singleton = true,
		options = normalized, argv = argv, argv_preview = preview(argv), target_summary = normalized.mode == "readers" and "PC/SC readers" or ("YubiKey index " .. tostring(normalized.device_index)), wall_timeout = normalized.wall_timeout,
		artifacts = { text_artifact("smartcard-inventory.txt", "smartcard_inventory", 524288) }, input_uploads = {}, confirmation = { required = false } }
end

local function auth_program_schema()
	return { action_id = "auth.program", label = "YubiKey Personalization", class = "SECURITY",
		native = { executable = "/usr/bin/ykpersonalize", version = "ykpers 1.20.0" },
		fields = {
			field("device_index", "YubiKey index", "integer", 1, { min = 1, max = 16 }),
			field("slot", "Configuration slot", "enum", "1", { options = { "1", "2" } }),
			field("operation", "Operation", "enum", "configure_hmac", { options = { "configure_hmac", "configure_hotp", "configure_static", "delete_slot", "swap_slots" } }),
			field("secret", "Secret key hex (not retained)", "secret", "", { help = "40 hex characters for HMAC challenge-response; 32 or 40 for HOTP/static." }),
			field("commit", "Commit to physical token", "boolean", false),
			field("wall_timeout", "Wall timeout (seconds)", "integer", 60, { min = 10, max = 180, advanced = true })
		}
	}
end

local function build_auth_program(options)
	local schema = auth_program_schema(); local normalized, err = defaults(schema, options, "YubiKey programming")
	if not normalized then return nil, err end
	local secret = trim(normalized.secret)
	normalized.device_index, err = integer(normalized.device_index, 1, 16, "Device index"); if not normalized.device_index then return nil, err end
	normalized.slot, err = enum(normalized.slot, { "1", "2" }, "Slot"); if not normalized.slot then return nil, err end
	normalized.operation, err = enum(normalized.operation, { "configure_hmac", "configure_hotp", "configure_static", "delete_slot", "swap_slots" }, "Operation"); if not normalized.operation then return nil, err end
	normalized.commit, err = boolean(normalized.commit, "Commit"); if normalized.commit == nil then return nil, err end
	normalized.wall_timeout, err = integer(normalized.wall_timeout, 10, 180, "Wall timeout"); if not normalized.wall_timeout then return nil, err end
	local needs_secret = normalized.operation:match("^configure_") ~= nil
	if needs_secret and (not secret:match("^[0-9A-Fa-f]+$") or (normalized.operation == "configure_hmac" and #secret ~= 40) or (normalized.operation ~= "configure_hmac" and #secret ~= 32 and #secret ~= 40)) then
		return nil, "The selected YubiKey profile requires a 32/40-character hex key (40 for HMAC challenge-response)"
	end
	if not needs_secret and secret ~= "" then return nil, "This YubiKey operation does not accept a secret key" end
	local argv = { "/usr/bin/ykpersonalize", "-N" .. tostring(normalized.device_index) }
	if normalized.operation == "swap_slots" then add(argv, "-x")
	else add(argv, "-" .. normalized.slot)
		if normalized.operation == "delete_slot" then add(argv, "-z")
		elseif normalized.operation == "configure_hmac" then add(argv, "-ochal-resp"); add(argv, "-ochal-hmac"); add(argv, "[PRIVATE_YUBIKEY_SECRET]")
		elseif normalized.operation == "configure_hotp" then add(argv, "-ooath-hotp"); add(argv, "[PRIVATE_YUBIKEY_SECRET]")
		else add(argv, "-ostatic-ticket"); add(argv, "[PRIVATE_YUBIKEY_SECRET]") end
	end
	if normalized.commit then add(argv, "-y") else add(argv, "-d") end
	local private_inputs = {}; if needs_secret then private_inputs[1] = private("yubikey-secret", secret) end
	normalized.secret = needs_secret and "[REDACTED]" or ""
	local shown = copy(argv); for index, item in ipairs(shown) do if item == "[PRIVATE_YUBIKEY_SECRET]" then shown[index] = "-a[PRIVATE]" end end
	local phrase = normalized.commit and ("PROGRAM YUBIKEY " .. tostring(normalized.device_index) .. " " .. normalized.operation:upper() .. " SLOT " .. normalized.slot) or nil
	return { action_id = schema.action_id, worker = "phase4_auth_program", label = "YubiKey " .. normalized.operation .. (normalized.commit and "" or " dry run"), class = "SECURITY", resource = "smartcard", singleton = true,
		options = normalized, private_inputs = private_inputs, argv = argv, argv_preview = preview(shown), target_summary = "YubiKey index " .. tostring(normalized.device_index) .. " / slot " .. normalized.slot,
		wall_timeout = normalized.wall_timeout, artifacts = {}, input_uploads = {}, confirmation = phrase and { required = true, phrase = phrase, reason = "This commits token configuration and may erase or replace authentication material. Confirm the exact physical token, slot, backup, and recovery path." } or { required = false } }
end

-- Camera stream and NTRIP -------------------------------------------------

local function camera_stream_schema(context)
	local devices = choice_map(context.camera_devices)
	local ipv4_addresses = {}
	for _, address in ipairs(context.local_addresses or {}) do
		if address.family == "inet" then ipv4_addresses[#ipv4_addresses + 1] = address end
	end
	local addresses = choice_map(ipv4_addresses)
	return { action_id = "camera.stream", label = "Temporary Authenticated Camera Stream", class = "DISRUPTIVE",
		native = { executable = "/usr/bin/mjpg_streamer", version = "mjpg-streamer 2.0" },
		fields = {
			field("device", "Reviewed UVC capture node", "enum", devices[1] and devices[1].value or "", { options = devices }),
			field("bind_address", "Exact local bind address", "enum", addresses[1] and addresses[1].value or "", { options = addresses }),
			field("port", "HTTP port", "integer", 8090, { min = 1024, max = 65535 }),
			field("width", "Width", "integer", 640, { min = 160, max = 3840 }),
			field("height", "Height", "integer", 480, { min = 120, max = 2160 }),
			field("fps", "Frames per second", "integer", 10, { min = 1, max = 30 }),
			field("quality", "JPEG quality", "integer", 80, { min = 10, max = 100 }),
			field("username", "Stream username", "text", "ddk", { required = true }),
			field("password", "Stream password (not retained)", "secret", "", { required = true }),
			field("duration", "Maximum stream duration (seconds)", "integer", 300, { min = 30, max = 3600 })
		}
	}
end

local function build_camera_stream(options, context)
	local schema = camera_stream_schema(context); local normalized, err = defaults(schema, options, "camera stream")
	if not normalized then return nil, err end
	local password = normalized.password
	if not selected(context.camera_devices, normalized.device, "Selected camera") then return nil, "Selected camera is not in the reviewed UVC inventory" end
	local bind = selected(context.local_addresses, normalized.bind_address, "Selected bind address")
	if not bind or bind.family ~= "inet" then return nil, "Stream bind address is not a current IPv4 address" end
	for _, item in ipairs({ { "port", 1024, 65535, "Port" }, { "width", 160, 3840, "Width" }, { "height", 120, 2160, "Height" }, { "fps", 1, 30, "FPS" }, { "quality", 10, 100, "Quality" }, { "duration", 30, 3600, "Duration" } }) do
		normalized[item[1]], err = integer(normalized[item[1]], item[2], item[3], item[4]); if not normalized[item[1]] then return nil, err end
	end
	normalized.username, err = text(normalized.username, "Username", 64, "^[A-Za-z0-9_.-]+$", true); if not normalized.username then return nil, err end
	password, err = text(password, "Password", 128, "^[A-Za-z0-9_.,@%%+=-]+$", true); if not password then return nil, err end
	if #password < 12 then return nil, "Stream password must be at least 12 characters" end
	local argv = { "/usr/bin/mjpg_streamer", "-i", "[DDK_CAMERA_INPUT]", "-o", "[DDK_AUTHENTICATED_HTTP_OUTPUT]" }
	normalized.password = "[REDACTED]"
	local phrase = "STREAM CAMERA " .. normalized.device .. " ON " .. normalized.bind_address .. ":" .. tostring(normalized.port)
	return { action_id = schema.action_id, worker = "phase4_camera_stream", label = "Temporary Camera Stream", class = "DISRUPTIVE", resource = "camera", singleton = true,
		options = normalized, private_inputs = { private("camera-password", password) }, argv = argv,
		argv_preview = "/usr/bin/mjpg_streamer -i '[SERVER_BUILT_UVC_INPUT]' -o '[SERVER_BUILT_AUTHENTICATED_HTTP_OUTPUT]'", target_summary = normalized.device .. " / " .. normalized.bind_address .. ":" .. tostring(normalized.port),
		wall_timeout = normalized.duration, artifacts = {}, input_uploads = {}, confirmation = { required = true, phrase = phrase, reason = "This opens a temporary authenticated camera listener on the exact local address. Confirm privacy consent, scene, network reachability, credentials, and duration." } }
end

local function ntrip_schema(context)
	local devices = choice_map(context.gps_devices)
	return { action_id = "gps.ntrip", label = "NTRIP Correction Client", class = "ACTION",
		native = { executable = "/usr/bin/ntripclient", version = "ntripclient 1.51" },
		fields = {
			field("device", "Reviewed GNSS serial receiver", "enum", devices[1] and devices[1].value or "", { options = devices }),
			field("server", "NTRIP caster", "text", "", { required = true }),
			field("port", "Caster port", "integer", 2101, { min = 1, max = 65535 }),
			field("mountpoint", "Mountpoint", "text", "", { required = true }),
			field("username", "Username", "text", "", { required = true }),
			field("password", "Password (not retained)", "secret", "", { required = true }),
			field("mode", "NTRIP transport", "enum", "auto", { options = { "auto", "http", "rtsp", "ntrip1", "udp" } }),
			field("baud", "Receiver baud", "enum", "115200", { options = { "4800", "9600", "19200", "38400", "57600", "115200", "230400" } }),
			field("parity", "Parity", "enum", "N", { options = { "N", "E", "O" } }),
			field("data_bits", "Data bits", "enum", "8", { options = { "7", "8" } }),
			field("stop_bits", "Stop bits", "enum", "1", { options = { "1", "2" } }),
			field("duration", "Correction session seconds", "integer", 300, { min = 30, max = 7200 })
		}
	}
end

local function build_ntrip(options, context)
	local schema = ntrip_schema(context); local normalized, err = defaults(schema, options, "NTRIP")
	if not normalized then return nil, err end
	local password = normalized.password; local device = selected(context.gps_devices, normalized.device, "Selected GNSS receiver")
	if not device then return nil, "Selected GNSS receiver is not in the reviewed live inventory" end
	normalized.server, err = validate_host(normalized.server, "Caster host"); if not normalized.server then return nil, err end
	normalized.port, err = integer(normalized.port, 1, 65535, "Caster port"); if not normalized.port then return nil, err end
	normalized.mountpoint, err = text(normalized.mountpoint, "Mountpoint", 256, "^[A-Za-z0-9_./-]+$", true); if not normalized.mountpoint then return nil, err end
	normalized.username, err = text(normalized.username, "Username", 128, "^[A-Za-z0-9_.@+/-]+$", true); if not normalized.username then return nil, err end
	password, err = text(password, "Password", 256, nil, true); if not password then return nil, err end
	normalized.mode, err = enum(normalized.mode, { "auto", "http", "rtsp", "ntrip1", "udp" }, "NTRIP mode"); if not normalized.mode then return nil, err end
	normalized.baud, err = enum(normalized.baud, { "4800", "9600", "19200", "38400", "57600", "115200", "230400" }, "Baud"); if not normalized.baud then return nil, err end
	normalized.parity, err = enum(normalized.parity, { "N", "E", "O" }, "Parity"); if not normalized.parity then return nil, err end
	normalized.data_bits, err = enum(normalized.data_bits, { "7", "8" }, "Data bits"); if not normalized.data_bits then return nil, err end
	normalized.stop_bits, err = enum(normalized.stop_bits, { "1", "2" }, "Stop bits"); if not normalized.stop_bits then return nil, err end
	normalized.duration, err = integer(normalized.duration, 30, 7200, "Duration"); if not normalized.duration then return nil, err end
	normalized.device_topology, normalized.device_usb_id = device.topology or "", device.usb_id or ""
	local argv = { "/usr/bin/ntripclient", "-s", normalized.server, "-r", tostring(normalized.port), "-m", normalized.mountpoint, "-u", normalized.username, "-p", "[PRIVATE_NTRIP_PASSWORD]", "-M", normalized.mode, "-D", normalized.device, "-B", normalized.baud, "-Y", normalized.parity, "-A", normalized.data_bits, "-T", normalized.stop_bits }
	normalized.password = "[REDACTED]"; local shown = copy(argv); for index, item in ipairs(shown) do if item == "[PRIVATE_NTRIP_PASSWORD]" then shown[index] = "[PRIVATE]" end end
	local phrase = "SEND NTRIP " .. normalized.mountpoint .. " TO " .. normalized.device
	return { action_id = schema.action_id, worker = "phase4_ntrip", label = "NTRIP Correction Session", class = "ACTION", resource = "serial", singleton = true,
		options = normalized, private_inputs = { private("ntrip-password", password) }, argv = argv, argv_preview = preview(shown), target_summary = normalized.server .. ":" .. tostring(normalized.port) .. " / " .. normalized.device,
		wall_timeout = normalized.duration, artifacts = {}, input_uploads = {}, confirmation = { required = true, phrase = phrase, reason = "This opens a network correction stream and writes RTCM data to the exact selected GNSS serial target. Confirm caster authorization, receiver identity, baud, and port ownership." } }
end

local schemas = {
	["monitoring.snapshot"] = monitoring_schema, ["wireless.survey"] = wireless_schema, ["usb.inventory"] = usb_inventory_schema,
	["forensics.inspect_file"] = forensics_schema, ["capture.replay"] = replay_schema, ["adsb.receive"] = adsb_schema,
	["radio.ais"] = ais_schema, ["bluetooth.scan"] = bluetooth_schema, ["automation.mqtt_publish"] = mqtt_schema,
	["automation.relay"] = relay_schema, ["industrial.modbus_read"] = modbus_schema, ["auth.inventory"] = auth_inventory_schema,
	["auth.program"] = auth_program_schema, ["camera.stream"] = camera_stream_schema, ["gps.ntrip"] = ntrip_schema
}

local builders = {
	["monitoring.snapshot"] = build_monitoring, ["wireless.survey"] = build_wireless, ["usb.inventory"] = build_usb_inventory,
	["forensics.inspect_file"] = build_forensics, ["capture.replay"] = build_replay, ["adsb.receive"] = build_adsb,
	["radio.ais"] = build_ais, ["bluetooth.scan"] = build_bluetooth, ["automation.mqtt_publish"] = build_mqtt,
	["automation.relay"] = build_relay, ["industrial.modbus_read"] = build_modbus, ["auth.inventory"] = build_auth_inventory,
	["auth.program"] = build_auth_program, ["camera.stream"] = build_camera_stream, ["gps.ntrip"] = build_ntrip
}

function M.describe(action_id, context)
	local builder = schemas[action_id]
	if not builder then return nil, "Unknown Phase 4 Operator Mode action" end
	return builder(context or {})
end

function M.prepare(action_id, options, context)
	local builder = builders[action_id]
	if not builder then return nil, "Unknown Phase 4 Operator Mode action" end
	return builder(options, context or {})
end

return M
