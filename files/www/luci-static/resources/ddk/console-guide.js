/* Technician workflow descriptions and conservative native-output interpretation. */
(function (root, factory) {
	var api = factory();
	if (typeof module === 'object' && module.exports) module.exports = api;
	else root.DDKGuide = api;
})(typeof globalThis !== 'undefined' ? globalThis : this, function () {
	'use strict';
	var catalog = {
		'network.lldp': { name: 'Switch & port', summary: 'Identify the connected switch, remote port and advertised management address.', output: 'Neighbor and switch-port inventory', module: 'network-discovery', group: 'network', requires: 'Connect the Ethernet cable to an LLDP/CDP-advertising switch. No neighbors means no advertisement was observed; it does not prove the cable is disconnected.', native: ['lldpcli'] },
		'network.snmp': { name: 'Equipment check', summary: 'Read switch interfaces, printer supplies, UPS status or a custom SNMP OID.', output: 'Numeric OIDs with equipment values', module: 'network-discovery', group: 'network', requires: 'Enter the target and its SNMP credentials. System checks use GET; other profiles walk the selected MIB subtree. SNMPv3 authPriv supports AES-128, AES-192/256 and DES. Match the equipment settings; AES-192/256 variants must also match.', native: ['snmpget', 'snmpwalk'] },
		'network.compare_scans': { name: 'Compare scans', summary: 'See what changed between two saved Nmap cases.', output: 'Host, port and service differences', module: 'network-discovery', group: 'network', requires: 'Run and save two completed Nmap jobs with XML or All artifact output. Choose earlier and later cases. Match targets and scan settings for a meaningful before/after comparison.', native: ['ndiff'] },
		'network.tracepath': { name: 'Path & MTU', summary: 'Locate path hops and packet-size constraints behind VPN or application failures.', output: 'Hop responses and reported path MTU', module: 'network-discovery', group: 'network', requires: 'Enter the destination. UDP probes and ICMP replies must pass along the route. Missing replies can indicate filtering; they do not prove a hop is down.', native: ['tracepath'] },
		'network.smb': { name: 'Windows & NAS shares', summary: 'List shares, browse a folder, or verify an upload/download round trip.', output: 'Share access, directory listing and verified transfer results', module: 'network-discovery', group: 'network', requires: 'Choose guest or enter credentials. Transfer tests create a unique orbit-test file in the selected folder, compare SHA-256 and attempt deletion even after Stop. Review cleanup results. SMB2 is the default; select NT1 only when the server requires SMB1.', native: ['smbclient'] },
		'network.nmap_lan_discovery': {
			name: 'Network discovery',
			summary: 'Find hosts, ports and services with Nmap.',
			output: 'Host and service inventory',
			module: 'network-discovery',
			group: 'network',
			requires: 'Select the interface or target for this job. Use an endpoint you manage for active tests.',
			native: ['nmap', 'arp-scan', 'fping', 'dig']
		},
		'network.arp_scan': {
			name: 'ARP discovery',
			summary: 'Find IPv4 devices on a local Ethernet or Wi-Fi segment.',
			output: 'IP, MAC and vendor list',
			module: 'network-discovery',
			group: 'network',
			requires: 'Select the interface or target for this job. Use an endpoint you manage for active tests.',
			native: ['nmap', 'arp-scan', 'fping', 'dig']
		},
		'network.fping': {
			name: 'Loss & latency',
			summary: 'Watch reachability, packet loss and response times.',
			output: 'Timestamped host measurements',
			module: 'network-discovery',
			group: 'network',
			requires: 'Select the interface or target for this job. Use an endpoint you manage for active tests.',
			native: ['nmap', 'arp-scan', 'fping', 'dig']
		},
		'network.dns': {
			name: 'DNS lookup',
			summary: 'Inspect records, resolver replies and delegation.',
			output: 'DNS answers and query status',
			module: 'network-discovery',
			group: 'network',
			requires: 'Select the interface or target for this job. Use an endpoint you manage for active tests.',
			native: ['nmap', 'arp-scan', 'fping', 'dig']
		},
		'network.interfaces': {
			name: 'Network interfaces',
			summary: 'Inspect addresses and link state on the router.',
			output: 'Interface and address listing',
			module: 'network-info',
			group: 'network',
			requires: 'Select the interface or target for this job. Use an endpoint you manage for active tests.',
			native: ['ip']
		},
		'network.routes': {
			name: 'Routing table',
			summary: 'Check where the router sends traffic.',
			output: 'IPv4 and IPv6 routes',
			module: 'network-info',
			group: 'network',
			requires: 'Select the interface or target for this job. Use an endpoint you manage for active tests.',
			native: ['ip']
		},
		'throughput.iperf3': {
			name: 'Throughput test',
			summary: 'Measure TCP or UDP performance against an iperf3 peer.',
			output: 'Transfer rates and test statistics',
			module: 'throughput',
			group: 'network',
			requires: 'Select the interface or target for this job. Use an endpoint you manage for active tests.',
			native: ['iperf3', 'bmon', 'iftop', 'vnstat']
		},
		'capture.lan_metadata_snapshot': {
			name: 'Packet capture',
			summary: 'Capture and decode traffic using a precise filter.',
			output: 'PCAP and decoded packets',
			module: 'packet-capture',
			group: 'network',
			requires: 'Select the interface or target for this job. Use an endpoint you manage for active tests.',
			native: ['tcpdump', 'tcpreplay', 'netsniff-ng', 'dnstop']
		},
		'capture.ring': {
			name: 'Rotating capture',
			summary: 'Keep a continuous traffic record within a chosen disk budget.',
			output: 'Rotating PCAP files',
			module: 'packet-capture',
			group: 'network',
			requires: 'Select the interface or target for this job. Use an endpoint you manage for active tests.',
			native: ['tcpdump', 'tcpreplay', 'netsniff-ng', 'dnstop']
		},
		'capture.inspect': {
			name: 'Inspect a capture',
			summary: 'Read a saved capture without collecting new traffic.',
			output: 'Decoded packet summary',
			module: 'packet-capture',
			group: 'network',
			requires: 'Select the interface or target for this job. Use an endpoint you manage for active tests.',
			native: ['tcpdump', 'tcpreplay', 'netsniff-ng', 'dnstop']
		},
		'capture.replay': {
			name: 'Replay a capture',
			summary: 'Send a saved packet capture through a selected interface.',
			output: 'Replay statistics',
			module: 'packet-capture',
			group: 'network',
			requires: 'Select the interface or target for this job. Use an endpoint you manage for active tests.',
			native: ['tcpdump', 'tcpreplay', 'netsniff-ng', 'dnstop']
		},
		'wireless.survey': {
			name: 'Wi-Fi survey',
			summary: 'Inspect channels, nearby networks or connected stations.',
			output: 'Wireless survey observations',
			module: 'wireless-diagnostics',
			group: 'network',
			requires: 'Select the interface or target for this job. Use an endpoint you manage for active tests.',
			native: ['aircrack-ng', 'airmon-ng', 'horst', 'wavemon', 'iw', 'iwinfo']
		},
		'wireless.monitor': {
			name: 'Wi-Fi monitor capture',
			summary: 'Capture wireless frames on a selected radio.',
			output: 'Wireless PCAP',
			module: 'wireless-diagnostics',
			group: 'network',
			requires: 'Select the interface or target for this job. Use an endpoint you manage for active tests.',
			native: ['aircrack-ng', 'airmon-ng', 'horst', 'wavemon', 'iw', 'iwinfo']
		},
		'wireless.file_analysis': {
			name: 'Wireless file analysis',
			summary: 'Inspect or analyze a saved wireless capture.',
			output: 'Native analysis and output files',
			module: 'wireless-diagnostics',
			group: 'network',
			requires: 'Select the interface or target for this job. Use an endpoint you manage for active tests.',
			native: ['aircrack-ng', 'airmon-ng', 'horst', 'wavemon', 'iw', 'iwinfo']
		},
		'android.identify': {
			name: 'Identify Android USB',
			summary: 'Inspect USB evidence for attached Android devices.',
			output: 'USB identity report',
			module: 'android-repair',
			group: 'devices',
			requires:
				'Connect the intended device and select its exact identity. Approve the device connection when requested.',
			native: ['adb']
		},
		'android.operator_guide': {
			name: 'Android connection guide',
			summary: 'Check the native Android tools and supported connection workflow.',
			output: 'Native tool reference',
			module: 'android-repair',
			group: 'devices',
			requires:
				'Connect the intended device and select its exact identity. Approve the device connection when requested.',
			native: ['adb']
		},
		'android.operator': {
			name: 'Android workbench',
			summary: 'Inspect devices, collect logs, transfer files and manage apps.',
			output: 'Selected device output and files',
			module: 'android-repair',
			group: 'devices',
			requires:
				'Connect the intended device and select its exact identity. Approve the device connection when requested.',
			native: ['adb']
		},
		'android.adb_diagnostics': {
			name: 'ADB diagnostics',
			summary: 'Run USB device diagnostics and collect selected files.',
			output: 'ADB output and diagnostic artifacts',
			module: 'android-repair',
			group: 'devices',
			requires:
				'Connect the intended device and select its exact identity. Approve the device connection when requested.',
			native: ['adb']
		},
		'android.adb_manage': {
			name: 'ADB device management',
			summary: 'Install, transfer, back up or manage a selected USB device.',
			output: 'Device operation log',
			module: 'android-repair',
			group: 'devices',
			requires:
				'Connect the intended device and select its exact identity. Approve the device connection when requested.',
			native: ['adb']
		},
		'apple.identify': {
			name: 'Identify Apple USB',
			summary: 'Identify an Apple device and its current USB mode.',
			output: 'Normal, recovery or DFU evidence',
			module: 'apple-repair',
			group: 'devices',
			requires:
				'Connect the intended device and select its exact identity. Approve the device connection when requested.',
			native: ['ideviceinfo', 'idevicerestore', 'irecovery']
		},
		'apple.operator_guide': {
			name: 'Apple connection guide',
			summary: 'Review installed Apple tools and connection requirements.',
			output: 'Native tool reference',
			module: 'apple-repair',
			group: 'devices',
			requires:
				'Connect the intended device and select its exact identity. Approve the device connection when requested.',
			native: ['ideviceinfo', 'idevicerestore', 'irecovery']
		},
		'apple.mobile_diagnostics': {
			name: 'iOS diagnostics',
			summary: 'Inspect a paired device using the installed Apple utilities.',
			output: 'Selected diagnostic output',
			module: 'apple-repair',
			group: 'devices',
			requires:
				'Connect the intended device and select its exact identity. Approve the device connection when requested.',
			native: ['ideviceinfo', 'idevicerestore', 'irecovery']
		},
		'apple.mobile_capture': {
			name: 'iOS logs & screenshot',
			summary: 'Capture device logs or a screenshot.',
			output: 'Syslog or screenshot file',
			module: 'apple-repair',
			group: 'devices',
			requires:
				'Connect the intended device and select its exact identity. Approve the device connection when requested.',
			native: ['ideviceinfo', 'idevicerestore', 'irecovery']
		},
		'apple.mobile_manage': {
			name: 'iOS device management',
			summary: 'Manage a selected paired device through supported native operations.',
			output: 'Device operation log',
			module: 'apple-repair',
			group: 'devices',
			requires:
				'Connect the intended device and select its exact identity. Approve the device connection when requested.',
			native: ['ideviceinfo', 'idevicerestore', 'irecovery']
		},
		'apple.recovery': {
			name: 'Apple recovery & DFU',
			summary: 'Inspect or control a device in recovery or DFU mode.',
			output: 'Recovery operation output',
			module: 'apple-repair',
			group: 'devices',
			requires:
				'Connect the intended device and select its exact identity. Approve the device connection when requested.',
			native: ['ideviceinfo', 'idevicerestore', 'irecovery']
		},
		'apple.restore': {
			name: 'Restore Apple firmware',
			summary: 'Restore a supported device from a selected IPSW and ticket.',
			output: 'Restore log',
			module: 'apple-repair',
			group: 'devices',
			requires:
				'Connect the intended device and select its exact identity. Approve the device connection when requested.',
			native: ['ideviceinfo', 'idevicerestore', 'irecovery']
		},
		'serial.inspect': {
			name: 'Identify serial ports',
			summary: 'Map serial nodes to the USB hardware behind them.',
			output: 'Port and hardware attribution',
			module: 'serial',
			group: 'hardware',
			requires: 'Attach the correct adapter or programmer and check the target wiring and parameters.',
			native: ['picocom', 'socat', 'ser2net', 'conserver']
		},
		'serial.console': {
			name: 'Serial console',
			summary: 'Open an interactive session with text or hex transmission.',
			output: 'Live serial output and session log',
			module: 'serial',
			group: 'hardware',
			requires: 'Attach the correct adapter or programmer and check the target wiring and parameters.',
			native: ['picocom', 'socat', 'ser2net', 'conserver']
		},
		'serial.session': {
			name: 'Serial receive & transmit',
			summary: 'Run a configured serial receive or transmit session.',
			output: 'Received serial bytes',
			module: 'serial',
			group: 'hardware',
			requires: 'Attach the correct adapter or programmer and check the target wiring and parameters.',
			native: ['picocom', 'socat', 'ser2net', 'conserver']
		},
		'serial.transfer': {
			name: 'Serial file transfer',
			summary: 'Send or receive a file through a selected serial adapter.',
			output: 'Transfer log and received file',
			module: 'serial',
			group: 'hardware',
			requires: 'Attach the correct adapter or programmer and check the target wiring and parameters.',
			native: ['picocom', 'socat', 'ser2net', 'conserver']
		},
		'cellular.diagnostics': {
			name: 'Cellular diagnostics',
			summary: 'Inspect the modem, SIM, signal and data-session state.',
			output: 'Selected modem diagnostics',
			module: 'cellular',
			group: 'network',
			requires: 'Select the interface or target for this job. Use an endpoint you manage for active tests.',
			native: ['qmicli', 'uqmi', 'qcsuper']
		},
		'cellular.snapshot': {
			name: 'Cellular snapshot',
			summary: 'Collect the built-in modem diagnostic snapshot.',
			output: 'Modem status report',
			module: 'cellular',
			group: 'network',
			requires: 'Select the interface or target for this job. Use an endpoint you manage for active tests.',
			native: ['qmicli', 'uqmi', 'qcsuper']
		},
		'cellular.control': {
			name: 'Cellular connection',
			summary: 'Control the selected modem connection or supported network mode.',
			output: 'Modem response',
			module: 'cellular',
			group: 'network',
			requires: 'Select the interface or target for this job. Use an endpoint you manage for active tests.',
			native: ['qmicli', 'uqmi', 'qcsuper']
		},
		'cellular.raw_command': {
			name: 'Modem AT & GNSS',
			summary: 'Use the EC25 AT interface for diagnostics and built-in GNSS.',
			output: 'AT responses and GNSS observations',
			module: 'cellular',
			group: 'network',
			requires: 'Select the interface or target for this job. Use an endpoint you manage for active tests.',
			native: ['qmicli', 'uqmi', 'qcsuper']
		},
		'cellular.profile': {
			name: 'Cellular APN profile',
			summary: 'Change the APN with a timed recovery window.',
			output: 'Profile confirmation or rollback result',
			module: 'cellular',
			group: 'network',
			requires: 'Select the interface or target for this job. Use an endpoint you manage for active tests.',
			native: ['qmicli', 'uqmi', 'qcsuper']
		},
		'automation.mqtt_subscribe': {
			name: 'MQTT topic monitor',
			summary: 'Subscribe to topics and inspect broker messages.',
			output: 'Topic and payload log',
			module: 'automation',
			group: 'hardware',
			requires: 'Attach the correct adapter or programmer and check the target wiring and parameters.',
			native: ['mosquitto_pub', 'mosquitto_sub', 'thd', 'crelay']
		},
		'automation.mqtt_publish': {
			name: 'MQTT publish',
			summary: 'Publish a payload or manage a retained message.',
			output: 'Broker operation output',
			module: 'automation',
			group: 'hardware',
			requires: 'Attach the correct adapter or programmer and check the target wiring and parameters.',
			native: ['mosquitto_pub', 'mosquitto_sub', 'thd', 'crelay']
		},
		'automation.relay': {
			name: 'USB relay control',
			summary: 'Inspect or change a selected USB relay channel.',
			output: 'Relay operation output',
			module: 'automation',
			group: 'hardware',
			requires: 'Attach the correct adapter or programmer and check the target wiring and parameters.',
			native: ['mosquitto_pub', 'mosquitto_sub', 'thd', 'crelay']
		},
		'bluetooth.scan': {
			name: 'Bluetooth discovery',
			summary: 'Discover nearby Classic or Low Energy devices.',
			output: 'Bluetooth discovery observations',
			module: 'bluetooth',
			group: 'hardware',
			requires: 'Attach the correct adapter or programmer and check the target wiring and parameters.',
			native: ['hciconfig', 'hcitool']
		},
		'bluetooth.services': {
			name: 'Bluetooth services & GATT',
			summary: 'Initialize an adapter, inspect services or access GATT attributes.',
			output: 'Selected service or attribute response',
			module: 'bluetooth',
			group: 'hardware',
			requires: 'Attach the correct adapter or programmer and check the target wiring and parameters.',
			native: ['hciconfig', 'hcitool']
		},
		'bluetooth.pairing': {
			name: 'Bluetooth connections',
			summary: 'Pair, connect, trust or disconnect through a chosen controller.',
			output: 'Connection operation log',
			module: 'bluetooth',
			group: 'hardware',
			requires: 'Attach the correct adapter or programmer and check the target wiring and parameters.',
			native: ['hciconfig', 'hcitool']
		},
		'camera.still_snapshot': {
			name: 'Camera still',
			summary: 'Capture an image from a selected USB camera.',
			output: 'Image file',
			module: 'camera',
			group: 'devices',
			requires:
				'Connect the intended device and select its exact identity. Approve the device connection when requested.',
			native: ['fswebcam', 'mjpg_streamer', 'motion', 'v4l2-ctl']
		},
		'camera.stream': {
			name: 'Camera live view',
			summary: 'Run the existing authenticated camera stream workflow.',
			output: 'Live viewing session',
			module: 'camera',
			group: 'devices',
			requires:
				'Connect the intended device and select its exact identity. Approve the device connection when requested.',
			native: ['fswebcam', 'mjpg_streamer', 'motion', 'v4l2-ctl']
		},
		'camera.video': {
			name: 'Camera controls & recording',
			summary: 'Inspect controls or record video from a selected camera.',
			output: 'Control output or video file',
			module: 'camera',
			group: 'devices',
			requires:
				'Connect the intended device and select its exact identity. Approve the device connection when requested.',
			native: ['fswebcam', 'mjpg_streamer', 'motion', 'v4l2-ctl']
		},
		'can.configure': {
			name: 'Set up CAN interface',
			summary: 'Configure bitrate and link state for a physical CAN adapter.',
			output: 'Interface configuration result',
			module: 'can',
			group: 'hardware',
			requires: 'Attach the correct adapter or programmer and check the target wiring and parameters.',
			native: ['candump', 'cansend']
		},
		'can.capture': {
			name: 'CAN capture',
			summary: 'Capture filtered frames from a selected CAN interface.',
			output: 'Timestamped CAN frames',
			module: 'can',
			group: 'hardware',
			requires: 'Attach the correct adapter or programmer and check the target wiring and parameters.',
			native: ['candump', 'cansend']
		},
		'can.transmit': {
			name: 'Send CAN frames',
			summary: 'Transmit explicit frames through the selected adapter.',
			output: 'Transmit result',
			module: 'can',
			group: 'hardware',
			requires: 'Attach the correct adapter or programmer and check the target wiring and parameters.',
			native: ['candump', 'cansend']
		},
		'can.replay': {
			name: 'Replay CAN log',
			summary: 'Replay a saved candump log onto a selected CAN interface.',
			output: 'Replay result',
			module: 'can',
			group: 'hardware',
			requires: 'Attach the correct adapter or programmer and check the target wiring and parameters.',
			native: ['candump', 'cansend']
		},
		'industrial.modbus_read': {
			name: 'Read Modbus registers',
			summary: 'Read holding registers over the existing Modbus workflow.',
			output: 'Register values',
			module: 'modbus-industrial',
			group: 'hardware',
			requires: 'Attach the correct adapter or programmer and check the target wiring and parameters.',
			native: ['mbpoll', 'mbusd', 'ptp4l', 'ntripclient']
		},
		'industrial.modbus_write': {
			name: 'Modbus workbench',
			summary: 'Read, poll or write coils and registers over TCP or RTU.',
			output: 'Values and optional write readback',
			module: 'modbus-industrial',
			group: 'hardware',
			requires: 'Attach the correct adapter or programmer and check the target wiring and parameters.',
			native: ['mbpoll', 'mbusd', 'ptp4l', 'ntripclient']
		},
		'firmware.identify': {
			name: 'Identify programmers',
			summary: 'Inspect attached programmer and debug-probe USB identities.',
			output: 'Programmer identity report',
			module: 'firmware-programming',
			group: 'hardware',
			requires: 'Attach the correct adapter or programmer and check the target wiring and parameters.',
			native: [
				'flashrom',
				'openocd',
				'avrdude',
				'dfu-util',
				'stm32flash',
				'bossac',
				'lpc21isp',
				'ftdi_eeprom'
			]
		},
		'firmware.operator_guide': {
			name: 'Programmer connection guide',
			summary: 'Review installed programming tools and hardware attribution.',
			output: 'Native tool reference',
			module: 'firmware-programming',
			group: 'hardware',
			requires: 'Attach the correct adapter or programmer and check the target wiring and parameters.',
			native: [
				'flashrom',
				'openocd',
				'avrdude',
				'dfu-util',
				'stm32flash',
				'bossac',
				'lpc21isp',
				'ftdi_eeprom'
			]
		},
		'firmware.openocd': {
			name: 'OpenOCD workbench',
			summary: 'Probe, read, program or debug a selected embedded target.',
			output: 'Native debug or programming output',
			module: 'firmware-programming',
			group: 'hardware',
			requires: 'Attach the correct adapter or programmer and check the target wiring and parameters.',
			native: [
				'flashrom',
				'openocd',
				'avrdude',
				'dfu-util',
				'stm32flash',
				'bossac',
				'lpc21isp',
				'ftdi_eeprom'
			]
		},
		'firmware.avrdude': {
			name: 'AVR programmer',
			summary: 'Read or program flash, EEPROM, memories and fuses.',
			output: 'Readback file or operation log',
			module: 'firmware-programming',
			group: 'hardware',
			requires: 'Attach the correct adapter or programmer and check the target wiring and parameters.',
			native: [
				'flashrom',
				'openocd',
				'avrdude',
				'dfu-util',
				'stm32flash',
				'bossac',
				'lpc21isp',
				'ftdi_eeprom'
			]
		},
		'firmware.dfu': {
			name: 'DFU programmer',
			summary: 'Read or program a selected native-supported DFU target.',
			output: 'Firmware file or operation log',
			module: 'firmware-programming',
			group: 'hardware',
			requires: 'Attach the correct adapter or programmer and check the target wiring and parameters.',
			native: [
				'flashrom',
				'openocd',
				'avrdude',
				'dfu-util',
				'stm32flash',
				'bossac',
				'lpc21isp',
				'ftdi_eeprom'
			]
		},
		'firmware.serial': {
			name: 'Serial programmer',
			summary: 'Use the installed STM32, BOSSA or LPC serial programmer.',
			output: 'Readback file or operation log',
			module: 'firmware-programming',
			group: 'hardware',
			requires: 'Attach the correct adapter or programmer and check the target wiring and parameters.',
			native: [
				'flashrom',
				'openocd',
				'avrdude',
				'dfu-util',
				'stm32flash',
				'bossac',
				'lpc21isp',
				'ftdi_eeprom'
			]
		},
		'firmware.ftdi': {
			name: 'FTDI EEPROM',
			summary: 'Back up, build or write a selected FTDI EEPROM configuration.',
			output: 'EEPROM backup and operation result',
			module: 'firmware-programming',
			group: 'hardware',
			requires: 'Attach the correct adapter or programmer and check the target wiring and parameters.',
			native: [
				'flashrom',
				'openocd',
				'avrdude',
				'dfu-util',
				'stm32flash',
				'bossac',
				'lpc21isp',
				'ftdi_eeprom'
			]
		},
		'firmware.flashrom': {
			name: 'SPI flash programmer',
			summary: 'Read, write or verify flash through an installed programmer.',
			output: 'Flash image or verification result',
			module: 'firmware-programming',
			group: 'hardware',
			requires: 'Attach the correct adapter or programmer and check the target wiring and parameters.',
			native: [
				'flashrom',
				'openocd',
				'avrdude',
				'dfu-util',
				'stm32flash',
				'bossac',
				'lpc21isp',
				'ftdi_eeprom'
			]
		},
		'storage.inspect': {
			name: 'Drive diagnostics',
			summary: 'Inspect SMART, disk health and supported filesystem details.',
			output: 'Native drive diagnostics',
			module: 'storage-recovery',
			group: 'data',
			requires: 'Choose the intended file or external drive. Preserve a backup before writing to a target.',
			native: ['e2fsck', 'badblocks', 'smartctl', 'unsquashfs']
		},
		'storage.repair': {
			name: 'Filesystem repair',
			summary: 'Run the selected repair or media-test operation on an external drive.',
			output: 'Repair or test log',
			module: 'storage-recovery',
			group: 'data',
			requires: 'Choose the intended file or external drive. Preserve a backup before writing to a target.',
			native: ['e2fsck', 'badblocks', 'smartctl', 'unsquashfs']
		},
		'storage.image': {
			name: 'Create disk image',
			summary: 'Image a chosen byte range from an external drive.',
			output: 'Raw image and optional checksum',
			module: 'storage-recovery',
			group: 'data',
			requires: 'Choose the intended file or external drive. Preserve a backup before writing to a target.',
			native: ['e2fsck', 'badblocks', 'smartctl', 'unsquashfs']
		},
		'storage.restore': {
			name: 'Restore disk image',
			summary: 'Write a selected image with optional offset-aware verification.',
			output: 'Restore and comparison result',
			module: 'storage-recovery',
			group: 'data',
			requires: 'Choose the intended file or external drive. Preserve a backup before writing to a target.',
			native: ['e2fsck', 'badblocks', 'smartctl', 'unsquashfs']
		},
		'storage.squashfs': {
			name: 'SquashFS inspection',
			summary: 'Inspect or extract a selected SquashFS filesystem.',
			output: 'File listing or extracted archive',
			module: 'storage-recovery',
			group: 'data',
			requires: 'Choose the intended file or external drive. Preserve a backup before writing to a target.',
			native: ['e2fsck', 'badblocks', 'smartctl', 'unsquashfs']
		},
		'storage.ddrescue': {
			name: 'Recovery imaging',
			summary: 'Recover an external drive into an image with a resumable map.',
			output: 'Recovery image and map',
			module: 'storage-recovery',
			group: 'data',
			requires: 'Choose the intended file or external drive. Preserve a backup before writing to a target.',
			native: ['e2fsck', 'badblocks', 'smartctl', 'unsquashfs']
		},
		'storage.clone': {
			name: 'Drive-to-drive recovery',
			summary: 'Recover directly between two external drives.',
			output: 'Destination data and resume map',
			module: 'storage-recovery',
			group: 'data',
			requires: 'Choose the intended file or external drive. Preserve a backup before writing to a target.',
			native: ['e2fsck', 'badblocks', 'smartctl', 'unsquashfs']
		},
		'cases.export': {
			name: 'Export saved case',
			summary: 'Bundle a saved case and its registered results.',
			output: 'Case archive',
			module: 'storage-recovery',
			group: 'data',
			requires: 'Choose the intended file or external drive. Preserve a backup before writing to a target.',
			native: ['e2fsck', 'badblocks', 'smartctl', 'unsquashfs']
		},
		'forensics.inspect_file': {
			name: 'File analysis',
			summary: 'Identify, hash or analyze a selected input file.',
			output: 'File analysis report',
			module: 'forensics',
			group: 'data',
			requires: 'Choose the intended file or external drive. Preserve a backup before writing to a target.',
			native: ['yara', 'ssdeep', 'hashdeep', 'checksec', 'file', 'xxd', 'strace', 'gdbserver', 'unsquashfs']
		},
		'forensics.hex': {
			name: 'Hex viewer',
			summary: 'Inspect bytes from a selected input file.',
			output: 'Hex and ASCII output',
			module: 'forensics',
			group: 'data',
			requires: 'Choose the intended file or external drive. Preserve a backup before writing to a target.',
			native: ['yara', 'ssdeep', 'hashdeep', 'checksec', 'file', 'xxd', 'strace', 'gdbserver', 'unsquashfs']
		},
		'forensics.trace': {
			name: 'Trace process syscalls',
			summary: 'Observe syscalls from an exact selected process.',
			output: 'Syscall trace',
			module: 'forensics',
			group: 'data',
			requires: 'Choose the intended file or external drive. Preserve a backup before writing to a target.',
			native: ['yara', 'ssdeep', 'hashdeep', 'checksec', 'file', 'xxd', 'strace', 'gdbserver', 'unsquashfs']
		},
		'forensics.debug_server': {
			name: 'Process debugger',
			summary: 'Attach a temporary GDB endpoint to a selected process.',
			output: 'Debugger session log',
			module: 'forensics',
			group: 'data',
			requires: 'Choose the intended file or external drive. Preserve a backup before writing to a target.',
			native: ['yara', 'ssdeep', 'hashdeep', 'checksec', 'file', 'xxd', 'strace', 'gdbserver', 'unsquashfs']
		},
		'monitoring.snapshot': {
			name: 'Traffic history',
			summary: 'Inspect interface history or a bounded traffic snapshot.',
			output: 'Native traffic statistics',
			module: 'monitoring',
			group: 'system',
			requires:
				'Choose the interface or process you want to inspect. Results describe this observation window.',
			native: ['vnstat', 'bmon', 'iftop', 'htop', 'nlbwmon']
		},
		'monitoring.bandwidth': {
			name: 'Bandwidth monitor',
			summary: 'Watch selected interfaces using the native bandwidth tools.',
			output: 'Bandwidth observations',
			module: 'monitoring',
			group: 'system',
			requires:
				'Choose the interface or process you want to inspect. Results describe this observation window.',
			native: ['vnstat', 'bmon', 'iftop', 'htop', 'nlbwmon']
		},
		'monitoring.resources': {
			name: 'Resource monitor',
			summary: 'Observe CPU and process resource usage.',
			output: 'Resource observations',
			module: 'monitoring',
			group: 'system',
			requires:
				'Choose the interface or process you want to inspect. Results describe this observation window.',
			native: ['vnstat', 'bmon', 'iftop', 'htop', 'nlbwmon']
		},
		'radio.rtl433_snapshot': {
			name: 'RTL-433 receiver',
			summary: 'Receive and decode supported sensor transmissions.',
			output: 'Decoded records and optional raw samples',
			module: 'sdr-radio',
			group: 'radio',
			requires: 'Connect a supported receiver and antenna. Select the correct tuner, frequency and input.',
			native: ['rtl_test', 'rtl_433', 'rtl_ais', 'rigctl']
		},
		'radio.ais': {
			name: 'AIS receiver',
			summary: 'Receive marine AIS through the selected tuner.',
			output: 'NMEA AIS records',
			module: 'sdr-radio',
			group: 'radio',
			requires: 'Connect a supported receiver and antenna. Select the correct tuner, frequency and input.',
			native: ['rtl_test', 'rtl_433', 'rtl_ais', 'rigctl']
		},
		'adsb.receive': {
			name: 'ADS-B receiver',
			summary: 'Receive aircraft broadcasts with the selected tuner.',
			output: 'Aircraft reception records',
			module: 'adsb',
			group: 'radio',
			requires: 'Connect a supported receiver and antenna. Select the correct tuner, frequency and input.',
			native: ['readsb', 'dump1090']
		},
		'radio.receiver_tools': {
			name: 'SDR bench',
			summary: 'Test a tuner or run a configured I/Q stream.',
			output: 'Receiver test or stream log',
			module: 'sdr-radio',
			group: 'radio',
			requires: 'Connect a supported receiver and antenna. Select the correct tuner, frequency and input.',
			native: ['rtl_test', 'rtl_433', 'rtl_ais', 'rigctl']
		},
		'gps.snapshot': {
			name: 'GNSS snapshot',
			summary: 'Capture and decode observations from a USB GNSS receiver.',
			output: 'NMEA and decoded observations',
			module: 'gps-gnss',
			group: 'radio',
			requires: 'Connect a supported receiver and antenna. Select the correct tuner, frequency and input.',
			native: ['gpsdecode', 'gpsd', 'cgps', 'rtkrcv', 'ntripclient']
		},
		'gps.ntrip': {
			name: 'NTRIP corrections',
			summary: 'Receive correction data from a chosen NTRIP caster.',
			output: 'Correction session output',
			module: 'gps-gnss',
			group: 'radio',
			requires: 'Connect a supported receiver and antenna. Select the correct tuner, frequency and input.',
			native: ['gpsdecode', 'gpsd', 'cgps', 'rtkrcv', 'ntripclient']
		},
		'gps.receiver_control': {
			name: 'Configure GNSS receiver',
			summary: 'Inspect or configure a selected external GNSS receiver.',
			output: 'Receiver response',
			module: 'gps-gnss',
			group: 'radio',
			requires: 'Connect a supported receiver and antenna. Select the correct tuner, frequency and input.',
			native: ['gpsdecode', 'gpsd', 'cgps', 'rtkrcv', 'ntripclient']
		},
		'gps.session': {
			name: 'GNSS & RTK session',
			summary: 'Run a temporary gpsd or RTKLIB receiver session.',
			output: 'Position observations and session output',
			module: 'gps-gnss',
			group: 'radio',
			requires: 'Connect a supported receiver and antenna. Select the correct tuner, frequency and input.',
			native: ['gpsdecode', 'gpsd', 'cgps', 'rtkrcv', 'ntripclient']
		},
		'auth.inventory': {
			name: 'Security token inventory',
			summary: 'Inspect supported smart cards and security tokens.',
			output: 'Token and reader inventory',
			module: 'smartcard-auth',
			group: 'hardware',
			requires: 'Attach the correct adapter or programmer and check the target wiring and parameters.',
			native: ['ykinfo', 'ykpersonalize', 'oathtool', 'stoken', 'pcsc_scan']
		},
		'auth.program': {
			name: 'Security token configuration',
			summary: 'Configure a selected supported security token.',
			output: 'Configuration result',
			module: 'smartcard-auth',
			group: 'hardware',
			requires: 'Attach the correct adapter or programmer and check the target wiring and parameters.',
			native: ['ykinfo', 'ykpersonalize', 'oathtool', 'stoken', 'pcsc_scan']
		},
		'auth.otp': {
			name: 'OATH token generator',
			summary: 'Generate a token using privately supplied OATH parameters.',
			output: 'Private token output',
			module: 'smartcard-auth',
			group: 'hardware',
			requires: 'Attach the correct adapter or programmer and check the target wiring and parameters.',
			native: ['ykinfo', 'ykpersonalize', 'oathtool', 'stoken', 'pcsc_scan']
		},
		'auth.stoken': {
			name: 'Software token tools',
			summary: 'Use the installed software-token utility with private inputs.',
			output: 'Private native token output',
			module: 'smartcard-auth',
			group: 'hardware',
			requires: 'Attach the correct adapter or programmer and check the target wiring and parameters.',
			native: ['ykinfo', 'ykpersonalize', 'oathtool', 'stoken', 'pcsc_scan']
		},
		'usb.inventory': {
			name: 'USB inventory',
			summary: 'Inspect USB descriptors and device topology.',
			output: 'USB inventory',
			module: 'usb-management',
			group: 'hardware',
			requires: 'Attach the correct adapter or programmer and check the target wiring and parameters.',
			native: ['lsusb', 'uhubctl', 'usbip']
		},
		'usb.power': {
			name: 'USB port power',
			summary: 'Control a chosen external hub port using its live topology.',
			output: 'Port power result',
			module: 'usb-management',
			group: 'hardware',
			requires: 'Attach the correct adapter or programmer and check the target wiring and parameters.',
			native: ['lsusb', 'uhubctl', 'usbip']
		},
		'usbip.attach': {
			name: 'USB/IP connection',
			summary: 'Attach or detach a specific exported USB device.',
			output: 'USB/IP connection result',
			module: 'usb-management',
			group: 'hardware',
			requires: 'Attach the correct adapter or programmer and check the target wiring and parameters.',
			native: ['lsusb', 'uhubctl', 'usbip']
		},
		'system.refresh': {
			name: 'System status',
			summary: 'Refresh the router system status snapshot.',
			output: 'System status report',
			module: 'system-information',
			group: 'system',
			requires:
				'Choose the interface or process you want to inspect. Results describe this observation window.',
			native: ['ubus', 'free', 'df']
		},
		'system.memory': {
			name: 'Memory & swap',
			summary: 'Inspect current memory and active swap.',
			output: 'Memory statistics',
			module: 'system-information',
			group: 'system',
			requires:
				'Choose the interface or process you want to inspect. Results describe this observation window.',
			native: ['ubus', 'free', 'df']
		},
		'storage.mounts': {
			name: 'Storage & mounts',
			summary: 'Inspect filesystem capacity and mount points.',
			output: 'Storage and mount listing',
			module: 'system-information',
			group: 'system',
			requires:
				'Choose the interface or process you want to inspect. Results describe this observation window.',
			native: ['ubus', 'free', 'df']
		},
		'packages.count': {
			name: 'Installed package count',
			summary: 'Count installed package records.',
			output: 'Package count',
			module: 'system-information',
			group: 'system',
			requires:
				'Choose the interface or process you want to inspect. Results describe this observation window.',
			native: ['ubus', 'free', 'df']
		}
	};
	var modules = {
		adsb: { name: 'ADS-B', group: 'radio' },
		'android-repair': { name: 'Android / ADB', group: 'devices' },
		'apple-repair': { name: 'Apple / iOS Repair', group: 'devices' },
		automation: { name: 'Automation / MQTT', group: 'hardware' },
		bluetooth: { name: 'Bluetooth', group: 'hardware' },
		camera: { name: 'Camera / Video', group: 'devices' },
		can: { name: 'CAN Bus', group: 'hardware' },
		cellular: { name: 'Cellular / Modem', group: 'network' },
		'firmware-programming': { name: 'Firmware / Embedded', group: 'hardware' },
		forensics: { name: 'Forensics / File Analysis', group: 'data' },
		'gps-gnss': { name: 'GPS / GNSS / RTK', group: 'radio' },
		'modbus-industrial': { name: 'Industrial / Modbus', group: 'hardware' },
		monitoring: { name: 'Monitoring', group: 'system' },
		'network-discovery': { name: 'Network Discovery', group: 'network' },
		'network-info': { name: 'Network Interface Status', group: 'network' },
		'packet-capture': { name: 'Capture & Traffic', group: 'network' },
		'sdr-radio': { name: 'SDR / Radio', group: 'radio' },
		serial: { name: 'USB & Serial Attribution', group: 'hardware' },
		'smartcard-auth': { name: 'Security / Authentication', group: 'hardware' },
		'storage-recovery': { name: 'Storage / Recovery', group: 'data' },
		'system-information': { name: 'System Information', group: 'system' },
		throughput: { name: 'Throughput & Live Traffic', group: 'network' },
		'usb-management': { name: 'USB Hardware', group: 'hardware' },
		'wireless-diagnostics': { name: 'Wi-Fi Diagnostics', group: 'network' }
	};
	var groups = [
		{ id: 'network', name: 'Network', icon: 'network' },
		{ id: 'devices', name: 'Devices', icon: 'phone' },
		{ id: 'hardware', name: 'Hardware', icon: 'chip' },
		{ id: 'radio', name: 'Radio & GNSS', icon: 'radio' },
		{ id: 'data', name: 'Storage & files', icon: 'drive' },
		{ id: 'system', name: 'System', icon: 'activity' }
	];
	var quick = [
		'network.nmap_lan_discovery',
		'android.operator',
		'capture.ring',
		'serial.console',
		'storage.ddrescue',
		'cellular.diagnostics'
	];
	var presets = {
		'network.lldp': [{ name: 'All ports', detail: 'Inspect every advertising neighbor', options: { interface: '' } }],
		'network.snmp': [
			{ name: 'Encrypted SNMPv3', detail: 'AES-128 with authentication; match the device settings', options: { version: '3', level: 'authPriv', privacy: 'AES', profile: 'system' } },
			{ name: 'Identity & uptime', detail: 'System name, description and uptime', options: { profile: 'system' } },
			{ name: 'Switch interfaces', detail: 'Status, errors and octet counters', options: { profile: 'interfaces' } },
			{ name: '64-bit counters', detail: 'High-capacity interface counters', options: { profile: 'interfaces64' } },
			{ name: 'Printer', detail: 'Printer-MIB supplies and status, if supported', options: { profile: 'printer' } },
			{ name: 'UPS', detail: 'UPS-MIB battery and power, if supported', options: { profile: 'ups' } }
		],
		'network.tracepath': [{ name: 'IPv4 path', detail: 'Start with a 1500-byte probe', options: { family: 'ipv4', length: 1500 } }, { name: 'IPv6 path', detail: 'Start with a 1500-byte probe', options: { family: 'ipv6', length: 1500 } }],
		'network.smb': [{ name: 'List shares', detail: 'Check access to the server', options: { operation: 'shares' } }, { name: 'Browse folder', detail: 'Read a directory listing', options: { operation: 'directory' } }, { name: 'Transfer check', detail: 'Upload, download, verify and clean up 1 MiB', options: { operation: 'transfer', transfer_mib: 1 } }],
		'network.nmap_lan_discovery': [
			{
				name: 'Find hosts',
				detail: 'Discover reachable devices',
				options: {
					scan_type: 'discovery',
					service_detection: false,
					os_detection: false,
					script_profile: 'none',
					scripts: [],
					ports: '',
					top_ports: 0
				}
			},
			{
				name: 'Identify services',
				detail: 'Common ports and service versions',
				options: {
					scan_type: 'syn',
					service_detection: true,
					os_detection: false,
					script_profile: 'none',
					scripts: [],
					ports: '',
					top_ports: 100,
					wall_timeout: 300
				}
			},
			{
				name: 'TCP connect',
				detail: 'A full TCP connection scan',
				options: {
					scan_type: 'connect',
					service_detection: true,
					script_profile: 'none',
					scripts: [],
					ports: '',
					top_ports: 100,
					wall_timeout: 300
				}
			}
		],
		'network.fping': [
			{
				name: 'Quick check',
				detail: '20 samples per host',
				options: { count: 20, period_ms: 1000, duration: 60 }
			},
			{
				name: 'Keep watching',
				detail: 'Continue until stopped',
				options: { count: 0, period_ms: 1000, duration: 0 }
			}
		],
		'android.operator': [
			{ name: 'Connection', detail: 'Check device authorization', options: { operation: 'get_state' } },
			{ name: 'Device details', detail: 'Read Android properties', options: { operation: 'properties' } },
			{ name: 'Collect logs', detail: 'Read the latest logcat entries', options: { operation: 'logcat' } },
			{ name: 'Browse files', detail: 'List a directory on the phone', options: { operation: 'list_path' } }
		],
		'network.dns': [
			{ name: 'IPv4 records', detail: 'A records', options: { record: 'A', short: false } },
			{ name: 'IPv6 records', detail: 'AAAA records', options: { record: 'AAAA', short: false } },
			{ name: 'Mail routing', detail: 'MX records', options: { record: 'MX', short: false } }
		],
		'capture.ring': [
			{
				name: 'Troubleshoot a LAN',
				detail: 'ARP, DHCP and DNS',
				options: { filter: 'arp or (udp and (port 53 or port 67 or port 68))', snaplen: 0, duration: 0 }
			},
			{
				name: 'Connection setup',
				detail: 'TCP SYN, FIN and RST packets',
				options: { filter: 'tcp[tcpflags] & (tcp-syn|tcp-fin|tcp-rst) != 0', snaplen: 0, duration: 0 }
			}
		],
		'storage.ddrescue': [
			{
				name: 'First pass',
				detail: 'Prioritize readable data',
				options: { no_scrape: true, retry_passes: 0 }
			},
			{
				name: 'Retry remaining',
				detail: 'One retry pass with scraping',
				options: { no_scrape: false, retry_passes: 1 }
			}
		]
	};
	var related = {
		network: ['network.fping', 'network.dns', 'capture.ring'],
		devices: ['android.operator', 'apple.mobile_diagnostics', 'forensics.inspect_file'],
		hardware: ['serial.console', 'usb.inventory', 'forensics.hex'],
		radio: ['radio.receiver_tools', 'gps.session', 'forensics.inspect_file'],
		data: ['forensics.inspect_file', 'forensics.hex', 'storage.ddrescue'],
		system: ['monitoring.resources', 'monitoring.bandwidth', 'network.interfaces']
	};
	var specificNext = {
		'network.nmap_lan_discovery': ['network.fping', 'network.snmp', 'network.compare_scans'],
		'network.lldp': ['network.snmp', 'network.nmap_lan_discovery'],
		'network.snmp': ['network.fping', 'network.nmap_lan_discovery', 'network.snmp'],
		'network.compare_scans': ['network.nmap_lan_discovery', 'network.fping'],
		'network.tracepath': ['network.fping', 'throughput.iperf3', 'capture.ring'],
		'network.smb': ['network.smb', 'network.tracepath', 'network.nmap_lan_discovery'],
		'network.arp_scan': ['network.nmap_lan_discovery', 'network.fping'],
		'network.fping': ['capture.ring', 'network.dns', 'throughput.iperf3'],
		'network.dns': ['network.fping', 'capture.ring'],
		'android.operator': ['android.operator', 'forensics.inspect_file'],
		'android.adb_diagnostics': ['android.operator'],
		'apple.mobile_diagnostics': ['apple.mobile_capture', 'apple.mobile_manage'],
		'apple.recovery': ['apple.restore', 'apple.identify'],
		'cellular.diagnostics': ['cellular.raw_command', 'cellular.control'],
		'can.capture': ['can.configure', 'can.replay'],
		'can.configure': ['can.capture', 'can.transmit'],
		'industrial.modbus_read': ['industrial.modbus_write'],
		'firmware.identify': ['firmware.openocd', 'firmware.flashrom'],
		'usb.inventory': ['serial.inspect', 'usbip.attach'],
		'bluetooth.scan': ['bluetooth.pairing', 'bluetooth.services'],
		'gps.snapshot': ['gps.session', 'gps.receiver_control'],
		'storage.inspect': ['storage.ddrescue', 'storage.clone'],
		'storage.ddrescue': ['storage.ddrescue', 'forensics.hex'],
		'storage.clone': ['storage.clone', 'storage.inspect']
	};
	function entry(id) {
		return (
			catalog[id] || {
				name: String(id || 'Tool').replace(/[._]/g, ' '),
				summary: 'Inspect the selected native operation and its result.',
				output: 'Native output',
				group: 'system',
				requires: 'Select the intended target and review the operation.',
				native: []
			}
		);
	}
	function searchText(id) {
		var e = entry(id);
		return [e.name, e.summary, e.output, id, e.module, (e.native || []).join(' '), e.group]
			.join(' ')
			.toLowerCase();
	}
	function matches(id, query) {
		var terms = String(query || '')
				.toLowerCase()
				.trim()
				.split(/\s+/)
				.filter(Boolean),
			text = searchText(id);
		return terms.every(function (term) {
			return text.indexOf(term) >= 0;
		});
	}
	function friendly(value) {
		var labels = {
			AES: 'AES-128 (standard)',
			'AES-192': 'AES-192 (Blumenthal)',
			'AES-256': 'AES-256 (Blumenthal)',
			'AES-192-C': 'AES-192 (Cisco / Reeder)',
			'AES-256-C': 'AES-256 (Cisco / Reeder)',
			DES: 'DES (legacy)',
			syn: 'TCP SYN',
			connect: 'TCP connect',
			syn_udp: 'TCP SYN + UDP',
			discovery: 'Discover hosts',
			get_state: 'Check connection',
			properties: 'Device properties',
			packages: 'List installed apps',
			list_path: 'List a directory',
			disk_usage: 'Storage usage',
			processes: 'Running processes',
			dumpsys: 'Inspect an Android service',
			logcat: 'Collect logcat',
			bugreport: 'Collect a bug report',
			pull_file: 'Download a file',
			pull_directory: 'Download a directory',
			push: 'Send a file',
			install: 'Install an APK',
			install_multiple: 'Install split APKs',
			uninstall: 'Uninstall an app',
			root: 'Restart ADB as root',
			remount: 'Remount device filesystems',
			tcpip: 'Enable network ADB',
			usb: 'USB',
			tcp: 'TCP',
			rtu: 'RTU',
			json: 'JSON',
			xml: 'XML',
			ipv4: 'IPv4',
			ipv6: 'IPv6',
			raw_iq: 'Raw I/Q',
			mqttv311: 'MQTT 3.1.1',
			mqttv5: 'MQTT 5',
			mqttv31: 'MQTT 3.1',
			noerror: 'NOERROR',
			gnss_status: 'GNSS status',
			gnss_position: 'GNSS position',
			gnss_start: 'Start GNSS',
			gnss_stop: 'Stop GNSS',
			custom_at: 'Custom AT command'
		};
		return (
			labels[value] ||
			String(value)
				.replace(/_/g, ' ')
				.replace(/^./, function (c) {
					return c.toUpperCase();
				})
		);
	}
	function inputKind(id, field, options) {
		if (field === 'packages') return 'android_package';
		if (/ticket/.test(field)) return 'apple_ticket';
		if (id === 'apple.restore' && field === 'restore_upload_id') return 'apple_restore';
		if (id === 'apple.recovery' && field === 'input_upload_id') return 'apple_recovery_input';
		if (id.indexOf('android.') === 0) {
			if (/install/.test(field) || ((options || {}).operation === 'install' && field === 'input'))
				return 'android_package';
			if (/restore/.test(field)) return 'android_backup';
		}
		if (!/^(input|upload|.*_upload_id|wordlist|rules|packages)$/.test(field)) return null;
		if (id.indexOf('capture.') === 0 || id === 'wireless.file_analysis')
			return field === 'wordlist' ? 'forensics_input' : 'capture_input';
		if (id.indexOf('firmware.') === 0) return 'firmware_image';
		if (id === 'storage.restore' || id === 'storage.squashfs') return 'storage_image';
		if (id.indexOf('forensics.') === 0) return 'forensics_input';
		return 'device_input';
	}
	function fileKind(file) {
		if (file.kind === 'pcap' || /\.pcap\d*$|\.(pcapng|cap)$/i.test(file.name)) return 'capture_input';
		if (/\.(raw|img|squashfs|sqfs)$/i.test(file.name)) return 'storage_image';
		if (/\.(bin|hex|elf|uf2|dfu|fw|rom)$/i.test(file.name)) return 'device_input';
		if (/\.(txt|json|cfg|exe|dll|so|apk|zip)$/i.test(file.name)) return 'forensics_input';
		return null;
	}
	function forInput(kind, id) {
		var list =
			{
				capture_input: [
					['capture.inspect', 'input', {}],
					['capture.replay', 'input', {}],
					['wireless.file_analysis', 'input', { operation: 'inspect' }]
				],
				forensics_input: [
					['forensics.inspect_file', 'input', {}],
					['forensics.hex', 'input', {}]
				],
				device_input: [
					['forensics.hex', 'input', {}],
					['android.operator', 'input', { operation: 'push' }],
					['serial.transfer', 'input', { direction: 'send_receive' }]
				],
				firmware_image: [
					['firmware.flashrom', 'input', { operation: 'verify' }],
					['firmware.openocd', 'upload', { operation: 'program' }],
					['firmware.avrdude', 'upload', { operation: 'verify_flash' }]
				],
				android_package: [['android.operator', 'input', { operation: 'install' }]],
				android_backup: [['android.adb_manage', 'restore_upload_id', { operation: 'restore' }]],
				apple_restore: [['apple.restore', 'restore_upload_id', { source: 'sealed_ipsw' }]],
				apple_recovery_input: [['apple.recovery', 'input_upload_id', { operation: 'send_file' }]],
				apple_ticket: [['apple.restore', 'ticket_upload_id', {}]],
				storage_image: [
					['forensics.hex', 'input', {}],
					['storage.squashfs', 'upload', {}],
					['storage.restore', 'upload', {}]
				]
			}[kind] || [];
		return list.map(function (item) {
			var options = Object.assign({}, item[2]);
			options[item[1]] = id;
			return { id: item[0], options: options };
		});
	}
	function analyze(job) {
		var meta = job.metadata || {},
			id = meta.action_id || '',
			options = meta.options || {},
			text = String(job.stdout || ''),
			error = String(job.stderr || ''),
			active = ['queued', 'running', 'stopping'].indexOf(job.status) >= 0;
		var result = {
			title: active
				? 'Observation in progress'
				: job.status === 'stopped'
					? 'Stopped; results retained'
					: job.status === 'failed'
						? 'Review the native error'
						: 'Job finished',
			description: entry(id).output + '.',
			metrics: [],
			columns: [],
			rows: [],
			hosts: [],
			note: 'Summary uses the output currently available in this job.',
			suggestions: [],
			errorHint: ''
		};
		var seen = new Set();
		function host(value) {
			if (
				typeof value === 'string' &&
				value.length <= 253 &&
				/^[A-Za-z0-9:.%_-]+$/.test(value) &&
				!seen.has(value)
			) {
				seen.add(value);
				result.hosts.push(value);
			}
		}
		if (meta.native_runtime && meta.native_runtime.sensitive) {
			result.title = 'Private result';
			result.description =
				'Review this result in the Output tab. Private token data is excluded from summaries and handoffs.';
			result.note = '';
			return result;
		}
		if (id === 'network.lldp') {
			function objects(value) { return Array.isArray(value) ? value : value ? [value] : []; }
			try {
				objects((JSON.parse(text).lldp || {}).interface).forEach(function (interfaces) {
					Object.keys(interfaces).forEach(function (localPort) {
						objects(interfaces[localPort]).forEach(function (neighbor) {
							var chassisMap = neighbor.chassis || {}, key = Object.keys(chassisMap)[0], chassis = chassisMap[key] || {}, port = neighbor.port || {};
							var address = chassis['mgmt-ip'] || '', addresses = Array.isArray(address) ? address : [address];
							addresses.forEach(host);
							result.rows.push([localPort, chassis.name || key || '', (port.id || {}).value || port.descr || '', addresses.join(', '), chassis.descr || '']);
						});
					});
				});
				result.metrics.push({ label: 'Neighbors advertised', value: String(result.rows.length) });
				result.columns = ['Router port', 'Switch', 'Switch port', 'Management address', 'Description'];
				result.description = result.rows.length ? 'Neighbor data advertised to this router.' : 'No neighbor advertisement is currently visible. Check LLDP/CDP on the connected switch and allow time for its next advertisement.';
			} catch (_) { result.note = 'Inspect native LLDP output; the JSON response is incomplete or unrecognized.'; }
		} else if (id === 'network.snmp') {
			host(options.host);
			var systemNames = { 1: 'Description', 2: 'Object ID', 3: 'Uptime', 4: 'Contact', 5: 'System name', 6: 'Location', 7: 'Services' };
			var interfaceNames = { 1: 'Index', 2: 'Description', 3: 'Type', 4: 'MTU', 5: 'Speed (bits/s)', 6: 'MAC', 7: 'Admin state', 8: 'Operational state', 9: 'Last change', 10: 'Inbound octets', 13: 'Inbound discards', 14: 'Inbound errors', 16: 'Outbound octets', 19: 'Outbound discards', 20: 'Outbound errors' };
			text.split(/\r?\n/).forEach(function (line) {
				var m = line.match(/^(\.\d+(?:\.\d+)*)\s*=\s*(.*)$/); if (!m) return;
				var sys = m[1].match(/^\.1\.3\.6\.1\.2\.1\.1\.(\d+)\.0$/), iface = m[1].match(/^\.1\.3\.6\.1\.2\.1\.2\.2\.1\.(\d+)\.(\d+)$/);
				var label = sys ? systemNames[sys[1]] : iface ? 'Interface ' + iface[2] + ': ' + (interfaceNames[iface[1]] || 'column ' + iface[1]) : '';
				result.rows.push([label || 'OID', m[1], m[2]]);
			});
			result.columns = ['Measurement', 'OID', 'Value'];
			result.metrics.push({ label: 'Values in preview', value: String(result.rows.length) });
			if (options.version === '3') result.metrics.push({ label: 'Requested security', value: options.level === 'authPriv' ? options.auth + ' / ' + friendly(options.privacy) : options.level });
			if (/No Such (?:Object|Instance)|End of MIB/i.test(text)) result.note = 'The agent does not expose some requested OIDs. Check its MIB support and access view; try System or a custom OID.';
			if (/Timeout|Authentication|authorization|Unknown user|pass phrase|decryption/i.test(text + error)) result.errorHint = 'Check UDP reachability, SNMP version, credentials and the agent access view. For v3, match the authentication method and exact encryption variant configured on the equipment. Encryption is never silently downgraded.';
		} else if (id === 'network.compare_scans') {
			text.split(/\r?\n/).forEach(function (line) { if (/^[+-][^+-]/.test(line)) result.rows.push([line[0] === '+' ? 'Added / current' : 'Removed / previous', line.slice(1)]); });
			result.columns = ['Change', 'Native difference'];
			result.metrics.push({ label: 'Changed lines in preview', value: String(result.rows.length) });
			result.description = /No differences reported/.test(text) ? 'Ndiff found no differences between these scans.' : 'Earlier scan compared with later scan. Native output preserves host and port context.';
			result.note = 'Different targets, scan settings or blocked probes can change results without an equipment change.';
		} else if (id === 'network.tracepath') {
			host(options.host);
			var mtus = Array.from(text.matchAll(/pmtu\s+(\d+)/g));
			if (mtus.length) result.metrics.push({ label: 'Reported path MTU', value: mtus[mtus.length - 1][1] + ' bytes' });
			result.metrics.push({ label: 'Destination', value: /\breached\b/.test(text) ? 'Reached' : active ? 'Probing' : 'Not confirmed' });
			text.split(/\r?\n/).forEach(function (line) { var m = line.match(/^\s*(\d+)[?:]\s+(.*)$/); if (m) result.rows.push([m[1], m[2]]); });
			result.columns = ['Hop', 'Response']; result.note = 'No reply may reflect UDP/ICMP filtering. Reported MTU describes this path and these probes; test the affected destination and address family.';
		} else if (id === 'network.smb') {
			host(options.host);
			if (options.operation === 'shares') {
				text.split(/\r?\n/).forEach(function (line) { var m = line.match(/^(Disk|IPC|Printer)\|([^|]*)\|(.*)$/); if (m) result.rows.push([m[2], m[1], m[3]]); });
				result.columns = ['Share', 'Type', 'Description']; result.metrics.push({ label: 'Shares listed', value: String(result.rows.length) });
			} else if (options.operation === 'directory') {
				text.split(/\r?\n/).forEach(function (line) { var m = line.match(/^\s{2}(.+?)\s+([DANSHR]+)\s+(\d+)\s+(.+)$/); if (m) result.rows.push([m[1], m[2], m[3], m[4]]); });
				result.columns = ['Name', 'Attributes', 'Bytes', 'Modified'];
			} else {
				var verified = text.match(/Transfer verified: (PASS|FAIL)/), bytes = text.match(/Bytes verified: (\d+)/);
				if (verified) result.metrics.push({ label: 'Content verification', value: verified[1] });
				if (bytes) result.metrics.push({ label: 'Bytes verified', value: bytes[1] });
				result.metrics.push({ label: 'Test file cleanup', value: /Transfer test file removed:/.test(text) ? 'Confirmed' : 'Review output' });
			}
			if (/NT_STATUS_LOGON_FAILURE|NT_STATUS_ACCESS_DENIED/.test(text + error)) result.errorHint = 'The server rejected authentication or permissions. Check the account/domain and share plus filesystem permissions; a read-only account cannot run the transfer test.';
		} else if (id === 'network.nmap_lan_discovery') {
			var current = '';
			text.split(/\r?\n/).forEach(function (line) {
				var m = line.match(/^Nmap scan report for (.+)$/);
				if (m) {
					current = (m[1].match(/\(([^()]+)\)$/) || [])[1] || m[1];
				}
				if (/^Host is up/.test(line)) {
					host(current);
				}
				var port = line.match(/^(\d+)\/(tcp|udp|sctp)\s+(open(?:\|filtered)?)\s+(\S+)(.*)$/);
				if (port) result.rows.push([current, port[1] + '/' + port[2], port[3], port[4] + port[5]]);
			});
			var done = text.match(
				/Nmap done: ([\d,]+) IP address(?:es)? \(([\d,]+) hosts? up\) scanned in ([\d.]+) seconds/
			);
			if (done) {
				result.metrics.push(
					{ label: 'Hosts up', value: done[2] },
					{ label: 'Addresses scanned', value: done[1] },
					{ label: 'Scan time', value: done[3] + ' s' }
				);
				result.description = 'Native Nmap completion summary.';
			} else if (result.hosts.length)
				result.metrics.push({ label: 'Hosts observed in preview', value: String(result.hosts.length) });
			result.columns = ['Host', 'Port', 'State', 'Service'];
		} else if (id === 'network.arp_scan') {
			text.split(/\r?\n/).forEach(function (line) {
				var m = line.match(/^(\d{1,3}(?:\.\d{1,3}){3})\s+([a-f\d:]{17})\s+(.+)$/i);
				if (m) {
					host(m[1]);
					result.rows.push([m[1], m[2], m[3]]);
				}
			});
			result.columns = ['Address', 'MAC', 'Vendor'];
			if (result.rows.length)
				result.metrics.push({ label: 'Responses in preview', value: String(result.rows.length) });
		} else if (id === 'network.fping') {
			var samples = {};
			(text + '\n' + error).split(/\r?\n/).forEach(function (line) {
				var m = line.match(/(?:\[[\d.]+\]\s*)?([^\s]+)\s+:.*?([\d.]+) ms \(([\d.]+) avg,\s*([\d.]+)% loss\)/);
				if (m) {
					host(m[1]);
					samples[m[1]] = [m[1], m[4] + '%', m[3] + ' ms', m[2] + ' ms'];
				}
				var s = line.match(
					/^(\S+)\s+: xmt\/rcv\/%loss = (\d+)\/(\d+)\/([\d.]+)%(?:, min\/avg\/max = ([\d.]+)\/([\d.]+)\/([\d.]+))?/
				);
				if (s) {
					host(s[1]);
					samples[s[1]] = [s[1], s[4] + '%', s[6] ? s[6] + ' ms' : 'No reply', '—'];
				}
			});
			result.rows = Object.values(samples);
			result.columns = ['Host', 'Observed loss', 'Mean latency', 'Latest response'];
			if (result.rows.length) {
				result.metrics.push({ label: 'Hosts with measurements', value: String(result.rows.length) });
				result.description = 'Latest visible measurement for each responding or summarized host.';
			}
		} else if (id === 'network.dns') {
			var status = text.match(/status:\s*([A-Z]+)/);
			if (status) result.metrics.push({ label: 'DNS response', value: status[1] });
			var timing = text.match(/Query time:\s*(\d+)\s*msec/);
			if (timing) result.metrics.push({ label: 'Query time', value: timing[1] + ' ms' });
			var answer = false;
			text.split(/\r?\n/).forEach(function (line) {
				if (/^;; ANSWER SECTION:/.test(line)) {
					answer = true;
					return;
				}
				if (answer && /^;;/.test(line)) {
					answer = false;
					return;
				}
				if (answer) {
					var m = line.match(/^(\S+)\s+(\d+)\s+IN\s+(\S+)\s+(.+)$/);
					if (m) {
						result.rows.push([m[1], m[3], m[4], m[2] + ' s']);
						if (m[3] === 'A' || m[3] === 'AAAA') host(m[4]);
					}
				}
			});
			result.columns = ['Name', 'Type', 'Answer', 'TTL'];
			if (status && status[1] === 'NXDOMAIN')
				result.errorHint =
					'The resolver reported that this name does not exist. Check the spelling and compare the authoritative DNS or another intended resolver.';
		} else if (id.indexOf('android.') === 0) {
			var properties = {};
			text.split(/\r?\n/).forEach(function (line) {
				var property = line.match(/^\[([^\]]+)\]: \[([^\]]*)\]$/);
				if (property) properties[property[1]] = property[2];
			});
			[
				['ro.product.model', 'Device model'],
				['ro.build.version.release', 'Android version'],
				['ro.build.version.security_patch', 'Security patch']
			].forEach(function (item) {
				if (properties[item[0]]) result.metrics.push({ label: item[1], value: properties[item[0]] });
			});
			if (options.operation === 'get_state' && /^device$/m.test(text)) {
				result.metrics.push({ label: 'ADB transport', value: 'Connected' });
				result.description = 'The selected ADB transport reported device state.';
			}
			if (options.operation === 'packages') {
				text.split(/\r?\n/).forEach(function (line) {
					var item = line.match(/^package:(?:([^=]+)=)?([A-Za-z0-9_.]+)$/);
					if (item) result.rows.push([item[2], item[1] || 'Not included']);
				});
				result.columns = ['Package', 'APK path'];
				if (result.rows.length)
					result.metrics.push({ label: 'Apps in available output', value: String(result.rows.length) });
			}
		} else if (id === 'throughput.iperf3') {
			try {
				var data = JSON.parse(text),
					end = data.end || {},
					received = end.sum_received,
					sent = end.sum_sent;
				if (received && Number.isFinite(received.bits_per_second))
					result.metrics.push({
						label: 'Received throughput',
						value: (received.bits_per_second / 1000000).toFixed(2) + ' Mbit/s'
					});
				if (sent && Number.isFinite(sent.bits_per_second))
					result.metrics.push({
						label: 'Sent throughput',
						value: (sent.bits_per_second / 1000000).toFixed(2) + ' Mbit/s'
					});
				if (data.error) result.errorHint = String(data.error);
			} catch (_) {}
		}
		if (/unauthorized/i.test(error + '\n' + text) && id.indexOf('android.') === 0)
			result.errorHint =
				'Unlock the phone, approve its USB debugging prompt, then refresh the device list and review the job again.';
		else if (/offline|no devices|device.*not found/i.test(error) && id.indexOf('android.') === 0)
			result.errorHint =
				'Check the cable or enabled network ADB endpoint. Refresh the device list and select the intended device again.';
		else if (/No space|not enough.*space|free.space|budget.*exceed/i.test(error))
			result.errorHint =
				'Review the Files tab, download or preserve useful results, then free storage or adjust the output budget before another run.';
		else if (/already.*(?:open|locked|busy)|resource.*locked/i.test(error))
			result.errorHint =
				'Check Active jobs for the selected device. Stop the job using it, or select another device and review again.';
		else if (job.status === 'failed' && !result.errorHint)
			result.errorHint =
				'Read the native error in Output, check the selected target and required hardware, then use Run again to edit the setup.';
		if (job.status !== 'failed' && !active && !result.metrics.length && !result.rows.length)
			result.description =
				'The native job ' +
				(job.status === 'stopped' ? 'was stopped' : 'finished') +
				'. Review its output and files before choosing a next step.';
		if (
			job.stdout_truncated ||
			job.stderr_truncated ||
			/truncat|Latest \d+ bytes/i.test(text) ||
			job.status !== 'complete'
		)
			result.note =
				'This is a partial observation from the available output. Download the complete artifact when available.';
		var next = specificNext[id] || related[entry(id).group] || [];
		result.suggestions = next
			.filter(function (nextId) {
				return !!catalog[nextId];
			})
			.slice(0, 3)
			.map(function (nextId) {
				var initial = {};
				if (['network.snmp','network.tracepath','network.smb'].indexOf(nextId) >= 0 && result.hosts.length) initial.host = result.hosts[0];
				if (nextId === 'network.compare_scans' && job.saved && id === 'network.nmap_lan_discovery') initial.current = job.id;
				if (nextId === 'network.smb' && id === 'network.smb') {
					['host','port','share','path','guest','username','domain','protocol'].forEach(function (key) { if (options[key] !== undefined) initial[key] = options[key]; });
					initial.operation = options.operation === 'shares' ? 'directory' : 'transfer';
					if (options.operation === 'shares') { var disk = result.rows.find(function (row) { return row[1] === 'Disk' && row[0].toUpperCase() !== 'IPC$'; }); if (disk) initial.share = disk[0]; }
				}
				if ((nextId === 'network.fping' || nextId === 'network.nmap_lan_discovery') && result.hosts.length)
					initial.targets = result.hosts.slice();
				if (nextId === 'capture.ring' && options.interface) initial.interface = options.interface;
				if (nextId === 'android.operator' && id.indexOf('android.') === 0) {
					['transport', 'device', 'host', 'port'].forEach(function (k) {
						if (options[k] !== undefined) initial[k] = options[k];
					});
					initial.operation = 'logcat';
				}
				if ((nextId === 'storage.ddrescue' || nextId === 'storage.clone') && id === nextId && job.saved) {
					initial = Object.assign({}, options, { resume: job.id });
				}
				return { id: nextId, options: initial };
			});
		return result;
	}
	return {
		catalog: catalog,
		modules: modules,
		groups: groups,
		quick: quick,
		presets: presets,
		entry: entry,
		matches: matches,
		friendly: friendly,
		inputKind: inputKind,
		fileKind: fileKind,
		forInput: forInput,
		analyze: analyze
	};
});
