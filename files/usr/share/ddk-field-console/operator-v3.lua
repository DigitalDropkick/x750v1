-- v3 native workflows. Pure schemas and literal argument builders.
local M = { actions = {} }
local validators

local function field(name, label, kind, default, extra)
	local result = { name = name, label = label, type = kind, default = default }
	for key, value in pairs(extra or {}) do result[key] = value end
	return result
end
local function integer(name, label, default, minimum, maximum)
	return field(name, label, "integer", default, { min = minimum, max = maximum })
end
local function choice(name, label, values, default)
	return field(name, label, "enum", default or values[1], { options = values })
end
local function live(name, label, source)
	return field(name, label, "enum", "", { source = source })
end
local function optional_live(name, label, source)
	return field(name,label,"enum","",{source=source,allow_empty=true})
end
local function text(name, label, default, validation)
	return field(name, label, "text", default or "", { validation = validation })
end
local function add(argv, ...)
	for _, value in ipairs({...}) do argv[#argv + 1] = tostring(value) end
end
local function artifact(name, maximum, kind)
	return { name = name, max_size = maximum or 16777216, kind = kind or "native_output", content_type = "text/plain", storage = "extroot" }
end
local function define(id, label, class, binaries, fields, build)
	M.actions[id] = { id = id, label = label, class = class, executables = binaries, fields = fields, build = build }
end
local function common(fields)
	fields[#fields + 1] = integer("duration", "Maximum seconds (0 = until finished or stopped)", 300, 0, 2147483647)
	fields[#fields + 1] = integer("output_mib", "Output budget (MiB)", 16, 1, 1024)
	fields[#fields].advanced = true
	return fields
end

define("network.arp_scan", "ARP discovery", "SECURITY", {"/usr/bin/arp-scan"}, common({
	live("interface", "Interface", "interfaces"), field("localnet", "Use interface subnet", "boolean", true),
	field("targets", "Other IPv4 targets or subnets", "target_list", {}, { validation = "ipv4_targets" }),
	integer("retry", "Retries", 2, 1, 20), integer("timeout_ms", "Reply timeout (ms)", 500, 10, 60000),
	integer("bandwidth", "Maximum bandwidth (bits/second)", 256000, 1000, 100000000),
	field("duplicates", "Show duplicate replies", "boolean", true)
}), function(o, c, p)
	local a = {"/usr/bin/arp-scan", "--interface="..o.interface, "--retry="..o.retry, "--timeout="..o.timeout_ms, "--bandwidth="..o.bandwidth}
	if not o.duplicates then add(a,"--ignoredups") end
	if o.localnet then add(a,"--localnet") else assert(#o.targets>0,"Enter at least one target"); for _,v in ipairs(o.targets) do add(a,v) end end
	p.resource="network-"..o.interface; return a
end)

define("network.fping", "Loss and latency monitor", "INFO", {"/usr/bin/fping"}, common({
	field("targets", "Hosts or IP addresses", "target_list", {"127.0.0.1"}, { validation = "hosts" }),
	choice("family", "Address family", {"ipv4","ipv6"}), integer("count", "Packets per host (0 = continuous)", 20, 0, 1000000),
	integer("period_ms", "Per-host interval (ms)", 1000, 10, 60000), integer("size", "Payload bytes", 56, 0, 65507),
	live("interface", "Interface", "interfaces"), field("dont_fragment", "Do not fragment", "boolean", false)
}), function(o,c,p)
	assert(#o.targets>0,"Enter at least one host")
	local a={"/usr/bin/fping",o.family=="ipv6" and "-6" or "-4","-D","-e","-o","-s","-p",tostring(o.period_ms),"-b",tostring(o.size),"-I",o.interface}
	if o.count==0 then add(a,"-l"); p.window=true else add(a,"-c",o.count) end
	if o.dont_fragment then add(a,"-M") end
	for _,v in ipairs(o.targets) do add(a,v) end
	p.success_codes={0,1};return a
end)

define("network.dns", "DNS query", "INFO", {"/usr/bin/dig"}, common({
	text("name","Name or address","example.com","dns"), text("server","DNS server (empty = system)","","optional_host"),
	choice("record","Record type",{"A","AAAA","CNAME","MX","TXT","NS","SOA","SRV","CAA","PTR","ANY","AXFR"}),
	integer("port","Server port",53,1,65535), field("tcp","Use TCP","boolean",false), field("dnssec","Request DNSSEC","boolean",false),
	field("trace","Trace delegation","boolean",false), field("short","Compact output","boolean",false),
	integer("timeout","Query timeout (seconds)",5,1,120),integer("tries","Attempts",2,1,10)
}),function(o,c,p)
	local a={"/usr/bin/dig"};if o.server~="" then add(a,"@"..o.server) end
	add(a,"-p",o.port,o.name,o.record,"+time="..o.timeout,"+tries="..o.tries)
	if o.tcp then add(a,"+tcp") end;if o.dnssec then add(a,"+dnssec") end;if o.trace then add(a,"+trace") end;if o.short then add(a,"+short") end
	return a
end)

define("automation.mqtt_subscribe", "MQTT topic monitor", "ACTION", {"/usr/bin/mosquitto_sub"}, common({
	text("host","Broker","127.0.0.1","host"),integer("port","Port",1883,1,65535),
	field("topics","Topics (wildcards supported)","target_list",{"#"},{validation="topics"}),
	integer("qos","QoS",0,0,2),choice("protocol","Protocol",{"mqttv311","mqttv5","mqttv31"}),
	text("username","Username"),field("password","Password","secret",""),field("tls","Use system TLS certificates","boolean",false),
	integer("count","Message count (0 = until stopped)",0,0,1000000),field("retained_only","Retained messages only","boolean",false),
	field("remove_retained","Clear matching retained messages","boolean",false)
}),function(o,c,p)
	assert(#o.topics>0,"Choose at least one topic")
	local a={"/usr/bin/mosquitto_sub","-h",o.host,"-p",tostring(o.port),"-q",tostring(o.qos),"-V",o.protocol,"-v"}
	if o.duration>0 then add(a,"-W",o.duration) end
	for _,v in ipairs(o.topics) do add(a,"-t",v) end
	if o.username~="" then add(a,"-u",o.username) end
	if o.password~="" then add(a,"-P",p.private("mqtt-password",o.password));o.password="[REDACTED]" end
	if o.tls then add(a,"--tls-use-os-certs") end;if o.count>0 then add(a,"-C",o.count) end
	if o.retained_only then add(a,"--retained-only") end
	if o.remove_retained then add(a,"--remove-retained");p.confirm="CLEAR RETAINED "..o.host.." "..table.concat(o.topics,",") end
	p.window=true;p.success_codes={0,27};return a
end)

local modem_queries={signal="--get-signal-info",system="--get-system-info",serving="--get-serving-system",data="--get-data-status",settings="--get-current-settings",capabilities="--get-capabilities",pin_status="--get-pin-status",sim_state="--uim-get-sim-state",carrier="--get-plmn",aggregation="--get-lte-cphy-ca-info",operating_mode="--get-device-operating-mode",cell_location="--get-cell-location-info"}
define("cellular.diagnostics","Cellular diagnostics","INFO",{"/sbin/uqmi"},common({
	choice("operation","Diagnostic",{"signal","system","serving","data","settings","capabilities","pin_status","sim_state","carrier","aggregation","operating_mode","cell_location"})
}),function(o,c,p) p.resource="modem-ec25";p.hardware="modem";return {"/sbin/uqmi","-d","/dev/cdc-wdm0",assert(modem_queries[o.operation])} end)

define("cellular.control","Cellular connection controls","DISRUPTIVE",{"/sbin/uqmi","/sbin/ifup"},common({
	choice("operation","Operation",{"reconnect","register","network_scan","network_modes","roaming","online"}),
	choice("network_mode","Allowed network modes",{"all","lte","umts","gsm","lte,umts","lte,umts,gsm"}),
	choice("roaming","Roaming preference",{"any","off","only"})
}),function(o,c,p)
	p.resource="modem-ec25";p.hardware="modem";p.confirm="CELLULAR "..o.operation:upper().." EC25"
	if o.operation=="reconnect" then assert(c.cellular_interface and c.cellular_interface~="","No modem-managed network interface detected");return {"/sbin/ifup",c.cellular_interface} end
	local a={"/sbin/uqmi","-d","/dev/cdc-wdm0"}
	if o.operation=="register" then add(a,"--network-register") elseif o.operation=="network_scan" then add(a,"--network-scan") elseif o.operation=="network_modes" then add(a,"--set-network-modes",o.network_mode) elseif o.operation=="roaming" then add(a,"--set-network-roaming",o.roaming) else add(a,"--set-device-operating-mode","online") end
	return a
end)

define("forensics.hex","Hex inspection","INFO",{"/usr/bin/xxd"},common({
	live("input","Input file","uploads"),integer("offset","Byte offset",0,0,1099511627776),integer("length","Bytes to display",4096,1,16777216),
	integer("columns","Bytes per line",16,1,64),field("plain","Plain hexadecimal","boolean",false)
}),function(o,c,p)
	local a={"/usr/bin/xxd","-s",tostring(o.offset),"-l",tostring(o.length),"-c",tostring(o.columns)}
	if o.plain then add(a,"-p") end;add(a,p.upload(o.input));return a
end)

define("auth.otp","OATH token generation","SECURITY",{"/usr/bin/oathtool"},common({
	choice("mode","Mode",{"totp","hotp"}),choice("algorithm","Algorithm",{"SHA1","SHA256","SHA512"}),
	field("key","Token seed","secret",""),field("base32","Base32 seed","boolean",true),integer("digits","Digits",6,6,8),
	integer("counter","HOTP counter",0,0,9007199254740991),integer("step","TOTP step (seconds)",30,1,3600)
}),function(o,c,p)
	assert(o.key~="","A token seed is required")
	if o.base32 then assert(o.key:match("^[A-Za-z2-7=]+$"),"Invalid Base32 seed") else assert(o.key:match("^[0-9A-Fa-f]+$") and #o.key%2==0,"Invalid hexadecimal seed") end
	local a={"/usr/bin/oathtool","--digits="..o.digits}
	if o.mode=="totp" then add(a,"--totp="..o.algorithm,"--time-step-size="..o.step.."s") else add(a,"--hotp","--counter="..o.counter) end
	if o.base32 then add(a,"--base32") end
	add(a,"-");p.stdin=p.private("otp-key",o.key);o.key="[REDACTED]";p.sensitive=true;return a
end)

define("bluetooth.services","Bluetooth services and GATT","SECURITY",{"/usr/bin/sdptool","/usr/bin/gatttool","/usr/bin/hciconfig"},common({
	live("controller","Bluetooth adapter","bluetooth_all"),choice("operation","Operation",{"services","primary","characteristics","descriptors","read","write","up","down","info"}),
	text("address","Remote device address","00:00:00:00:00:00","mac"),choice("address_type","LE address type",{"public","random"}),
	text("handle","Attribute handle","0x0001","handle"),text("value","Write value (hexadecimal)","","optional_hex"),
	choice("security","Security level",{"low","medium","high"})
}),function(o,c,p)
	p.hardware="bluetooth";p.resource="bluetooth-"..o.controller
	if o.operation=="up" or o.operation=="down" or o.operation=="info" then
		local a={"/usr/bin/hciconfig",o.controller};if o.operation~="info" then add(a,o.operation);p.confirm="BLUETOOTH "..o.controller.." "..o.operation:upper() end;return a
	end
	if o.operation=="services" then return {"/usr/bin/sdptool","-i",o.controller,"browse",o.address} end
	local a={"/usr/bin/gatttool","-i",o.controller,"-b",o.address,"-t",o.address_type,"--sec-level="..o.security}
	if o.operation=="primary" then add(a,"--primary") elseif o.operation=="characteristics" then add(a,"--characteristics") elseif o.operation=="descriptors" then add(a,"--char-desc") elseif o.operation=="read" then add(a,"--char-read","--handle="..o.handle) else assert(o.value~="","Enter write bytes");add(a,"--char-write-req","--handle="..o.handle,"--value="..o.value);p.confirm="GATT WRITE "..o.address.." "..o.handle end
	return a
end)

define("can.capture","CAN capture","ACTION",{"/usr/bin/candump"},common({
	live("interface","CAN interface","can_devices"),text("filter","CAN ID:mask filter (optional)","","can_filter"),
	integer("count","Frames (0 = until stopped)",0,0,10000000),field("log_format","Replay-compatible log format","boolean",true),field("errors","Decode error frames","boolean",true),field("ascii","Show ASCII","boolean",false)
}),function(o,c,p)
	local a={"/usr/bin/candump"};if o.log_format then add(a,"-L") else add(a,"-t","a","-x") end;if o.errors then add(a,"-e") end;if o.ascii then add(a,"-a") end;if o.count>0 then add(a,"-n",o.count) end
	add(a,o.interface..(o.filter~="" and ","..o.filter or ""));p.window=true;p.hardware="can";p.resource="can-rx-"..o.interface;return a
end)

define("can.transmit","CAN transmit","DISRUPTIVE",{"/usr/bin/cansend"},common({
	live("interface","CAN interface","can_devices"),text("frame","Frame (ID#DATA or CAN-FD ID##FLAGDATA)","123#01020304","can_frame")
}),function(o,c,p) p.hardware="can";p.resource="can-tx-"..o.interface;p.confirm="SEND CAN "..o.interface.." "..o.frame;return {"/usr/bin/cansend",o.interface,o.frame} end)

define("can.configure","CAN interface setup","DISRUPTIVE",{"/sbin/ip","/usr/libexec/ddk-device-session"},common({
	live("interface","CAN interface","can_devices"),choice("operation","Operation",{"up","down","bitrate","restart"}),integer("bitrate","Bitrate",500000,1000,10000000),
	integer("restart_ms","Automatic bus-off restart (ms)",100,0,60000)
}),function(o,c,p)
	p.hardware="can";p.resource="can-config-"..o.interface;p.confirm="CONFIGURE CAN "..o.interface.." "..o.operation:upper()
	if o.operation=="bitrate" then return {"/usr/libexec/ddk-device-session","can",o.interface,tostring(o.bitrate),tostring(o.restart_ms)} end
	local a={"/sbin/ip","link","set",o.interface}
	if o.operation=="up" or o.operation=="down" then add(a,o.operation) elseif o.operation=="restart" then add(a,"type","can","restart") else add(a,"type","can","bitrate",o.bitrate,"restart-ms",o.restart_ms) end
	return a
end)

define("wireless.monitor","Wireless monitor capture","SECURITY",{"/usr/sbin/tcpdump"},common({
	live("phy","Radio","wireless_phys"),integer("channel","Channel (0 = keep current shared channel)",0,0,196),
	integer("packet_count","Packets (0 = until stopped)",0,0,100000000),integer("capture_mib","PCAP budget (MiB)",512,1,8192),
	integer("snaplen","Bytes per frame (0 = full frame)",0,0,262144),text("filter","Capture filter (BPF)","","bpf")
}),function(o,c,p)
	local radio;for _,item in ipairs(c.wireless_phys or {}) do if item.value==o.phy then radio=item end end
	assert(radio,"Select a current wireless radio")
	if o.channel~=0 then assert(not radio.active,"This radio has active interfaces; keep its current channel or select an unused radio") end
	p.hardware="monitor";p.resource="wireless-"..o.phy;p.window=true;p.monitor=true
	p.confirm="MONITOR "..o.phy..(o.channel==0 and " CURRENT CHANNEL" or " CHANNEL "..o.channel)
	local a={"/usr/sbin/tcpdump","-i","@MONITOR@","-s",tostring(o.snaplen),"-U","-w","@ARTIFACT@/wireless.pcap"}
	if o.packet_count>0 then add(a,"-c",o.packet_count) end
	if o.filter~="" then add(a,o.filter) end
	p.artifacts={artifact("wireless.pcap",o.capture_mib*1048576,"wireless_capture")};p.artifacts[1].content_type="application/vnd.tcpdump.pcap";return a
end)

define("usb.power","USB hub port power","DISRUPTIVE",{"/usr/sbin/uhubctl"},common({
	optional_live("hub","USB hub","usb_hubs"),choice("operation","Operation",{"status","on","off","cycle"}),integer("port","Hub port",1,1,255),integer("delay","Cycle delay (seconds)",2,1,120)
}),function(o,c,p)
	local a={"/usr/sbin/uhubctl"};if o.operation=="status" and o.hub=="" then return a end
	local hub;for _,item in ipairs(c.usb_hubs or {}) do if item.value==o.hub then hub=item end end
	assert(hub and o.port<=hub.ports,"Choose an available hub and port")
	add(a,"-l",o.hub,"-p",o.port,"-e")
	if o.operation~="status" then
		if o.operation~="on" then local target,reason=c.usb_policy.check_port(c.usb_inventory,o.hub,o.port);assert(target,"This port supplies "..tostring(reason).."; use a different port") end
		add(a,"-a",o.operation);if o.operation=="cycle" then add(a,"-d",o.delay) end
		p.hardware="usb_power";p.confirm="USB POWER "..o.operation:upper().." "..o.hub.." PORT "..o.port
	end
	p.resource="usb-power-"..o.hub.."-"..o.port;return a
end)

define("usbip.attach","USB/IP connections","DISRUPTIVE",{"/usr/libexec/ddk-usbip-client","/usr/sbin/usbip"},common({
	choice("operation","Operation",{"list_remote","list_local","ports","attach","detach"}),text("host","Remote USB/IP host","192.168.8.100","host"),
	integer("server_port","USB/IP server port",3240,1,65535),text("busid","Remote device bus ID","1-1","usb_busid"),optional_live("port","Imported port to detach","usbip_ports")
}),function(o,c,p)
	local a={"/usr/libexec/ddk-usbip-client"}
	if o.operation=="list_remote" then add(a,"list","--host",o.host,"--server-port",o.server_port)
	elseif o.operation=="list_local" then a={"/usr/sbin/usbip","list","-l"}
	elseif o.operation=="ports" then add(a,"ports")
	elseif o.operation=="attach" then add(a,"attach","--host",o.host,"--server-port",o.server_port,"--busid",o.busid);p.hardware="usbip";p.confirm="ATTACH USB "..o.host.." "..o.busid
	else assert(o.port~="","Select an imported USB/IP port");add(a,"detach","--port",o.port);p.hardware="usbip";p.confirm="DETACH USB/IP PORT "..o.port end
	if not p.confirm then p.class="INFO" end;p.resource="usbip";return a
end)

define("industrial.modbus_write","Modbus reads, polling, and writes","DISRUPTIVE",{"/usr/libexec/ddk-modbus-client"},common({
	choice("transport","Transport",{"tcp","rtu"}),text("host","Modbus host","127.0.0.1","host"),integer("port","TCP port",502,1,65535),
	optional_live("device","RTU adapter","serial_devices"),choice("baud","Baud rate",{"1200","2400","4800","9600","19200","38400","57600","115200"},"19200"),
	choice("parity","Parity",{"N","E","O"},"E"),choice("stop_bits","Stop bits",{"1","2"}),field("rs485","Driver RS485 mode","boolean",false),choice("rts","RTS direction",{"none","up","down"}),
	integer("unit","Slave / unit ID",1,1,247),choice("operation","Function",{"read_coils","read_discrete","read_holding","read_input","write_coil","write_register","write_coils","write_registers"},"read_holding"),
	integer("address","Zero-based start address",0,0,65535),integer("count","Read count",1,1,2000),
	field("values","Write values (one decimal value per line)","integer_list",{0},{min=0,max=65535}),
	field("verify","Read back after write","boolean",true),integer("timeout","Response timeout (seconds)",3,1,120),
	integer("cycles","Poll cycles (0 = until stopped)",1,0,1000000),integer("interval","Poll interval (seconds)",1,1,3600)
}),function(o,c,p)
	local writing=o.operation:match("^write_")~=nil;local coils=o.operation:find("coil",1,true)~=nil or o.operation=="read_discrete"
	if o.transport=="rtu" then assert(o.device~="","Select an RTU adapter");p.hardware="serial" end
	local count=writing and #o.values or o.count
	local max=writing and (coils and 1968 or 123) or (coils and 2000 or 125)
	if o.operation=="write_coil" or o.operation=="write_register" then max=1 end
	assert(count>=1 and count<=max and o.address+count<=65536,"Address/count exceeds the selected Modbus function's range")
	if writing and coils then for _,value in ipairs(o.values) do assert(value==0 or value==1,"Coils accept only 0 or 1") end end
	local a={"/usr/libexec/ddk-modbus-client","--transport",o.transport,"--unit",tostring(o.unit),"--function",o.operation,"--address",tostring(o.address),"--count",tostring(o.count),"--timeout",tostring(o.timeout),"--cycles",tostring(o.cycles),"--interval",tostring(o.interval)}
	if o.transport=="tcp" then add(a,"--host",o.host,"--port",o.port);p.resource="modbus-"..o.host:gsub("[^A-Za-z0-9_.-]","-").."-"..o.port
	else add(a,"--device",o.device,"--baud",o.baud,"--parity",o.parity,"--stop-bits",o.stop_bits,"--rts",o.rts);if o.rs485 then add(a,"--rs485") end end
	if writing then
		local values={};for _,value in ipairs(o.values) do values[#values+1]=tostring(value) end;add(a,"--values",table.concat(values,","));if o.verify then add(a,"--verify") end
		p.confirm="MODBUS WRITE "..(o.transport=="tcp" and o.host..":"..o.port or o.device).." UNIT "..o.unit.." ADDRESS "..o.address
	else p.class="ACTION" end
	p.window=o.cycles==0;p.target_summary=(o.transport=="tcp" and o.host..":"..o.port or o.device).." / unit "..o.unit.." / address "..o.address;return a
end)

define("cellular.raw_command","EC25 AT and built-in GNSS","DISRUPTIVE",{"/usr/bin/socat"},common({
	choice("operation","Operation",{"modem_info","gnss_status","gnss_position","gnss_start","gnss_stop","custom_at"}),
	text("command","AT command","AT","at_command"),integer("reply_timeout","Reply inactivity timeout (seconds)",5,1,120)
}),function(o,c,p)
	assert(c.modem_at_node,"The EC25 AT interface is not present")
	local commands={modem_info="ATI",gnss_status="AT+QGPS?",gnss_position="AT+QGPSLOC=2",gnss_start="AT+QGPS=1",gnss_stop="AT+QGPSEND"}
	local command=commands[o.operation] or o.command
	p.hardware="modem_at";p.resource="modem-ec25";o.device=c.modem_at_node
	p.stdin=p.private("modem-at",command.."\r");p.window=true
	if o.operation=="custom_at" or o.operation=="gnss_start" or o.operation=="gnss_stop" then p.confirm="EC25 "..o.operation:upper() else p.class="INFO" end
	if o.operation=="custom_at" then o.command="[REDACTED]" end
	return {"/usr/bin/socat","-T",tostring(o.reply_timeout),"STDIO,ignoreeof","OPEN:"..c.modem_at_node..",rawer,echo=0,b115200,clocal=1"}
end)

define("serial.console","Interactive serial console","ACTION",{"/usr/bin/socat"},common({
	live("device","Serial adapter","serial_devices"),choice("baud","Baud rate",{"9600","19200","38400","57600","115200","230400","460800","921600"},"115200"),
	choice("parity","Parity",{"none","even","odd"}),choice("data_bits","Data bits",{"8","7"}),choice("stop_bits","Stop bits",{"1","2"}),
	field("rtscts","RTS/CTS flow control","boolean",false)
}),function(o,c,p)
	p.hardware="serial";p.resource="serial-"..o.device:gsub("/","-");p.interactive=true;p.window=true
	p.confirm="OPEN SERIAL "..o.device.." AT "..o.baud
	local address="OPEN:"..o.device..",rawer,echo=0,clocal=1,b"..o.baud..",cs"..o.data_bits
	address=address..(o.parity=="none" and ",parenb=0" or ",parenb=1,parodd="..(o.parity=="odd" and "1" or "0"))..",cstopb="..(o.stop_bits=="2" and "1" or "0")..",crtscts="..(o.rtscts and "1" or "0")
	return {"/usr/bin/socat","STDIO",address}
end)

define("android.operator","Android device tools","DISRUPTIVE",{"/usr/bin/adb"},common({
	choice("transport","Connection",{"usb","tcp"}),optional_live("device","USB device","android_devices"),
	text("host","Network device host","192.168.8.100","host"),integer("port","ADB port",5555,1,65535),
	choice("operation","Operation",{"get_state","properties","packages","list_path","disk_usage","processes","dumpsys","logcat","bugreport","pull_file","pull_directory","push","install","install_multiple","uninstall","reboot","root","remount","tcpip","usb"}),
	text("remote_path","Path on Android device","/sdcard/Download","android_path"),
	optional_live("input","Input file","uploads"),field("packages","APK files for split install","upload_list",{},{source="apk_uploads"}),
	text("package","Application package name","com.example.app","package"),
	choice("service","Dumpsys service",{"battery","package","connectivity","wifi","telephony.registry","diskstats","meminfo","activity","power","usb","deviceidle","netstats"}),
	integer("user","Android user ID",0,0,99999),field("replace","Replace installed package","boolean",true),field("downgrade","Allow package downgrade","boolean",false),
	field("test_package","Allow test packages","boolean",false),field("keep_data","Keep app data on uninstall","boolean",false),
	choice("reboot_mode","Reboot destination",{"system","recovery","bootloader"}),integer("log_lines","Log lines",2000,1,1000000),
	integer("artifact_mib","File / directory budget (MiB)",1024,1,16384)
}),function(o,c,p)
	local target
	if o.transport=="tcp" then target=(o.host:find(":",1,true) and "["..o.host.."]" or o.host)..":"..o.port;p.adb_connect=target
	else
		assert(o.device~="","Select a USB device, or choose a network connection")
		for _,device in ipairs(c.android_devices or {}) do if (device.value or device.serial)==o.device then target=o.device end end
		assert(target,"Selected ADB transport is no longer present")
	end
	p.adb=true;p.resource="adb";p.target_summary=target
	local a={"/usr/bin/adb","-P","5038","-s",target};local op=o.operation
	if op=="get_state" then add(a,"get-state")
	elseif op=="properties" then add(a,"shell","getprop")
	elseif op=="packages" then add(a,"shell","pm","list","packages","-f","--user",o.user)
	elseif op=="list_path" then add(a,"shell","ls","-la", "'"..o.remote_path.."'")
	elseif op=="disk_usage" then add(a,"shell","df","-h")
	elseif op=="processes" then add(a,"shell","ps","-A")
	elseif op=="dumpsys" then add(a,"shell","dumpsys",o.service)
	elseif op=="logcat" then add(a,"logcat","-d","-v","threadtime","-t",o.log_lines)
	elseif op=="bugreport" then add(a,"bugreport")
	elseif op=="pull_file" then
		add(a,"pull",o.remote_path,"@ARTIFACT@/android-file.bin");p.artifacts={artifact("android-file.bin",o.artifact_mib*1048576,"android_file")};p.artifacts[1].content_type="application/octet-stream"
	elseif op=="pull_directory" then
		add(a,"pull",o.remote_path,"@WORK@/android-directory");p.workspaces={{name="android-directory",storage="extroot",reserve_size=o.artifact_mib*1048576}}
		p.artifacts={artifact("android-files.tar",o.artifact_mib*1048576,"android_directory")};p.artifacts[1].content_type="application/x-tar";p.archive_directory=true
	elseif op=="push" then add(a,"push",p.upload(o.input),o.remote_path)
	elseif op=="install" or op=="install_multiple" then
		add(a,op=="install" and "install" or "install-multiple")
		if o.replace then add(a,"-r") end;if o.downgrade then add(a,"-d") end;if o.test_package then add(a,"-t") end
		local inputs=op=="install" and {o.input} or o.packages;assert(#inputs>0,"Select at least one APK")
		for _,id in ipairs(inputs) do
			local found=false;for _,u in ipairs(c.uploads or {}) do if u.id==id and u.kind=="android_package" and u.original_name:lower():match("[.]apk$") then found=true end end
			assert(found,"Installation requires sealed APK files; select every split including the base APK")
			add(a,p.upload(id))
		end;p.apk_inputs=true
	elseif op=="uninstall" then add(a,"uninstall");if o.keep_data then add(a,"-k") end;add(a,o.package)
	elseif op=="reboot" then add(a,"reboot");if o.reboot_mode~="system" then add(a,o.reboot_mode) end
	elseif op=="tcpip" then add(a,"tcpip",o.port)
	else add(a,op) end
	if ({push=true,install=true,install_multiple=true,uninstall=true,reboot=true,root=true,remount=true,tcpip=true,usb=true})[op] then p.confirm="ANDROID "..op:upper().." "..target else p.class="ACTION" end
	return a
end)

define("camera.video", "Camera recording and controls", "ACTION", {"/usr/bin/v4l2-ctl"}, common({
	live("device","Camera","camera_devices"),choice("operation","Operation",{"formats","controls","record","set_control"}),
	integer("width","Width",640,16,4096),integer("height","Height",480,16,2160),choice("format","Pixel format",{"MJPG","H264","YUYV"}),
	integer("frames","Frames (0 = until stopped)",0,0,10000000),integer("record_mib","Recording budget (MiB)",512,1,8192),
	text("control","Control name","brightness","identifier"),integer("value","Control value",128,-2147483648,2147483647)
}),function(o,c,p)
	p.hardware="camera";p.resource="camera-"..o.device:gsub("/","-")
	local a={"/usr/bin/v4l2-ctl","-d",o.device}
	if o.operation=="formats" then add(a,"--list-formats-ext") elseif o.operation=="controls" then add(a,"--list-ctrls-menus")
	elseif o.operation=="set_control" then add(a,"--set-ctrl="..o.control.."="..o.value);p.confirm="SET CAMERA "..o.device.." "..o.control.."="..o.value
	else
		local filename=o.format=="MJPG" and "camera.mjpg" or o.format=="H264" and "camera.h264" or "camera.yuyv"
		add(a,"--set-fmt-video=width="..o.width..",height="..o.height..",pixelformat="..o.format,"--stream-mmap=3","--stream-poll","--stream-count="..o.frames,"--stream-to=@ARTIFACT@/"..filename)
		local adef=artifact(filename,o.record_mib*1048576,"video");adef.content_type="application/octet-stream";p.artifacts={adef};p.window=true
	end;return a
end)

define("radio.receiver_tools","SDR benchmark and I/Q stream","ACTION",{"/usr/bin/rtl_test","/usr/bin/rtl_tcp"},common({
	live("device","RTL-SDR receiver","rtl_devices"),choice("operation","Operation",{"benchmark","ppm","stream"}),
	integer("frequency","Frequency (Hz)",433920000,24000000,1766000000),integer("sample_rate","Sample rate",1024000,225001,3200000),
	integer("gain","Gain (dB; 0 = automatic)",0,0,50),integer("ppm","Frequency correction (ppm)",0,-1000,1000),
	live("listen_address","Listen address","service_addresses"),integer("port","Stream port",1234,1024,65535)
}),function(o,c,p)
	for _,device in ipairs(c.rtl_devices or {}) do if type(device)=="table" and (device.value or device.selector)==o.device then p.rtl_identity=device end end
	p.hardware="rtl_sdr";p.resource="rtl-sdr-"..o.device:gsub("[^A-Za-z0-9_.-]","-");p.window=true
	if o.operation~="stream" then
		local a={"/usr/bin/rtl_test","-d",o.device,"-s",tostring(o.sample_rate)};if o.operation=="ppm" then add(a,"-p",10) end;return a
	end
	p.confirm="STREAM SDR "..o.device.." ON "..o.listen_address..":"..o.port
	return {"/usr/bin/rtl_tcp","-d",o.device,"-a",o.listen_address,"-p",tostring(o.port),"-f",tostring(o.frequency),"-s",tostring(o.sample_rate),"-g",tostring(o.gain),"-P",tostring(o.ppm),"-n","32"}
end)

define("gps.receiver_control","GNSS receiver configuration","DISRUPTIVE",{"/usr/bin/gpsctl"},common({
	live("device","GNSS receiver","gps_devices"),choice("operation","Operation",{"identify","nmea","binary","speed","rate","reset"}),
	choice("baud","Baud rate",{"4800","9600","19200","38400","57600","115200","230400"}),integer("cycle_ms","Measurement period (ms)",1000,100,60000)
}),function(o,c,p)
	p.hardware="serial";p.resource="serial-"..o.device:gsub("/","-")
	local a={"/usr/bin/gpsctl","--direct"};if o.duration>0 then add(a,"--timeout",o.duration) end
	if o.operation=="speed" then add(a,"--speed",o.baud) elseif o.operation=="rate" then add(a,"--rate",o.cycle_ms/1000)
	elseif o.operation~="identify" then add(a,"--"..o.operation) end
	if o.operation~="identify" then p.confirm="CONFIGURE GNSS "..o.device.." "..o.operation:upper() end
	add(a,o.device);return a
end)

define("monitoring.bandwidth","Live bandwidth monitor","INFO",{"/usr/sbin/bmon"},common({
	live("interface","Interface","interfaces"),integer("interval","Sample interval (seconds)",1,1,60),field("bits","Display bits per second","boolean",true)
}),function(o,c,p)
	p.window=true;local a={"/usr/sbin/bmon","-p",o.interface,"-r",tostring(o.interval),"-o","ascii","-a"};if o.bits then add(a,"-b") end;return a
end)

define("capture.inspect","Inspect a saved capture","INFO",{"/usr/sbin/tcpdump"},common({
	live("input","Capture file","uploads"),integer("count","Packets (0 = all)",1000,0,10000000),choice("detail","Packet detail",{"summary","verbose","hex","ascii"}),
	field("numeric","Numeric addresses and ports","boolean",true)
}),function(o,c,p)
	local a={"/usr/sbin/tcpdump","-r",p.upload(o.input)};if o.numeric then add(a,"-nn") end;if o.count>0 then add(a,"-c",o.count) end
	if o.detail=="verbose" then add(a,"-vvv") elseif o.detail=="hex" then add(a,"-XX") elseif o.detail=="ascii" then add(a,"-A") end;return a
end)

define("storage.ddrescue","Resumable storage recovery","ACTION",{"/usr/sbin/ddrescue"},common({
	live("device","Source drive or partition","storage_devices"),integer("offset","Source byte offset",0,0,8796093022208),
	integer("length","Bytes to recover",1073741824,512,8796093022208),integer("retry_passes","Retry passes",1,0,1000),
	field("no_scrape","Fast first pass (skip scraping)","boolean",true),field("direct","Direct device access","boolean",false),
	live("resume","Resume saved recovery (or New recovery)","recovery_jobs")
}),function(o,c,p)
	local device;for _,d in ipairs(c.storage_devices or {}) do if (d.value or d.node)==o.device then device=d end end
	assert(device and not device.mounted,"Choose an unmounted source drive or partition")
	assert(o.offset+o.length<=device.size,"Requested range exceeds the source size")
	p.hardware="storage";p.resource="storage-"..device.disk;p.device_identity=device
	if o.resume~="new" then
		for _,r in ipairs(c.recovery_jobs or {}) do
			if r.value==o.resume then
				assert(r.options.device==o.device and r.options.offset==o.offset and r.options.length==o.length,"Resume requires the same source and byte range")
				p.recovery=r.value;p.recovery_identity=r.device_identity
			end
		end
		assert(p.recovery,"Saved recovery is unavailable")
	end
	local a={"/usr/sbin/ddrescue","--input-position="..o.offset,"--output-position=0","--size="..o.length,"--retry-passes="..o.retry_passes}
	if o.no_scrape then add(a,"--no-scrape") end;if o.direct then add(a,"--idirect") end
	add(a,o.device,"@ARTIFACT@/recovery.raw","@ARTIFACT@/recovery.map")
	p.artifacts={artifact("recovery.raw",o.length,"storage_image"),artifact("recovery.map",16777216,"recovery_map")};p.artifacts[1].content_type="application/octet-stream"
	return a
end)

define("storage.clone","Clone or recover onto another drive","DISRUPTIVE",{"/usr/sbin/ddrescue"},common({
 live("device","Source drive or partition","storage_devices"),live("target","Destination drive or partition (overwritten)","storage_devices"),
 integer("offset","Source byte offset",0,0,8796093022208),integer("target_offset","Destination byte offset",0,0,8796093022208),integer("length","Bytes to copy (0 = remaining source)",0,0,8796093022208),
 integer("retry_passes","Retry passes",1,0,1000),field("no_scrape","Fast first pass","boolean",true),field("direct","Direct source access","boolean",false),
 live("resume","Resume saved clone","clone_jobs")
}),function(o,c,p)
 local source,target;for _,device in ipairs(c.storage_devices or {}) do if (device.value or device.node)==o.device then source=device end;if (device.value or device.node)==o.target then target=device end end
 assert(source and target and source.disk~=target.disk,"Select source and destination on two different physical drives")
 assert(not source.mounted and not target.mounted,"Unmount all source and destination partitions before cloning")
 if o.length==0 then o.length=source.size-o.offset end
 assert(o.length>0 and o.offset+o.length<=source.size,"Copy range exceeds the source")
 assert(o.target_offset+o.length<=target.size,"Destination is too small for this range")
 p.hardware="storage";p.resource="storage-"..source.disk;p.device_identity=source;p.clone_target=target
 if o.resume~="new" then
  for _,record in ipairs(c.clone_jobs or {}) do if record.value==o.resume then
   for _,field in ipairs({"device","target","offset","target_offset","length"}) do assert(record.options[field]==o[field],"Resume needs the same source, destination and byte range") end
   assert(record.device_identity and record.clone_target and record.device_identity.serial==source.serial and record.clone_target.serial==target.serial and record.device_identity.size==source.size and record.clone_target.size==target.size,"Saved clone device identities no longer match")
   p.clone_resume=record.value
  end end
  assert(p.clone_resume,"Choose an available saved clone")
 end
 p.confirm="OVERWRITE "..o.target.." FROM "..o.device.." "..o.length.." BYTES AT "..o.target_offset
 local a={"/usr/sbin/ddrescue","--force","--input-position="..o.offset,"--output-position="..o.target_offset,"--size="..o.length,"--retry-passes="..o.retry_passes}
 if o.no_scrape then add(a,"--no-scrape") end;if o.direct then add(a,"--idirect") end
 add(a,o.device,o.target,"@ARTIFACT@/clone.map")
 p.artifacts={artifact("clone.map",16777216,"recovery_map")};return a
end)

define("capture.ring","Rotating packet capture","SECURITY",{"/usr/sbin/tcpdump"},common({
	live("interface","Interface","interfaces"),text("filter","Capture filter (BPF)","","bpf"),
	integer("segment_mb","Maximum file size (decimal MB)",64,1,4096),integer("segments","Files in rotation",4,2,64),
	integer("snaplen","Bytes per packet (0 = full packet)",0,0,262144),field("promiscuous","Promiscuous capture","boolean",true)
}),function(o,c,p)
	local a={"/usr/sbin/tcpdump","-i",o.interface,"-s",tostring(o.snaplen),"-U","-C",tostring(o.segment_mb),"-W",tostring(o.segments),"-w","@ARTIFACT@/capture.pcap"}
	if not o.promiscuous then add(a,"-p") end;if o.filter~="" then add(a,o.filter) end
	local size=o.segment_mb*1000000+262144
	p.artifacts={artifact("capture.pcap",size,"pcap")}
	local width=#tostring(o.segments-1)
	for i=0,o.segments-1 do local item=artifact("capture.pcap"..string.format("%0"..width.."d",i),size,"pcap");item.content_type="application/vnd.tcpdump.pcap";p.artifacts[#p.artifacts+1]=item end
	p.window=true;p.resource="capture-"..o.interface;return a
end)

define("can.replay","Replay saved CAN frames","DISRUPTIVE",{"/usr/bin/canplayer"},common({
	live("interface","Destination CAN interface","can_devices"),live("input","candump log file","uploads"),
	text("recorded_interface","Interface name in the log","can0","interface_name"),integer("loops","Replay loops",1,1,1000000),
	field("ignore_timing","Send without recorded timing","boolean",false),integer("gap_ms","Minimum gap (milliseconds)",1,0,60000)
}),function(o,c,p)
	p.hardware="can";p.resource="can-tx-"..o.interface;p.confirm="REPLAY CAN "..o.interface.." "..o.input
	local a={"/usr/bin/canplayer","-I",p.upload(o.input),"-l",tostring(o.loops),"-g",tostring(o.gap_ms)}
	if o.ignore_timing then add(a,"-t") end;add(a,o.interface.."="..o.recorded_interface);return a
end)

define("serial.transfer","Serial file transfer","ACTION",{"/usr/bin/socat"},common({
	live("device","Serial adapter","serial_devices"),choice("direction","Transfer",{"receive","send_receive"}),optional_live("input","File to transmit","uploads"),
	choice("baud","Baud rate",{"1200","2400","4800","9600","19200","38400","57600","115200","230400","460800","921600"},"115200"),
	integer("idle_timeout","Stop after idle seconds (0 = wait)",10,0,3600),field("rtscts","RTS/CTS flow control","boolean",false)
}),function(o,c,p)
	p.hardware="serial";p.resource="serial-"..o.device:gsub("/","-");p.window=true
	local a={"/usr/bin/socat"};if o.idle_timeout>0 then add(a,"-T",o.idle_timeout) end
	if o.direction=="send_receive" then p.upload(o.input);p.stdin_upload=o.input;p.confirm="SEND FILE "..o.input.." TO "..o.device end
	add(a,"STDIO,ignoreeof","OPEN:"..o.device..",rawer,echo=0,clocal=1,b"..o.baud..",crtscts="..(o.rtscts and "1" or "0"))
	p.stdout_artifact="serial-transfer.bin";p.artifacts={artifact("serial-transfer.bin",o.output_mib*1048576,"serial_capture")};p.artifacts[1].content_type="application/octet-stream";return a
end)

define("auth.stoken","Software token tools","SECURITY",{"/usr/bin/stoken"},common({
	choice("operation","Operation",{"tokencode","show","export"}),field("token","Token string","secret",""),
	field("password","Token password (if encrypted)","secret",""),field("pin","Token PIN (if required)","secret",""),
	choice("format","Export format",{"v3","sdtid","android","iphone","blocks"})
}),function(o,c,p)
	assert(o.token~="","Provide a token string")
	local path=p.private("stoken-token",o.token):gsub("@PRIVATE@","@PRIVATE_FILE@")
	local a={"/usr/bin/stoken",o.operation,"--file",path}
	if o.password~="" then add(a,"--password",p.private("stoken-password",o.password)) end
	if o.pin~="" then assert(o.pin:match("^%d+$") and #o.pin<=8,"PIN must contain at most eight digits");add(a,"--pin",p.private("stoken-pin",o.pin)) end
	if o.operation=="export" then add(a,"--"..o.format) end
	o.token="[REDACTED]";o.password="[REDACTED]";o.pin="[REDACTED]";p.sensitive=true;return a
end)

define("forensics.trace","Process syscall tracing","SECURITY",{"/usr/bin/strace"},common({
	live("process","Process to trace","processes"),choice("calls","System calls",{"all","%file","%net","%process","%memory","%desc","%signal"}),
	field("follow","Follow child processes","boolean",true),field("summary","Summary counts only","boolean",false),
	field("failed_only","Failed calls only","boolean",false),integer("string_bytes","Maximum decoded string bytes",256,1,65536)
}),function(o,c,p)
	local selected;for _,item in ipairs(c.processes or {}) do if item.value==o.process then selected=item end end;assert(selected,"Select a live process")
	p.process_identity=selected;p.hardware="process";p.resource="process-"..o.process;p.window=true
	p.confirm="TRACE PROCESS "..o.process.." "..selected.name
	local a={"/usr/bin/strace","-p",o.process,"-tt","-T","-s",tostring(o.string_bytes),"-e","trace="..o.calls,"-o","@ARTIFACT@/syscalls.txt"}
	if o.follow then add(a,"-f") end;if o.summary then add(a,"-c") end;if o.failed_only then add(a,"-Z") end
	p.artifacts={artifact("syscalls.txt",o.output_mib*1048576,"syscall_trace")};return a
end)

define("monitoring.resources","CPU and process observation","INFO",{"/usr/bin/top"},common({
	integer("interval","Sample interval (seconds)",2,1,60),integer("samples","Samples (0 = until stopped)",0,0,1000000)
}),function(o,c,p)
	p.window=true;local a={"/usr/bin/top","-b","-d",tostring(o.interval)};if o.samples>0 then add(a,"-n",o.samples) end;return a
end)

local function selected_usb(o,c,p,source)
	local selected;for _,device in ipairs(c[source] or {}) do if device.value==o.device then selected=device end end
	assert(selected,"Select a current USB device")
	p.hardware="usb_target";p.usb_identity=selected;p.resource="usb-"..selected.value
	return selected
end

define("firmware.ftdi","FTDI EEPROM backup and configuration","DISRUPTIVE",{"/usr/bin/ftdi_eeprom"},common({
	live("device","FTDI adapter","ftdi_devices"),choice("operation","Operation",{"read","build","write","erase"}),
	integer("vendor_id","New vendor ID (decimal; 0 = keep current)",0,0,65535),integer("product_id","New product ID (decimal; 0 = keep current)",0,0,65535),
	text("manufacturer","Manufacturer","FTDI","config_string"),text("product","Product description","USB Serial Converter","config_string"),text("serial","New serial number","DDK001","config_string"),
	integer("max_power","Maximum bus power (mA)",100,0,500),field("self_powered","Self-powered device","boolean",false),field("remote_wakeup","Remote wakeup","boolean",false),
	choice("channel_a","Channel A mode",{"UART","FIFO","OPTO","CPU","FT1284"}),choice("channel_b","Channel B mode",{"UART","FIFO","OPTO","CPU","FT1284"})
}),function(o,c,p)
	local device=selected_usb(o,c,p,"ftdi_devices");p.ftdi=true
	if o.vendor_id==0 then o.vendor_id=tonumber(device.usb_id:sub(1,4),16) end;if o.product_id==0 then o.product_id=tonumber(device.usb_id:sub(6,9),16) end
	if o.operation=="write" or o.operation=="erase" then p.confirm="FTDI "..o.operation:upper().." "..o.device end
	p.artifacts=o.operation=="erase" and {} or {artifact("ftdi-eeprom.bin",65536,"firmware_backup")}
	if o.operation=="write" or o.operation=="erase" then p.artifacts[#p.artifacts+1]=artifact("ftdi-backup.bin",65536,"firmware_backup") end
	return {"/usr/bin/ftdi_eeprom","--device","d:"..device.busnum.."/"..device.devnum,"--"..({read="read-eeprom",build="build-eeprom",write="flash-eeprom",erase="erase-eeprom"})[o.operation],"@FTDI_CONFIG@"}
end)

define("firmware.flashrom","SPI flash read, write, and verify","DISRUPTIVE",{"/usr/sbin/flashrom-usb"},common({
	choice("programmer","Programmer",{"ch341a_spi","ft2232_spi","serprog","buspirate_spi"}),optional_live("device","USB programmer","flashrom_devices"),
	optional_live("serial_device","Serial programmer","serial_devices"),choice("operation","Operation",{"probe","read","verify","write","erase"}),
	text("chip","Chip name (empty = detect)","","chip_name"),optional_live("input","Firmware image","uploads"),
	choice("channel","FTDI channel",{"A","B","C","D"}),integer("divisor","FTDI clock divisor (even)",2,2,131072),integer("baud","Serial baud",115200,1200,2000000),
	integer("image_mib","Maximum chip image (MiB)",32,1,256),field("no_verify","Skip automatic write verification","boolean",false),field("force","Force native operation","boolean",false)
}),function(o,c,p)
	local programmer=o.programmer
	if programmer=="serprog" or programmer=="buspirate_spi" then
		assert(o.serial_device~="","Select a serial programmer");o.device=o.serial_device;p.hardware="serial";p.resource="serial-"..o.device:gsub("/","-")
		if programmer=="buspirate_spi" then assert(o.baud==115200 or o.baud==230400 or o.baud==250000 or o.baud==2000000,"Bus Pirate supports 115200, 230400, 250000, or 2000000 baud");programmer=programmer..":dev="..o.serial_device..",serialspeed="..o.baud else programmer=programmer..":dev="..o.serial_device..":"..o.baud end
	else
		local device=selected_usb(o,c,p,"flashrom_devices")
		local expected=programmer=="ch341a_spi" and "1a86:5512" or device.usb_id
		if programmer=="ch341a_spi" then assert(device.usb_id==expected,"Select a CH341A SPI programmer")
		else
			local types={["0403:6010"]="2232H",["0403:6011"]="4232H",["0403:6014"]="232H"}
			local kind=assert(types[device.usb_id],"Select an FTDI MPSSE programmer")
			assert(o.divisor%2==0,"FTDI divisor must be even")
			assert(o.channel=="A" or (kind~="232H" and (kind=="4232H" or o.channel=="B")),"That chip has no selected channel")
			programmer=programmer..":type="..kind..",port="..o.channel..",divisor="..o.divisor
			if device.serial~="" then assert(device.serial:match("^[A-Za-z0-9_.-]+$"),"Native flashrom cannot represent this serial descriptor");programmer=programmer..",serial="..device.serial end
		end
		local matches=0;for _,candidate in ipairs(c.flashrom_devices or {}) do if candidate.usb_id==expected and (o.programmer=="ch341a_spi" or device.serial=="" or candidate.serial==device.serial) then matches=matches+1 end end
		assert(matches==1,"This native programmer cannot distinguish these identical adapters; disconnect duplicates")
		p.usb_unique={usb_id=expected,serial=o.programmer=="ch341a_spi" and "" or device.serial}
	end
	local a={"/usr/sbin/flashrom-usb","-p",programmer};if o.chip~="" then add(a,"-c",o.chip) end
	if o.operation=="read" then add(a,"-r","@ARTIFACT@/spi-flash.bin");p.artifacts={artifact("spi-flash.bin",o.image_mib*1048576,"firmware_backup")}
	elseif o.operation=="verify" or o.operation=="write" then add(a,o.operation=="write" and "-w" or "-v",p.upload(o.input))
	elseif o.operation=="erase" then add(a,"-E") end
	if o.no_verify then add(a,"-n") end;if o.force then add(a,"-f") end
	if o.operation=="write" or o.operation=="erase" then p.confirm="FLASH "..o.operation:upper().." "..o.device end
	return a
end)

define("wireless.file_analysis","Wireless capture analysis","SECURITY",{"/usr/bin/aircrack-ng","/usr/bin/airdecap-ng"},common({
	live("input","Wireless PCAP file","uploads"),choice("operation","Operation",{"inspect","wep_recovery","wpa_wordlist","decrypt"}),
	text("bssid","Access point MAC (optional)","","optional_mac"),text("ssid","Network name", "","ssid"),
	optional_live("wordlist","Wordlist file","uploads"),choice("key_type","Decryption key",{"wpa_passphrase","wpa_pmk","wep"}),
	field("key","Decryption key","secret",""),field("keep_header","Keep 802.11 headers","boolean",true),integer("capture_mib","Decrypted output budget (MiB)",512,1,8192)
}),function(o,c,p)
	if o.operation=="decrypt" then
		assert(o.key~="","Provide the capture decryption key")
		if o.key_type=="wpa_passphrase" then assert(#o.key>=8 and #o.key<=63 and o.ssid~="","WPA needs an SSID and an 8-63 byte passphrase")
		else assert(o.key:match("^%x+$") and #o.key%2==0,"Provide a hexadecimal key");if o.key_type=="wpa_pmk" then assert(#o.key==64 and o.ssid~="","PMK needs 64 hex digits and an SSID") end end
		local a={"/usr/bin/airdecap-ng","-o","@ARTIFACT@/wireless-decrypted.pcap","-c","@ARTIFACT@/wireless-corrupt.pcap"}
		if o.keep_header then add(a,"-l") end;if o.bssid~="" then add(a,"-b",o.bssid) end;if o.ssid~="" then add(a,"-e",o.ssid) end
		add(a,({wpa_passphrase="-p",wpa_pmk="-k",wep="-w"})[o.key_type],p.private("wireless-key",o.key),p.upload(o.input));o.key="[REDACTED]"
		p.artifacts={artifact("wireless-decrypted.pcap",o.capture_mib*1048576,"pcap"),artifact("wireless-corrupt.pcap",o.capture_mib*1048576,"pcap")};return a
	end
	local a={"/usr/bin/aircrack-ng","-p","1"}
	if o.bssid~="" then add(a,"-b",o.bssid) end;if o.ssid~="" then add(a,"-e",o.ssid) end
	if o.operation=="wpa_wordlist" then assert(o.bssid~="" or o.ssid~="","Select the SSID or BSSID to test");add(a,"-a","2","-q","-w",p.upload(o.wordlist));p.sensitive=true
	elseif o.operation=="wep_recovery" then assert(o.bssid~="" or o.ssid~="","Select the SSID or BSSID to test");add(a,"-a","1","-q");p.sensitive=true
	else p.stdin=p.private("wireless-inspect","0\n");p.success_codes={0,1} end
	add(a,p.upload(o.input));return a
end)

define("cases.export","Export a saved case","INFO",{"/bin/tar"},common({
	live("case","Saved case","saved_cases")
}),function(o,c,p)
	local selected;for _,item in ipairs(c.saved_cases or {}) do if item.value==o.case then selected=item end end;assert(selected,"Choose a saved case")
	p.source_case=o.case;p.resource="case-export-"..o.case
	local a={"/bin/tar","-cf","@ARTIFACT@/case.tar","-C","@CASE_EXPORT@","."}
	p.case_files=selected.files;p.artifacts={artifact("case.tar",selected.archive_size,"case_archive")};p.artifacts[1].content_type="application/x-tar";return a
end)

define("cellular.profile","Cellular APN profile with automatic recovery","DISRUPTIVE",{"/usr/libexec/ddk-device-session","/bin/ubus"},common({
 text("apn","APN","","apn"),choice("pdp","PDP type",{"ipv4","ipv6","ipv4v6"},"ipv4v6"),choice("auth","Authentication",{"none","pap","chap","both"}),
 text("username","Username"),field("replace_password","Replace saved password","boolean",false),field("password","New password","secret",""),integer("recovery_seconds","Confirm-or-revert window (seconds)",180,60,600)
}),function(o,c,p)
 assert(c.cellular_interface and c.cellular_interface:match("^[A-Za-z0-9_]+$"),"Choose a single EC25 QMI interface in the router network configuration")
 p.resource="modem-ec25";p.hardware="modem";p.cellular=true;p.wall_timeout=0
 p.required_executables={"/bin/ubus"};p.confirm="APPLY CELLULAR PROFILE "..c.cellular_interface
 local password="-";if o.replace_password then password=p.private("cellular-password",o.password=="" and "\n" or o.password):gsub("@PRIVATE@","@PRIVATE_FILE@");o.password="[REDACTED]" end
 return {"/usr/libexec/ddk-device-session","cellular",c.cellular_interface,o.apn,o.pdp,o.auth,o.username=="" and "@EMPTY@" or o.username,password,"@CELLULAR_JOB@",tostring(o.recovery_seconds)}
end)

define("bluetooth.pairing","Bluetooth pairing and connections","ACTION",{"/usr/libexec/ddk-device-session","/usr/bin/bluetoothctl"},common({
 live("controller","Bluetooth adapter","bluetooth_all"),choice("operation","Operation",{"info","pair","connect","disconnect","trust","untrust","remove"}),
 text("address","Remote Bluetooth address","00:00:00:00:00:00","mac"),field("pin","Pairing PIN (when required)","secret","")
}),function(o,c,p)
 p.hardware="bluetooth";p.resource="bluetooth-session";p.required_executables={"/usr/bin/bluetoothctl","/usr/bin/hciconfig","/usr/bin/bluetoothd"}
 if o.operation~="info" then p.confirm="BLUETOOTH "..o.operation:upper().." "..o.address end
 local pin="-";if o.pin~="" then assert(o.pin:match("^%d+$") and #o.pin<=16,"Use a pairing PIN of 1-16 digits");pin=p.private("bluetooth-pin",o.pin):gsub("@PRIVATE@","@PRIVATE_FILE@");o.pin="[REDACTED]" end
 return {"/usr/libexec/ddk-device-session","bluetooth",o.controller,o.address,o.operation,pin}
end)

define("gps.session","GNSS and RTK receiver session","ACTION",{"/usr/libexec/ddk-device-session","/usr/sbin/gpsd","/usr/bin/rtkrcv"},common({
 live("device","Receiver","gps_devices"),choice("operation","Session",{"gpsd","rtk"}),
 choice("baud","Baud",{"9600","19200","38400","57600","115200","230400","460800","921600"},"115200"),
 choice("receiver_mode","gpsd receiver control",{"passive","configure"}),
 choice("format","RTK receiver format",{"ubx","rtcm3","oem4","skytraq","sbf","binex","javad"}),
 choice("position_mode","Position mode",{"single","dgps","kinematic","static","movingbase","fixed","ppp-kine","ppp-static"}),
 choice("frequency","Frequencies",{"l1","l1+l2","l1+l2+l5"},"l1+l2"),
 optional_live("corrections","Recorded RTCM3 corrections (optional)","uploads"),integer("solution_mib","Solution output budget (MiB)",256,1,8192)
}),function(o,c,p)
 p.hardware="serial";p.resource="serial-"..o.device:gsub("/","-");p.window=true
 if o.operation=="gpsd" then
  if o.receiver_mode=="configure" then p.confirm="CONFIGURE GNSS "..o.device end
  p.required_executables={"/usr/sbin/gpsd","/usr/bin/gpspipe"}
  return {"/usr/libexec/ddk-device-session","gps",o.device,o.baud,o.receiver_mode}
 end
 p.required_executables={"/usr/bin/rtkrcv"};p.rtk=true
 local a={"/usr/libexec/ddk-device-session","rtk","@RTK_CONFIG@","@ARTIFACT@/gnss-solution.pos"}
 if o.corrections~="" then p.rtk_corrections=p.upload(o.corrections) end
 p.artifacts={artifact("gnss-solution.pos",o.solution_mib*1048576,"gnss_solution"),artifact("rtkrcv.nav",4194304,"gnss_navigation")}
 return a
end)

define("forensics.debug_server","Attach a GDB debugger","DISRUPTIVE",{"/usr/bin/gdbserver"},common({
 live("process","Target process","processes"),integer("port","Loopback port (use SSH forwarding)",2345,1024,65535)
}),function(o,c,p)
 for _,process in ipairs(c.processes or {}) do if process.value==o.process then p.process_identity=process end end
 assert(p.process_identity,"Select a live process")
 p.hardware="process";p.debugserver=true;p.resource="process-"..o.process;p.confirm="DEBUG PROCESS "..o.process.." "..p.process_identity.name
 return {"/usr/bin/gdbserver","--once","--attach","127.0.0.1:"..o.port,o.process}
end)

-- Transfers and recovery should finish naturally unless the operator sets a deadline.
for _,id in ipairs({"storage.ddrescue","android.operator","serial.console","automation.mqtt_subscribe","camera.video","can.capture","wireless.monitor","monitoring.bandwidth","capture.ring","serial.transfer","monitoring.resources","forensics.trace","cases.export","gps.session","forensics.debug_server","storage.clone"}) do
	for _,f in ipairs(M.actions[id].fields) do if f.name=="duration" then f.default=0 end end
end

-- Keep the form focused on controls used by the selected operation.
local function show_fields(id, names, source, values)
 local wanted={};for name in names:gmatch("[^,]+") do wanted[name]=true end
 for _,f in ipairs(M.actions[id].fields) do if wanted[f.name] then f.show_when={field=source,values=values} end end
end
show_fields("wireless.file_analysis","wordlist","operation",{"wpa_wordlist"})
show_fields("wireless.file_analysis","key_type,key,keep_header,capture_mib","operation",{"decrypt"})
show_fields("android.operator","device","transport",{"usb"})
show_fields("android.operator","host,port","transport",{"tcp"})
show_fields("android.operator","remote_path","operation",{"list_path","pull_file","pull_directory","push"})
show_fields("android.operator","input","operation",{"push","install"})
show_fields("android.operator","packages","operation",{"install_multiple"})
show_fields("android.operator","package,keep_data","operation",{"uninstall"})
show_fields("android.operator","service","operation",{"dumpsys"})
show_fields("android.operator","user","operation",{"packages"})
show_fields("android.operator","replace,downgrade,test_package","operation",{"install","install_multiple"})
show_fields("android.operator","reboot_mode","operation",{"reboot"})
show_fields("android.operator","log_lines","operation",{"logcat"})
show_fields("android.operator","artifact_mib","operation",{"pull_file","pull_directory"})
show_fields("cellular.raw_command","command","operation",{"custom_at"})
show_fields("cellular.control","network_mode","operation",{"network_modes"})
show_fields("cellular.control","roaming","operation",{"roaming"})
show_fields("camera.video","width,height,format,frames,record_mib","operation",{"record"})
show_fields("camera.video","control,value","operation",{"set_control"})
show_fields("radio.receiver_tools","frequency,gain,ppm,listen_address,port","operation",{"stream"})
show_fields("industrial.modbus_write","host,port","transport",{"tcp"})
show_fields("industrial.modbus_write","device,baud,parity,stop_bits,rs485,rts","transport",{"rtu"})
show_fields("industrial.modbus_write","values,verify","operation",{"write_coil","write_register","write_coils","write_registers"})
show_fields("industrial.modbus_write","count,cycles,interval","operation",{"read_coils","read_discrete","read_holding","read_input"})
show_fields("usbip.attach","host,server_port","operation",{"list_remote","attach"})
show_fields("usbip.attach","busid","operation",{"attach"})
show_fields("usbip.attach","port","operation",{"detach"})
show_fields("usb.power","delay","operation",{"cycle"})
show_fields("gps.receiver_control","baud","operation",{"speed"})
show_fields("gps.receiver_control","cycle_ms","operation",{"rate"})
show_fields("serial.transfer","input","direction",{"send_receive"})
show_fields("auth.stoken","format","operation",{"export"})
show_fields("auth.otp","counter","mode",{"hotp"})
show_fields("auth.otp","algorithm,step","mode",{"totp"})
show_fields("cellular.profile","password","replace_password",{true})
show_fields("bluetooth.pairing","pin","operation",{"pair"})
show_fields("gps.session","receiver_mode","operation",{"gpsd"})
show_fields("gps.session","format,position_mode,frequency,corrections,solution_mib","operation",{"rtk"})
show_fields("can.configure","bitrate,restart_ms","operation",{"bitrate"})
show_fields("firmware.flashrom","device,channel,divisor","programmer",{"ch341a_spi","ft2232_spi"})
show_fields("firmware.flashrom","serial_device,baud","programmer",{"serprog","buspirate_spi"})
show_fields("firmware.flashrom","input","operation",{"verify","write"})
show_fields("firmware.flashrom","image_mib","operation",{"read"})
show_fields("firmware.ftdi","vendor_id,product_id,manufacturer,product,serial,max_power,self_powered,remote_wakeup,channel_a,channel_b","operation",{"build","write"})

for _,f in ipairs(M.actions["android.operator"].fields) do if f.name=="port" then f.show_when={any={{field="transport",equals="tcp"},{field="operation",equals="tcpip"}}} end end
show_fields("firmware.flashrom","channel,divisor","programmer",{"ft2232_spi"})

local function copy(value)
	if type(value)~="table" then return value end
	local result={};for k,v in pairs(value) do result[k]=copy(v) end;return result
end

function M.describe(id, context)
	local spec=M.actions[id];if not spec then return nil,"Unknown v3 action" end
	local fields=copy(spec.fields)
	for _,f in ipairs(fields) do
		if f.source then
			f.options={}
			if f.allow_empty then f.options[1]={value="",label="Select when required"} end
			for _,item in ipairs(context[f.source] or {}) do
				local value=type(item)=="table" and (item.value or item.selector or item.id or item.name or item.node or item.serial) or item
				f.options[#f.options+1]={value=value,label=type(item)=="table" and (item.label or item.original_name or value) or value}
			end
			if f.type~="upload_list" then f.default=f.options[1] and f.options[1].value or "" end
		end
	end
	return {action_id=id,label=spec.label,class=spec.class,native={executables=copy(spec.executables)},fields=fields}
end

local function validate_text(value, f)
	assert(type(value)=="string" and #value<=8192 and not value:find("[%z\r\n]"),f.label.." contains invalid text")
	local rule=f.validation
	if rule=="host" or rule=="optional_host" then
		if value=="" and rule=="optional_host" then return value end
		assert(validators.valid_ipv4(value) or validators.valid_ipv6(value) or (not value:match("^[0-9.]+$") and validators.valid_hostname(value)),"Invalid host: "..f.label)
	elseif rule=="apn" then assert(#value>0 and #value<=100 and value:match("^[A-Za-z0-9][A-Za-z0-9_.-]*$"),"Enter the APN supplied by the carrier")
	elseif rule=="dns" then assert(#value>0 and #value<=253 and value:match("^[A-Za-z0-9_][A-Za-z0-9_.-]*$"),"Invalid DNS name")
	elseif rule=="bpf" then assert(#value<=8192,"BPF expression is too long")
	elseif rule=="interface_name" then assert(value:match("^[A-Za-z0-9_][A-Za-z0-9_.-]*$") and #value<=15,"Invalid interface name")
	elseif rule=="config_string" then assert(#value<=96 and value:match("^[A-Za-z0-9 _.+/-]*$"),"Use letters, digits, spaces, or ._+/- in descriptors")
	elseif rule=="chip_name" then assert(#value<=96 and value:match("^[A-Za-z0-9_(). /+-]*$"),"Invalid flash chip name")
	elseif rule=="identifier" then assert(value:match("^[A-Za-z_][A-Za-z0-9_]*$") and #value<=64,"Invalid control identifier")
	elseif rule=="usb_busid" then assert(value:match("^%d+%-%d+[%.%d]*$") and #value<=32 and not value:find("..",1,true) and value:sub(-1)~=".","Invalid USB bus ID")
	elseif rule=="at_command" then assert(value:match("^AT[A-Za-z0-9+?=, ._:;/-]*$") and #value<=512,"Enter one AT command without line breaks")
	elseif rule=="android_path" then assert(value:match("^/[A-Za-z0-9_./ +@%%:=-]+$") and not value:find("//",1,true) and not (value.."/"):find("/../",1,true) and not (value.."/"):find("/./",1,true),"Enter an absolute Android path without traversal")
	elseif rule=="package" then assert(value:match("^[A-Za-z][A-Za-z0-9_]*%.[A-Za-z0-9_.]+$") and not value:find("..",1,true) and #value<=192,"Invalid application package name")
	elseif rule=="ssid" then assert(#value<=32,"SSID exceeds 32 bytes")
	elseif rule=="optional_mac" then assert(value=="" or value:match("^%x%x:%x%x:%x%x:%x%x:%x%x:%x%x$"),"Invalid access point address")
	elseif rule=="mac" then assert(value:match("^%x%x:%x%x:%x%x:%x%x:%x%x:%x%x$"),"Invalid Bluetooth address")
	elseif rule=="handle" then assert(value:match("^0x%x+$") and tonumber(value)<=65535,"Invalid attribute handle")
	elseif rule=="optional_hex" then assert(value=="" or (value:match("^%x+$") and #value%2==0),"Expected pairs of hexadecimal digits")
	elseif rule=="can_filter" then assert(value=="" or value:match("^%x+:%x+$"),"Use hexadecimal CAN ID:mask")
	elseif rule=="can_frame" then
        local normalized=value:gsub("%.","")
        local id,payload=normalized:match("^(%x+)#(.*)$")
        assert(id and (#id==3 or #id==8) and tonumber(id,16)<=(#id==3 and 2047 or 536870911),"CAN ID exceeds its 11-bit or 29-bit range")
        local raw,dlc=payload:match("^(.*)_([%x])$");if raw then payload=raw;assert(tonumber(dlc,16)>=9,"Extended DLC must be 9-F") end
        local flag,fd=payload:match("^#(%x)(%x*)$")
        local rtr=payload=="R" or payload:match("^R[0-8]$")
        local data=payload:match("^%x*$")
        assert((flag and not dlc and #fd<=128 and #fd%2==0) or (rtr and (not dlc or payload=="R8")) or (data and #data<=16 and #data%2==0 and (not dlc or #data==16)),"Use ID#DATA, ID#R[0-8], or ID##FLAGDATA; optional extended DLC follows an 8-byte classic frame")
        value=normalized

	end
	return value
end

function M.prepare(id, options, context)
	local spec=M.actions[id];if not spec then return nil,"Unknown v3 action" end
	if type(options)~="table" then return nil,"Options must be an object" end
	context=context or {};validators=context.validators or validators
	local ok,result=pcall(function()
		local schema=assert(M.describe(id,context));local allowed={};local o={}
		for _,f in ipairs(schema.fields) do
			allowed[f.name]=true;local v=options[f.name];if v==nil then v=copy(f.default) end
			if f.type=="integer" then assert(type(v)=="number" and v==math.floor(v) and v>=f.min and v<=f.max,f.label.." is outside its range")
			elseif f.type=="boolean" then assert(type(v)=="boolean",f.label.." must be true or false")
			elseif f.type=="enum" then local found=false;for _,item in ipairs(f.options or {}) do if v==(type(item)=="table" and item.value or item) then found=true end end;assert(found,"Select an available "..f.label)
			elseif f.type=="integer_list" then
				assert(type(v)=="table" and #v<=1968,"Provide at most 1968 values")
				for k,item in pairs(v) do assert(type(k)=="number" and k==math.floor(k) and k>=1 and k<=#v and type(item)=="number" and item==math.floor(item) and item>=f.min and item<=f.max,"Invalid integer list") end
			elseif f.type=="target_list" or f.type=="upload_list" then
				assert(type(v)=="table" and #v<=64,f.label.." must contain at most 64 entries")
				for k,item in pairs(v) do
					assert(type(k)=="number" and k>=1 and k<=#v and k==math.floor(k),"Invalid list")
					if f.type=="upload_list" then local found=false;for _,option in ipairs(f.options) do if option.value==item then found=true end end;assert(found,"Select an available input file")
					elseif f.validation=="hosts" then validate_text(item,{label=f.label,validation="host"})
					elseif f.validation=="ipv4_targets" then local parsed,family=validators.validate_target(item);assert(parsed and family=="ipv4","ARP targets must be IPv4 addresses/subnets")
					else validate_text(item,{label=f.label});assert(#item>0,"Empty topic") end
				end
			else validate_text(v,f) end
			o[f.name]=v
		end
		for key in pairs(options) do assert(allowed[key],"Unknown "..spec.label.." option: "..tostring(key)) end
		local p={action_id=id,worker="v3_native",label=spec.label,class=spec.class,options=o,artifacts={},private_inputs={},input_uploads={},singleton=false,wall_timeout=o.duration or 60}
		p.private=function(name,value) p.private_inputs[#p.private_inputs+1]={name=name,hex=(value:gsub(".",function(c)return string.format("%02x",c:byte())end))};return "@PRIVATE@/"..name end
		p.upload=function(upload_id)
			for _,u in ipairs(context.uploads or {}) do if u.id==upload_id then p.input_uploads[#p.input_uploads+1]={id=u.id,kind=u.kind};return "@UPLOAD@/"..u.id end end
			error("Select a sealed input")
		end
		p.argv=spec.build(o,context,p)
		local preview={};for _,v in ipairs(p.argv) do assert(type(v)=="string" and v~="" and not v:find("[%z\r\n]"),"Invalid native argument");preview[#preview+1]="'"..v:gsub("'","'\\''").."'" end
		p.argv_preview=table.concat(preview," ");p.target_summary=p.target_summary or o.device or o.interface or o.host or o.address or o.name or spec.label
		if not p.sensitive then p.artifacts[#p.artifacts+1]=artifact("native-output.txt",o.output_mib*1048576) end
		p.confirmation={required=p.confirm~=nil,phrase=p.confirm,reason=p.confirm and "Confirm this operation on the displayed target and parameters." or nil}
		p.private=nil;p.upload=nil
		return p
	end)
	if not ok then return nil,tostring(result):gsub("^.-:%d+: ","") end
	return result
end

return M
