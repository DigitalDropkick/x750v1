local module_path = arg[1] or "files/usr/share/ddk-field-console/operator-phase3.lua"
local phase3 = assert(dofile(module_path))

local function expect(value, message)
	if not value then error(message or "expectation failed", 2) end
end

local function contains(argv, wanted)
	for _, value in ipairs(argv or {}) do if value == wanted then return true end end
	return false
end

local function contains_text(argv, wanted)
	for _, value in ipairs(argv or {}) do if tostring(value):find(wanted, 1, true) then return true end end
	return false
end

local context = {
	programmer_devices = {
		{ value = "usb:1-9", label = "J-Link / 1366:0105 / 1-9", topology = "1-9", usb_id = "1366:0105", serial = "PROBE123" }
	},
	firmware_connection_devices = {
		{ value = "usb:1-9", label = "J-Link USB", kind = "usb", topology = "1-9", usb_id = "1366:0105", serial = "PROBE123" },
		{ value = "/dev/ttyUSB9", label = "Reviewed USB serial", kind = "serial", node = "/dev/ttyUSB9", topology = "1-8", usb_id = "0403:6001" }
	},
	dfu_devices = {
		{ value = "dfu:1-7", label = "DFU / 0483:df11 / 1-7", topology = "1-7", usb_id = "0483:df11", busnum = 1, devnum = 7, serial = "TEST123" }
	},
	firmware_serial_devices = {
		{ value = "/dev/ttyUSB9", label = "Reviewed USB serial", topology = "1-8", usb_id = "0403:6001" }
	},
	openocd_board_configs = { { value = "board/stm32f4discovery.cfg", label = "board/stm32f4discovery.cfg" } },
	openocd_interface_configs = { { value = "interface/jlink.cfg", label = "interface/jlink.cfg" } },
	openocd_target_configs = { { value = "target/stm32f4x.cfg", label = "target/stm32f4x.cfg" } },
	avrdude_programmers = { { value = "jlink", label = "jlink" } },
	avrdude_parts = { { value = "m328p", label = "ATmega328P" } },
	dfu_programmer_targets = { { value = "atmega32u4", label = "atmega32u4" } },
	storage_devices = {
		{ value = "/dev/sdb", label = "USB disk / 64 MiB", size = 67108864, kind = "disk", disk = "sdb", fs_type = "", mounted = false },
		{ value = "/dev/sdb1", label = "USB ext4 partition / 32 MiB", size = 33554432, kind = "partition", disk = "sdb", fs_type = "ext4", mounted = false }
	},
	uploads = {
		{ id = "upload-1700000000-100-1", kind = "firmware_image", original_name = "firmware.bin", size = 1048576, sha256 = string.rep("a", 64) },
		{ id = "upload-1700000000-100-2", kind = "storage_image", original_name = "recovery.img", size = 8388608, sha256 = string.rep("b", 64) },
		{ id = "upload-1700000000-100-3", kind = "storage_image", original_name = "filesystem.squashfs", size = 4194304, sha256 = string.rep("c", 64) }
	}
}

local action_ids = {
	"firmware.openocd", "firmware.avrdude", "firmware.dfu", "firmware.serial",
	"storage.inspect", "storage.repair", "storage.image", "storage.restore", "storage.squashfs"
}
for _, action_id in ipairs(action_ids) do
	local schema, err = phase3.describe(action_id, context)
	expect(schema and not err, "schema failed: " .. action_id .. " / " .. tostring(err))
	expect(schema.action_id == action_id and type(schema.fields) == "table" and #schema.fields > 0, "schema contract mismatch: " .. action_id)
end

local openocd_probe = assert(phase3.prepare("firmware.openocd", { device = "usb:1-9" }, context))
expect(openocd_probe.argv[1] == "/usr/bin/openocd" and contains(openocd_probe.argv, "/usr/share/openocd/scripts/interface/jlink.cfg"), "OpenOCD probe argv mismatch")
expect(not openocd_probe.confirmation.required and not contains_text(openocd_probe.argv, "@UPLOAD@"), "OpenOCD probe boundary mismatch")

local openocd_program = assert(phase3.prepare("firmware.openocd", {
	device = "usb:1-9", operation = "program", upload = "upload-1700000000-100-1", address = "0x08000000"
}, context))
expect(openocd_program.confirmation.required and #openocd_program.input_uploads == 1, "OpenOCD programming confirmation/input binding is missing")
expect(openocd_program.confirmation.phrase:find("usb:1-9", 1, true), "OpenOCD confirmation is not target-bound")

local avrdude_read = assert(phase3.prepare("firmware.avrdude", {
	device = "usb:1-9", programmer = "jlink", part = "m328p", operation = "read_flash"
}, context))
expect(avrdude_read.argv[1] == "/usr/bin/avrdude" and contains(avrdude_read.argv, "usb:PROBE123") and contains_text(avrdude_read.argv, "flash:r:@ARTIFACT@/firmware-read.bin:r"), "AVRDUDE backup argv mismatch")
expect(#avrdude_read.artifacts == 1 and not avrdude_read.confirmation.required, "AVRDUDE read artifact/confirmation mismatch")

local avrdude_write = assert(phase3.prepare("firmware.avrdude", {
	device = "usb:1-9", programmer = "jlink", part = "m328p", operation = "write_flash", upload = "upload-1700000000-100-1"
}, context))
expect(contains_text(avrdude_write.argv, "@UPLOAD@/upload-1700000000-100-1") and avrdude_write.confirmation.required, "AVRDUDE write plan mismatch")

local dfu_read = assert(phase3.prepare("firmware.dfu", { device = "dfu:1-7", operation = "read" }, context))
expect(dfu_read.argv[1] == "/usr/bin/dfu-util" and contains(dfu_read.argv, "-U") and #dfu_read.artifacts == 1, "dfu-util read plan mismatch")
expect(not dfu_read.confirmation.required, "DFU read unexpectedly requires confirmation")

local dfu_erase = assert(phase3.prepare("firmware.dfu", {
	tool = "dfu-programmer", device = "dfu:1-7", target = "atmega32u4", operation = "erase"
}, context))
expect(dfu_erase.argv[1] == "/usr/bin/dfu-programmer" and contains(dfu_erase.argv, "atmega32u4:1,7") and contains(dfu_erase.argv, "erase") and dfu_erase.confirmation.required, "dfu-programmer erase plan mismatch")

local serial_read = assert(phase3.prepare("firmware.serial", {
	tool = "stm32flash", device = "/dev/ttyUSB9", operation = "read", length = 65536
}, context))
expect(serial_read.argv[1] == "/usr/bin/stm32flash" and contains(serial_read.argv, "@ARTIFACT@/firmware-serial-read.bin"), "STM32Flash read plan mismatch")
expect(#serial_read.artifacts == 1 and not serial_read.confirmation.required, "serial read artifact/confirmation mismatch")
expect(serial_read.options.device_topology == "1-8" and serial_read.options.device_usb_id == "0403:6001", "serial target binding metadata mismatch")

local serial_write = assert(phase3.prepare("firmware.serial", {
	tool = "bossac", device = "/dev/ttyUSB9", operation = "write", upload = "upload-1700000000-100-1"
}, context))
expect(serial_write.argv[1] == "/usr/bin/bossac" and contains(serial_write.argv, "--write") and serial_write.confirmation.required, "BOSSA write plan mismatch")

local smart = assert(phase3.prepare("storage.inspect", { device = "/dev/sdb", operation = "smart_all" }, context))
expect(smart.argv[1] == "/usr/sbin/smartctl" and contains(smart.argv, "-x") and not smart.confirmation.required, "SMART read-only plan mismatch")

local repair = assert(phase3.prepare("storage.repair", { device = "/dev/sdb1", operation = "fsck_assume_yes" }, context))
expect(repair.argv[1] == "/usr/sbin/e2fsck" and contains(repair.argv, "-y") and repair.confirmation.required, "filesystem repair plan mismatch")
expect(repair.confirmation.phrase:find("/dev/sdb1", 1, true), "storage repair confirmation is not target-bound")

local image = assert(phase3.prepare("storage.image", { device = "/dev/sdb", offset = 4096, length = 8388608 }, context))
expect(image.argv[1] == "/bin/dd" and contains(image.argv, "skip=4096") and contains(image.argv, "count=8388608"), "raw imaging byte-bound argv mismatch")
expect(#image.artifacts == 2 and not image.confirmation.required, "raw imaging artifacts/confirmation mismatch")

local restore = assert(phase3.prepare("storage.restore", { device = "/dev/sdb", upload = "upload-1700000000-100-2" }, context))
expect(restore.argv[1] == "/bin/dd" and contains_text(restore.argv, "@UPLOAD@/upload-1700000000-100-2"), "raw restore argv mismatch")
expect(restore.confirmation.required and restore.confirmation.phrase:find(string.rep("b", 64), 1, true), "raw restore confirmation is not hash-bound")

local squash = assert(phase3.prepare("storage.squashfs", {
	upload = "upload-1700000000-100-3", operation = "extract", paths = { "etc/config/network", "www/index.html" }, output_limit_mib = 64
}, context))
expect(squash.argv[1] == "/usr/sbin/unsquashfs" and contains(squash.argv, "@WORK@/squashfs-recovery"), "SquashFS extraction argv mismatch")
expect(#squash.workspaces == 1 and squash.workspaces[1].reserve_size == 67108864 and #squash.artifacts == 1, "SquashFS workspace/artifact boundary mismatch")

local rejected = phase3.prepare("storage.image", { device = "/dev/sdb", executable = "/bin/sh" }, context)
expect(rejected == nil, "unknown executable option was accepted")
rejected = phase3.prepare("firmware.openocd", { device = "usb:1-9", interface_config = "../../etc/passwd" }, context)
expect(rejected == nil, "OpenOCD config traversal was accepted")
rejected = phase3.prepare("storage.image", { device = "/dev/sda1", length = 4096 }, context)
expect(rejected == nil, "non-inventoried system storage target was accepted")
rejected = phase3.prepare("storage.image", { device = "/dev/sdb", offset = 67108863, length = 2 }, context)
expect(rejected == nil, "out-of-range storage image was accepted")
rejected = phase3.prepare("storage.restore", { device = "/dev/sdb", upload = "upload-1700000000-100-2", offset = 4096, verify = true }, context)
expect(rejected == nil, "unsupported nonzero-offset restore verification was accepted")
rejected = phase3.prepare("storage.squashfs", { upload = "upload-1700000000-100-3", operation = "extract", paths = { "../etc/shadow" } }, context)
expect(rejected == nil, "SquashFS path traversal was accepted")

print("DDK_OPERATOR_PHASE3_TEST_OK")
