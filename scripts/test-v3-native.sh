#!/bin/sh
# Runs on the router against a separately staged worker and synthetic fixtures.
set -eu
umask 077
stage=/tmp/ddk-v3-full
[ -f "$stage/usr/libexec/ddk-v3-worker" ] && [ -f "$stage/usr/share/ddk-field-console/operator-v3.lua" ] || exit 66
lua - "$stage" <<'LUA'
local root=arg[1]
local fs=require "nixio.fs"
local json=require "luci.jsonc"
local n=require "nixio"
assert(type(fs.statvfs)=="function", "statvfs unavailable")
local space=assert(fs.statvfs("/overlay"));assert(space.bavail and space.bsize)
local function fixture(id,action,argv,options,runtime,duration)
	local dir=root.."/state/jobs/"..id
	assert(not fs.stat(dir),"Fixture collision")
	fs.mkdirr(dir);fs.mkdirr(root.."/persist/artifacts/"..id)
	local function write(name,value) assert(fs.writefile(dir.."/"..name,value)) end
	write("metadata.json",json.stringify({id=id,action_id=action,options=options,native_runtime=runtime}))
	write("argv",table.concat(argv,"\n").."\n");write("wall-timeout",tostring(duration or 5).."\n")
	write("lock-keys","");write("stdout","");write("stderr","")
	return dir,write
end
local function execute(id)
	print("Native fixture "..id)
	return os.execute("/usr/bin/lua "..root.."/usr/libexec/ddk-v3-worker "..id.." v3_native")
end
local function check(dir,expected,contains)
	assert(fs.readfile(dir.."/status")==expected.."\n",fs.readfile(dir.."/stderr"))
	if contains then assert((fs.readfile(dir.."/stdout") or ""):find(contains,1,true),"Missing expected native output") end
end
local epoch=tostring(os.time())
local id="job-"..epoch.."-1"
local dir=fixture(id,"network.fping",{"/usr/bin/fping","-c","2","-p","100","127.0.0.1"},{},{output_mib=1,success_codes={0,1}},5)
execute(id);check(dir,"complete","127.0.0.1")
id="job-"..epoch.."-2"
dir=fixture(id,"network.fping",{"/usr/bin/fping","-l","-p","100","127.0.0.1"},{},{output_mib=1,window=true},1)
execute(id);check(dir,"complete","127.0.0.1")
id="job-"..epoch.."-3"
dir=fixture(id,"network.fping",{"/usr/bin/fping","-l","-p","100","127.0.0.1"},{},{output_mib=1,window=true},0)
os.execute("/usr/bin/lua "..root.."/usr/libexec/ddk-v3-worker "..id.." v3_native >/dev/null 2>&1 &")
n.nanosleep(1,0);fs.writefile(dir.."/stop-request","stop\n")
for _=1,30 do if fs.readfile(dir.."/status")=="stopped\n" then break end;n.nanosleep(0,200000000) end
check(dir,"stopped","127.0.0.1")
assert(fs.stat(root.."/persist/artifacts/"..id.."/native-output.txt","size")>0)
id="job-"..epoch.."-4"
local write
dir,write=fixture(id,"auth.otp",{"/usr/bin/oathtool","--hotp","--counter=0","-"},{},{output_mib=1,sensitive=true,stdin="@PRIVATE@/otp-key"},5)
-- RFC 4226 public test vector, not an operator credential.
write("private-otp-key.hex",("3132333435363738393031323334353637383930"):gsub(".",function(c)return string.format("%02x",c:byte())end).."\n")
execute(id);check(dir,"complete","755224")
assert(not fs.stat(dir.."/private-otp-key.hex") and not fs.stat(dir.."/private-otp-key.bin") and not fs.stat(dir.."/native.out"))
id="job-"..epoch.."-5"
dir=fixture(id,"network.dns",{"/bin/sh","-c","true"},{},{output_mib=1},5)
execute(id);check(dir,"failed")
id="job-"..epoch.."-6"
dir=fixture(id,"forensics.hex",{"/usr/bin/xxd","-c","1","-l","3"},{},{output_mib=1,interactive=true},5)
fs.writefile(dir.."/tx-1-000001-1.hex","414243")
execute(id);check(dir,"complete","00000002: 43")
assert(not fs.stat(dir.."/tx-1-000001-1.hex"))
id="job-"..epoch.."-7"
fs.writefile(root.."/quota.bin",string.rep("Q",2097152))
dir=fixture(id,"forensics.hex",{"/usr/bin/xxd",root.."/quota.bin"},{},{output_mib=1},10)
execute(id)
local state=fs.readfile(dir.."/status")
assert(state=="failed\n" or state=="stopped\n")
assert(fs.stat(root.."/persist/artifacts/"..id.."/native-output.txt","size")<=1048576,"Native file quota uses unexpected units")
fs.unlink(root.."/quota.bin")
id="job-"..epoch.."-8"
dir,write=fixture(id,"network.nmap_lan_discovery",{"/usr/bin/nmap","-n","-Pn","-sT","-p","80","--script=http-title","--script-args-file","@PRIVATE_FILE@/nse-arguments","-oX",root.."/persist/artifacts/"..id.."/nmap.xml","127.0.0.1"},{},{output_mib=1},30)
write("private-nse-arguments.hex",('http.useragent="DDK-v3-native-test"'):gsub(".",function(c)return string.format("%02x",c:byte())end).."\n")
execute(id);check(dir,"complete")
assert((fs.readfile(root.."/persist/artifacts/"..id.."/nmap.xml") or ""):find("</nmaprun>",1,true))
assert(not fs.stat(dir.."/private-nse-arguments.bin"))
id="job-"..epoch.."-9"
dir=fixture(id,"android.operator",{"/usr/bin/adb","-P","5038","-s","DDK-NATIVE-ABSENT","shell","getprop"},{operation="properties"},{output_mib=1,adb=true},10)
execute(id);check(dir,"failed")
for line in (fs.readfile("/proc/net/tcp") or ""):gmatch("[^\n]+") do
	local address,state=line:match("^%s*%d+:%s+(%S+)%s+%S+%s+(%S+)")
	assert(not(address and address:match(":13AE$") and state=="0A"),"Isolated ADB listener leaked")
end
id="job-"..epoch.."-10"
dir=fixture(id,"wireless.monitor",{"/usr/sbin/tcpdump","-i","@MONITOR@"},{phy="phy999999",channel=0},{output_mib=1,hardware="monitor",monitor=true},5)
execute(id);check(dir,"failed")
assert((fs.readfile(dir.."/stderr") or ""):find("Selected radio disconnected",1,true))
id="job-"..epoch.."-11"
local target=assert(n.fork())
if target==0 then n.exec("/bin/sleep","60");os.exit(127) end
n.nanosleep(0,200000000)
local rest=assert(fs.readfile("/proc/"..target.."/stat")):match("^%d+ %(.+%) (.*)$");local fields={};for f in rest:gmatch("%S+") do fields[#fields+1]=f end
local identity={value=tostring(target),exe=assert(fs.readlink("/proc/"..target.."/exe")),starttime=fields[20],name="ddk-test-sleep"}
dir=fixture(id,"forensics.debug_server",{"/usr/bin/gdbserver","--once","--attach","127.0.0.1:52345",tostring(target)},{process=tostring(target)},{output_mib=1,hardware="process",debugserver=true,process_identity=identity},0)
local ok,why=pcall(function()
 os.execute("/usr/bin/lua "..root.."/usr/libexec/ddk-v3-worker "..id.." v3_native >/dev/null 2>&1 &")
 n.nanosleep(2,0);assert(fs.readfile(dir.."/status")=="running\n",fs.readfile(dir.."/stderr"))
 fs.writefile(dir.."/stop-request","stop\n")
 for _=1,30 do if fs.readfile(dir.."/status")=="stopped\n" then break end;n.nanosleep(0,200000000) end
 check(dir,"stopped");n.nanosleep(0,300000000)
 local current=assert(fs.readfile("/proc/"..target.."/stat")):match("^%d+ %(.+%) (%S+)")
 assert(current~="T" and current~="t","Owned debugger left its target stopped")
end)
n.kill(target,15);n.waitpid(target);assert(ok,why)
print("DDK_V3_NATIVE_OK: loopback, timed receive, cancellation, partial output, RFC OTP, executable rejection, serial pipe, file quota, NSE arguments, ADB cleanup, missing-radio rejection, GDB target resume")
LUA
