-- Digital Dropkick Field Console Operator Mode action schemas and argv builders.
--
-- This module is deliberately pure: browser values are decoded by ddk-console,
-- validated here, and converted only into literal argv elements. It never runs a
-- command, accepts an executable path, or emits shell syntax.

local M = {}

local MAX_TARGETS = 64
local MAX_TARGET_LENGTH = 253
local MAX_PORT_EXPRESSION = 256

local function trim(value)
	return (tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function copy_array(value)
	local result = {}
	for index, item in ipairs(value or {}) do result[index] = item end
	return result
end

local function is_integer(value)
	return type(value) == "number" and value == math.floor(value)
end

local function validate_integer(value, minimum, maximum, label)
	if not is_integer(value) or value < minimum or value > maximum then
		return nil, string.format("%s must be an integer from %s to %s", label, tostring(minimum), tostring(maximum))
	end
	return value
end

local function validate_number(value, minimum, maximum, label)
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge or
	   value < minimum or value > maximum then
		return nil, string.format("%s must be a number from %s to %s", label, tostring(minimum), tostring(maximum))
	end
	return value
end

local function valid_ipv4(address)
	local count = 0
	for octet in address:gmatch("[^.]+") do
		count = count + 1
		if count > 4 or not octet:match("^%d+$") then return false end
		local number = tonumber(octet)
		if not number or number > 255 then return false end
	end
	return count == 4 and not address:match("^%.") and not address:match("%.$") and not address:find("..", 1, true)
end

local function valid_ipv4_range(address)
	local count = 0
	local saw_range = false
	for part in address:gmatch("[^.]+") do
		count = count + 1
		if count > 4 then return false end
		local first, last = part:match("^(%d+)%-(%d+)$")
		if first then
			first, last = tonumber(first), tonumber(last)
			if first > 255 or last > 255 or first > last then return false end
			saw_range = true
		elseif not part:match("^%d+$") or tonumber(part) > 255 then
			return false
		end
	end
	return count == 4 and saw_range and not address:match("^%.") and not address:match("%.$")
end

local function count_hextets(part)
	if part == "" then return 0 end
	if part:match("^:") or part:match(":$") or part:find("::", 1, true) then return nil end
	local count = 0
	for hextet in part:gmatch("[^:]+") do
		if not hextet:match("^[0-9A-Fa-f]+$") or #hextet > 4 then return nil end
		count = count + 1
	end
	return count
end

local function valid_ipv6(address)
	if address == "" or #address > 45 or not address:match("^[0-9A-Fa-f:]+$") then return false end
	local compressed = address:find("::", 1, true)
	if compressed then
		if address:find("::", compressed + 2, true) then return false end
		local left = count_hextets(address:sub(1, compressed - 1))
		local right = count_hextets(address:sub(compressed + 2))
		return left ~= nil and right ~= nil and left + right < 8
	end
	return count_hextets(address) == 8
end

local function valid_hostname(hostname)
	if hostname:sub(-1) == "." then hostname = hostname:sub(1, -2) end
	if hostname == "" or #hostname > MAX_TARGET_LENGTH then return false end
	local count = 0
	for label in hostname:gmatch("[^.]+") do
		count = count + 1
		if #label > 63 or not label:match("^[A-Za-z0-9][A-Za-z0-9-]*[A-Za-z0-9]$") then
			if not label:match("^[A-Za-z0-9]$") then return false end
		end
	end
	return count > 0 and not hostname:find("..", 1, true)
end

local function validate_target(value)
	if type(value) ~= "string" then return nil, nil, "Every target must be a string" end
	value = trim(value)
	if value == "" or #value > MAX_TARGET_LENGTH or value:find("[%z\1-\32\127]") then
		return nil, nil, "A target is empty, too long, or contains control characters"
	end

	local address, prefix = value:match("^(.-)/(%d+)$")
	address = address or value
	if valid_ipv4(address) then
		if prefix and tonumber(prefix) > 32 then return nil, nil, "An IPv4 prefix exceeds /32" end
		return value, "ipv4"
	elseif valid_ipv6(address) then
		if prefix and tonumber(prefix) > 128 then return nil, nil, "An IPv6 prefix exceeds /128" end
		return value, "ipv6"
	elseif not prefix and valid_ipv4_range(address) then
		return value, "ipv4"
	elseif not prefix and valid_hostname(address) then
		return value, "hostname"
	end
	return nil, nil, "Target must be an IPv4/IPv6 address, CIDR, hostname, or validated IPv4 octet range"
end

local function validate_target_list(value, required, label)
	if type(value) ~= "table" then return nil, nil, label .. " must be a JSON array" end
	local result = {}
	local families = {}
	for index, target in ipairs(value) do
		if index > MAX_TARGETS then return nil, nil, label .. " exceeds the 64-entry request limit" end
		local normalized, family, err = validate_target(target)
		if not normalized then return nil, nil, err end
		result[#result + 1] = normalized
		families[family] = true
	end
	for key in pairs(value) do
		if type(key) ~= "number" or key < 1 or key > #result or key ~= math.floor(key) then
			return nil, nil, label .. " must be a dense JSON array"
		end
	end
	if required and #result == 0 then return nil, nil, label .. " requires at least one entry" end
	if families.ipv4 and families.ipv6 then return nil, nil, "IPv4 and IPv6 targets require separate Nmap jobs" end
	return result, families
end

local function valid_port_number(value)
	if not value:match("^%d+$") then return false end
	local number = tonumber(value)
	return number and number >= 1 and number <= 65535
end

local function validate_ports(value, label)
	if type(value) ~= "string" then return nil, label .. " must be a string" end
	value = trim(value)
	if value == "" then return "" end
	if #value > MAX_PORT_EXPRESSION or value:find("[^0-9,TUS:%-]") then
		return nil, label .. " contains unsupported characters or exceeds 256 bytes"
	end
	for item in value:gmatch("[^,]+") do
		item = item:gsub("^[TUS]:", "")
		if item == "" then return nil, label .. " contains an empty protocol section" end
		if item ~= "-" then
			local first, last = item:match("^(%d*)%-(%d*)$")
			if first then
				if first ~= "" and not valid_port_number(first) then return nil, label .. " contains an invalid range start" end
				if last ~= "" and not valid_port_number(last) then return nil, label .. " contains an invalid range end" end
				if first ~= "" and last ~= "" and tonumber(first) > tonumber(last) then return nil, label .. " contains a descending range" end
			elseif not valid_port_number(item) then
				return nil, label .. " contains an invalid port"
			end
		end
	end
	return value
end

local function enum(value, choices, label)
	if type(value) ~= "string" then return nil, label .. " must be a string" end
	for _, choice in ipairs(choices) do
		if value == choice then return value end
	end
	return nil, label .. " is not an allowed value"
end

local function boolean(value, label)
	if type(value) ~= "boolean" then return nil, label .. " must be true or false" end
	return value
end

local function interface_choices(context)
	local result, seen = {}, {}
	for _, item in ipairs(context.interfaces or {}) do
		local name = type(item) == "table" and item.name or item
		if type(name) == "string" and name:match("^[A-Za-z0-9_.-]+$") and #name <= 15 and not seen[name] then
			seen[name] = true
			result[#result + 1] = { value = name, label = name }
		end
	end
	table.sort(result, function(a, b) return a.value < b.value end)
	return result, seen
end

local function field(name, label, kind, default, extra)
	local result = { name = name, label = label, type = kind, default = default }
	for key, value in pairs(extra or {}) do result[key] = value end
	return result
end

local scan_types = { "discovery", "syn", "connect", "udp", "syn_udp", "ack", "window", "maimon", "null", "fin", "xmas", "ip_protocol", "list" }
local discovery_methods = { "native", "skip", "arp", "icmp_echo", "icmp_timestamp", "icmp_netmask", "tcp_syn", "tcp_ack", "udp" }
local dns_modes = { "native", "never", "always", "system" }
local script_profiles = { "none", "default", "safe", "version", "vuln" }
local output_formats = { "text", "xml", "grepable", "all" }

local function nmap_schema(context)
	local interfaces = interface_choices(context)
	local default_targets = {}
	if type(context.lan_cidr) == "string" and context.lan_cidr ~= "" then default_targets[1] = context.lan_cidr end
	return {
		action_id = "network.nmap_lan_discovery",
		label = "Nmap Operator Scan",
		class = "SECURITY",
		native = { executable = "/usr/bin/nmap", version = "7.91" },
		fields = {
			field("targets", "Targets", "target_list", default_targets, { required = true, rows = 3, help = "One IP, CIDR, hostname, or IPv4 octet range per line. IPv4 and IPv6 run separately." }),
			field("exclude_targets", "Exclude targets", "target_list", {}, { rows = 2, advanced = true }),
			field("scan_type", "Scan type", "enum", "discovery", { options = copy_array(scan_types) }),
			field("ports", "Ports", "port_expression", "", { advanced = true, placeholder = "T:22,80,443,U:53" }),
			field("top_ports", "Top ports", "integer", 0, { min = 0, max = 65535, advanced = true, help = "0 uses the native default or the explicit Ports value." }),
			field("fast_scan", "Fast port set", "boolean", false, { advanced = true }),
			field("interface", "Interface", "enum", context.lan_interface or "", { options = interfaces, allow_empty = true, advanced = true }),
			field("discovery_method", "Host discovery", "enum", "native", { options = copy_array(discovery_methods), advanced = true }),
			field("discovery_ports", "Discovery probe ports", "port_expression", "", { advanced = true, placeholder = "80,443" }),
			field("timing", "Timing template", "enum", "3", { options = { "0", "1", "2", "3", "4", "5" } }),
			field("dns", "DNS resolution", "enum", "never", { options = copy_array(dns_modes) }),
			field("service_detection", "Service/version detection", "boolean", false),
			field("version_intensity", "Version intensity", "integer", 7, { min = 0, max = 9, advanced = true }),
			field("os_detection", "OS detection", "boolean", false),
			field("osscan_limit", "Limit OS detection to promising targets", "boolean", true, { advanced = true }),
			field("osscan_guess", "Aggressive OS guessing", "boolean", false, { advanced = true }),
			field("traceroute", "Traceroute", "boolean", false),
			field("script_profile", "NSE script profile", "enum", "none", { options = copy_array(script_profiles), advanced = true, help = "Only exact installed Nmap categories are accepted; arbitrary script paths and script arguments are not." }),
			field("reason", "Show reasons", "boolean", true, { advanced = true }),
			field("open_only", "Show open ports only", "boolean", false, { advanced = true }),
			field("sequential_ports", "Scan ports sequentially", "boolean", false, { advanced = true }),
			field("max_retries", "Maximum retries", "integer", 2, { min = 0, max = 10, advanced = true }),
			field("host_timeout", "Host timeout (seconds)", "integer", 0, { min = 0, max = 3600, advanced = true }),
			field("min_rate", "Minimum packets/second", "integer", 0, { min = 0, max = 100000, advanced = true }),
			field("max_rate", "Maximum packets/second", "integer", 0, { min = 0, max = 100000, advanced = true }),
			field("scan_delay_ms", "Scan delay (milliseconds)", "integer", 0, { min = 0, max = 60000, advanced = true }),
			field("source_port", "Source port", "integer", 0, { min = 0, max = 65535, advanced = true }),
			field("fragment", "Fragment probes", "boolean", false, { advanced = true }),
			field("mtu", "Fragment MTU", "integer", 0, { min = 0, max = 65528, advanced = true, help = "0 disables custom MTU; otherwise the value must be a multiple of 8." }),
			field("ttl", "Packet TTL", "integer", 0, { min = 0, max = 255, advanced = true }),
			field("data_length", "Random payload bytes", "integer", 0, { min = 0, max = 1400, advanced = true }),
			field("badsum", "Deliberately invalid checksums", "boolean", false, { advanced = true }),
			field("verbosity", "Verbosity", "integer", 0, { min = 0, max = 2, advanced = true }),
			field("packet_trace", "Packet trace", "boolean", false, { advanced = true }),
			field("output_format", "Artifact output", "enum", "xml", { options = copy_array(output_formats) }),
			field("wall_timeout", "Job wall timeout (seconds)", "integer", 120, { min = 10, max = 1800, help = "Independent appliance deadline; completed native artifacts are validated before download." })
		}
	}
end

local function defaults_from_schema(schema)
	local result = {}
	for _, item in ipairs(schema.fields) do
		if type(item.default) == "table" then result[item.name] = copy_array(item.default) else result[item.name] = item.default end
	end
	return result
end

local function normalize_nmap(options, context)
	if type(options) ~= "table" then return nil, "Options must be a JSON object" end
	local schema = nmap_schema(context)
	local normalized = defaults_from_schema(schema)
	local allowed = {}
	for _, item in ipairs(schema.fields) do allowed[item.name] = true end
	for key, value in pairs(options) do
		if type(key) ~= "string" or not allowed[key] then return nil, "Unknown Nmap option: " .. tostring(key) end
		normalized[key] = value
	end

	local families, err
	normalized.targets, families, err = validate_target_list(normalized.targets, true, "Targets")
	if not normalized.targets then return nil, err end
	local exclude_families
	normalized.exclude_targets, exclude_families, err = validate_target_list(normalized.exclude_targets, false, "Exclude targets")
	if not normalized.exclude_targets then return nil, err end
	normalized.scan_type, err = enum(normalized.scan_type, scan_types, "Scan type"); if not normalized.scan_type then return nil, err end
	normalized.ports, err = validate_ports(normalized.ports, "Ports"); if not normalized.ports then return nil, err end
	normalized.discovery_ports, err = validate_ports(normalized.discovery_ports, "Discovery probe ports"); if not normalized.discovery_ports then return nil, err end
	normalized.discovery_method, err = enum(normalized.discovery_method, discovery_methods, "Host discovery"); if not normalized.discovery_method then return nil, err end
	normalized.dns, err = enum(normalized.dns, dns_modes, "DNS resolution"); if not normalized.dns then return nil, err end
	normalized.script_profile, err = enum(normalized.script_profile, script_profiles, "NSE script profile"); if not normalized.script_profile then return nil, err end
	normalized.output_format, err = enum(normalized.output_format, output_formats, "Artifact output"); if not normalized.output_format then return nil, err end
	normalized.timing, err = enum(normalized.timing, { "0", "1", "2", "3", "4", "5" }, "Timing template"); if not normalized.timing then return nil, err end

	local _, interface_set = interface_choices(context)
	if type(normalized.interface) ~= "string" or (normalized.interface ~= "" and not interface_set[normalized.interface]) then
		return nil, "Interface is not present in the live server interface inventory"
	end

	for _, item in ipairs({
		{ "top_ports", 0, 65535, "Top ports" }, { "version_intensity", 0, 9, "Version intensity" },
		{ "max_retries", 0, 10, "Maximum retries" }, { "host_timeout", 0, 3600, "Host timeout" },
		{ "min_rate", 0, 100000, "Minimum rate" }, { "max_rate", 0, 100000, "Maximum rate" },
		{ "scan_delay_ms", 0, 60000, "Scan delay" }, { "source_port", 0, 65535, "Source port" },
		{ "mtu", 0, 65528, "MTU" }, { "ttl", 0, 255, "TTL" }, { "data_length", 0, 1400, "Data length" },
		{ "verbosity", 0, 2, "Verbosity" }, { "wall_timeout", 10, 1800, "Wall timeout" }
	}) do
		normalized[item[1]], err = validate_integer(normalized[item[1]], item[2], item[3], item[4])
		if normalized[item[1]] == nil then return nil, err end
	end
	for _, name in ipairs({ "fast_scan", "service_detection", "os_detection", "osscan_limit", "osscan_guess", "traceroute", "reason", "open_only", "sequential_ports", "fragment", "badsum", "packet_trace" }) do
		normalized[name], err = boolean(normalized[name], name)
		if normalized[name] == nil then return nil, err end
	end

	if normalized.mtu ~= 0 and (normalized.mtu < 8 or normalized.mtu % 8 ~= 0) then return nil, "Fragment MTU must be 0 or a multiple of 8" end
	if normalized.min_rate > 0 and normalized.max_rate > 0 and normalized.min_rate > normalized.max_rate then return nil, "Minimum rate cannot exceed maximum rate" end
	if normalized.ports ~= "" and normalized.top_ports > 0 then return nil, "Ports and Top ports are mutually exclusive" end
	if normalized.fast_scan and (normalized.ports ~= "" or normalized.top_ports > 0) then return nil, "Fast scan cannot be combined with Ports or Top ports" end
	local no_ports = normalized.scan_type == "discovery" or normalized.scan_type == "list" or normalized.scan_type == "ip_protocol"
	if no_ports and (normalized.ports ~= "" or normalized.top_ports > 0 or normalized.fast_scan) then return nil, "The selected scan type does not accept a port selection" end
	if no_ports and (normalized.service_detection or normalized.os_detection or normalized.open_only) then return nil, "Service, OS, and open-only options require a port scan" end
	if normalized.discovery_method ~= "tcp_syn" and normalized.discovery_method ~= "tcp_ack" and normalized.discovery_method ~= "udp" and normalized.discovery_ports ~= "" then
		return nil, "Discovery probe ports require TCP SYN, TCP ACK, or UDP discovery"
	end
	if families.ipv6 and normalized.discovery_method == "arp" then return nil, "ARP discovery is not valid for IPv6 targets" end
	if (families.ipv6 and exclude_families.ipv4) or (not families.ipv6 and exclude_families.ipv6) then
		return nil, "Exclude targets must use the same IP family as the Nmap job"
	end
	return normalized, families
end

local scan_flags = {
	discovery = "-sn", syn = "-sS", connect = "-sT", udp = "-sU", ack = "-sA",
	window = "-sW", maimon = "-sM", null = "-sN", fin = "-sF", xmas = "-sX",
	ip_protocol = "-sO", list = "-sL"
}

local discovery_flags = {
	skip = "-Pn", arp = "-PR", icmp_echo = "-PE", icmp_timestamp = "-PP", icmp_netmask = "-PM"
}

local function add(argv, value)
	if type(value) == "number" and value == math.floor(value) then
		argv[#argv + 1] = string.format("%.0f", value)
	else
		argv[#argv + 1] = tostring(value)
	end
end

local function preview_arg(value)
	if value:match("^[A-Za-z0-9_@%%+=:,./-]+$") then return value end
	return "'" .. value:gsub("'", "'\\''") .. "'"
end

local function build_nmap(options, context)
	local normalized, families_or_error = normalize_nmap(options, context)
	if not normalized then return nil, families_or_error end
	local families = families_or_error
	local argv = { "/usr/bin/nmap" }
	local artifacts = {}
	if families.ipv6 then add(argv, "-6") end
	if normalized.scan_type == "syn_udp" then add(argv, "-sS"); add(argv, "-sU") else add(argv, scan_flags[normalized.scan_type]) end
	add(argv, "-T" .. normalized.timing)
	if normalized.interface ~= "" then add(argv, "-e"); add(argv, normalized.interface) end
	if discovery_flags[normalized.discovery_method] then
		add(argv, discovery_flags[normalized.discovery_method])
	elseif normalized.discovery_method == "tcp_syn" then add(argv, "-PS" .. normalized.discovery_ports)
	elseif normalized.discovery_method == "tcp_ack" then add(argv, "-PA" .. normalized.discovery_ports)
	elseif normalized.discovery_method == "udp" then add(argv, "-PU" .. normalized.discovery_ports) end
	if normalized.dns == "never" then add(argv, "-n")
	elseif normalized.dns == "always" then add(argv, "-R")
	elseif normalized.dns == "system" then add(argv, "--system-dns") end
	if normalized.ports ~= "" then add(argv, "-p"); add(argv, normalized.ports)
	elseif normalized.top_ports > 0 then add(argv, "--top-ports"); add(argv, normalized.top_ports)
	elseif normalized.fast_scan then add(argv, "-F") end
	if normalized.service_detection then add(argv, "-sV"); add(argv, "--version-intensity"); add(argv, normalized.version_intensity) end
	if normalized.os_detection then
		add(argv, "-O")
		if normalized.osscan_limit then add(argv, "--osscan-limit") end
		if normalized.osscan_guess then add(argv, "--osscan-guess") end
	end
	if normalized.traceroute then add(argv, "--traceroute") end
	if normalized.script_profile ~= "none" then add(argv, "--script=" .. normalized.script_profile) end
	if normalized.reason then add(argv, "--reason") end
	if normalized.open_only then add(argv, "--open") end
	if normalized.sequential_ports then add(argv, "-r") end
	add(argv, "--max-retries"); add(argv, normalized.max_retries)
	if normalized.host_timeout > 0 then add(argv, "--host-timeout"); add(argv, normalized.host_timeout .. "s") end
	if normalized.min_rate > 0 then add(argv, "--min-rate"); add(argv, normalized.min_rate) end
	if normalized.max_rate > 0 then add(argv, "--max-rate"); add(argv, normalized.max_rate) end
	if normalized.scan_delay_ms > 0 then add(argv, "--scan-delay"); add(argv, normalized.scan_delay_ms .. "ms") end
	if normalized.source_port > 0 then add(argv, "--source-port"); add(argv, normalized.source_port) end
	if normalized.fragment then add(argv, "-f") end
	if normalized.mtu > 0 then add(argv, "--mtu"); add(argv, normalized.mtu) end
	if normalized.ttl > 0 then add(argv, "--ttl"); add(argv, normalized.ttl) end
	if normalized.data_length > 0 then add(argv, "--data-length"); add(argv, normalized.data_length) end
	if normalized.badsum then add(argv, "--badsum") end
	if normalized.verbosity == 1 then add(argv, "-v") elseif normalized.verbosity == 2 then add(argv, "-vv") end
	if normalized.packet_trace then add(argv, "--packet-trace") end
	if #normalized.exclude_targets > 0 then add(argv, "--exclude"); add(argv, table.concat(normalized.exclude_targets, ",")) end
	if normalized.output_format == "xml" then
		add(argv, "-oX"); add(argv, "@JOB@/nmap.xml")
		artifacts[#artifacts + 1] = { name = "nmap.xml", kind = "nmap_xml", content_type = "application/xml", max_size = 2097152 }
	elseif normalized.output_format == "grepable" then
		add(argv, "-oG"); add(argv, "@JOB@/nmap.gnmap")
		artifacts[#artifacts + 1] = { name = "nmap.gnmap", kind = "nmap_grepable", content_type = "text/plain", max_size = 1048576 }
	elseif normalized.output_format == "all" then
		add(argv, "-oA"); add(argv, "@JOB@/nmap")
		artifacts[#artifacts + 1] = { name = "nmap.nmap", kind = "nmap_text", content_type = "text/plain", max_size = 1048576 }
		artifacts[#artifacts + 1] = { name = "nmap.xml", kind = "nmap_xml", content_type = "application/xml", max_size = 2097152 }
		artifacts[#artifacts + 1] = { name = "nmap.gnmap", kind = "nmap_grepable", content_type = "text/plain", max_size = 1048576 }
	end
	for _, target in ipairs(normalized.targets) do add(argv, target) end

	local preview = {}
	for _, item in ipairs(argv) do preview[#preview + 1] = preview_arg(item:gsub("^@JOB@/", "[DDK_ARTIFACT]/")) end
	local consequential = normalized.script_profile == "vuln" or normalized.fragment or normalized.badsum
	local target_summary = table.concat(normalized.targets, ", ")
	return {
		action_id = "network.nmap_lan_discovery",
		worker = "operator_nmap",
		label = "Nmap Operator Scan",
		class = "SECURITY",
		resource = "network_probe",
		singleton = true,
		options = normalized,
		argv = argv,
		argv_preview = table.concat(preview, " "),
		target_summary = target_summary,
		wall_timeout = normalized.wall_timeout,
		artifacts = artifacts,
		confirmation = {
			required = consequential,
			phrase = consequential and ("RUN ACTIVE SCAN ON " .. target_summary) or nil,
			reason = consequential and "Vulnerability scripts, fragmentation, or invalid checksums can trigger defenses or affect fragile targets." or nil
		}
	}
end

local capture_output_formats = { "decoded", "pcap", "decoded_pcap" }
local capture_dns_modes = { "none", "network", "full" }
local capture_directions = { "inout", "in", "out" }
local capture_timestamps = { "date", "epoch", "none" }
local capture_payload_modes = { "none", "ascii", "hex", "ascii_hex" }

local function capture_schema(context)
	local interfaces = interface_choices(context)
	interfaces[#interfaces + 1] = { value = "any", label = "any (all interfaces)" }
	table.sort(interfaces, function(a, b) return a.value < b.value end)
	return {
		action_id = "capture.lan_metadata_snapshot",
		label = "tcpdump Operator Capture",
		class = "SECURITY",
		native = { executable = "/usr/sbin/tcpdump", version = "4.9.3", libpcap = "1.10.1" },
		fields = {
			field("interface", "Capture interface", "enum", context.lan_interface or "", { options = interfaces }),
			field("filter", "Capture filter (BPF)", "text", "arp or icmp or (ip and udp and (port 67 or port 68))", { help = "Passed as one argv element and compiled by tcpdump before capture; never evaluated by a shell." }),
			field("duration", "Duration (seconds)", "integer", 20, { min = 1, max = 1800 }),
			field("packet_count", "Packet ceiling", "integer", 128, { min = 0, max = 1000000, help = "0 uses only the duration and artifact-size ceilings." }),
			field("snap_length", "Snap length (bytes)", "integer", 96, { min = 0, max = 262144, help = "0 uses tcpdump's native default." }),
			field("output_format", "Output", "enum", "decoded_pcap", { options = copy_array(capture_output_formats) }),
			field("promiscuous", "Promiscuous mode", "boolean", false),
			field("direction", "Direction", "enum", "inout", { options = copy_array(capture_directions), advanced = true }),
			field("dns", "Name resolution", "enum", "none", { options = copy_array(capture_dns_modes), advanced = true }),
			field("timestamps", "Timestamps", "enum", "date", { options = copy_array(capture_timestamps), advanced = true }),
			field("payload", "Decoded payload display", "enum", "none", { options = copy_array(capture_payload_modes), advanced = true }),
			field("link_header", "Show link-layer header", "boolean", true, { advanced = true }),
			field("verbosity", "Decode verbosity", "integer", 0, { min = 0, max = 3, advanced = true }),
			field("immediate_mode", "Immediate packet delivery", "boolean", false, { advanced = true }),
			field("buffer_kib", "Capture buffer (KiB)", "integer", 0, { min = 0, max = 16384, advanced = true, help = "0 uses the native default." })
		}
	}
end

local function normalize_capture(options, context)
	if type(options) ~= "table" then return nil, "Options must be a JSON object" end
	local schema = capture_schema(context)
	local normalized = defaults_from_schema(schema)
	local allowed = {}
	for _, item in ipairs(schema.fields) do allowed[item.name] = true end
	for key, value in pairs(options) do
		if type(key) ~= "string" or not allowed[key] then return nil, "Unknown tcpdump option: " .. tostring(key) end
		normalized[key] = value
	end
	local _, interface_set = interface_choices(context)
	interface_set.any = true
	if type(normalized.interface) ~= "string" or not interface_set[normalized.interface] then return nil, "Capture interface is not present in the live server inventory" end
	if type(normalized.filter) ~= "string" then return nil, "Capture filter must be a string" end
	normalized.filter = trim(normalized.filter)
	if #normalized.filter > 1024 or normalized.filter:find("[%z\1-\31\127]") then return nil, "Capture filter exceeds 1024 bytes or contains control characters" end
	local err
	normalized.output_format, err = enum(normalized.output_format, capture_output_formats, "Capture output"); if not normalized.output_format then return nil, err end
	normalized.direction, err = enum(normalized.direction, capture_directions, "Capture direction"); if not normalized.direction then return nil, err end
	normalized.dns, err = enum(normalized.dns, capture_dns_modes, "Name resolution"); if not normalized.dns then return nil, err end
	normalized.timestamps, err = enum(normalized.timestamps, capture_timestamps, "Timestamps"); if not normalized.timestamps then return nil, err end
	normalized.payload, err = enum(normalized.payload, capture_payload_modes, "Payload display"); if not normalized.payload then return nil, err end
	for _, item in ipairs({
		{ "duration", 1, 1800, "Duration" }, { "packet_count", 0, 1000000, "Packet ceiling" },
		{ "snap_length", 0, 262144, "Snap length" }, { "verbosity", 0, 3, "Verbosity" },
		{ "buffer_kib", 0, 16384, "Capture buffer" }
	}) do
		normalized[item[1]], err = validate_integer(normalized[item[1]], item[2], item[3], item[4])
		if normalized[item[1]] == nil then return nil, err end
	end
	for _, name in ipairs({ "promiscuous", "link_header", "immediate_mode" }) do
		normalized[name], err = boolean(normalized[name], name)
		if normalized[name] == nil then return nil, err end
	end
	return normalized
end

local function add_capture_decode_flags(argv, normalized)
	if normalized.dns == "none" then add(argv, "-nn") elseif normalized.dns == "network" then add(argv, "-n") end
	if normalized.timestamps == "date" then add(argv, "-tttt") elseif normalized.timestamps == "epoch" then add(argv, "-tt") else add(argv, "-t") end
	if normalized.link_header then add(argv, "-e") end
	if normalized.verbosity == 1 then add(argv, "-v") elseif normalized.verbosity == 2 then add(argv, "-vv") elseif normalized.verbosity == 3 then add(argv, "-vvv") end
	if normalized.payload == "ascii" then add(argv, "-A") elseif normalized.payload == "hex" then add(argv, "-x") elseif normalized.payload == "ascii_hex" then add(argv, "-X") end
end

local function build_capture(options, context)
	local normalized, err = normalize_capture(options, context)
	if not normalized then return nil, err end
	local argv = { "/usr/sbin/tcpdump", "-i", normalized.interface }
	if not normalized.promiscuous then add(argv, "-p") end
	if normalized.direction ~= "inout" then add(argv, "-Q"); add(argv, normalized.direction) end
	if normalized.snap_length > 0 then add(argv, "-s"); add(argv, normalized.snap_length) end
	if normalized.packet_count > 0 then add(argv, "-c"); add(argv, normalized.packet_count) end
	if normalized.buffer_kib > 0 then add(argv, "-B"); add(argv, normalized.buffer_kib) end
	if normalized.immediate_mode then add(argv, "--immediate-mode") end
	local artifacts = {}
	local decode_argv
	if normalized.output_format == "pcap" or normalized.output_format == "decoded_pcap" then
		add(argv, "-U"); add(argv, "-w"); add(argv, "@JOB@/capture.pcap")
		artifacts[#artifacts + 1] = { name = "capture.pcap", kind = "pcap", content_type = "application/vnd.tcpdump.pcap", max_size = 8388608 }
		if normalized.output_format == "decoded_pcap" then
			decode_argv = { "/usr/sbin/tcpdump", "-r", "@JOB@/capture.pcap" }
			add_capture_decode_flags(decode_argv, normalized)
		end
	else
		add(argv, "-l")
		add_capture_decode_flags(argv, normalized)
	end
	if normalized.filter ~= "" then add(argv, normalized.filter) end
	local preview = {}
	for _, item in ipairs(argv) do preview[#preview + 1] = preview_arg(item:gsub("^@JOB@/", "[DDK_ARTIFACT]/")) end
	local consequential = normalized.promiscuous or normalized.interface == "any" or normalized.payload ~= "none" or normalized.output_format ~= "decoded"
	return {
		action_id = "capture.lan_metadata_snapshot",
		worker = "operator_tcpdump",
		label = "tcpdump Operator Capture",
		class = "SECURITY",
		resource = "packet_capture",
		singleton = true,
		options = normalized,
		argv = argv,
		decode_argv = decode_argv,
		argv_preview = table.concat(preview, " "),
		target_summary = normalized.interface .. (normalized.filter ~= "" and (" / " .. normalized.filter) or " / all traffic"),
		wall_timeout = normalized.duration,
		artifacts = artifacts,
		confirmation = {
			required = consequential,
			phrase = consequential and ("CAPTURE ON " .. normalized.interface) or nil,
			reason = consequential and "Promiscuous, all-interface, payload, or PCAP capture can collect private customer traffic." or nil
		}
	}
end

local iperf_modes = { "client", "server" }
local iperf_protocols = { "tcp", "udp" }
local iperf_ip_versions = { "auto", "4", "6" }
local iperf_transfer_modes = { "duration", "bytes", "blocks" }

local function local_address_choices(context)
	local result, set = { { value = "", label = "Automatic (client only)" } }, { [""] = true }
	for _, item in ipairs(context.local_addresses or {}) do
		if type(item) == "table" and type(item.address) == "string" and type(item.interface) == "string" and
		   item.address:match("^[A-Za-z0-9:.]+$") and item.interface:match("^[A-Za-z0-9_.-]+$") and not set[item.address] then
			set[item.address] = item
			result[#result + 1] = { value = item.address, label = item.address .. " (" .. item.interface .. ")" }
		end
	end
	return result, set
end

local function iperf_schema(context)
	local addresses = local_address_choices(context)
	local interfaces = interface_choices(context)
	table.insert(interfaces, 1, { value = "", label = "Automatic" })
	local congestion = { { value = "", label = "Native default" } }
	for _, name in ipairs(context.congestion_controls or {}) do congestion[#congestion + 1] = { value = name, label = name } end
	return {
		action_id = "throughput.iperf3",
		label = "iperf3 Operator Test",
		class = "ACTION",
		native = { executable = "/usr/bin/iperf3", version = "3.11", help_behavior = "Installed --help and -h return zero bytes; option table verified from the exact binary." },
		fields = {
			field("mode", "Mode", "enum", "client", { options = copy_array(iperf_modes) }),
			field("host", "Server host (client mode)", "text", "", { placeholder = "192.168.8.10", show_when = { field = "mode", equals = "client" } }),
			field("port", "Port", "integer", 5201, { min = 1, max = 65535 }),
			field("protocol", "Protocol (client mode)", "enum", "tcp", { options = copy_array(iperf_protocols), show_when = { field = "mode", equals = "client" } }),
			field("duration", "Test/server window (seconds)", "integer", 10, { min = 1, max = 3600 }),
			field("wall_timeout", "Client wall timeout (seconds)", "integer", 60, { min = 10, max = 7200, help = "Independent appliance deadline.", show_when = { field = "mode", equals = "client" } }),
			field("parallel", "Parallel streams", "integer", 1, { min = 1, max = 32, show_when = { field = "mode", equals = "client" } }),
			field("bitrate", "Target bitrate (bits/second)", "integer", 1000000, { min = 0, max = 10000000000, help = "0 requests the native unlimited setting.", show_when = { field = "mode", equals = "client" } }),
			field("reverse", "Reverse direction", "boolean", false, { show_when = { field = "mode", equals = "client" } }),
			field("bidirectional", "Bidirectional test", "boolean", false, { show_when = { field = "mode", equals = "client" } }),
			field("bind_address", "Local bind address", "enum", "", { options = addresses, advanced = true, help = "Server mode requires one exact address currently assigned to this router." }),
			field("bind_device", "Bind device", "enum", "", { options = interfaces, advanced = true }),
			field("ip_version", "IP version", "enum", "auto", { options = copy_array(iperf_ip_versions), advanced = true }),
			field("transfer_mode", "Transfer stop condition", "enum", "duration", { options = copy_array(iperf_transfer_modes), advanced = true, show_when = { field = "mode", equals = "client" } }),
			field("transfer_amount", "Bytes or blocks", "integer", 1048576, { min = 1, max = 1000000000000, advanced = true, show_when = { field = "mode", equals = "client" } }),
			field("omit", "Warm-up omitted (seconds)", "integer", 0, { min = 0, max = 60, advanced = true, show_when = { field = "mode", equals = "client" } }),
			field("interval", "Report interval (seconds)", "integer", 1, { min = 0, max = 60, advanced = true }),
			field("buffer_length", "Buffer/datagram length", "integer", 0, { min = 0, max = 1048576, advanced = true, show_when = { field = "mode", equals = "client" } }),
			field("window", "Socket window (bytes)", "integer", 0, { min = 0, max = 16777216, advanced = true, show_when = { field = "mode", equals = "client" } }),
			field("mss", "TCP maximum segment size", "integer", 0, { min = 0, max = 65535, advanced = true, show_when = { field = "mode", equals = "client" } }),
			field("no_delay", "Disable Nagle", "boolean", false, { advanced = true, show_when = { field = "mode", equals = "client" } }),
			field("zerocopy", "Zero-copy transmit", "boolean", false, { advanced = true, show_when = { field = "mode", equals = "client" } }),
			field("dont_fragment", "IPv4 UDP do-not-fragment", "boolean", false, { advanced = true, show_when = { field = "mode", equals = "client" } }),
			field("congestion", "TCP congestion algorithm", "enum", "", { options = congestion, advanced = true, show_when = { field = "mode", equals = "client" } }),
			field("tos", "IP TOS", "integer", 0, { min = 0, max = 255, advanced = true, show_when = { field = "mode", equals = "client" } }),
			field("connect_timeout_ms", "Connect timeout (ms)", "integer", 5000, { min = 100, max = 60000, advanced = true, show_when = { field = "mode", equals = "client" } }),
			field("get_server_output", "Retrieve server output", "boolean", true, { advanced = true, show_when = { field = "mode", equals = "client" } }),
			field("one_off", "Server exits after one client", "boolean", true, { advanced = true, show_when = { field = "mode", equals = "server" } }),
			field("server_bitrate_limit", "Server bitrate limit", "integer", 0, { min = 0, max = 10000000000, advanced = true, show_when = { field = "mode", equals = "server" } }),
			field("json_output", "JSON artifact", "boolean", true)
		}
	}
end

local function validate_iperf_host(value)
	local normalized, family, err = validate_target(value)
	if not normalized then return nil, nil, err end
	if normalized:find("/", 1, true) or valid_ipv4_range(normalized) then return nil, nil, "iperf3 host must identify one host, not a CIDR or range" end
	return normalized, family
end

local function normalize_iperf(options, context)
	if type(options) ~= "table" then return nil, "Options must be a JSON object" end
	local schema = iperf_schema(context)
	local normalized = defaults_from_schema(schema)
	local allowed = {}
	for _, item in ipairs(schema.fields) do allowed[item.name] = true end
	for key, value in pairs(options) do
		if type(key) ~= "string" or not allowed[key] then return nil, "Unknown iperf3 option: " .. tostring(key) end
		normalized[key] = value
	end
	local err
	normalized.mode, err = enum(normalized.mode, iperf_modes, "Mode"); if not normalized.mode then return nil, err end
	normalized.protocol, err = enum(normalized.protocol, iperf_protocols, "Protocol"); if not normalized.protocol then return nil, err end
	normalized.ip_version, err = enum(normalized.ip_version, iperf_ip_versions, "IP version"); if not normalized.ip_version then return nil, err end
	normalized.transfer_mode, err = enum(normalized.transfer_mode, iperf_transfer_modes, "Transfer stop condition"); if not normalized.transfer_mode then return nil, err end
	local host_family
	if normalized.mode == "client" then
		normalized.host, host_family, err = validate_iperf_host(normalized.host)
		if not normalized.host then return nil, err end
	elseif type(normalized.host) ~= "string" then return nil, "Server host field must remain a string"
	else normalized.host = "" end
	local _, address_set = local_address_choices(context)
	if type(normalized.bind_address) ~= "string" or not address_set[normalized.bind_address] then return nil, "Bind address is not assigned to this router" end
	if normalized.mode == "server" and normalized.bind_address == "" then return nil, "Server mode requires an exact currently assigned bind address" end
	local _, interface_set = interface_choices(context)
	interface_set[""] = true
	if type(normalized.bind_device) ~= "string" or not interface_set[normalized.bind_device] then return nil, "Bind device is not present in the live interface inventory" end
	local congestion_set = { [""] = true }
	for _, name in ipairs(context.congestion_controls or {}) do congestion_set[name] = true end
	if type(normalized.congestion) ~= "string" or not congestion_set[normalized.congestion] then return nil, "Congestion algorithm is not available in the running kernel" end
	for _, item in ipairs({
		{ "port", 1, 65535, "Port" }, { "duration", 1, 3600, "Duration" }, { "wall_timeout", 10, 7200, "Wall timeout" }, { "parallel", 1, 32, "Parallel streams" },
		{ "bitrate", 0, 10000000000, "Bitrate" }, { "transfer_amount", 1, 1000000000000, "Transfer amount" },
		{ "omit", 0, 60, "Omit" }, { "interval", 0, 60, "Interval" }, { "buffer_length", 0, 1048576, "Buffer length" },
		{ "window", 0, 16777216, "Window" }, { "mss", 0, 65535, "MSS" }, { "tos", 0, 255, "TOS" },
		{ "connect_timeout_ms", 100, 60000, "Connect timeout" }, { "server_bitrate_limit", 0, 10000000000, "Server bitrate limit" }
	}) do
		normalized[item[1]], err = validate_integer(normalized[item[1]], item[2], item[3], item[4])
		if normalized[item[1]] == nil then return nil, err end
	end
	for _, name in ipairs({ "reverse", "bidirectional", "no_delay", "zerocopy", "dont_fragment", "get_server_output", "one_off", "json_output" }) do
		normalized[name], err = boolean(normalized[name], name)
		if normalized[name] == nil then return nil, err end
	end
	if normalized.reverse and normalized.bidirectional then return nil, "Reverse and bidirectional modes are mutually exclusive" end
	if normalized.mode == "client" and normalized.transfer_mode == "duration" and normalized.wall_timeout < normalized.duration + normalized.omit + 5 then return nil, "Client wall timeout must allow the test duration, omitted warm-up, and five seconds of control overhead" end
	if normalized.mode == "server" and (normalized.protocol ~= "tcp" or normalized.wall_timeout ~= 60 or normalized.parallel ~= 1 or
	   normalized.bitrate ~= 1000000 or normalized.reverse or normalized.bidirectional or normalized.transfer_mode ~= "duration" or
	   normalized.transfer_amount ~= 1048576 or normalized.omit ~= 0 or normalized.buffer_length ~= 0 or normalized.window ~= 0 or
	   normalized.mss ~= 0 or normalized.no_delay or normalized.zerocopy or normalized.dont_fragment or normalized.congestion ~= "" or
	   normalized.tos ~= 0 or normalized.connect_timeout_ms ~= 5000 or not normalized.get_server_output) then
		return nil, "Client-only iperf3 options must remain at their defaults in server mode"
	end
	if normalized.mode == "client" and (not normalized.one_off or normalized.server_bitrate_limit ~= 0) then
		return nil, "Server-only iperf3 options must remain at their defaults in client mode"
	end
	if normalized.protocol == "udp" and normalized.zerocopy then return nil, "Zero-copy is not valid for UDP tests" end
	if normalized.protocol == "udp" and normalized.no_delay then return nil, "TCP no-delay is not valid for UDP tests" end
	if normalized.protocol == "udp" and normalized.congestion ~= "" then return nil, "TCP congestion control is not valid for UDP tests" end
	if normalized.protocol == "udp" and normalized.mss ~= 0 then return nil, "TCP maximum segment size is not valid for UDP tests" end
	if normalized.protocol ~= "udp" and normalized.dont_fragment then return nil, "Do-not-fragment is available only for IPv4 UDP tests" end
	if normalized.dont_fragment and (normalized.ip_version == "6" or host_family == "ipv6") then return nil, "Do-not-fragment is not valid for IPv6 tests" end
	if normalized.ip_version == "4" and host_family == "ipv6" then return nil, "IPv6 host conflicts with IPv4-only mode" end
	if normalized.ip_version == "6" and host_family == "ipv4" then return nil, "IPv4 host conflicts with IPv6-only mode" end
	local bind_record = address_set[normalized.bind_address]
	local bind_family = type(bind_record) == "table" and bind_record.family or nil
	if normalized.ip_version == "4" and bind_family == "inet6" then return nil, "IPv6 bind address conflicts with IPv4-only mode" end
	if normalized.ip_version == "6" and bind_family == "inet" then return nil, "IPv4 bind address conflicts with IPv6-only mode" end
	if host_family == "ipv4" and bind_family == "inet6" then return nil, "IPv4 target cannot use an IPv6 bind address" end
	if host_family == "ipv6" and bind_family == "inet" then return nil, "IPv6 target cannot use an IPv4 bind address" end
	if normalized.bind_device ~= "" and type(bind_record) == "table" and bind_record.interface ~= normalized.bind_device then
		return nil, "Bind address is not assigned to the selected bind device"
	end
	return normalized
end

local function build_iperf(options, context)
	local normalized, err = normalize_iperf(options, context)
	if not normalized then return nil, err end
	local argv = { "/usr/bin/iperf3" }
	if normalized.mode == "client" then add(argv, "--client"); add(argv, normalized.host) else add(argv, "--server") end
	add(argv, "--port"); add(argv, normalized.port)
	if normalized.bind_address ~= "" then add(argv, "--bind"); add(argv, normalized.bind_address) end
	if normalized.bind_device ~= "" then add(argv, "--bind-dev"); add(argv, normalized.bind_device) end
	if normalized.ip_version == "4" then add(argv, "--version4") elseif normalized.ip_version == "6" then add(argv, "--version6") end
	if normalized.mode == "client" and normalized.protocol == "udp" then add(argv, "--udp") end
	if normalized.mode == "client" then
		if normalized.transfer_mode == "duration" then add(argv, "--time"); add(argv, normalized.duration)
		elseif normalized.transfer_mode == "bytes" then add(argv, "--bytes"); add(argv, normalized.transfer_amount)
		else add(argv, "--blockcount"); add(argv, normalized.transfer_amount) end
		add(argv, "--parallel"); add(argv, normalized.parallel)
		if normalized.protocol == "udp" or normalized.bitrate ~= 1000000 then add(argv, "--bitrate"); add(argv, normalized.bitrate) end
		if normalized.reverse then add(argv, "--reverse") end
		if normalized.bidirectional then add(argv, "--bidir") end
		if normalized.omit > 0 then add(argv, "--omit"); add(argv, normalized.omit) end
		add(argv, "--interval"); add(argv, normalized.interval)
		if normalized.buffer_length > 0 then add(argv, "--length"); add(argv, normalized.buffer_length) end
		if normalized.window > 0 then add(argv, "--window"); add(argv, normalized.window) end
		if normalized.mss > 0 then add(argv, "--set-mss"); add(argv, normalized.mss) end
		if normalized.no_delay then add(argv, "--no-delay") end
		if normalized.zerocopy then add(argv, "--zerocopy") end
		if normalized.dont_fragment then add(argv, "--dont-fragment") end
		if normalized.congestion ~= "" then add(argv, "--congestion"); add(argv, normalized.congestion) end
		if normalized.tos > 0 then add(argv, "--tos"); add(argv, normalized.tos) end
		add(argv, "--connect-timeout"); add(argv, normalized.connect_timeout_ms)
		if normalized.get_server_output then add(argv, "--get-server-output") end
	else
		if normalized.one_off then add(argv, "--one-off") end
		add(argv, "--idle-timeout"); add(argv, normalized.duration)
		add(argv, "--interval"); add(argv, normalized.interval)
		if normalized.server_bitrate_limit > 0 then add(argv, "--server-bitrate-limit"); add(argv, normalized.server_bitrate_limit) end
	end
	add(argv, "--forceflush")
	local artifacts = {}
	if normalized.json_output then
		add(argv, "--json"); add(argv, "--logfile"); add(argv, "@JOB@/iperf3.json")
		artifacts[#artifacts + 1] = { name = "iperf3.json", kind = "iperf3_json", content_type = "application/json", max_size = 2097152 }
	end
	local preview = {}
	for _, item in ipairs(argv) do preview[#preview + 1] = preview_arg(item:gsub("^@JOB@/", "[DDK_ARTIFACT]/")) end
	local endpoint_host = normalized.mode == "client" and normalized.host or normalized.bind_address
	local target_summary = (valid_ipv6(endpoint_host) and ("[" .. endpoint_host .. "]") or endpoint_host) .. ":" .. normalized.port
	return {
		action_id = "throughput.iperf3",
		worker = "operator_iperf3",
		label = normalized.mode == "client" and "iperf3 Client Test" or "iperf3 Temporary Server",
		class = "ACTION",
		resource = "throughput",
		singleton = true,
		options = normalized,
		argv = argv,
		argv_preview = table.concat(preview, " "),
		target_summary = target_summary,
		wall_timeout = normalized.mode == "client" and normalized.wall_timeout or normalized.duration,
		artifacts = artifacts,
		confirmation = {
			required = normalized.mode == "server",
			phrase = normalized.mode == "server" and ("START IPERF SERVER ON " .. target_summary) or nil,
			reason = normalized.mode == "server" and "This opens a temporary iperf3 listener on the selected local address until one client completes or the validated window ends." or nil
		}
	}
end

local function exact_device_choices(items, value_key, label_key)
	local choices, set = {}, {}
	for _, item in ipairs(items or {}) do
		local value = type(item) == "table" and item[value_key] or nil
		local label = type(item) == "table" and item[label_key] or nil
		if type(value) == "string" and value ~= "" and not value:find("[%z\r\n]") and not set[value] then
			set[value] = item
			choices[#choices + 1] = { value = value, label = type(label) == "string" and label ~= "" and label or value }
		end
	end
	table.sort(choices, function(a, b) return a.label < b.label end)
	return choices, set
end

local rtl_decoder_modes = { "default", "selected", "all_including_disabled" }
local rtl_output_formats = { "json", "kv", "csv" }
local rtl_units = { "native", "si", "customary" }
local rtl_analyzers = { "off", "analyze", "pulse" }

local function rtl433_schema(context)
	local devices = exact_device_choices(context.rtl_devices, "selector", "label")
	local default_device = devices[1] and devices[1].value or ""
	return {
		action_id = "radio.rtl433_snapshot",
		label = "RTL-433 Operator Receive",
		class = "ACTION",
		native = { executable = "/usr/bin/rtl_433", package_version = "20.11-2" },
		fields = {
			field("device", "RTL-SDR device", "enum", default_device, { options = devices, help = "Only live, unclaimed, reviewed RTL2832/RTL2838 USB devices are offered; selection uses the USB serial." }),
			field("frequencies", "Frequencies (Hz)", "integer_list", { 433920000 }, { min = 100000, max = 2000000000, rows = 3, help = "One frequency per line; up to 16. rtl_433 hops between multiple frequencies." }),
			field("duration", "Receive duration (seconds)", "integer", 60, { min = 1, max = 900 }),
			field("sample_rate", "Sample rate (samples/second)", "integer", 250000, { min = 225001, max = 3200000 }),
			field("gain", "Gain (dB; 0 = automatic)", "number", 0, { min = -10, max = 100, step = 0.1 }),
			field("ppm", "Frequency correction (PPM)", "integer", 0, { min = -200, max = 200 }),
			field("decoder_mode", "Decoder profile", "enum", "default", { options = copy_array(rtl_decoder_modes) }),
			field("decoder_ids", "Selected decoder IDs", "integer_list", {}, { min = 1, max = 175, rows = 4, show_when = { field = "decoder_mode", equals = "selected" }, help = "One exact rtl_433 20.11 protocol ID per line; up to 64." }),
			field("output_format", "Decoded artifact format", "enum", "json", { options = copy_array(rtl_output_formats) }),
			field("units", "Unit conversion", "enum", "native", { options = copy_array(rtl_units), advanced = true }),
			field("hop_interval", "Hop interval (seconds)", "integer", 600, { min = 1, max = 900, advanced = true, help = "Used only when more than one frequency is selected." }),
			field("detection_level", "Manual detection level dB (0 = automatic)", "number", 0, { min = -30, max = 0, step = 0.1, advanced = true }),
			field("analyzer", "Signal analyzer", "enum", "off", { options = copy_array(rtl_analyzers), advanced = true }),
			field("metadata_time", "Include event time", "boolean", true, { advanced = true }),
			field("metadata_protocol", "Include protocol metadata", "boolean", true, { advanced = true }),
			field("metadata_level", "Include signal level", "boolean", false, { advanced = true }),
			field("metadata_stats", "Include receiver statistics", "boolean", false, { advanced = true }),
			field("metadata_bits", "Include decoded bit representation", "boolean", false, { advanced = true }),
			field("quit_after_event", "Stop after first decoded event", "boolean", false, { advanced = true }),
			field("raw_iq", "Save bounded raw I/Q artifact", "boolean", false, { advanced = true, help = "Creates one fixed uint8 complex-sample artifact under the DDK job; never per-signal files." }),
			field("raw_samples", "Raw sample ceiling", "integer", 1048576, { min = 1, max = 4194304, advanced = true, show_when = { field = "raw_iq", equals = true }, help = "Each sample is two bytes; the maximum artifact is 8 MiB." }),
			field("verbosity", "Native verbosity", "integer", 0, { min = 0, max = 3, advanced = true })
		}
	}
end

local function validate_integer_list(value, minimum, maximum, maximum_count, label)
	if type(value) ~= "table" then return nil, label .. " must be a JSON array" end
	local result, seen = {}, {}
	for index, item in ipairs(value) do
		if index > maximum_count then return nil, label .. " exceeds the " .. maximum_count .. "-entry limit" end
		local normalized, err = validate_integer(item, minimum, maximum, label .. " entry")
		if normalized == nil then return nil, err end
		if seen[normalized] then return nil, label .. " contains a duplicate value" end
		seen[normalized] = true
		result[#result + 1] = normalized
	end
	for key in pairs(value) do
		if type(key) ~= "number" or key < 1 or key > #result or key ~= math.floor(key) then return nil, label .. " must be a dense JSON array" end
	end
	return result
end

local function normalize_rtl433(options, context)
	if type(options) ~= "table" then return nil, "Options must be a JSON object" end
	local schema = rtl433_schema(context)
	local normalized = defaults_from_schema(schema)
	local allowed = {}
	for _, item in ipairs(schema.fields) do allowed[item.name] = true end
	for key, value in pairs(options) do
		if type(key) ~= "string" or not allowed[key] then return nil, "Unknown rtl_433 option: " .. tostring(key) end
		normalized[key] = value
	end
	local _, devices = exact_device_choices(context.rtl_devices, "selector", "label")
	if type(normalized.device) ~= "string" or not devices[normalized.device] then return nil, "RTL-SDR device is not present in the live reviewed hardware inventory" end
	local err
	normalized.frequencies, err = validate_integer_list(normalized.frequencies, 100000, 2000000000, 16, "Frequencies")
	if not normalized.frequencies or #normalized.frequencies == 0 then return nil, err or "At least one receive frequency is required" end
	normalized.decoder_ids, err = validate_integer_list(normalized.decoder_ids, 1, 175, 64, "Decoder IDs")
	if not normalized.decoder_ids then return nil, err end
	normalized.decoder_mode, err = enum(normalized.decoder_mode, rtl_decoder_modes, "Decoder profile"); if not normalized.decoder_mode then return nil, err end
	normalized.output_format, err = enum(normalized.output_format, rtl_output_formats, "Output format"); if not normalized.output_format then return nil, err end
	normalized.units, err = enum(normalized.units, rtl_units, "Units"); if not normalized.units then return nil, err end
	normalized.analyzer, err = enum(normalized.analyzer, rtl_analyzers, "Analyzer"); if not normalized.analyzer then return nil, err end
	for _, item in ipairs({
		{ "duration", 1, 900, "Duration" }, { "sample_rate", 225001, 3200000, "Sample rate" },
		{ "ppm", -200, 200, "PPM" }, { "hop_interval", 1, 900, "Hop interval" },
		{ "raw_samples", 1, 4194304, "Raw sample ceiling" }, { "verbosity", 0, 3, "Verbosity" }
	}) do
		normalized[item[1]], err = validate_integer(normalized[item[1]], item[2], item[3], item[4])
		if normalized[item[1]] == nil then return nil, err end
	end
	if normalized.sample_rate > 300000 and normalized.sample_rate < 900001 then return nil, "RTL-SDR sample rate must be 225001-300000 or 900001-3200000 samples/second" end
	normalized.gain, err = validate_number(normalized.gain, -10, 100, "Gain"); if normalized.gain == nil then return nil, err end
	normalized.detection_level, err = validate_number(normalized.detection_level, -30, 0, "Detection level"); if normalized.detection_level == nil then return nil, err end
	for _, name in ipairs({ "metadata_time", "metadata_protocol", "metadata_level", "metadata_stats", "metadata_bits", "quit_after_event", "raw_iq" }) do
		normalized[name], err = boolean(normalized[name], name)
		if normalized[name] == nil then return nil, err end
	end
	if normalized.decoder_mode == "selected" and #normalized.decoder_ids == 0 then return nil, "Selected decoder mode requires at least one decoder ID" end
	if normalized.decoder_mode ~= "selected" and #normalized.decoder_ids > 0 then return nil, "Decoder IDs are accepted only with the selected decoder profile" end
	if #normalized.frequencies == 1 and normalized.hop_interval ~= 600 then return nil, "Hop interval applies only to multi-frequency receive jobs" end
	if not normalized.raw_iq and normalized.raw_samples ~= 1048576 then return nil, "Raw sample ceiling applies only when raw I/Q output is enabled" end
	return normalized
end

local function build_rtl433(options, context)
	local normalized, err = normalize_rtl433(options, context)
	if not normalized then return nil, err end
	local argv = { "/usr/bin/rtl_433", "-c", "/dev/null", "-d", normalized.device }
	for _, frequency in ipairs(normalized.frequencies) do add(argv, "-f"); add(argv, frequency) end
	if #normalized.frequencies > 1 then add(argv, "-H"); add(argv, normalized.hop_interval) end
	add(argv, "-s"); add(argv, normalized.sample_rate)
	add(argv, "-g"); add(argv, normalized.gain)
	add(argv, "-p"); add(argv, normalized.ppm)
	if normalized.decoder_mode == "selected" then
		add(argv, "-R"); add(argv, 0)
		for _, decoder in ipairs(normalized.decoder_ids) do add(argv, "-R"); add(argv, decoder) end
	elseif normalized.decoder_mode == "all_including_disabled" then add(argv, "-G") end
	if normalized.detection_level ~= 0 then add(argv, "-Y"); add(argv, "level=" .. tostring(normalized.detection_level)) end
	if normalized.analyzer == "analyze" then add(argv, "-a") elseif normalized.analyzer == "pulse" then add(argv, "-A") end
	if normalized.units ~= "native" then add(argv, "-C"); add(argv, normalized.units) end
	if normalized.metadata_time then add(argv, "-M"); add(argv, "time") end
	if normalized.metadata_protocol then add(argv, "-M"); add(argv, "protocol") end
	if normalized.metadata_level then add(argv, "-M"); add(argv, "level") end
	if normalized.metadata_stats then add(argv, "-M"); add(argv, "stats") end
	if normalized.metadata_bits then add(argv, "-M"); add(argv, "bits") end
	if normalized.quit_after_event then add(argv, "-E"); add(argv, "quit") end
	for _ = 1, normalized.verbosity do add(argv, "-v") end
	add(argv, "-F"); add(argv, normalized.output_format)
	add(argv, "-T"); add(argv, normalized.duration)
	local artifacts = {}
	local decoded_name = normalized.output_format == "json" and "rtl433.jsonl" or (normalized.output_format == "csv" and "rtl433.csv" or "rtl433.txt")
	artifacts[#artifacts + 1] = { name = decoded_name, kind = "rtl433_" .. normalized.output_format, content_type = normalized.output_format == "json" and "application/x-ndjson" or "text/plain", max_size = 2097152 }
	if normalized.raw_iq then
		add(argv, "-n"); add(argv, normalized.raw_samples)
		add(argv, "-W"); add(argv, "@JOB@/rtl433.cu8")
		artifacts[#artifacts + 1] = { name = "rtl433.cu8", kind = "rtl433_raw_iq", content_type = "application/octet-stream", max_size = 8388608 }
	end
	local preview = {}
	for _, item in ipairs(argv) do preview[#preview + 1] = preview_arg(item:gsub("^@JOB@/", "[DDK_ARTIFACT]/")) end
	return {
		action_id = "radio.rtl433_snapshot", worker = "operator_rtl433", label = "RTL-433 Operator Receive", class = "ACTION",
		resource = "rtl_sdr", singleton = true, options = normalized, argv = argv,
		argv_preview = table.concat(preview, " "), target_summary = normalized.device .. " at " .. table.concat(normalized.frequencies, ", ") .. " Hz",
		wall_timeout = normalized.duration + 10, artifacts = artifacts,
		confirmation = { required = false }
	}
end

local camera_formats = { "jpeg", "png" }
local camera_flips = { "none", "horizontal", "vertical" }
local camera_banners = { "none", "top", "bottom" }

local function camera_schema(context)
	local devices = exact_device_choices(context.camera_devices, "node", "label")
	local default_device = devices[1] and devices[1].value or ""
	return {
		action_id = "camera.still_snapshot", label = "Camera Still Operator", class = "ACTION",
		native = { executable = "/usr/bin/fswebcam", version = "20140113" },
		fields = {
			field("device", "UVC capture node", "enum", default_device, { options = devices, help = "Only live UVC character devices from sysfs are offered." }),
			field("format", "Image format", "enum", "jpeg", { options = copy_array(camera_formats) }),
			field("resolution", "Resolution", "text", "1280x720", { placeholder = "1920x1080", help = "Validated WxH request; the camera driver remains authoritative about supported modes." }),
			field("frames", "Frames to capture", "integer", 1, { min = 1, max = 64 }),
			field("skip", "Frames to skip first", "integer", 5, { min = 0, max = 120 }),
			field("delay", "Pre-capture delay (seconds)", "integer", 0, { min = 0, max = 30 }),
			field("jpeg_quality", "JPEG quality", "integer", 90, { min = 0, max = 95, show_when = { field = "format", equals = "jpeg" } }),
			field("png_compression", "PNG compression", "integer", 3, { min = 0, max = 10, show_when = { field = "format", equals = "png" } }),
			field("palette", "Capture palette", "text", "", { advanced = true, placeholder = "MJPEG", help = "Empty uses native negotiation; otherwise a validated palette token is passed to fswebcam." }),
			field("input", "Video input number/name", "text", "", { advanced = true }),
			field("fps", "Requested frame rate (0 = native)", "number", 0, { min = 0, max = 120, step = 0.01, advanced = true }),
			field("flip", "Flip", "enum", "none", { options = copy_array(camera_flips), advanced = true }),
			field("rotate", "Rotate", "enum", "0", { options = { "0", "90", "180", "270" }, advanced = true }),
			field("greyscale", "Greyscale", "boolean", false, { advanced = true }),
			field("invert", "Invert colors", "boolean", false, { advanced = true }),
			field("deinterlace", "Deinterlace", "boolean", false, { advanced = true }),
			field("banner", "Banner", "enum", "none", { options = copy_array(camera_banners), advanced = true }),
			field("gmt", "Banner timestamp in GMT", "boolean", false, { advanced = true, show_when = { field = "banner", not_equals = "none" } }),
			field("title", "Banner title", "text", "", { advanced = true, show_when = { field = "banner", not_equals = "none" } }),
			field("subtitle", "Banner subtitle", "text", "", { advanced = true, show_when = { field = "banner", not_equals = "none" } }),
			field("info", "Banner info", "text", "", { advanced = true, show_when = { field = "banner", not_equals = "none" } })
		}
	}
end

local function validate_camera_text(value, label, maximum, pattern)
	if type(value) ~= "string" or #value > maximum or value:find("[%z\r\n]") or (value ~= "" and pattern and not value:match(pattern)) then
		return nil, label .. " contains unsupported characters or is too long"
	end
	return value
end

local function normalize_camera(options, context)
	if type(options) ~= "table" then return nil, "Options must be a JSON object" end
	local schema = camera_schema(context)
	local normalized = defaults_from_schema(schema)
	local allowed = {}
	for _, item in ipairs(schema.fields) do allowed[item.name] = true end
	for key, value in pairs(options) do
		if type(key) ~= "string" or not allowed[key] then return nil, "Unknown fswebcam option: " .. tostring(key) end
		normalized[key] = value
	end
	local _, devices = exact_device_choices(context.camera_devices, "node", "label")
	if type(normalized.device) ~= "string" or not devices[normalized.device] then return nil, "Camera node is not present in the live reviewed UVC inventory" end
	local err
	normalized.format, err = enum(normalized.format, camera_formats, "Image format"); if not normalized.format then return nil, err end
	normalized.flip, err = enum(normalized.flip, camera_flips, "Flip"); if not normalized.flip then return nil, err end
	normalized.banner, err = enum(normalized.banner, camera_banners, "Banner"); if not normalized.banner then return nil, err end
	normalized.rotate, err = enum(normalized.rotate, { "0", "90", "180", "270" }, "Rotate"); if not normalized.rotate then return nil, err end
	local width, height = type(normalized.resolution) == "string" and normalized.resolution:match("^(%d+)x(%d+)$") or nil, nil
	if type(normalized.resolution) == "string" then width, height = normalized.resolution:match("^(%d+)x(%d+)$") end
	width, height = tonumber(width), tonumber(height)
	if not width or not height or width < 16 or height < 16 or width > 8192 or height > 8192 or width * height > 8847360 then return nil, "Resolution must be WxH and no more than 8.85 megapixels for this 121 MiB appliance" end
	normalized.resolution = tostring(width) .. "x" .. tostring(height)
	for _, item in ipairs({ { "frames", 1, 64, "Frames" }, { "skip", 0, 120, "Skip" }, { "delay", 0, 30, "Delay" }, { "jpeg_quality", 0, 95, "JPEG quality" }, { "png_compression", 0, 10, "PNG compression" } }) do
		normalized[item[1]], err = validate_integer(normalized[item[1]], item[2], item[3], item[4]); if normalized[item[1]] == nil then return nil, err end
	end
	normalized.fps, err = validate_number(normalized.fps, 0, 120, "FPS"); if normalized.fps == nil then return nil, err end
	normalized.palette, err = validate_camera_text(normalized.palette, "Palette", 32, "^[A-Za-z0-9_.-]+$"); if normalized.palette == nil then return nil, err end
	normalized.input, err = validate_camera_text(normalized.input, "Input", 64, "^[A-Za-z0-9 _.:-]+$"); if normalized.input == nil then return nil, err end
	for _, name in ipairs({ "title", "subtitle", "info" }) do normalized[name], err = validate_camera_text(normalized[name], name, 128); if normalized[name] == nil then return nil, err end end
	for _, name in ipairs({ "greyscale", "invert", "deinterlace", "gmt" }) do normalized[name], err = boolean(normalized[name], name); if normalized[name] == nil then return nil, err end end
	if normalized.format == "jpeg" and normalized.png_compression ~= 3 then return nil, "PNG compression must remain at its default for JPEG output" end
	if normalized.format == "png" and normalized.jpeg_quality ~= 90 then return nil, "JPEG quality must remain at its default for PNG output" end
	if normalized.banner == "none" and (normalized.gmt or normalized.title ~= "" or normalized.subtitle ~= "" or normalized.info ~= "") then return nil, "Banner fields require a top or bottom banner" end
	return normalized
end

local function build_camera(options, context)
	local normalized, err = normalize_camera(options, context)
	if not normalized then return nil, err end
	local artifact_name = normalized.format == "png" and "snapshot.png" or "snapshot.jpg"
	local argv = { "/usr/bin/fswebcam", "--quiet", "--device", normalized.device, "--resolution", normalized.resolution }
	if normalized.input ~= "" then add(argv, "--input"); add(argv, normalized.input) end
	if normalized.palette ~= "" then add(argv, "--palette"); add(argv, normalized.palette) end
	if normalized.fps > 0 then add(argv, "--fps"); add(argv, normalized.fps) end
	if normalized.delay > 0 then add(argv, "--delay"); add(argv, normalized.delay) end
	add(argv, "--frames"); add(argv, normalized.frames)
	if normalized.skip > 0 then add(argv, "--skip"); add(argv, normalized.skip) end
	if normalized.flip ~= "none" then add(argv, "--flip"); add(argv, normalized.flip == "horizontal" and "h" or "v") end
	if normalized.rotate ~= "0" then add(argv, "--rotate"); add(argv, normalized.rotate) end
	if normalized.greyscale then add(argv, "--greyscale") end
	if normalized.invert then add(argv, "--invert") end
	if normalized.deinterlace then add(argv, "--deinterlace") end
	if normalized.banner == "none" then add(argv, "--no-banner") elseif normalized.banner == "top" then add(argv, "--top-banner") else add(argv, "--bottom-banner") end
	if normalized.gmt then add(argv, "--gmt") end
	for _, item in ipairs({ { "title", "--title" }, { "subtitle", "--subtitle" }, { "info", "--info" } }) do if normalized[item[1]] ~= "" then add(argv, item[2]); add(argv, normalized[item[1]]) end end
	if normalized.format == "png" then add(argv, "--png"); add(argv, normalized.png_compression) else add(argv, "--jpeg"); add(argv, normalized.jpeg_quality) end
	add(argv, "@JOB@/" .. artifact_name)
	local preview = {}
	for _, item in ipairs(argv) do preview[#preview + 1] = preview_arg(item:gsub("^@JOB@/", "[DDK_ARTIFACT]/")) end
	return {
		action_id = "camera.still_snapshot", worker = "operator_camera", label = "Camera Still Operator", class = "ACTION",
		resource = "camera", singleton = true, options = normalized, argv = argv, argv_preview = table.concat(preview, " "),
		target_summary = normalized.device .. " at " .. normalized.resolution .. " / " .. normalized.format,
		wall_timeout = normalized.delay + 30, artifacts = { { name = artifact_name, kind = "camera_snapshot", content_type = normalized.format == "png" and "image/png" or "image/jpeg", max_size = 4194304 } },
		confirmation = { required = false }
	}
end

local serial_modes = { "receive", "transmit_receive" }
local serial_bauds = { "50", "75", "110", "134", "150", "200", "300", "600", "1200", "1800", "2400", "4800", "9600", "19200", "38400", "57600", "115200", "230400", "460800", "500000", "576000", "921600", "1000000", "1152000", "1500000", "2000000", "2500000", "3000000", "3500000", "4000000" }
local serial_parities = { "none", "even", "odd" }
local serial_flows = { "none", "software", "hardware" }
local serial_endings = { "none", "cr", "lf", "crlf" }
local serial_encodings = { "text", "hex" }
local serial_views = { "hex_ascii", "hex", "ascii" }

local function serial_schema(context)
	local devices = exact_device_choices(context.serial_devices, "node", "label")
	local default_device = devices[1] and devices[1].value or ""
	return {
		action_id = "serial.session", label = "Bounded Serial Operator", class = "ACTION",
		native = { executable = "/usr/bin/socat", version = "1.7.4.1", tty_state = "/bin/stty 9.0" },
		fields = {
			field("device", "Serial device", "enum", default_device, { options = devices, help = "Only live, idle, reviewed general-purpose USB serial nodes are offered. Quectel EC25 nodes are never eligible." }),
			field("mode", "Session mode", "enum", "receive", { options = copy_array(serial_modes) }),
			field("baud", "Baud rate", "enum", "115200", { options = copy_array(serial_bauds) }),
			field("data_bits", "Data bits", "enum", "8", { options = { "5", "6", "7", "8" } }),
			field("parity", "Parity", "enum", "none", { options = copy_array(serial_parities) }),
			field("stop_bits", "Stop bits", "enum", "1", { options = { "1", "2" } }),
			field("flow", "Flow control", "enum", "none", { options = copy_array(serial_flows) }),
			field("duration", "Session window (seconds)", "integer", 15, { min = 1, max = 300 }),
			field("read_kib", "Receive artifact ceiling (KiB)", "integer", 64, { min = 1, max = 2048 }),
			field("output_view", "Job preview", "enum", "hex_ascii", { options = copy_array(serial_views) }),
			field("transmit_encoding", "Transmit encoding", "enum", "text", { options = copy_array(serial_encodings), show_when = { field = "mode", equals = "transmit_receive" } }),
			field("transmit_data", "Transmit data", "multiline", "", { rows = 5, show_when = { field = "mode", equals = "transmit_receive" }, help = "Text accepts tabs and line breaks; hex accepts byte pairs separated by whitespace or colons. Maximum 4096 bytes." }),
			field("line_ending", "Append line ending", "enum", "none", { options = copy_array(serial_endings), show_when = { field = "mode", equals = "transmit_receive" }, help = "Applied only to text encoding." })
		}
	}
end

local function text_to_hex(value)
	return (value:gsub(".", function(character) return string.format("%02x", string.byte(character)) end))
end

local function normalize_serial(options, context)
	if type(options) ~= "table" then return nil, "Options must be a JSON object" end
	local schema = serial_schema(context)
	local normalized = defaults_from_schema(schema)
	local allowed = {}
	for _, item in ipairs(schema.fields) do allowed[item.name] = true end
	for key, value in pairs(options) do
		if type(key) ~= "string" or not allowed[key] then return nil, "Unknown serial option: " .. tostring(key) end
		normalized[key] = value
	end
	local _, devices = exact_device_choices(context.serial_devices, "node", "label")
	if type(normalized.device) ~= "string" or not devices[normalized.device] then return nil, "Serial device is not present in the live reviewed general-purpose inventory" end
	local err
	normalized.mode, err = enum(normalized.mode, serial_modes, "Mode"); if not normalized.mode then return nil, err end
	normalized.baud, err = enum(normalized.baud, serial_bauds, "Baud"); if not normalized.baud then return nil, err end
	normalized.data_bits, err = enum(normalized.data_bits, { "5", "6", "7", "8" }, "Data bits"); if not normalized.data_bits then return nil, err end
	normalized.parity, err = enum(normalized.parity, serial_parities, "Parity"); if not normalized.parity then return nil, err end
	normalized.stop_bits, err = enum(normalized.stop_bits, { "1", "2" }, "Stop bits"); if not normalized.stop_bits then return nil, err end
	normalized.flow, err = enum(normalized.flow, serial_flows, "Flow control"); if not normalized.flow then return nil, err end
	normalized.output_view, err = enum(normalized.output_view, serial_views, "Output preview"); if not normalized.output_view then return nil, err end
	normalized.transmit_encoding, err = enum(normalized.transmit_encoding, serial_encodings, "Transmit encoding"); if not normalized.transmit_encoding then return nil, err end
	normalized.line_ending, err = enum(normalized.line_ending, serial_endings, "Line ending"); if not normalized.line_ending then return nil, err end
	normalized.duration, err = validate_integer(normalized.duration, 1, 300, "Duration"); if normalized.duration == nil then return nil, err end
	normalized.read_kib, err = validate_integer(normalized.read_kib, 1, 2048, "Receive ceiling"); if normalized.read_kib == nil then return nil, err end
	if type(normalized.transmit_data) ~= "string" or #normalized.transmit_data > 12288 or normalized.transmit_data:find("%z") then return nil, "Transmit data is invalid or too large" end
	local payload_hex = ""
	if normalized.mode == "receive" then
		if normalized.transmit_encoding ~= "text" or normalized.transmit_data ~= "" or normalized.line_ending ~= "none" then return nil, "Transmit fields must remain at defaults in receive-only mode" end
	else
		if normalized.transmit_encoding == "text" then
			if normalized.transmit_data:find("[%z\1-\8\11\12\14-\31\127]") then return nil, "Text transmit data contains unsupported control bytes" end
			local suffix = normalized.line_ending == "cr" and "\r" or (normalized.line_ending == "lf" and "\n" or (normalized.line_ending == "crlf" and "\r\n" or ""))
			payload_hex = text_to_hex(normalized.transmit_data .. suffix)
		else
			if normalized.line_ending ~= "none" then return nil, "Line ending is available only for text transmit encoding" end
			payload_hex = normalized.transmit_data:gsub("[%s:]", ""):lower()
			if payload_hex == "" or payload_hex:find("[^0-9a-f]") or #payload_hex % 2 ~= 0 then return nil, "Hex transmit data must contain complete hexadecimal byte pairs" end
		end
		if #payload_hex == 0 then return nil, "Transmit-and-receive mode requires at least one byte" end
		if #payload_hex > 8192 then return nil, "Transmit payload exceeds 4096 bytes" end
	end
	local transmit_bytes = #payload_hex / 2
	normalized.transmit_data = nil
	normalized.transmit_bytes = transmit_bytes
	return normalized, payload_hex
end

local function build_serial(options, context)
	local normalized, payload_hex_or_error = normalize_serial(options, context)
	if not normalized then return nil, payload_hex_or_error end
	local parity = normalized.parity == "none" and ",parenb=0,parodd=0" or (normalized.parity == "even" and ",parenb=1,parodd=0" or ",parenb=1,parodd=1")
	local flow = normalized.flow == "hardware" and ",crtscts=1,ixon=0,ixoff=0" or (normalized.flow == "software" and ",crtscts=0,ixon=1,ixoff=1" or ",crtscts=0,ixon=0,ixoff=0")
	local address = "OPEN:" .. normalized.device .. ",b" .. normalized.baud .. ",raw,echo=0,clocal=1,cs" .. normalized.data_bits ..
		(normalized.stop_bits == "2" and ",cstopb=1" or ",cstopb=0") .. parity .. flow
	local argv = { "/usr/bin/socat", "-T", tostring(normalized.duration) }
	if normalized.mode == "receive" then add(argv, "-u"); add(argv, address); add(argv, "STDOUT")
	else add(argv, "-,ignoreeof"); add(argv, address) end
	local preview = {}
	for _, item in ipairs(argv) do preview[#preview + 1] = preview_arg(item) end
	local consequential = normalized.mode == "transmit_receive"
	local phrase = consequential and ("TRANSMIT " .. normalized.transmit_bytes .. " BYTES TO " .. normalized.device .. " AT " .. normalized.baud) or nil
	return {
		action_id = "serial.session", worker = "operator_serial", label = consequential and "Serial Transmit / Receive" or "Serial Receive", class = "ACTION",
		resource = "serial", singleton = true, options = normalized, private_input_hex = consequential and payload_hex_or_error or nil,
		argv = argv, argv_preview = table.concat(preview, " "),
		target_summary = normalized.device .. " / " .. normalized.baud .. " " .. normalized.data_bits .. (normalized.parity:sub(1, 1):upper()) .. normalized.stop_bits .. " / " .. normalized.flow,
		wall_timeout = normalized.duration + 5,
		artifacts = { { name = "serial.bin", kind = "serial_capture", content_type = "application/octet-stream", max_size = normalized.read_kib * 1024 } },
		confirmation = { required = consequential, phrase = phrase, reason = consequential and "The selected bytes will be transmitted to the exact non-reserved serial target before the bounded receive window." or nil }
	}
end

local gps_decode_modes = { "verbose", "json", "nmea", "minimum" }

local function gps_schema(context)
	local devices = exact_device_choices(context.gps_devices, "node", "label")
	local default_device = devices[1] and devices[1].value or ""
	return {
		action_id = "gps.snapshot", label = "GPS / GNSS Operator Receive", class = "ACTION",
		native = { executable = "/bin/dd", decoder = "/usr/bin/gpsdecode", decoder_version = "3.23.1" },
		fields = {
			field("device", "GNSS serial node", "enum", default_device, { options = devices, help = "Only live, idle, reviewed USB GNSS serial nodes are offered. EC25 nodes are excluded." }),
			field("duration", "Receive duration (seconds)", "integer", 30, { min = 1, max = 300 }),
			field("capture_kib", "Raw byte ceiling (KiB)", "integer", 64, { min = 1, max = 2048 }),
			field("decode_mode", "gpsdecode output", "enum", "verbose", { options = copy_array(gps_decode_modes) }),
			field("position_summary", "Validated position summary", "boolean", true, { help = "Available with verbose gpsdecode output; precise coordinates remain transient." }),
			field("decoded_artifact", "Save decoded text artifact", "boolean", true),
			field("raw_artifact", "Save raw receiver bytes", "boolean", false, { help = "Raw data can contain precise location and device-specific messages." }),
			field("types", "gpsdecode type filter", "text", "", { advanced = true, placeholder = "TPV,SKY", help = "Optional comma-separated gpsdecode type tokens; arbitrary decoder commands are not accepted." }),
			field("unscaled", "Unscaled values", "boolean", false, { advanced = true }),
			field("split24", "Split AIS type 24", "boolean", false, { advanced = true }),
			field("debug", "Decoder debug level", "integer", 0, { min = 0, max = 5, advanced = true })
		}
	}
end

local function normalize_gps(options, context)
	if type(options) ~= "table" then return nil, "Options must be a JSON object" end
	local schema = gps_schema(context)
	local normalized = defaults_from_schema(schema)
	local allowed = {}
	for _, item in ipairs(schema.fields) do allowed[item.name] = true end
	for key, value in pairs(options) do
		if type(key) ~= "string" or not allowed[key] then return nil, "Unknown GPS/GNSS option: " .. tostring(key) end
		normalized[key] = value
	end
	local _, devices = exact_device_choices(context.gps_devices, "node", "label")
	if type(normalized.device) ~= "string" or not devices[normalized.device] then return nil, "GNSS device is not present in the live reviewed receiver inventory" end
	local err
	normalized.decode_mode, err = enum(normalized.decode_mode, gps_decode_modes, "Decode mode"); if not normalized.decode_mode then return nil, err end
	normalized.duration, err = validate_integer(normalized.duration, 1, 300, "Duration"); if normalized.duration == nil then return nil, err end
	normalized.capture_kib, err = validate_integer(normalized.capture_kib, 1, 2048, "Capture ceiling"); if normalized.capture_kib == nil then return nil, err end
	normalized.debug, err = validate_integer(normalized.debug, 0, 5, "Debug level"); if normalized.debug == nil then return nil, err end
	for _, name in ipairs({ "position_summary", "decoded_artifact", "raw_artifact", "unscaled", "split24" }) do
		normalized[name], err = boolean(normalized[name], name); if normalized[name] == nil then return nil, err end
	end
	normalized.types, err = validate_camera_text(normalized.types, "Type filter", 64, "^[A-Za-z0-9_,.-]+$"); if normalized.types == nil then return nil, err end
	if normalized.position_summary and normalized.decode_mode ~= "verbose" then return nil, "Validated position summary requires verbose gpsdecode output" end
	if not normalized.position_summary and not normalized.decoded_artifact and not normalized.raw_artifact then return nil, "Select a position summary or at least one GNSS artifact" end
	return normalized
end

local function build_gps(options, context)
	local normalized, err = normalize_gps(options, context)
	if not normalized then return nil, err end
	local argv = { "/bin/dd", "if=" .. normalized.device, "bs=256", "count=" .. tostring(normalized.capture_kib * 4) }
	local decode_argv = { "/usr/bin/gpsdecode", "-d" }
	if normalized.decode_mode == "verbose" then add(decode_argv, "-v")
	elseif normalized.decode_mode == "json" then add(decode_argv, "-j")
	elseif normalized.decode_mode == "nmea" then add(decode_argv, "-n")
	else add(decode_argv, "-m") end
	if normalized.types ~= "" then add(decode_argv, "-t"); add(decode_argv, normalized.types) end
	if normalized.unscaled then add(decode_argv, "-u") end
	if normalized.split24 then add(decode_argv, "-s") end
	if normalized.debug > 0 then add(decode_argv, "-D"); add(decode_argv, normalized.debug) end
	local capture_preview, decode_preview = {}, {}
	for _, item in ipairs(argv) do capture_preview[#capture_preview + 1] = preview_arg(item) end
	for _, item in ipairs(decode_argv) do decode_preview[#decode_preview + 1] = preview_arg(item) end
	local artifacts = {}
	if normalized.raw_artifact then artifacts[#artifacts + 1] = { name = "gnss.raw", kind = "gnss_raw", content_type = "application/octet-stream", max_size = normalized.capture_kib * 1024 } end
	if normalized.decoded_artifact then artifacts[#artifacts + 1] = { name = "gnss.decoded", kind = "gnss_decoded", content_type = "text/plain", max_size = 2097152 } end
	return {
		action_id = "gps.snapshot", worker = "operator_gps", label = "GPS / GNSS Operator Receive", class = "ACTION",
		resource = "serial", singleton = true, options = normalized, argv = argv, decode_argv = decode_argv,
		argv_preview = "capture: " .. table.concat(capture_preview, " ") .. "\ndecode: " .. table.concat(decode_preview, " "),
		target_summary = normalized.device .. " / " .. normalized.duration .. " seconds / " .. normalized.capture_kib .. " KiB ceiling",
		wall_timeout = normalized.duration + 10, artifacts = artifacts, confirmation = { required = false }
	}
end

local adb_diagnostic_operations = { "get_state", "get_serialno", "get_devpath", "getprop", "list_packages", "logcat", "bugreport", "pull", "backup" }
local adb_manage_operations = { "push", "install", "uninstall", "restore", "reboot", "root", "remount", "usb", "tcpip" }
local adb_package_scopes = { "all", "third_party", "system", "enabled", "disabled" }
local adb_log_formats = { "brief", "process", "tag", "thread", "raw", "time", "threadtime", "long" }
local adb_reboot_targets = { "normal", "bootloader", "recovery" }

local function adb_device_choices(context)
	return exact_device_choices(context.android_devices, "serial", "label")
end

local function upload_choices(context, accepted_kind, require_apk)
	local choices, records = {}, {}
	for _, upload in ipairs(context.uploads or {}) do
		local accepted = accepted_kind == "any_android" and upload.kind ~= "apple_restore" or upload.kind == accepted_kind
		if accepted and (not require_apk or tostring(upload.original_name or ""):lower():match("[.]apk$") ~= nil) and
		   type(upload.id) == "string" and upload.id:match("^upload%-%d+%-%d+%-%d+$") then
			choices[#choices + 1] = { value = upload.id, label = upload.original_name .. " / " .. tostring(upload.size) .. " bytes / " .. upload.sha256:sub(1, 12) }
			records[upload.id] = upload
		end
	end
	table.sort(choices, function(a, b) return a.label < b.label end)
	return choices, records
end

local function validate_android_path(value, label)
	if type(value) ~= "string" or #value < 2 or #value > 256 or value:sub(1, 1) ~= "/" or
	   value:find("//", 1, true) or value:find("[%z\r\n]") or not value:match("^[A-Za-z0-9_./ +@%%:=%-]+$") then
		return nil, label .. " must be one bounded absolute Android-device path"
	end
	for segment in value:gmatch("[^/]+") do if segment == "." or segment == ".." then return nil, label .. " cannot contain dot traversal segments" end end
	return value
end

local function validate_package_name(value, label, allow_empty)
	if allow_empty and value == "" then return "" end
	if type(value) ~= "string" or #value < 3 or #value > 192 or
	   value:sub(-1) == "." or not value:match("^[A-Za-z][A-Za-z0-9_]*[.][A-Za-z0-9_.]+$") or value:find("..", 1, true) then
		return nil, label .. " is not a valid bounded Android package identifier"
	end
	return value
end

local function validate_package_list(value)
	if type(value) ~= "table" then return nil, "Package names must be a JSON array" end
	local result, seen = {}, {}
	for index, item in ipairs(value) do
		if index > 128 then return nil, "Package list exceeds 128 entries" end
		local package, err = validate_package_name(item, "Package name", false)
		if not package then return nil, err end
		if seen[package] then return nil, "Package list contains a duplicate" end
		seen[package], result[#result + 1] = true, package
	end
	for key in pairs(value) do if type(key) ~= "number" or key < 1 or key > #result or key ~= math.floor(key) then return nil, "Package names must be a dense JSON array" end end
	return result
end

local function validate_log_filters(value)
	if type(value) ~= "table" then return nil, "Logcat filters must be a JSON array" end
	local result = {}
	for index, item in ipairs(value) do
		if index > 32 or type(item) ~= "string" or #item > 70 or not item:match("^[A-Za-z0-9_*.-]+:[VDIWEFS]$") then
			return nil, "Each logcat filter must be TAG:PRIORITY with a reviewed priority letter"
		end
		result[#result + 1] = item
	end
	for key in pairs(value) do if type(key) ~= "number" or key < 1 or key > #result or key ~= math.floor(key) then return nil, "Logcat filters must be a dense JSON array" end end
	return result
end

local function adb_diagnostics_schema(context)
	local devices = adb_device_choices(context)
	local default_device = devices[1] and devices[1].value or ""
	return {
		action_id = "android.adb_diagnostics", label = "Android ADB Diagnostics & Backup", class = "ACTION",
		native = { executable = "/usr/bin/adb", version = "1.0.32", isolated_server_port = 5038 },
		fields = {
			field("device", "Authorized ADB device", "enum", default_device, { options = devices, help = "Only live ADB transports correlated with a reviewed USB Android identity are offered." }),
			field("operation", "Native operation", "enum", "get_state", { options = copy_array(adb_diagnostic_operations) }),
			field("wall_timeout", "Wall timeout (seconds)", "integer", 60, { min = 10, max = 900 }),
			field("property", "Android property (empty = all)", "text", "", { show_when = { field = "operation", equals = "getprop" }, placeholder = "ro.build.version.release" }),
			field("package_scope", "Package scope", "enum", "all", { options = copy_array(adb_package_scopes), show_when = { field = "operation", equals = "list_packages" } }),
			field("package_filter", "Package-name substring", "text", "", { show_when = { field = "operation", equals = "list_packages" } }),
			field("package_paths", "Include APK paths", "boolean", false, { show_when = { field = "operation", equals = "list_packages" } }),
			field("log_format", "Logcat format", "enum", "threadtime", { options = copy_array(adb_log_formats), show_when = { field = "operation", equals = "logcat" } }),
			field("log_lines", "Logcat lines", "integer", 500, { min = 1, max = 5000, show_when = { field = "operation", equals = "logcat" } }),
			field("log_filters", "Logcat filters", "target_list", {}, { rows = 4, show_when = { field = "operation", equals = "logcat" }, placeholder = "ActivityManager:I\n*:S" }),
			field("remote_path", "Remote file path", "text", "", { show_when = { field = "operation", equals = "pull" }, placeholder = "/sdcard/Download/file.bin" }),
			field("pull_preserve", "Preserve timestamp/mode", "boolean", false, { show_when = { field = "operation", equals = "pull" } }),
			field("backup_apk", "Include APK files", "boolean", false, { show_when = { field = "operation", equals = "backup" } }),
			field("backup_obb", "Include OBB files", "boolean", false, { show_when = { field = "operation", equals = "backup" } }),
			field("backup_shared", "Include shared storage", "boolean", false, { show_when = { field = "operation", equals = "backup" } }),
			field("backup_all", "All applications", "boolean", false, { show_when = { field = "operation", equals = "backup" } }),
			field("backup_system", "Include system apps with all", "boolean", true, { show_when = { field = "operation", equals = "backup" } }),
			field("backup_packages", "Specific package IDs", "target_list", {}, { rows = 5, show_when = { field = "operation", equals = "backup" } })
		}
	}
end

local function normalize_adb_diagnostics(options, context)
	if type(options) ~= "table" then return nil, "Options must be a JSON object" end
	local schema = adb_diagnostics_schema(context)
	local normalized, allowed = defaults_from_schema(schema), {}
	for _, item in ipairs(schema.fields) do allowed[item.name] = true end
	for key, value in pairs(options) do if type(key) ~= "string" or not allowed[key] then return nil, "Unknown ADB diagnostics option: " .. tostring(key) end normalized[key] = value end
	local _, devices = adb_device_choices(context)
	if type(normalized.device) ~= "string" or not devices[normalized.device] then return nil, "ADB device is not present in the live reviewed USB transport inventory" end
	local err
	normalized.operation, err = enum(normalized.operation, adb_diagnostic_operations, "ADB operation"); if not normalized.operation then return nil, err end
	normalized.wall_timeout, err = validate_integer(normalized.wall_timeout, 10, 900, "Wall timeout"); if not normalized.wall_timeout then return nil, err end
	normalized.property, err = validate_camera_text(normalized.property, "Property", 128, "^[A-Za-z0-9_.-]+$"); if normalized.property == nil then return nil, err end
	normalized.package_scope, err = enum(normalized.package_scope, adb_package_scopes, "Package scope"); if not normalized.package_scope then return nil, err end
	normalized.package_filter, err = validate_camera_text(normalized.package_filter, "Package filter", 96, "^[A-Za-z0-9_.-]+$"); if normalized.package_filter == nil then return nil, err end
	normalized.log_format, err = enum(normalized.log_format, adb_log_formats, "Log format"); if not normalized.log_format then return nil, err end
	normalized.log_lines, err = validate_integer(normalized.log_lines, 1, 5000, "Log lines"); if not normalized.log_lines then return nil, err end
	normalized.log_filters, err = validate_log_filters(normalized.log_filters); if not normalized.log_filters then return nil, err end
	normalized.backup_packages, err = validate_package_list(normalized.backup_packages); if not normalized.backup_packages then return nil, err end
	for _, name in ipairs({ "package_paths", "pull_preserve", "backup_apk", "backup_obb", "backup_shared", "backup_all", "backup_system" }) do normalized[name], err = boolean(normalized[name], name); if normalized[name] == nil then return nil, err end end
	if normalized.operation == "pull" then normalized.remote_path, err = validate_android_path(normalized.remote_path, "Remote pull path"); if not normalized.remote_path then return nil, err end
	elseif normalized.remote_path ~= "" or normalized.pull_preserve then return nil, "Pull fields are accepted only for the pull operation" end
	if normalized.operation ~= "getprop" and normalized.property ~= "" then return nil, "Property is accepted only for getprop" end
	if normalized.operation ~= "list_packages" and (normalized.package_scope ~= "all" or normalized.package_filter ~= "" or normalized.package_paths) then return nil, "Package-list fields are accepted only for list_packages" end
	if normalized.operation ~= "logcat" and (normalized.log_format ~= "threadtime" or normalized.log_lines ~= 500 or #normalized.log_filters > 0) then return nil, "Logcat fields are accepted only for logcat" end
	if normalized.operation ~= "backup" and (normalized.backup_apk or normalized.backup_obb or normalized.backup_shared or normalized.backup_all or not normalized.backup_system or #normalized.backup_packages > 0) then return nil, "Backup fields are accepted only for backup" end
	if normalized.operation == "backup" and not normalized.backup_all and not normalized.backup_shared and #normalized.backup_packages == 0 then return nil, "ADB backup requires all apps, shared storage, or at least one package" end
	if normalized.operation ~= "get_state" and devices[normalized.device].state ~= "device" then return nil, "Selected ADB transport is not in the authorized device state" end
	return normalized
end

local function build_adb_diagnostics(options, context)
	local normalized, err = normalize_adb_diagnostics(options, context)
	if not normalized then return nil, err end
	local argv = { "/usr/bin/adb", "-P", "5038", "-s", normalized.device }
	local artifacts = {}
	local op = normalized.operation
	if op == "get_state" then add(argv, "get-state")
	elseif op == "get_serialno" then add(argv, "get-serialno")
	elseif op == "get_devpath" then add(argv, "get-devpath")
	elseif op == "getprop" then add(argv, "shell"); add(argv, "getprop"); if normalized.property ~= "" then add(argv, normalized.property) end
	elseif op == "list_packages" then
		add(argv, "shell"); add(argv, "pm"); add(argv, "list"); add(argv, "packages")
		if normalized.package_scope == "third_party" then add(argv, "-3") elseif normalized.package_scope == "system" then add(argv, "-s") elseif normalized.package_scope == "enabled" then add(argv, "-e") elseif normalized.package_scope == "disabled" then add(argv, "-d") end
		if normalized.package_paths then add(argv, "-f") end
		if normalized.package_filter ~= "" then add(argv, normalized.package_filter) end
	elseif op == "logcat" then
		add(argv, "logcat"); add(argv, "-d"); add(argv, "-v"); add(argv, normalized.log_format); add(argv, "-t"); add(argv, normalized.log_lines)
		for _, filter in ipairs(normalized.log_filters) do add(argv, filter) end
		artifacts[#artifacts + 1] = { name = "android-logcat.txt", kind = "android_logcat", content_type = "text/plain", max_size = 8388608, storage = "extroot" }
	elseif op == "bugreport" then
		add(argv, "bugreport")
		artifacts[#artifacts + 1] = { name = "android-bugreport.txt", kind = "android_bugreport", content_type = "text/plain", max_size = 268435456, storage = "extroot" }
	elseif op == "pull" then
		add(argv, "pull"); if normalized.pull_preserve then add(argv, "-a") end; add(argv, normalized.remote_path); add(argv, "@ARTIFACT@/android-pull.bin")
		artifacts[#artifacts + 1] = { name = "android-pull.bin", kind = "android_pull", content_type = "application/octet-stream", max_size = 268435456, storage = "extroot" }
	else
		add(argv, "backup"); add(argv, "-f"); add(argv, "@ARTIFACT@/android-backup.ab")
		add(argv, normalized.backup_apk and "-apk" or "-noapk"); add(argv, normalized.backup_obb and "-obb" or "-noobb"); add(argv, normalized.backup_shared and "-shared" or "-noshared")
		if normalized.backup_all then add(argv, "-all"); add(argv, normalized.backup_system and "-system" or "-nosystem") end
		for _, package in ipairs(normalized.backup_packages) do add(argv, package) end
		artifacts[#artifacts + 1] = { name = "android-backup.ab", kind = "android_backup", content_type = "application/octet-stream", max_size = 1073741824, storage = "extroot" }
	end
	local preview = {}
	for _, item in ipairs(argv) do preview[#preview + 1] = preview_arg(item:gsub("^@ARTIFACT@/", "[DDK_EXTROOT_ARTIFACT]/")) end
	return { action_id = "android.adb_diagnostics", worker = "operator_adb", label = "ADB " .. op, class = "ACTION", resource = "adb", singleton = true,
		options = normalized, argv = argv, argv_preview = table.concat(preview, " "), target_summary = normalized.device .. " / " .. op,
		wall_timeout = normalized.wall_timeout, artifacts = artifacts, confirmation = { required = false } }
end

local function adb_manage_schema(context)
	local devices = adb_device_choices(context)
	local push_uploads = upload_choices(context, "any_android", false)
	local install_uploads = upload_choices(context, "android_package", true)
	local restore_uploads = upload_choices(context, "android_backup", false)
	return {
		action_id = "android.adb_manage", label = "Android ADB Device Management", class = "DISRUPTIVE",
		native = { executable = "/usr/bin/adb", version = "1.0.32", isolated_server_port = 5038 },
		fields = {
			field("device", "Authorized ADB device", "enum", devices[1] and devices[1].value or "", { options = devices }),
			field("operation", "Device-changing operation", "enum", "install", { options = copy_array(adb_manage_operations) }),
			field("wall_timeout", "Wall timeout (seconds)", "integer", 300, { min = 10, max = 1800 }),
			field("push_upload_id", "Sealed file to push", "enum", "", { options = push_uploads, show_when = { field = "operation", equals = "push" } }),
			field("push_remote_path", "Remote destination", "text", "", { show_when = { field = "operation", equals = "push" }, placeholder = "/sdcard/Download/file.bin" }),
			field("install_upload_id", "Sealed APK", "enum", "", { options = install_uploads, show_when = { field = "operation", equals = "install" } }),
			field("install_replace", "Replace existing app", "boolean", true, { show_when = { field = "operation", equals = "install" } }),
			field("install_test", "Allow test package", "boolean", false, { show_when = { field = "operation", equals = "install" } }),
			field("install_downgrade", "Allow version downgrade", "boolean", false, { show_when = { field = "operation", equals = "install" } }),
			field("install_external", "Request external storage", "boolean", false, { show_when = { field = "operation", equals = "install" } }),
			field("uninstall_package", "Package ID", "text", "", { show_when = { field = "operation", equals = "uninstall" }, placeholder = "com.example.app" }),
			field("uninstall_keep_data", "Keep app data/cache", "boolean", false, { show_when = { field = "operation", equals = "uninstall" } }),
			field("restore_upload_id", "Sealed ADB backup", "enum", "", { options = restore_uploads, show_when = { field = "operation", equals = "restore" } }),
			field("reboot_target", "Reboot destination", "enum", "normal", { options = copy_array(adb_reboot_targets), show_when = { field = "operation", equals = "reboot" } }),
			field("tcpip_port", "Device ADB TCP port", "integer", 5555, { min = 1024, max = 65535, show_when = { field = "operation", equals = "tcpip" } })
		}
	}
end

local function normalize_adb_manage(options, context)
	if type(options) ~= "table" then return nil, "Options must be a JSON object" end
	local schema = adb_manage_schema(context)
	local normalized, allowed = defaults_from_schema(schema), {}
	for _, item in ipairs(schema.fields) do allowed[item.name] = true end
	for key, value in pairs(options) do if type(key) ~= "string" or not allowed[key] then return nil, "Unknown ADB management option: " .. tostring(key) end normalized[key] = value end
	local _, devices = adb_device_choices(context)
	if type(normalized.device) ~= "string" or not devices[normalized.device] or devices[normalized.device].state ~= "device" then return nil, "ADB device is not present in the live authorized USB transport inventory" end
	local push_choices, push_records = upload_choices(context, "any_android", false)
	local install_choices, install_records = upload_choices(context, "android_package", true)
	local restore_choices, restore_records = upload_choices(context, "android_backup", false)
	local err
	normalized.operation, err = enum(normalized.operation, adb_manage_operations, "ADB operation"); if not normalized.operation then return nil, err end
	normalized.wall_timeout, err = validate_integer(normalized.wall_timeout, 10, 1800, "Wall timeout"); if not normalized.wall_timeout then return nil, err end
	normalized.reboot_target, err = enum(normalized.reboot_target, adb_reboot_targets, "Reboot target"); if not normalized.reboot_target then return nil, err end
	normalized.tcpip_port, err = validate_integer(normalized.tcpip_port, 1024, 65535, "ADB TCP port"); if not normalized.tcpip_port then return nil, err end
	for _, name in ipairs({ "install_replace", "install_test", "install_downgrade", "install_external", "uninstall_keep_data" }) do normalized[name], err = boolean(normalized[name], name); if normalized[name] == nil then return nil, err end end
	if normalized.operation == "push" then
		if not push_records[normalized.push_upload_id] then return nil, "Push requires one live sealed DDK input" end
		normalized.push_remote_path, err = validate_android_path(normalized.push_remote_path, "Remote push path"); if not normalized.push_remote_path then return nil, err end
	elseif normalized.push_upload_id ~= "" or normalized.push_remote_path ~= "" then return nil, "Push fields are accepted only for push" end
	if normalized.operation == "install" then if not install_records[normalized.install_upload_id] then return nil, "Install requires one sealed APK upload" end
	elseif normalized.install_upload_id ~= "" or not normalized.install_replace or normalized.install_test or normalized.install_downgrade or normalized.install_external then return nil, "Install fields are accepted only for install" end
	if normalized.operation == "uninstall" then normalized.uninstall_package, err = validate_package_name(normalized.uninstall_package, "Uninstall package", false); if not normalized.uninstall_package then return nil, err end
	elseif normalized.uninstall_package ~= "" or normalized.uninstall_keep_data then return nil, "Uninstall fields are accepted only for uninstall" end
	if normalized.operation == "restore" then if not restore_records[normalized.restore_upload_id] then return nil, "Restore requires one sealed ADB backup upload" end
	elseif normalized.restore_upload_id ~= "" then return nil, "Restore upload is accepted only for restore" end
	if normalized.operation ~= "reboot" and normalized.reboot_target ~= "normal" then return nil, "Reboot target is accepted only for reboot" end
	if normalized.operation ~= "tcpip" and normalized.tcpip_port ~= 5555 then return nil, "TCP port is accepted only for tcpip" end
	return normalized, { push = push_records, install = install_records, restore = restore_records }
end

local function build_adb_manage(options, context)
	local normalized, records_or_error = normalize_adb_manage(options, context)
	if not normalized then return nil, records_or_error end
	local records, input_uploads = records_or_error, {}
	local argv = { "/usr/bin/adb", "-P", "5038", "-s", normalized.device }
	local op, material = normalized.operation, normalized.device
	if op == "push" then
		add(argv, "push"); add(argv, "-p"); add(argv, "@UPLOAD@/" .. normalized.push_upload_id); add(argv, normalized.push_remote_path)
		input_uploads[1] = { id = normalized.push_upload_id, kind = records.push[normalized.push_upload_id].kind }; material = normalized.push_remote_path
	elseif op == "install" then
		add(argv, "install"); if normalized.install_replace then add(argv, "-r") end; if normalized.install_test then add(argv, "-t") end; if normalized.install_downgrade then add(argv, "-d") end; if normalized.install_external then add(argv, "-s") end
		add(argv, "@UPLOAD@/" .. normalized.install_upload_id); input_uploads[1] = { id = normalized.install_upload_id, kind = "android_package" }; material = normalized.install_upload_id
	elseif op == "uninstall" then add(argv, "uninstall"); if normalized.uninstall_keep_data then add(argv, "-k") end; add(argv, normalized.uninstall_package); material = normalized.uninstall_package
	elseif op == "restore" then add(argv, "restore"); add(argv, "@UPLOAD@/" .. normalized.restore_upload_id); input_uploads[1] = { id = normalized.restore_upload_id, kind = "android_backup" }; material = normalized.restore_upload_id
	elseif op == "reboot" then add(argv, "reboot"); if normalized.reboot_target ~= "normal" then add(argv, normalized.reboot_target) end; material = normalized.reboot_target
	elseif op == "tcpip" then add(argv, "tcpip"); add(argv, normalized.tcpip_port); material = tostring(normalized.tcpip_port)
	else add(argv, op) end
	local preview = {}
	for _, item in ipairs(argv) do preview[#preview + 1] = preview_arg(item:gsub("^@UPLOAD@/", "[SEALED_DDK_UPLOAD]/")) end
	local phrase = "RUN ADB " .. op:upper() .. " ON " .. normalized.device .. " TARGET " .. material
	return { action_id = "android.adb_manage", worker = "operator_adb", label = "ADB " .. op, class = "DISRUPTIVE", resource = "adb", singleton = true,
		options = normalized, argv = argv, argv_preview = table.concat(preview, " "), target_summary = normalized.device .. " / " .. op .. " / " .. material,
		wall_timeout = normalized.wall_timeout, artifacts = {}, input_uploads = input_uploads,
		confirmation = { required = true, phrase = phrase, reason = "This native ADB operation can change device data, state, boot mode, privileges, or exposure. Confirm the exact transport and material target." } }
end

function M.describe(action_id, context)
	if action_id == "network.nmap_lan_discovery" then return nmap_schema(context or {}) end
	if action_id == "capture.lan_metadata_snapshot" then return capture_schema(context or {}) end
	if action_id == "throughput.iperf3" then return iperf_schema(context or {}) end
	if action_id == "radio.rtl433_snapshot" then return rtl433_schema(context or {}) end
	if action_id == "camera.still_snapshot" then return camera_schema(context or {}) end
	if action_id == "serial.session" then return serial_schema(context or {}) end
	if action_id == "gps.snapshot" then return gps_schema(context or {}) end
	if action_id == "android.adb_diagnostics" then return adb_diagnostics_schema(context or {}) end
	if action_id == "android.adb_manage" then return adb_manage_schema(context or {}) end
	return nil, "Action does not expose an Operator Mode schema"
end

function M.prepare(action_id, options, context)
	if action_id == "network.nmap_lan_discovery" then return build_nmap(options, context or {}) end
	if action_id == "capture.lan_metadata_snapshot" then return build_capture(options, context or {}) end
	if action_id == "throughput.iperf3" then return build_iperf(options, context or {}) end
	if action_id == "radio.rtl433_snapshot" then return build_rtl433(options, context or {}) end
	if action_id == "camera.still_snapshot" then return build_camera(options, context or {}) end
	if action_id == "serial.session" then return build_serial(options, context or {}) end
	if action_id == "gps.snapshot" then return build_gps(options, context or {}) end
	if action_id == "android.adb_diagnostics" then return build_adb_diagnostics(options, context or {}) end
	if action_id == "android.adb_manage" then return build_adb_manage(options, context or {}) end
	return nil, "Action does not accept structured Operator Mode parameters"
end

return M
