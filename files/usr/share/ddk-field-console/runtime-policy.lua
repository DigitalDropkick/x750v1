-- Small pure policies shared by the backend and host behavioral tests.
local M = {}

function M.terminal(status)
	return status == "complete" or status == "stopped" or status == "failed"
end

function M.artifact_valid(stat, maximum, preserve_partial)
	return type(stat) == "table" and stat.type == "reg" and
		type(stat.size) == "number" and stat.size > 0 and
		type(maximum) == "number" and maximum > 0 and
		(stat.size <= maximum or preserve_partial == true)
end

function M.availability(schema, exists)
	local native = type(schema.native) == "table" and schema.native or {}
	local executables = native.executables or { native.executable }
	local available, missing = {}, {}
	for _, executable in ipairs(executables) do
		if exists(executable) then available[#available + 1] = executable
		else missing[#missing + 1] = executable end
	end
	return { available = available, missing = missing, any_available = #available > 0 }
end

function M.resource(kind, target)
	-- Exact selected-device ownership; normalization never widens a lock.
	local encoded = tostring(target or ""):gsub(".", function(c) return string.format("%02x", c:byte()) end)
	return kind .. "-" .. encoded
end

function M.redact_stream(reader, writer, secrets)
	local values, longest = {}, 1
	for _, value in pairs(secrets) do
		if value ~= "" then values[#values+1]=value;longest=math.max(longest,#value) end
	end
	local pending = ""
	while true do
		local block=reader();local ended=block==nil
		pending=pending..(block or "")
		local boundary=ended and #pending or math.max(0,#pending-longest+1)
		local cursor=1
		while cursor<=boundary do
			local first,last
			for _,secret in ipairs(values) do
				local a,b=pending:find(secret,cursor,true)
				if a and (not first or a<first or (a==first and b>last)) then first,last=a,b end
			end
			if first and first<=boundary then
				writer(pending:sub(cursor,first-1).."[REDACTED]");cursor=last+1
			else writer(pending:sub(cursor,boundary));cursor=boundary+1 end
		end
		pending=pending:sub(cursor)
		if ended then break end
	end
end

function M.serial_input(options)
	if type(options)~="table" then return nil,"Serial input must be an object" end
	for key in pairs(options) do if key~="data" and key~="encoding" and key~="ending" then return nil,"Unknown serial input option" end end
	local data,encoding,ending=options.data,options.encoding or "text",options.ending or "crlf"
	if type(data)~="string" or #data>8192 then return nil,"Send at most 8 KiB per serial write" end
	if encoding=="hex" then
		data=data:gsub("%s","")
		if #data%2~=0 or data:find("[^0-9A-Fa-f]") then return nil,"Hex input requires complete byte pairs" end
		data=data:gsub("..",function(pair)return string.char(tonumber(pair,16))end)
	elseif encoding~="text" then return nil,"Choose text or hexadecimal input" end
	local endings={none="",cr="\r",lf="\n",crlf="\r\n"}
	if endings[ending]==nil then return nil,"Invalid line ending" end
	data=data..endings[ending]
	if #data>8192 then return nil,"Serial write including its line ending exceeds 8 KiB" end
	if #data==0 then return nil,"Enter serial data" end
	return (data:gsub(".",function(c)return string.format("%02x",c:byte())end))
end

return M
