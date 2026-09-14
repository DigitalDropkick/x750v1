'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const guide = require('../files/www/luci-static/resources/ddk/console-guide.js');
const root = path.join(__dirname, '../files/usr/share/ddk-field-console/tools');
const manifests = fs
	.readdirSync(root)
	.filter((name) => name.endsWith('.json'))
	.map((name) => JSON.parse(fs.readFileSync(path.join(root, name))));
const actions = manifests.flatMap((module) => module.actions);
function result(id, stdout = '', stderr = '', extra = {}) {
	return guide.analyze({ metadata: { action_id: id }, status: 'complete', stdout, stderr, ...extra });
}
test('Every advertised action has searchable task guidance and belongs to a real family', () => {
	assert.deepEqual(Object.keys(guide.catalog).sort(), actions.map((action) => action.id).sort());
	for (const action of actions) {
		const entry = guide.entry(action.id);
		assert(entry.name.length > 3);
		assert(entry.summary.length > 15);
		assert(entry.output.length > 5);
		assert(guide.groups.some((group) => group.id === entry.group));
		assert(guide.matches(action.id, action.id));
		assert(guide.matches(action.id, entry.name));
	}
	assert(guide.matches('network.fping', 'loss latency'));
	assert(guide.matches('android.operator', 'android logs'));
	assert(!guide.matches('network.fping', 'no_such_workflow'));
});
test('Nmap summaries preserve zero and singular counts, services and exact observed targets', () => {
	const empty = result(
		'network.nmap_lan_discovery',
		'Nmap done: 1 IP address (0 hosts up) scanned in 4.32 seconds'
	);
	assert.deepEqual(
		empty.metrics.map((metric) => metric.value),
		['0', '1', '4.32 s']
	);
	assert.deepEqual(empty.hosts, []);
	const scan = result(
		'network.nmap_lan_discovery',
		'Nmap scan report for switch.test (192.0.2.4)\nHost is up (0.005s latency).\n22/tcp open ssh OpenSSH 9\n161/udp open|filtered snmp\nNmap done: 256 IP addresses (1 host up) scanned in 2.30 seconds'
	);
	assert.deepEqual(scan.hosts, ['192.0.2.4']);
	assert.equal(scan.rows[1][2], 'open|filtered');
	assert.deepEqual(scan.suggestions.find((next) => next.id === 'network.fping').options.targets, [
		'192.0.2.4'
	]);
	assert.equal(result('network.nmap_lan_discovery', 'unrecognized output').metrics.length, 0);
});
test('fping reports loss and mean latency without inventing a response for an unreachable host', () => {
	const scan = result(
		'network.fping',
		'192.0.2.1 : [0], 64 bytes, 2.10 ms (2.10 avg, 0% loss)\n',
		'192.0.2.2 : xmt/rcv/%loss = 3/0/100%\n192.0.2.1 : xmt/rcv/%loss = 3/3/0%, min/avg/max = 1.0/2.0/3.0'
	);
	assert.equal(scan.rows.find((row) => row[0] === '192.0.2.1')[2], '2.0 ms');
	assert.equal(scan.rows.find((row) => row[0] === '192.0.2.2')[2], 'No reply');
});
test('DNS and throughput use native fields only', () => {
	const dns = result(
		'network.dns',
		';; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 1\n;; ANSWER SECTION:\nexample.test. 60 IN A 192.0.2.1\n;; Query time: 12 msec\n'
	);
	assert.deepEqual(dns.hosts, ['192.0.2.1']);
	assert.equal(dns.rows[0][3], '60 s');
	assert.equal(dns.metrics[1].value, '12 ms');
	const iperf = result(
		'throughput.iperf3',
		JSON.stringify({ end: { sum_received: { bits_per_second: 123456789 } } })
	);
	assert.equal(iperf.metrics[0].value, '123.46 Mbit/s');
	assert.equal(result('throughput.iperf3', 'incomplete JSON').metrics.length, 0);
});
test('Partial, failed and sensitive results remain explicit', () => {
	assert.match(result('network.fping', 'sample', '', { status: 'running' }).note, /partial/i);
	assert.match(result('network.fping', 'sample', '', { stdout_truncated: true }).note, /partial/i);
	assert.match(
		result('android.operator', '', 'error: device unauthorized', { status: 'failed' }).errorHint,
		/approve.*USB debugging/i
	);
	const sensitive = result('auth.otp', '123456', '', {
		metadata: { action_id: 'auth.otp', native_runtime: { sensitive: true } }
	});
	assert.deepEqual(sensitive.metrics, []);
	assert.deepEqual(sensitive.suggestions, []);
	assert(!JSON.stringify(sensitive).includes('123456'));
});
test('Capture ring files and typed inputs have reviewable handoffs', () => {
	assert.equal(guide.fileKind({ name: 'capture.pcap00', kind: 'pcap' }), 'capture_input');
	assert.equal(guide.fileKind({ name: 'unknown.log' }), null);
	const replay = guide
		.forInput('capture_input', 'upload-fixture')
		.find((next) => next.id === 'capture.replay');
	assert.deepEqual(replay.options, { input: 'upload-fixture' });
	const transfer = guide
		.forInput('device_input', 'upload-fixture')
		.find((next) => next.id === 'serial.transfer');
	assert.equal(transfer.options.direction, 'send_receive');
	assert.equal(guide.inputKind('android.operator', 'input', { operation: 'install' }), 'android_package');
	assert.equal(guide.inputKind('apple.restore', 'ticket_upload_id', {}), 'apple_ticket');
	for (const kind of [
		'capture_input',
		'forensics_input',
		'device_input',
		'firmware_image',
		'android_package',
		'android_backup',
		'apple_restore',
		'apple_recovery_input',
		'apple_ticket',
		'storage_image'
	])
		for (const next of guide.forInput(kind, 'upload-fixture'))
			assert(actions.some((action) => action.id === next.id));
});

test('Android summaries use selected native properties and package lines', () => {
	const properties = result(
		'android.operator',
		'[ro.product.model]: [Test handset]\n[ro.serialno]: [private-fixture]\n[ro.build.version.release]: [14]'
	);
	assert.equal(properties.metrics[0].value, 'Test handset');
	assert(!JSON.stringify(properties).includes('private-fixture'));
	const packages = result(
		'android.operator',
		'package:/data/app/example.apk=com.example.app\npackage:com.example.other',
		'',
		{ metadata: { action_id: 'android.operator', options: { operation: 'packages' } } }
	);
	assert.equal(packages.rows.length, 2);
	assert.equal(packages.rows[0][0], 'com.example.app');
});
