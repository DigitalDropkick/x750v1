local policy = dofile('files/usr/share/ddk-field-console/runtime-policy.lua')
assert(policy.terminal('complete') and policy.terminal('stopped') and policy.terminal('failed'))
assert(not policy.terminal('running') and not policy.terminal('stopping'))
assert(policy.artifact_valid({type='reg',size=24}, 1024))
assert(not policy.artifact_valid({type='lnk',size=24}, 1024))
assert(not policy.artifact_valid({type='reg',size=2048}, 1024))
assert(policy.artifact_valid({type='reg',size=2048}, 1024, true))
assert(not policy.artifact_valid({type='lnk',size=2048}, 1024, true))
assert(not policy.artifact_valid({type='reg',size=0}, 1024))
local availability = policy.availability({native={executables={'/usr/bin/file','/usr/bin/yara'}}}, function(path) return path=='/usr/bin/file' end)
assert(availability.any_available and #availability.available==1 and availability.missing[1]=='/usr/bin/yara')
assert(policy.resource('camera','/dev/video0') ~= policy.resource('camera','/dev/video1'))
assert(policy.resource('serial','/dev/ttyUSB1') == policy.resource('serial','/dev/ttyUSB1'))
print('DDK_RUNTIME_POLICY_TEST_OK')

for chunk=1,31 do
	local source=string.rep('public ',10000)..'secret-boundary'..string.rep(' end',10000)..'secret-boundary'
	local cursor,output=1,{}
	policy.redact_stream(function()if cursor>#source then return nil end;local value=source:sub(cursor,cursor+chunk-1);cursor=cursor+chunk;return value end,function(value)output[#output+1]=value end,{'secret-boundary'})
	assert(table.concat(output)==source:gsub('secret%-boundary','[REDACTED]'),'Redaction lost data at a chunk boundary')
end

assert(policy.serial_input({data="AT",encoding="text",ending="crlf"})=="41540d0a")
assert(policy.serial_input({data="00 ff 1b",encoding="hex",ending="none"})=="00ff1b")
assert(not policy.serial_input({data="f",encoding="hex"}))
assert(not policy.serial_input({data="x",command="whoami"}))
