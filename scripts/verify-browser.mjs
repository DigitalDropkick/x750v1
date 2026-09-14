#!/usr/bin/env node

import { mkdtempSync, rmSync, writeFileSync, readFileSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawn } from 'node:child_process';
import { once } from 'node:events';

const base = process.env.DDK_BROWSER_BASE || 'http://192.168.8.1';
const session = process.env.DDK_BROWSER_SESSION || '';
const outputDir = process.env.DDK_BROWSER_OUTPUT_DIR || tmpdir();
const orbit = process.env.DDK_BROWSER_ORBIT === '1';

if (!/^[a-fA-F0-9]{32}$/.test(session)) {
	throw new Error('DDK_BROWSER_SESSION must contain one transient 32-character LuCI session ID.');
}

const profile = mkdtempSync(join(tmpdir(), 'ddk-browser-profile-'));
const uploadProofPath = join(profile, 'ddk-browser-upload-proof.bin');
writeFileSync(
	uploadProofPath,
	process.env.DDK_BROWSER_SLOW_UPLOAD === '1' ? Buffer.alloc(8 * 1048576, 0x44) : 'test'
);
const chrome = spawn(
	'/usr/bin/google-chrome',
	[
		'--headless=new',
		'--disable-gpu',
		'--disable-background-networking',
		'--disable-component-update',
		'--disable-default-apps',
		'--disable-sync',
		'--metrics-recording-only',
		'--no-first-run',
		'--no-default-browser-check',
		'--remote-debugging-address=127.0.0.1',
		'--remote-debugging-port=0',
		`--user-data-dir=${profile}`,
		'about:blank'
	],
	{ stdio: ['ignore', 'ignore', 'pipe'] }
);

let websocketUrl;
let stderr = '';
chrome.stderr.setEncoding('utf8');
chrome.stderr.on('data', (chunk) => {
	stderr += chunk;
	const match = stderr.match(/DevTools listening on (ws:\/\/[^\s]+)/);
	if (match) websocketUrl = match[1];
});

async function waitUntil(test, timeoutMs, message) {
	const deadline = Date.now() + timeoutMs;
	while (Date.now() < deadline) {
		const result = await test();
		if (result) return result;
		await new Promise((resolve) => setTimeout(resolve, 100));
	}
	throw new Error(message);
}

let socket;
let nextId = 1;
const pending = new Map();
const browserErrors = [];
const externalRequests = [];
const allowedOrigin = new URL(base).origin;

function call(method, params = {}, sessionId) {
	const id = nextId++;
	return new Promise((resolve, reject) => {
		pending.set(id, { resolve, reject });
		socket.send(JSON.stringify({ id, method, params, ...(sessionId ? { sessionId } : {}) }));
	});
}

async function evaluate(sessionId, expression) {
	const result = await call(
		'Runtime.evaluate',
		{ expression, returnByValue: true, awaitPromise: true },
		sessionId
	);
	if (result.exceptionDetails) throw new Error(result.exceptionDetails.text || 'Browser evaluation failed.');
	return result.result && result.result.value;
}

async function openPage(sessionId, path, width, height) {
	await call(
		'Emulation.setDeviceMetricsOverride',
		{
			width,
			height,
			deviceScaleFactor: 1,
			mobile: width <= 480
		},
		sessionId
	);
	await call('Page.navigate', { url: `${base}/cgi-bin/luci/admin/ddk/${path}` }, sessionId);
	await waitUntil(
		async () =>
			evaluate(
				sessionId,
				`location.pathname.endsWith('/${path}') && document.readyState === 'complete' && document.querySelector('#ddk-app')?.dataset.page === '${path}'`
			),
		60000,
		`Timed out loading ${path}.`
	);
	await waitUntil(
		async () =>
			evaluate(
				sessionId,
				'!!document.querySelector("#ddk-app .ddk-brand") && !document.querySelector("#ddk-app .ddk-loading")'
			),
		60000,
		`Timed out rendering ${path}.`
	);
	const renderError = await evaluate(
		sessionId,
		"document.querySelector('#ddk-app .ddk-alert-error')?.textContent || ''"
	);
	if (renderError) throw new Error('Page ' + path + ': ' + renderError);
}

async function screenshot(sid, filename) {
	const capture = await call(
		'Page.captureScreenshot',
		{ format: 'png', fromSurface: true, captureBeyondViewport: false },
		sid
	);
	const target = join(outputDir, orbit ? filename.replace('ddk-v4-', 'ddk-orbit-') : filename);
	writeFileSync(target, Buffer.from(capture.data, 'base64'));
	return target;
}
const createdJobs = new Set(),
	createdInputs = new Set();
let activeSession;
async function backend(args) {
	if (!args.every((value) => /^[A-Za-z0-9._/-]+$/.test(value))) throw Error('Invalid fixture request');
	const value = await evaluate(
		activeSession,
		`(async()=>{const response=await fetch('/cgi-bin/cgi-exec',{method:'POST',credentials:'same-origin',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({sessionid:${JSON.stringify(session)},command:${JSON.stringify('/usr/libexec/ddk-console ' + args.join(' '))}}).toString()});return JSON.parse(await response.text());})()`
	);
	if (!value.ok) throw Error(value.message);
	return value.data;
}
async function verifyFlows(sid) {
	activeSession = sid;
	const inspect = (expression) => evaluate(sid, expression);
	const wait = (expression, label) => waitUntil(() => inspect(expression), 30000, label || expression);
	async function click(selector) {
		const position = await inspect(
			`(()=>{const n=document.querySelector(${JSON.stringify(selector)});if(!n||n.disabled)throw Error('Control unavailable: '+${JSON.stringify(selector)});n.scrollIntoView({block:'center'});const r=n.getBoundingClientRect();return {x:r.x+r.width/2,y:r.y+r.height/2};})()`
		);
		for (const type of ['mousePressed', 'mouseReleased'])
			await call('Input.dispatchMouseEvent', { type, button: 'left', clickCount: 1, ...position }, sid);
	}
	async function label(text, scope = 'document') {
		const selector = await inspect(
			`(()=>{const n=Array.from(${scope}.querySelectorAll('button')).find(n=>n.textContent.trim()===${JSON.stringify(text)}&&!n.disabled&&n.getClientRects().length&&!n.closest('[inert]'));if(!n)throw Error('Button unavailable: '+${JSON.stringify(text)});n.dataset.testClick='target';return '[data-test-click="target"]';})()`
		);
		await click(selector);
		await inspect("document.querySelector('[data-test-click]')?.removeAttribute('data-test-click')");
	}
	async function key(value, modifiers = 0) {
		for (const type of ['keyDown', 'keyUp'])
			await call('Input.dispatchKeyEvent', { type, key: value, modifiers }, sid);
	}
	async function set(name, value) {
		await inspect(
			`(()=>{const n=document.querySelector('[name='+${JSON.stringify(name)}+']');if(!n)throw Error('Missing field '+${JSON.stringify(name)});if(n.type==='checkbox')n.checked=${JSON.stringify(value)};else n.value=${JSON.stringify(String(value))};n.dispatchEvent(new Event('change',{bubbles:true}));})()`
		);
	}
	async function openAction(id) {
		await click('[data-action="' + id + '"]');
		await wait("!!document.querySelector('.ddk-modal [name]')", 'Form did not render: ' + id);
	}
	async function startReviewed() {
		const previous = await inspect('location.hash');
		await label('Review setup →');
		await wait("!!document.querySelector('.ddk-review')", 'Review did not render');
		await label('Start job');
		await wait(
			"location.pathname.endsWith('/jobs') && /^#job-/.test(location.hash) && !document.querySelector('.ddk-modal') && document.querySelector('.ddk-job-detail')?.dataset.selectedJob===location.hash.slice(1) && location.hash!==" +
				JSON.stringify(previous),
			'Job workspace did not open'
		);
		const id = await inspect('location.hash.slice(1)');
		createdJobs.add(id);
		return id;
	}
	if (process.env.DDK_BROWSER_QUICK !== '1') {
		for (const width of (orbit ? [1440, 440, 390, 320] : [1440, 390, 320])) {
			for (const page of ['overview', 'tools', 'jobs', 'settings', 'packages']) {
				await openPage(sid, page, width, 900);
				const result = await inspect(
					"({version:document.body.innerText.includes('X750 / v4.1.0-beta.1'),overflow:document.documentElement.scrollWidth>innerWidth,coerced:/\\[object (?:HTML|Object)|^null$/m.test(document.body.innerText),logo:document.querySelector('.ddk-nav-home img')?.naturalWidth})"
				);
				if (!result.version || result.overflow || result.coerced || !result.logo)
					throw Error(page + ' at ' + width + ': ' + JSON.stringify(result));
                if(orbit && !await inspect("document.documentElement.dataset.orbit==='true' && !!document.querySelector('.orbit-masthead') && document.querySelectorAll('.ddk-nav-links [aria-current=page]').length===1"))throw Error('Orbit navigation did not initialize correctly');
                if(page==='tools' && !await inspect("(()=>{const input=document.querySelector('.ddk-library-search input'),icon=document.querySelector('.ddk-library-search svg');return input.getBoundingClientRect().left+parseFloat(getComputedStyle(input).paddingLeft)>=icon.getBoundingClientRect().right+8;})()"))throw Error('Tool search text overlaps its icon');
				if (width === 1440 || width === 390 || width === 440) await screenshot(sid, 'ddk-v4-' + page + '-' + width + '.png');
			}
			console.log('Five responsive pages passed at ' + width + 'px');
		}
		await openPage(sid, 'tools', 1440, 1000);
		if ((await inspect("document.querySelectorAll('[data-action]').length")) !== 92)
			throw Error('Tool coverage changed');
		const modules = await backend(['capabilities']);
		const actions = modules
			.flatMap((module) => module.actions)
			.filter((action) => action.parameter_schema === 'operator-v1');
		const contracts = [];
		for (const [index, action] of actions.entries()) {
			await openAction(action.id);
			const contract = await inspect(
				"({focused:!!document.activeElement.closest('.ddk-modal'),fields:Array.from(document.querySelectorAll('.ddk-modal [name]')).map(n=>({name:n.name,type:n.type,values:['operation','direction','source'].includes(n.name)?Array.from(n.options||[]).map(o=>o.value):undefined})),overflow:document.querySelector('.ddk-modal-panel').scrollWidth>document.querySelector('.ddk-modal-panel').clientWidth})"
			);
			if (!contract.focused || contract.overflow) throw Error('Form focus/overflow: ' + action.id);
			contracts.push({ id: action.id, ...contract });
			if (action.id === 'android.operator') {
				await set('transport', 'tcp');
				if (!(await inspect("!document.querySelector('[name=host]').closest('label').hidden")))
					throw Error('Network ADB fields hidden');
				await set('operation', 'install');
				if (
					!(await inspect(
						"!!document.querySelector('[name=input]').closest('label').querySelector('.ddk-inline-upload')"
					))
				)
					throw Error('APK upload not in Android form');
			}
			await key('Escape');
			await wait("!document.querySelector('.ddk-modal')", 'Escape did not close dialog');
			if (!(await inspect('document.activeElement.dataset.action === ' + JSON.stringify(action.id))))
				throw Error('Focus did not return to tool');
			if ((index + 1) % 10 === 0) console.log('Tool forms checked: ' + (index + 1) + ' / ' + actions.length);
		}
		const handoffs = await inspect(
			"Object.fromEntries(['capture_input','forensics_input','device_input','firmware_image','android_package','android_backup','apple_restore','apple_recovery_input','apple_ticket','storage_image'].map(k=>[k,DDKGuide.forInput(k,'fixture')]))"
		);
		for (const items of Object.values(handoffs))
			for (const item of items) {
				const contract = contracts.find((c) => c.id === item.id);
				for (const [name, value] of Object.entries(item.options)) {
					const field = contract.fields.find((f) => f.name === name);
					if (!field || (field.values && !field.values.includes(value)))
						throw Error('Invalid input handoff ' + item.id + ' ' + name);
				}
			}
		console.log('All 78 tool forms and typed input handoffs passed');
	}
    if (orbit) {
        await openPage(sid, 'overview', 440, 956);
        if (!await inspect("document.querySelector('.ddk-quick-grid [data-action]').getBoundingClientRect().top < innerHeight - 90")) throw Error('Orbit buries starting workflows below the phone viewport');
        await click('.orbit-telemetry summary');
        if (!await inspect("document.querySelector('.orbit-telemetry').open && document.querySelector('.ddk-health-strip').getClientRects().length > 0")) throw Error('Appliance telemetry cannot be expanded');
        await click('.orbit-telemetry summary');
        await click('.orbit-connection');
        await wait("!!document.querySelector('.orbit-dialog[open]')", 'Connection dialog did not open');
        await label('Done');
        if (!await inspect("document.activeElement.classList.contains('orbit-connection')")) throw Error('Connection dialog lost focus');
        await call('Network.emulateNetworkConditions', {offline:true,latency:0,downloadThroughput:-1,uploadThroughput:-1}, sid);
        try {
            await click('[data-action="network.nmap_lan_discovery"]');
            await wait("document.querySelector('.orbit-connection').dataset.state==='offline'", 'Lost router connection was not surfaced');
            if (!await inspect("document.querySelector('.orbit-masthead').inert")) throw Error('Companion header remains interactive behind a modal');
        } finally {
            await call('Network.emulateNetworkConditions', {offline:false,latency:0,downloadThroughput:-1,uploadThroughput:-1}, sid);
        }
        await key('Escape');
        await openAction('network.nmap_lan_discovery');
        await wait("document.querySelector('.orbit-connection').dataset.state==='connected'", 'Connection status did not recover');
        if (!await inspect("Array.from(document.querySelectorAll('.ddk-modal input:not([type=hidden]):not([type=checkbox]):not([type=radio]):not([type=file]), .ddk-modal textarea, .ddk-modal select')).every(n=>parseFloat(getComputedStyle(n).fontSize)>=16)")) throw Error('Orbit form text triggers iPhone focus zoom');
        await key('Escape');
        await screenshot(sid, 'ddk-v4-overview-440.png');
        console.log('Orbit telemetry, connection dialog, modal isolation, offline/reconnect and phone field sizing passed');
    }
	await openPage(sid, 'tools', 1440, 1000);
	await inspect(
		"(()=>{let n=document.querySelector('[aria-label=\"Search tool library\"]');n.value='loss latency';n.dispatchEvent(new Event('input'));})()"
	);
	if (!(await inspect('!document.querySelector(\'[data-tool="network.fping"]\').hidden')))
		throw Error('Action search missed packet loss');
	await inspect(
		"(()=>{let n=document.querySelector('[aria-label=\"Search tool library\"]');n.value='';n.dispatchEvent(new Event('input'));})()"
	);
	await click('[data-tool="network.fping"] .ddk-favorite');
	await click('[data-view="favorites"]');
	if (!(await inspect('!document.querySelector(\'[data-tool="network.fping"]\').hidden')))
		throw Error('Favorite not available');
	await click('[data-view="all"]');
	await key('k', 2);
	await wait('!!document.querySelector(\'[aria-label="Find a tool"]\')', 'Keyboard search missing');
	await key('Escape');
	for (const width of [390, 320]) {
		await call(
			'Emulation.setDeviceMetricsOverride',
			{ width, height: 900, deviceScaleFactor: 1, mobile: true },
			sid
		);
		for (const id of ['network.nmap_lan_discovery', 'android.operator']) {
			await openAction(id);
			if (
				!(await inspect(
					"document.querySelector('.ddk-modal-panel').scrollWidth<=document.querySelector('.ddk-modal-panel').clientWidth"
				))
			)
				throw Error('Mobile form overflow');
			if (width === 390) await screenshot(sid, 'ddk-v4-' + id.replaceAll('.', '-') + '-390.png');
			await key('Escape');
		}
	}
	await call(
		'Emulation.setDeviceMetricsOverride',
		{ width: 1440, height: 1000, deviceScaleFactor: 1, mobile: false },
		sid
	);
	await openAction('network.nmap_lan_discovery');
	await set('targets', 'not a valid target');
	await label('Review setup →');
	await wait("!document.querySelector('.ddk-modal [role=alert]').hidden", 'Inline validation missing');
	if ((await inspect("document.querySelectorAll('.ddk-modal').length")) !== 1)
		throw Error('Nested validation dialog');
	await set('targets', '127.0.0.1');
	await set('interface', 'lo');
	await set('scan_type', 'connect');
	await set('ports', '22');
	await set('discovery_method', 'skip');
	await label('Review setup →');
	await wait("!!document.querySelector('.ddk-review')", 'Nmap review missing');
	await label('← Edit setup');
	if (!(await inspect("document.querySelector('[name=targets]').value==='127.0.0.1'")))
		throw Error('Back lost setup');
	const nmap = await startReviewed();
	await wait(
		"document.querySelector('.ddk-job-detail .ddk-state')?.textContent==='complete'",
		'Nmap did not complete'
	);
	await label('Summary');
	if (
		!(await inspect("document.querySelector('.ddk-result-summary').innerText.includes('Addresses scanned')"))
	)
		throw Error('Native Nmap summary did not parse');
	await click('.ddk-next-steps .ddk-search-result');
	await wait("!!document.querySelector('.ddk-modal [name]')");
	if (!(await inspect("document.querySelector('[name=targets]').value==='127.0.0.1'")))
		throw Error('Observed host handoff lost');
	await set('interface', 'lo');
	await set('count', 0);
	await set('duration', 0);
	await set('period_ms', 100);
	await set('output_mib', 1);
	const fping = await startReviewed();
	await label('Output');
	await wait(
		"document.querySelector('.ddk-job-output').textContent.includes('127.0.0.1')",
		'Live fping output missing'
	);
	await inspect(
		"(()=>{const n=document.querySelector('[aria-label=\"Filter output lines\"]');n.focus();n.value='127.';n.dispatchEvent(new Event('input'));window.__v4Focus=n;})()"
	);
	await new Promise((resolve) => setTimeout(resolve, 2500));
	if (!(await inspect("document.activeElement===window.__v4Focus && window.__v4Focus.value==='127.'")))
		throw Error(
			'Polling disrupted output controls: ' +
				JSON.stringify(
					await inspect(
						"({active:document.activeElement.outerHTML.slice(0,250),same:document.activeElement===window.__v4Focus,connected:window.__v4Focus.isConnected,value:window.__v4Focus.value,status:document.querySelector('.ddk-job-detail .ddk-state')?.textContent,present:!!document.querySelector('[aria-label=\"Filter output lines\"]')})"
					)
				)
		);
	await label('Stop & keep results');
	await wait(
		"document.querySelector('.ddk-job-detail .ddk-state')?.textContent==='stopped'",
		'Stop lost job state'
	);
	await label('Save as case');
	await wait('!!document.querySelector(\'[aria-label="Case name"]\')');
	await inspect("document.querySelector('[aria-label=\"Case name\"]').value='DDK v4 browser fixture'");
	await label('Save case');
	await wait(
		"document.querySelector('.ddk-result-head').innerText.includes('SAVED CASE')",
		'Case was not saved'
	);
	await label('Summary');
	await screenshot(sid, 'ddk-v4-live-case.png');
	await label('Output');
	await label('Download text');
	await waitUntil(
		() => existsSync(join(profile, 'ddk-' + fping + '-output.txt')),
		15000,
		'Text download did not finish'
	);
	if (!readFileSync(join(profile, 'ddk-' + fping + '-output.txt'), 'utf8').includes('127.0.0.1'))
		throw Error('Downloaded text lost native output');
	await label('Export case');
	await wait("!!document.querySelector('.ddk-modal [name]')");
	const exported = await startReviewed();
	await wait(
		"document.querySelector('.ddk-job-detail .ddk-state')?.textContent==='complete'",
		'Case export failed'
	);
	await openPage(sid, 'jobs', 1440, 1000);
	await inspect('location.hash=' + JSON.stringify(fping));
	await wait("document.querySelector('.ddk-job-detail h2')?.textContent==='DDK v4 browser fixture'");
	await click('[data-tab="files"]');
	await label('Download');
	await waitUntil(
		() => existsSync(join(profile, 'ddk-' + fping + '-native-output.txt')),
		15000,
		'Artifact download did not finish'
	);
	if (!readFileSync(join(profile, 'ddk-' + fping + '-native-output.txt'), 'utf8').includes('127.0.0.1'))
		throw Error('Downloaded artifact lost native output');
	await label('Use as input →');
	await wait(
		"document.querySelector('.ddk-modal')?.textContent.includes('Choose a tool to review')",
		'Reusable file handoff missing'
	);
	await click('.ddk-modal .ddk-search-result');
	await wait("!!document.querySelector('.ddk-modal [name]')");
	if (!(await inspect("/^upload-/.test(document.querySelector('[name=input]').value)")))
		throw Error('Reusable input was not selected');
	createdInputs.add(await inspect("document.querySelector('[name=input]').value"));
	await key('Escape');
	await openPage(sid, 'tools', 1440, 1000);
	await openAction('forensics.hex');
	await click('.ddk-inline-upload');
	await wait("!!document.querySelector('.ddk-modal:last-child input[type=file]')");
	const doc = await call('DOM.getDocument', {}, sid);
	const node = await call(
		'DOM.querySelector',
		{ nodeId: doc.root.nodeId, selector: '.ddk-modal:last-child input[type=file]' },
		sid
	);
	await call('DOM.setFileInputFiles', { nodeId: node.nodeId, files: [uploadProofPath] }, sid);
	await label('Upload file');
	await wait(
		"document.querySelectorAll('.ddk-modal').length===1 && document.querySelector('[name=input]')?.selectedOptions[0]?.textContent.includes('ddk-browser-upload-proof.bin')",
		'Inline upload did not return to populated form'
	);
	createdInputs.add(await inspect("document.querySelector('[name=input]').value"));
	await key('Escape');
	await screenshot(sid, 'ddk-v4-tools-after-upload.png');
	if (!nmap || !exported) throw Error('Job fixture IDs missing');
	console.log(
		'Native Nmap, observed-host handoff, live fping, stable polling, stop, save, export, file reuse and inline upload passed'
	);
}
try {
	await waitUntil(() => websocketUrl, 10000, 'Chrome DevTools endpoint did not start.');
	socket = new WebSocket(websocketUrl);
	await new Promise((resolve, reject) => {
		socket.addEventListener('open', resolve, { once: true });
		socket.addEventListener('error', reject, { once: true });
	});
	socket.addEventListener('message', (event) => {
		const message = JSON.parse(event.data);
		if (message.id && pending.has(message.id)) {
			const handler = pending.get(message.id);
			pending.delete(message.id);
			if (message.error) handler.reject(new Error(message.error.message));
			else handler.resolve(message.result || {});
		} else if (message.method === 'Runtime.exceptionThrown') {
			browserErrors.push(message.params.exceptionDetails.text || 'Uncaught runtime exception');
		} else if (message.method === 'Log.entryAdded' && message.params.entry.level === 'error') {
			browserErrors.push(message.params.entry.text);
		} else if (message.method === 'Network.requestWillBeSent') {
			const url = message.params.request.url;
			if (/^https?:/.test(url) && new URL(url).origin !== allowedOrigin) externalRequests.push(url);
		}
	});

	const target = await call('Target.createTarget', { url: 'about:blank' });
	const attached = await call('Target.attachToTarget', { targetId: target.targetId, flatten: true });
	const pageSession = attached.sessionId;
	await call('Browser.setDownloadBehavior', { behavior: 'allow', downloadPath: profile });
	await call('Page.enable', {}, pageSession);
	await call('Runtime.enable', {}, pageSession);
	await call('Log.enable', {}, pageSession);
	await call('Network.enable', {}, pageSession);
    if(orbit) await call('Page.addScriptToEvaluateOnNewDocument', {source:"sessionStorage.setItem('ddk-orbit','1');"}, pageSession);
	const cookie = await call(
		'Network.setCookie',
		{
			name: 'sysauth_http',
			value: session,
			url: `${base}/cgi-bin/luci/`,
			httpOnly: true,
			sameSite: 'Strict'
		},
		pageSession
	);
	if (!cookie.success) throw new Error('Chrome rejected the transient LuCI cookie.');

	if (process.env.DDK_BROWSER_PREVIEW === '1') {
		const assetRoot = new URL('../files/www/luci-static/resources/ddk/', import.meta.url);
		socket.addEventListener('message', (event) => {
			const message = JSON.parse(event.data);
			if (message.method !== 'Fetch.requestPaused') return;
			const filename = new URL(message.params.request.url).pathname.split('/').pop();
			const body = Buffer.concat([
				filename === 'console-app.js' && orbit ? readFileSync(new URL('orbit.js', assetRoot)) : Buffer.alloc(0),
				filename === 'console-app.js'
					? readFileSync(new URL('console-guide.js', assetRoot))
					: Buffer.alloc(0),
				readFileSync(new URL(filename, assetRoot)),
				filename === 'console.css' && orbit ? readFileSync(new URL('orbit.css', assetRoot)) : Buffer.alloc(0)
			]);
			call(
				'Fetch.fulfillRequest',
				{
					requestId: message.params.requestId,
					responseCode: 200,
					responseHeaders: [
						{ name: 'Content-Type', value: filename.endsWith('.css') ? 'text/css' : 'application/javascript' }
					],
					body: body.toString('base64')
				},
				pageSession
			).catch((error) => browserErrors.push(error.message));
		});
		await call(
			'Fetch.enable',
			{
				patterns: ['console-app.js', 'console-guide.js', 'console.css'].map((name) => ({
					urlPattern: '*/luci-static/resources/ddk/' + name + '*',
					requestStage: 'Request'
				}))
			},
			pageSession
		);
	}
	await verifyFlows(pageSession);
	const unexpected = browserErrors.filter(
		(error) =>
			!error.includes('was loaded over an insecure connection. This file should be served over HTTPS.') &&
			!(orbit && error.includes('net::ERR_INTERNET_DISCONNECTED')) &&
			!error.includes('403 (Access to path denied by ACL)')
	);
	if (unexpected.length) throw new Error('Browser errors: ' + unexpected.join('; '));
	if (externalRequests.length) throw new Error('Unexpected external requests');
	console.log(
		'DDK_BROWSER_V4_OK: responsive pages, tool forms, native loopback lifecycle, partial save/download/reuse, input upload, retention, authentication'
	);
} finally {
	if (activeSession) {
		for (const id of createdJobs) {
			try {
				let job = await backend(['job', 'status', id]);
				if (['queued', 'running', 'stopping'].includes(job.status)) {
					await backend(['job', 'stop', id]);
					await waitUntil(
						async () =>
							!['queued', 'running', 'stopping'].includes((await backend(['job', 'status', id])).status),
						30000,
						'Fixture stop did not finish'
					);
				}
				await backend(['job', 'delete', id]);
			} catch (error) {
				console.error('Fixture cleanup required for ' + id + ': ' + error.message);
			}
		}
		for (const id of createdInputs) {
			try {
				await backend(['upload', 'delete', id]);
			} catch (error) {
				console.error('Input fixture cleanup required for ' + id + ': ' + error.message);
			}
		}
	}
	if (socket && socket.readyState === WebSocket.OPEN) socket.close();
	if (chrome.exitCode === null) {
		chrome.kill('SIGTERM');
		await Promise.race([once(chrome, 'exit'), new Promise((resolve) => setTimeout(resolve, 3000))]);
	}
	rmSync(profile, { recursive: true, force: true, maxRetries: 5, retryDelay: 100 });
}
