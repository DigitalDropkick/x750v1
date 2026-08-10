local module_path = arg[1] or "files/usr/share/ddk-field-console/operator-apple.lua"
local apple = assert(dofile(module_path))

local function expect(value, message)
	if not value then error(message or "expectation failed", 2) end
end

local function contains(argv, wanted)
	for _, value in ipairs(argv or {}) do if value == wanted then return true end end
	return false
end

local context = {
	apple_normal_devices = {
		{ value = "00008110-0011223344556677", label = "00008110-0011223344556677 / NORMAL", udid = "00008110-0011223344556677", mode = "normal" }
	},
	apple_recovery_devices = {
		{ value = "ecid:0x1234abcd", label = "0x1234abcd / RECOVERY", ecid = "0x1234abcd", mode = "recovery" }
	},
	apple_restore_devices = {
		{ value = "udid:00008110-0011223344556677", label = "normal", selector = "udid", identifier = "00008110-0011223344556677", mode = "normal" },
		{ value = "ecid:0x1234abcd", label = "recovery", selector = "ecid", identifier = "0x1234abcd", mode = "recovery" }
	},
	uploads = {
		{ id = "upload-1700000000-100-1", kind = "apple_restore", original_name = "signed.ipsw", size = 4294967296, sha256 = string.rep("a", 64) },
		{ id = "upload-1700000000-100-2", kind = "apple_recovery_input", original_name = "payload.bin", size = 4096, sha256 = string.rep("b", 64) },
		{ id = "upload-1700000000-100-3", kind = "apple_ticket", original_name = "device.shsh", size = 2048, sha256 = string.rep("c", 64) }
	}
}

for _, action_id in ipairs({ "apple.mobile_diagnostics", "apple.mobile_manage", "apple.mobile_capture", "apple.recovery", "apple.restore" }) do
	local schema, err = apple.describe(action_id, context)
	expect(schema and not err, "schema failed: " .. action_id .. " / " .. tostring(err))
	expect(schema.action_id == action_id and type(schema.fields) == "table", "schema contract mismatch: " .. action_id)
end

local diagnostics = assert(apple.prepare("apple.mobile_diagnostics", {
	device = "00008110-0011223344556677", operation = "mobilegestalt", wall_timeout = 60,
	info_domain = "", info_key = "", info_simple = false, info_xml = false, diagnostic_type = "All",
	gestalt_keys = { "ProductType", "ProductVersion" }, ioreg_plane = "", ioreg_key = ""
}, context))
expect(diagnostics.argv[1] == "/usr/bin/idevicediagnostics" and contains(diagnostics.argv, "ProductVersion"), "diagnostics argv mismatch")
expect(not diagnostics.confirmation.required, "read-only diagnostics unexpectedly requires confirmation")

local rejected = apple.prepare("apple.mobile_diagnostics", { device = "00008110-0011223344556677", operation = "info", unexpected = "x" }, context)
expect(rejected == nil, "unknown Apple diagnostics option was accepted")
rejected = apple.prepare("apple.mobile_diagnostics", {
	device = "00008110-0011223344556677", operation = "info", wall_timeout = 60,
	info_domain = "", info_key = "ProductType;touch", info_simple = false, info_xml = false,
	diagnostic_type = "All", gestalt_keys = {}, ioreg_plane = "", ioreg_key = ""
}, context)
expect(rejected == nil, "ideviceinfo key injection text was accepted")

local manage = assert(apple.prepare("apple.mobile_manage", {
	device = "00008110-0011223344556677", operation = "set_name", wall_timeout = 120,
	device_name = "Digital Dropkick Bench iPhone", timestamp = 0, latitude = 0, longitude = 0
}, context))
expect(manage.argv[1] == "/usr/bin/idevicename" and manage.argv[#manage.argv] == "Digital Dropkick Bench iPhone", "set-name argv mismatch")
expect(manage.confirmation.required and manage.confirmation.phrase:find("00008110", 1, true), "management confirmation is not target-bound")

local capture = assert(apple.prepare("apple.mobile_capture", {
	device = "00008110-0011223344556677", operation = "syslog", duration = 90,
	match = "SpringBoard", trigger = "", untrigger = "", processes = "SpringBoard|backboardd",
	exclude_processes = "", quiet = true, kernel_filter = "no_kernel"
}, context))
expect(capture.argv[1] == "/usr/bin/idevicesyslog" and contains(capture.argv, "--no-colors") and capture.artifacts[1].name == "apple-syslog.txt", "syslog plan mismatch")
expect(capture.wall_timeout == 100 and not capture.confirmation.required, "syslog deadline/confirmation mismatch")

local query = assert(apple.prepare("apple.recovery", {
	device = "ecid:0x1234abcd", operation = "query", wall_timeout = 120, verbosity = 0,
	recovery_command = "", input_upload_id = ""
}, context))
expect(query.argv[1] == "/usr/bin/irecovery" and contains(query.argv, "-q") and not query.confirmation.required, "recovery query plan mismatch")

local send_file = assert(apple.prepare("apple.recovery", {
	device = "ecid:0x1234abcd", operation = "send_file", wall_timeout = 120, verbosity = 2,
	recovery_command = "", input_upload_id = "upload-1700000000-100-2"
}, context))
expect(contains(send_file.argv, "@UPLOAD@/upload-1700000000-100-2") and send_file.confirmation.required, "recovery file plan mismatch")

local restore = assert(apple.prepare("apple.restore", {
	device = "ecid:0x1234abcd", source = "sealed_ipsw", restore_upload_id = "upload-1700000000-100-1",
	mode = "erase", wall_timeout = 7200, plain_progress = true, debug = false, custom = false,
	cydia = false, exclude_baseband = false, fetch_shsh = false, no_restore = false,
	keep_personalized = false, pwn_dfu = false, allow_restore_mode = true,
	ticket_upload_id = "upload-1700000000-100-3"
}, context))
expect(restore.argv[1] == "/usr/bin/idevicerestore" and contains(restore.argv, "-e") and contains(restore.argv, "-y"), "restore destructive argv mismatch")
expect(contains(restore.argv, "@WORK@/restore-cache") and #restore.workspaces == 1 and restore.workspaces[1].storage == "extroot", "restore workspace is missing")
expect(#restore.input_uploads == 2 and restore.confirmation.required and restore.confirmation.phrase:find("0x1234abcd", 1, true), "restore upload/confirmation mismatch")

local latest = assert(apple.prepare("apple.restore", {
	device = "udid:00008110-0011223344556677", source = "latest_signed", restore_upload_id = "",
	mode = "no_action", wall_timeout = 7200, plain_progress = true, debug = false, custom = false,
	cydia = false, exclude_baseband = false, fetch_shsh = false, no_restore = false,
	keep_personalized = false, pwn_dfu = false, allow_restore_mode = false, ticket_upload_id = ""
}, context))
expect(contains(latest.argv, "-l") and contains(latest.argv, "-n") and #latest.input_uploads == 0, "latest/no-action restore plan mismatch")

local empty_context = { apple_normal_devices = {}, apple_recovery_devices = {}, apple_restore_devices = {}, uploads = {} }
rejected = apple.prepare("apple.mobile_manage", { device = "00008110-0011223344556677" }, empty_context)
expect(rejected == nil, "Apple management accepted an absent target")
rejected = apple.prepare("apple.recovery", { device = "ecid:0x1234abcd" }, empty_context)
expect(rejected == nil, "Apple recovery accepted an absent target")

print("DDK_OPERATOR_APPLE_TEST_OK")
