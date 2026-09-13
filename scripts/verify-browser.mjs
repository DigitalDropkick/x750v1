#!/usr/bin/env node

import { mkdtempSync, rmSync, writeFileSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawn } from 'node:child_process';
import { once } from 'node:events';

const base = process.env.DDK_BROWSER_BASE || 'http://192.168.8.1';
const session = process.env.DDK_BROWSER_SESSION || '';
const outputDir = process.env.DDK_BROWSER_OUTPUT_DIR || tmpdir();

if (!/^[a-fA-F0-9]{32}$/.test(session)) {
	throw new Error('DDK_BROWSER_SESSION must contain one transient 32-character LuCI session ID.');
}

const profile = mkdtempSync(join(tmpdir(), 'ddk-browser-profile-'));
const uploadProofPath = join(profile, 'ddk-browser-upload-proof.bin');
writeFileSync(uploadProofPath, process.env.DDK_BROWSER_SLOW_UPLOAD==='1' ? Buffer.alloc(8*1048576,0x44) : 'test');
const chrome = spawn('/usr/bin/google-chrome', [
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
], { stdio: [ 'ignore', 'ignore', 'pipe' ] });

let websocketUrl;
let stderr = '';
chrome.stderr.setEncoding('utf8');
chrome.stderr.on('data', chunk => {
	stderr += chunk;
	const match = stderr.match(/DevTools listening on (ws:\/\/[^\s]+)/);
	if (match) websocketUrl = match[1];
});

async function waitUntil(test, timeoutMs, message) {
	const deadline = Date.now() + timeoutMs;
	while (Date.now() < deadline) {
		const result = await test();
		if (result) return result;
		await new Promise(resolve => setTimeout(resolve, 100));
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
	const result = await call('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true }, sessionId);
	if (result.exceptionDetails) throw new Error(result.exceptionDetails.text || 'Browser evaluation failed.');
	return result.result && result.result.value;
}

async function openPage(sessionId, path, width, height) {
	await call('Emulation.setDeviceMetricsOverride', {
		width,
		height,
		deviceScaleFactor: 1,
		mobile: width <= 480
	}, sessionId);
	await call('Page.navigate', { url: `${base}/cgi-bin/luci/admin/ddk/${path}` }, sessionId);
	await waitUntil(async () => evaluate(sessionId, `location.pathname.endsWith('/${path}') && document.readyState === 'complete' && document.querySelector('#ddk-app')?.dataset.page === '${path}'`), 60000, `Timed out loading ${path}.`);
	await waitUntil(async () => evaluate(sessionId, '!!document.querySelector("#ddk-app .ddk-brand") && !document.querySelector("#ddk-app .ddk-loading")'), 60000, `Timed out rendering ${path}.`);
	const renderError=await evaluate(sessionId,"document.querySelector('#ddk-app .ddk-alert-error')?.textContent || ''");
	if(renderError)throw new Error('Page '+path+': '+renderError);
}

async function validateBrand(sessionId, page) {
	await waitUntil(async () => evaluate(sessionId, `(() => {
		const images = [
			document.querySelector('.ddk-brand-mark img'),
			document.querySelector('.ddk-nav-mark img'),
			document.querySelector('.ddk-brand-media img')
		];
		return images.every(image => image && image.complete);
	})()`), 60000, `Timed out loading local brand images for ${page}.`);
	const result = await evaluate(sessionId, `(() => {
		const logo = document.querySelector('.ddk-brand-mark img');
		const navLogo = document.querySelector('.ddk-nav-mark img');
		const scene = document.querySelector('.ddk-brand-media img');
		return {
			logo: !!logo && logo.complete && logo.naturalWidth === 160,
			navLogo: !!navLogo && navLogo.complete && navLogo.naturalWidth === 160,
			scene: !!scene && scene.complete && scene.naturalWidth === 960,
			scenePath: scene ? new URL(scene.src).pathname : '',
			accent: getComputedStyle(document.querySelector('.ddk-console')).getPropertyValue('--ddk-accent').trim(),
			brandHeight: document.querySelector('.ddk-brand')?.getBoundingClientRect().height || 0
		};
	})()`);
	if (!result.logo || !result.navLogo || !result.scene || !result.scenePath.endsWith(`/brand/${page}.webp`) || result.accent !== '#4d7c0f' || result.brandHeight < 170) {
		throw new Error(`${page} brand validation failed: ${JSON.stringify(result)}`);
	}
}

async function screenshot(sessionId, filename) {
	const capture = await call('Page.captureScreenshot', { format: 'png', fromSurface: true, captureBeyondViewport: false }, sessionId);
	const path = join(outputDir, filename);
	writeFileSync(path, Buffer.from(capture.data, 'base64'));
	return path;
}

async function waitForJobs(sessionId) {
	await waitUntil(async () => evaluate(sessionId, 'document.querySelectorAll("#ddk-app .ddk-job-list, #ddk-app .ddk-empty").length >= 2'), 60000, 'Timed out rendering job and report data.');
}

async function verifyFlows(sid) {
	const evalPage = expression => evaluate(sid, expression);
	const click = label => evalPage(`(() => { const node=Array.from(document.querySelectorAll('button')).reverse().find(n=>n.textContent.trim()===${JSON.stringify(label)} && !n.disabled); if(!node)throw Error('Button unavailable');node.click(); })()`);
	const waitText = text => waitUntil(() => evalPage(`document.body.textContent.includes(${JSON.stringify(text)})`),60000,'Missing interface text: '+text);
	const set = (name,value) => evalPage(`(() => {const n=document.querySelector('[name="${name}"]');if(!n)throw Error('Missing field');n.value=${JSON.stringify(String(value))};n.dispatchEvent(new Event('change',{bubbles:true}));})()`);
	for (const width of (process.env.DDK_BROWSER_QUICK==='1' ? [] : [1440,390,320])) {
		for (const page of ['overview','tools','jobs','settings','packages']) {
			await openPage(sid,page,width,900);
			if (!await evalPage("document.body.textContent.includes('X750 / v3.0.0') && document.documentElement.scrollWidth <= window.innerWidth")) throw new Error(`Page/version/overflow: ${page} at ${width}`);
			await validateBrand(sid,page);
		}
		console.log('Responsive pages passed at '+width+'px');
	}
	await openPage(sid,'tools',1440,1000);
	const actions = ['network.nmap_lan_discovery','network.arp_scan','android.operator','capture.ring','wireless.monitor','serial.console','gps.session','can.capture','can.transmit','industrial.modbus_write','firmware.openocd','firmware.ftdi','storage.clone','apple.mobile_manage','bluetooth.pairing','usbip.attach','auth.otp'];
	for(const action of actions) {
		const control=await evalPage(`(() => {const n=document.querySelector('[data-action="${action}"]');return {found:!!n,enabled:!!n&&!n.disabled};})()`);
		if(!control.enabled)throw new Error('Tool control unavailable: '+action+' '+JSON.stringify(control));
		await evalPage(`document.querySelector('[data-action="${action}"]').click()`);
		await waitUntil(()=>evalPage("!!document.querySelector('.ddk-modal [name]')"),60000,'Tool form failed: '+action);
		if(action==='android.operator') {
			await set('transport','tcp');
			if(!await evalPage("!!document.querySelector('[name=host]') && !document.querySelector('[name=host]').closest('label').hidden")) throw new Error('Android network transport is inaccessible');
		}
		await click('Close');
		console.log('Opened form: '+action);
	}
	console.log('Network, Android and hardware tool forms passed');
	await openPage(sid,'jobs',1440,1000);await waitForJobs(sid);
	await click('Loss and Latency');await waitText('Hosts or IP addresses');
	await set('targets','127.0.0.1');await set('interface','lo');await set('count',0);await set('duration',0);await set('period_ms',100);await set('output_mib',1);
	await click('Validate & Review');await waitText('Start Native Action');
	if(!await evalPage("document.querySelector('.ddk-operator-review').textContent.includes('127.0.0.1')"))throw new Error('Loopback preview lost target');
	const existing=await evalPage("Array.from(document.querySelectorAll('[data-job]')).map(n=>n.dataset.job)");
	await click('Start Native Action');
	const job=await waitUntil(()=>evalPage(`Array.from(document.querySelectorAll('[data-job]')).map(n=>n.dataset.job).find(id=>!${JSON.stringify(existing)}.includes(id))`),60000,'Native job did not appear');
	const clickJob=label=>evalPage(`(()=>{const n=Array.from(document.querySelector('[data-job="${job}"]').querySelectorAll('button')).find(n=>n.textContent.trim()===${JSON.stringify(label)}&&!n.disabled);if(!n)throw Error('Missing job control');n.click();})()`);
	await waitUntil(()=>evalPage(`document.querySelector('[data-job="${job}"]').textContent.includes('127.0.0.1')`),60000,'No native loopback result');
	await clickJob('Stop and Keep Results');
	await waitUntil(()=>evalPage(`document.querySelector('[data-job="${job}"]').textContent.includes('Save Across Reboots')`),60000,'Stop did not preserve job');
	await clickJob('Save Across Reboots');
	await waitUntil(()=>evalPage(`document.querySelector('[data-job="${job}"]').textContent.includes('SAVED')`),60000,'Case was not saved');
	await evalPage(`(()=>{const original=window.fetch;window.ddkDownloadProof=null;window.fetch=async(...args)=>{const response=await original(...args);if(String(args[0]).includes('cgi-download'))window.ddkDownloadProof={ok:response.ok,loopback:(await response.clone().text()).includes('127.0.0.1')};return response;};})()`);
	await clickJob('Download native-output.txt (incomplete)');
	const download=await waitUntil(()=>evalPage('window.ddkDownloadProof'),60000,'No authenticated download');
	if(!download.ok||!download.loopback)throw new Error('Native result download failed');
	console.log('DDK_BROWSER_FIXTURE_JOB='+job);
	await screenshot(sid,'ddk-v3-jobs-desktop.png');
	await clickJob('Reuse native-output.txt');await waitText('Input ready');await click('Close');
	await openPage(sid,'settings',390,900);
	await click('Save Retention Settings');await waitText('Saved. Job cleanup');
	await call('DOM.enable',{},sid);
	const doc=await call('DOM.getDocument',{},sid);const file=await call('DOM.querySelector',{nodeId:doc.root.nodeId,selector:'input[type=file]'},sid);
	await call('DOM.setFileInputFiles',{nodeId:file.nodeId,files:[uploadProofPath]},sid);
	if(process.env.DDK_BROWSER_SLOW_UPLOAD==='1') { await call('Network.emulateNetworkConditions',{offline:false,latency:0,downloadThroughput:-1,uploadThroughput:100000},sid);console.log('Testing an 8 MiB upload across the native 60-second request timeout'); }
	await click('Upload & Seal Input');await waitUntil(()=>evalPage("document.body.textContent.includes('Sealed ddk-browser-upload-proof.bin')"),180000,'Upload did not finish');
	if(process.env.DDK_BROWSER_SLOW_UPLOAD==='1') await call('Network.emulateNetworkConditions',{offline:false,latency:0,downloadThroughput:-1,uploadThroughput:-1},sid);
	await screenshot(sid,'ddk-v3-settings-mobile.png');
	const denied=await evalPage(`(async()=>{const f=document.querySelector('script[data-ddk-config]');const r=await fetch('/cgi-bin/cgi-download',{method:'POST',body:new URLSearchParams({sessionid:${JSON.stringify(session)},path:'/etc/hostname'}),credentials:'same-origin'});return r.status!==200;})()`);
	if(!denied)throw new Error('Download escaped application ACL');
	await call('Page.navigate',{url:base+'/ddk'},sid);
	await waitUntil(async()=>{try{return await evalPage("location.pathname==='/cgi-bin/luci/admin/ddk/overview' && !!document.querySelector('#ddk-app .ddk-brand') && !document.querySelector('#ddk-app .ddk-loading')");}catch{return false;}},60000,'The /ddk shortcut did not reach the authenticated dashboard');
	console.log('Native job, preserved partial output, saved case, download/reuse and upload passed');
}

try {
	await waitUntil(() => websocketUrl, 10000, 'Chrome DevTools endpoint did not start.');
	socket = new WebSocket(websocketUrl);
	await new Promise((resolve, reject) => {
		socket.addEventListener('open', resolve, { once: true });
		socket.addEventListener('error', reject, { once: true });
	});
	socket.addEventListener('message', event => {
		const message = JSON.parse(event.data);
		if (message.id && pending.has(message.id)) {
			const handler = pending.get(message.id);
			pending.delete(message.id);
			if (message.error) handler.reject(new Error(message.error.message));
			else handler.resolve(message.result || {});
		}
		else if (message.method === 'Runtime.exceptionThrown') {
			browserErrors.push(message.params.exceptionDetails.text || 'Uncaught runtime exception');
		}
		else if (message.method === 'Log.entryAdded' && message.params.entry.level === 'error') {
			browserErrors.push(message.params.entry.text);
		}
		else if (message.method === 'Network.requestWillBeSent') {
			const url = message.params.request.url;
			if (/^https?:/.test(url) && new URL(url).origin !== allowedOrigin) externalRequests.push(url);
		}
	});

	const target = await call('Target.createTarget', { url: 'about:blank' });
	const attached = await call('Target.attachToTarget', { targetId: target.targetId, flatten: true });
	const pageSession = attached.sessionId;
	await call('Page.enable', {}, pageSession);
	await call('Runtime.enable', {}, pageSession);
	await call('Log.enable', {}, pageSession);
	await call('Network.enable', {}, pageSession);
	const cookie = await call('Network.setCookie', {
		name: 'sysauth_http',
		value: session,
		url: `${base}/cgi-bin/luci/`,
		httpOnly: true,
		sameSite: 'Strict'
	}, pageSession);
	if (!cookie.success) throw new Error('Chrome rejected the transient LuCI cookie.');

	if (process.env.DDK_BROWSER_STAGED === '1') {
        const source = readFileSync('/tmp/ddk-v3-full/www/luci-static/resources/ddk/console-app.js');
        socket.addEventListener('message', event => {
            const message = JSON.parse(event.data);
            if (message.method === 'Fetch.requestPaused') {
                call('Fetch.fulfillRequest', {requestId:message.params.requestId,responseCode:200,responseHeaders:[{name:'Content-Type',value:'application/javascript'}],body:source.toString('base64')}, pageSession).catch(error => browserErrors.push(error.message));
            }
        });
        await call('Fetch.enable',{patterns:[{urlPattern:'*/luci-static/resources/ddk/console-app.js*',requestStage:'Request'}]},pageSession);
    }
    await verifyFlows(pageSession);
    const unexpected=browserErrors.filter(error=>!error.includes("was loaded over an insecure connection. This file should be served over HTTPS.") && !error.includes('403 (Access to path denied by ACL)'));
    if (unexpected.length) throw new Error('Browser errors: '+unexpected.join('; '));
    if (externalRequests.length) throw new Error('Unexpected external requests');
    console.log('DDK_BROWSER_V3_OK: responsive pages, tool forms, native loopback lifecycle, partial save/download/reuse, input upload, retention, authentication');
}

finally {
	if (socket && socket.readyState === WebSocket.OPEN) socket.close();
	if (chrome.exitCode === null) {
		chrome.kill('SIGTERM');
		await Promise.race([
			once(chrome, 'exit'),
			new Promise(resolve => setTimeout(resolve, 3000))
		]);
	}
	rmSync(profile, { recursive: true, force: true, maxRetries: 5, retryDelay: 100 });
}
