local m=dofile("files/usr/share/ddk-field-console/operator-actions.lua")
local c={interfaces={{name="lo"}},lan_interface="lo",lan_cidr="127.0.0.1/32",nmap_scripts={"http-title","smb-os-discovery"}}
local function plan(o) local p,e=m.prepare("network.nmap_lan_discovery",o,c);assert(p,e);return p end
local p=plan({targets={"127.0.0.1"},scan_type="connect",ports="1-65535",scripts={"http-title"},nse_arguments="http.useragent=A string, with spaces\nexample.value=quoted \"data\"",wall_timeout=7200,output_format="all",output_mib=128})
assert(p.wall_timeout==7200 and #p.artifacts==3 and p.artifacts[1].storage=="extroot" and p.artifacts[1].max_size==134217728)
assert(p.options.nse_arguments=="[REDACTED]" and p.options.nse_argument_file==nil)
assert(not p.argv_preview:find("A string",1,true))
assert(p.argv_preview:find("--script=http-title",1,true) and p.argv_preview:find("--script-args-file",1,true))
local private=p.private_inputs[1].hex:gsub("..",function(h)return string.char(tonumber(h,16))end)
assert(private=='http.useragent="A string, with spaces",example.value="quoted \\"data\\""')
assert(not m.prepare("network.nmap_lan_discovery",{scripts={"/tmp/custom.nse"}},c))
assert(not m.prepare("network.nmap_lan_discovery",{scripts={"uninstalled-script"}},c))
assert(not m.prepare("network.nmap_lan_discovery",{scripts={"http-title"},nse_arguments="broken key=value"},c))
assert(not m.prepare("network.nmap_lan_discovery",{nse_arguments="key=value"},c))
for _,category in ipairs({"auth","broadcast","brute","discovery","dos","exploit","external","fuzzer","intrusive","malware","safe","version","vuln"}) do assert(plan({script_profile=category})) end
print("DDK_NETWORK_V3_OK: script inventory, full categories, private literal arguments, larger extroot output, duration")
