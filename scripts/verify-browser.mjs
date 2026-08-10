#!/usr/bin/env node

import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
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
	await waitUntil(async () => evaluate(sessionId, `location.pathname.endsWith('/${path}') && document.readyState === 'complete' && document.querySelector('#ddk-app')?.dataset.page === '${path}'`), 15000, `Timed out loading ${path}.`);
	await waitUntil(async () => evaluate(sessionId, '!!document.querySelector("#ddk-app .ddk-brand") && !document.querySelector("#ddk-app .ddk-loading")'), 15000, `Timed out rendering ${path}.`);
}

async function validateBrand(sessionId, page) {
	await waitUntil(async () => evaluate(sessionId, `(() => {
		const images = [
			document.querySelector('.ddk-brand-mark img'),
			document.querySelector('.ddk-nav-mark img'),
			document.querySelector('.ddk-brand-media img')
		];
		return images.every(image => image && image.complete);
	})()`), 15000, `Timed out loading local brand images for ${page}.`);
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
	await waitUntil(async () => evaluate(sessionId, 'document.querySelectorAll("#ddk-app .ddk-job-list, #ddk-app .ddk-empty").length >= 2'), 15000, 'Timed out rendering job and report data.');
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

	await call('Page.navigate', { url: `${base}/ddk` }, pageSession);
	await waitUntil(async () => evaluate(pageSession, `location.pathname.endsWith('/cgi-bin/luci/admin/ddk/overview') && document.readyState === 'complete' && document.querySelector('#ddk-app')?.dataset.page === 'overview'`), 15000, 'Timed out following the /ddk shortcut.');
	await waitUntil(async () => evaluate(pageSession, '!!document.querySelector("#ddk-app .ddk-brand") && !document.querySelector("#ddk-app .ddk-loading")'), 15000, 'Timed out rendering the shortcut destination.');
	const shortcut = await evaluate(pageSession, `({
		path: location.pathname,
		version: document.body.textContent.includes('X750 / v2.0.0'),
		serial: document.body.textContent.includes('4 nodes · 4 MODEM RESERVED · 0 GENERAL'),
		overflow: document.documentElement.scrollWidth > window.innerWidth,
		login: document.body.textContent.includes('Authorization Required')
	})`);
	if (!shortcut.version || !shortcut.serial || shortcut.overflow || shortcut.login) throw new Error(`Shortcut validation failed: ${JSON.stringify(shortcut)}`);
	await validateBrand(pageSession, 'overview');

	await openPage(pageSession, 'overview', 320, 844);
	await call('Input.dispatchKeyEvent', { type: 'rawKeyDown', key: 'Tab', code: 'Tab', windowsVirtualKeyCode: 9 }, pageSession);
	await call('Input.dispatchKeyEvent', { type: 'keyUp', key: 'Tab', code: 'Tab', windowsVirtualKeyCode: 9 }, pageSession);
	const compactOverview = await evaluate(pageSession, `(() => {
		const focusTarget = document.activeElement;
		const focusStyle = focusTarget && focusTarget !== document.body ? getComputedStyle(focusTarget) : null;
		const touchTargets = Array.from(document.querySelectorAll('.ddk-nav a, .ddk-console button.ddk-button, .ddk-console a.ddk-button'));
		return {
			overflow: document.documentElement.scrollWidth > window.innerWidth,
			serial: document.body.textContent.includes('4 nodes · 4 MODEM RESERVED · 0 GENERAL'),
			inspect: Array.from(document.querySelectorAll('button')).some(node => node.textContent.trim() === 'Inspect Serial Attribution' && !node.disabled),
			focus: !!focusStyle && focusStyle.outlineStyle !== 'none' && parseFloat(focusStyle.outlineWidth) >= 2,
			touchTargets: touchTargets.length > 0 && touchTargets.every(node => node.getBoundingClientRect().height >= 43.5),
			width: window.innerWidth
		};
	})()`);
	if (compactOverview.overflow || !compactOverview.serial || !compactOverview.inspect || !compactOverview.focus || !compactOverview.touchTargets || compactOverview.width !== 320) {
		throw new Error(`Compact Overview validation failed: ${JSON.stringify(compactOverview)}`);
	}
	await validateBrand(pageSession, 'overview');
	const overviewPath = await screenshot(pageSession, 'ddk-v200-overview-320.png');

	await openPage(pageSession, 'jobs', 1440, 1000);
	await waitForJobs(pageSession);
	const desktop = await evaluate(pageSession, `(() => {
		const button = Array.from(document.querySelectorAll('button')).find(node => node.textContent.trim() === 'Discover LAN Hosts');
		const cellularButton = Array.from(document.querySelectorAll('button')).find(node => node.textContent.trim() === 'Cellular Snapshot');
		const captureButton = Array.from(document.querySelectorAll('button')).find(node => node.textContent.trim() === 'Capture LAN Metadata');
		const radioButton = Array.from(document.querySelectorAll('button')).find(node => node.textContent.trim() === 'RTL-433 Sensor Snapshot');
		const cameraButton = Array.from(document.querySelectorAll('button')).find(node => node.textContent.trim() === 'Camera Still Snapshot');
		const gpsButton = Array.from(document.querySelectorAll('button')).find(node => node.textContent.trim() === 'GPS / GNSS Position Snapshot');
		const canButton = Array.from(document.querySelectorAll('button')).find(node => node.textContent.trim() === 'Passive CAN Frame Snapshot');
		return {
			login: document.body.textContent.includes('Authorization Required'),
			version: document.body.textContent.includes('X750 / v2.0.0'),
			button: !!button,
			enabled: !!button && !button.disabled,
			cellular: !!cellularButton && !cellularButton.disabled,
			capture: !!captureButton && !captureButton.disabled,
			radioHardwareRequired: document.body.textContent.includes('RTL-433 receiver state: HARDWARE REQUIRED'),
			radioDisabled: !!radioButton && radioButton.disabled,
			cameraHardwareRequired: document.body.textContent.includes('Camera state: HARDWARE REQUIRED'),
			cameraDisabled: !!cameraButton && cameraButton.disabled,
			gpsUnavailable: document.body.textContent.includes('GPS / GNSS state: REVIEWED USB GNSS RECEIVER NOT DETECTED'),
			gpsDisabled: !!gpsButton && gpsButton.disabled,
			canUnavailable: document.body.textContent.includes('CAN state: CAN INTERFACE NOT DETECTED; CANDUMP EXECUTABLE UNAVAILABLE'),
			canDisabled: !!canButton && canButton.disabled,
			securityStyle: !!button && button.classList.contains('ddk-button-security'),
			captureSecurityStyle: !!captureButton && captureButton.classList.contains('ddk-button-security'),
			radioActionStyle: !!radioButton && radioButton.classList.contains('ddk-button-action'),
			cameraActionStyle: !!cameraButton && cameraButton.classList.contains('ddk-button-action'),
			gpsActionStyle: !!gpsButton && gpsButton.classList.contains('ddk-button-action'),
			canActionStyle: !!canButton && canButton.classList.contains('ddk-button-action'),
			overflow: document.documentElement.scrollWidth > window.innerWidth,
			buttons: Array.from(document.querySelectorAll('button')).map(node => node.textContent.trim()),
			heading: document.querySelector('.ddk-brand h2')?.textContent || ''
		};
	})()`);
	if (desktop.login || !desktop.version || !desktop.button || !desktop.enabled || !desktop.cellular || !desktop.capture || !desktop.radioHardwareRequired || !desktop.radioDisabled || !desktop.cameraHardwareRequired || !desktop.cameraDisabled || !desktop.gpsUnavailable || !desktop.gpsDisabled || !desktop.canUnavailable || !desktop.canDisabled || !desktop.securityStyle || !desktop.captureSecurityStyle || !desktop.radioActionStyle || !desktop.cameraActionStyle || !desktop.gpsActionStyle || !desktop.canActionStyle || desktop.overflow) {
		throw new Error(`Desktop Jobs validation failed: ${JSON.stringify(desktop)}`);
	}
	await validateBrand(pageSession, 'jobs');
	const desktopPath = await screenshot(pageSession, 'ddk-v200-jobs-desktop.png');

	await openPage(pageSession, 'tools', 1440, 1000);
	const tools = await evaluate(pageSession, `(() => {
		const card = Array.from(document.querySelectorAll('.ddk-tool')).find(node => node.textContent.includes('Network Discovery'));
		const button = card && Array.from(card.querySelectorAll('button')).find(node => node.textContent.trim() === 'network.nmap_lan_discovery');
		const cellularCard = Array.from(document.querySelectorAll('.ddk-tool')).find(node => node.textContent.includes('Cellular / Modem'));
		const cellularButton = cellularCard && Array.from(cellularCard.querySelectorAll('button')).find(node => node.textContent.trim() === 'cellular.snapshot');
		const serialCard = Array.from(document.querySelectorAll('.ddk-tool')).find(node => node.textContent.includes('USB & Serial Attribution'));
		const serialButton = serialCard && Array.from(serialCard.querySelectorAll('button')).find(node => node.textContent.trim() === 'serial.inspect');
		const captureCard = Array.from(document.querySelectorAll('.ddk-tool')).find(node => node.textContent.includes('Capture & Traffic'));
		const captureButton = captureCard && Array.from(captureCard.querySelectorAll('button')).find(node => node.textContent.trim() === 'capture.lan_metadata_snapshot');
		const radioCard = Array.from(document.querySelectorAll('.ddk-tool')).find(node => node.textContent.includes('SDR / Radio') && node.textContent.includes('radio.rtl433_snapshot'));
		const radioButton = radioCard && Array.from(radioCard.querySelectorAll('button')).find(node => node.textContent.trim() === 'radio.rtl433_snapshot');
		const cameraCard = Array.from(document.querySelectorAll('.ddk-tool')).find(node => node.textContent.includes('Camera / Video') && node.textContent.includes('camera.still_snapshot'));
		const cameraButton = cameraCard && Array.from(cameraCard.querySelectorAll('button')).find(node => node.textContent.trim() === 'camera.still_snapshot');
		const gpsCard = Array.from(document.querySelectorAll('.ddk-tool')).find(node => node.textContent.includes('GPS / GNSS / RTK') && node.textContent.includes('gps.snapshot'));
		const gpsButton = gpsCard && Array.from(gpsCard.querySelectorAll('button')).find(node => node.textContent.trim() === 'gps.snapshot');
		const canCard = Array.from(document.querySelectorAll('.ddk-tool')).find(node => node.textContent.includes('CAN Bus') && node.textContent.includes('can.capture'));
		const canButton = canCard && Array.from(canCard.querySelectorAll('button')).find(node => node.textContent.trim() === 'can.capture');
		const androidCard = Array.from(document.querySelectorAll('.ddk-tool')).find(node => node.textContent.includes('Android / ADB'));
		const androidIdentity = androidCard && Array.from(androidCard.querySelectorAll('button')).find(node => node.textContent.trim() === 'android.identify');
		const androidGuide = androidCard && Array.from(androidCard.querySelectorAll('button')).find(node => node.textContent.trim() === 'android.operator_guide');
		const androidShell = androidCard && Array.from(androidCard.querySelectorAll('button')).find(node => node.textContent.trim() === 'android.shell');
		const appleCard = Array.from(document.querySelectorAll('.ddk-tool')).find(node => node.textContent.includes('Apple / iOS Repair'));
		const appleIdentity = appleCard && Array.from(appleCard.querySelectorAll('button')).find(node => node.textContent.trim() === 'apple.identify');
		const appleGuide = appleCard && Array.from(appleCard.querySelectorAll('button')).find(node => node.textContent.trim() === 'apple.operator_guide');
		const appleRestore = appleCard && Array.from(appleCard.querySelectorAll('button')).find(node => node.textContent.trim() === 'apple.restore');
		const firmwareCard = Array.from(document.querySelectorAll('.ddk-tool')).find(node => node.textContent.includes('Firmware / Embedded'));
		const firmwareIdentity = firmwareCard && Array.from(firmwareCard.querySelectorAll('button')).find(node => node.textContent.trim() === 'firmware.identify');
		const firmwareGuide = firmwareCard && Array.from(firmwareCard.querySelectorAll('button')).find(node => node.textContent.trim() === 'firmware.operator_guide');
		const firmwareWrite = firmwareCard && Array.from(firmwareCard.querySelectorAll('button')).find(node => node.textContent.trim() === 'firmware.write');
		return {
			card: !!card,
			ready: !!card && card.textContent.includes('READY'),
			button: !!button,
			enabled: !!button && !button.disabled,
			cellularCard: !!cellularCard,
			cellularReady: !!cellularCard && cellularCard.textContent.includes('READY'),
			cellularButton: !!cellularButton && !cellularButton.disabled,
			serialCard: !!serialCard,
			serialReady: !!serialCard && serialCard.textContent.includes('READY'),
			serialButton: !!serialButton && !serialButton.disabled,
			captureCard: !!captureCard,
			captureReady: !!captureCard && captureCard.textContent.includes('READY'),
			captureButton: !!captureButton && !captureButton.disabled && captureButton.classList.contains('ddk-button-security'),
			radioCard: !!radioCard,
			radioHardwareRequired: !!radioCard && radioCard.textContent.includes('HARDWARE REQUIRED'),
			radioButtonDisabled: !!radioButton && radioButton.disabled && radioButton.classList.contains('ddk-button-action'),
			cameraCard: !!cameraCard,
			cameraHardwareRequired: !!cameraCard && cameraCard.textContent.includes('HARDWARE REQUIRED'),
			cameraButtonDisabled: !!cameraButton && cameraButton.disabled && cameraButton.classList.contains('ddk-button-action'),
			gpsCard: !!gpsCard,
			gpsHardwareRequired: !!gpsCard && gpsCard.textContent.includes('HARDWARE REQUIRED'),
			gpsButtonDisabled: !!gpsButton && gpsButton.disabled && gpsButton.classList.contains('ddk-button-action'),
			canCard: !!canCard,
			canHardwareRequired: !!canCard && canCard.textContent.includes('HARDWARE REQUIRED'),
			canRuntimeVisible: !!canCard && canCard.textContent.includes('candump'),
			canButtonDisabled: !!canButton && canButton.disabled && canButton.classList.contains('ddk-button-action'),
			androidCard: !!androidCard && androidCard.textContent.includes('READY / NO DEVICE'),
			androidActions: !!androidIdentity && !androidIdentity.disabled && !!androidGuide && !androidGuide.disabled && !!androidShell && androidShell.disabled,
			appleCard: !!appleCard && appleCard.textContent.includes('READY / NO DEVICE'),
			appleActions: !!appleIdentity && !appleIdentity.disabled && !!appleGuide && !appleGuide.disabled && !!appleRestore && appleRestore.disabled,
			firmwareCard: !!firmwareCard && firmwareCard.textContent.includes('READY / NO DEVICE'),
			firmwareActions: !!firmwareIdentity && !firmwareIdentity.disabled && !!firmwareGuide && !firmwareGuide.disabled && !!firmwareWrite && firmwareWrite.disabled
		};
	})()`);
	if (!tools.card || !tools.ready || !tools.button || !tools.enabled || !tools.cellularCard || !tools.cellularReady || !tools.cellularButton || !tools.serialCard || !tools.serialReady || !tools.serialButton || !tools.captureCard || !tools.captureReady || !tools.captureButton || !tools.radioCard || !tools.radioHardwareRequired || !tools.radioButtonDisabled || !tools.cameraCard || !tools.cameraHardwareRequired || !tools.cameraButtonDisabled || !tools.gpsCard || !tools.gpsHardwareRequired || !tools.gpsButtonDisabled || !tools.canCard || !tools.canHardwareRequired || !tools.canRuntimeVisible || !tools.canButtonDisabled || !tools.androidCard || !tools.androidActions || !tools.appleCard || !tools.appleActions || !tools.firmwareCard || !tools.firmwareActions) {
		throw new Error(`Tool Registry validation failed: ${JSON.stringify(tools)}`);
	}
	await evaluate(pageSession, 'window.confirm = () => true');
	await evaluate(pageSession, "(() => { const card = Array.from(document.querySelectorAll('.ddk-tool')).find(node => node.textContent.includes('Android / ADB')); Array.from(card.querySelectorAll('button')).find(node => node.textContent.trim() === 'android.identify').click(); return true; })()");
	await waitUntil(async () => evaluate(pageSession, "document.querySelector('.ddk-output')?.textContent.includes('ANDROID USB IDENTITY SNAPSHOT') && document.querySelector('.ddk-output')?.textContent.includes('browser memory only')"), 10000, 'Timed out rendering the private Android identity response.');
	await evaluate(pageSession, "(() => { const card = Array.from(document.querySelectorAll('.ddk-tool')).find(node => node.textContent.includes('Android / ADB')); Array.from(card.querySelectorAll('button')).find(node => node.textContent.trim() === 'android.operator_guide').click(); return true; })()");
	await waitUntil(async () => evaluate(pageSession, "document.querySelector('.ddk-output')?.textContent.includes('ANDROID / ADB FULL CLI HANDOFF') && document.querySelector('.ddk-output')?.textContent.includes('adb                INSTALLED') && document.querySelector('.ddk-output')?.textContent.includes('browser does not execute')"), 10000, 'Timed out rendering the Android full CLI handoff.');
	await validateBrand(pageSession, 'tools');
	await evaluate(pageSession, `(() => {
		const cellularCard = Array.from(document.querySelectorAll('.ddk-tool')).find(node => node.textContent.includes('Cellular / Modem'));
		cellularCard.scrollIntoView({ block: 'center' });
		return true;
	})()`);
	await new Promise(resolve => setTimeout(resolve, 200));
	const toolsPath = await screenshot(pageSession, 'ddk-v200-tools-desktop.png');

	for (const page of [ 'packages', 'settings' ]) {
		await openPage(pageSession, page, 1440, 900);
		await validateBrand(pageSession, page);
		const overflow = await evaluate(pageSession, 'document.documentElement.scrollWidth > window.innerWidth');
		if (overflow) throw new Error(`${page} has horizontal document overflow.`);
	}

	await openPage(pageSession, 'tools', 390, 844);
	const mobileTools = await evaluate(pageSession, "(() => { const cards = Array.from(document.querySelectorAll('.ddk-tool')); const android = cards.find(node => node.textContent.includes('Android / ADB')); const apple = cards.find(node => node.textContent.includes('Apple / iOS Repair')); const firmware = cards.find(node => node.textContent.includes('Firmware / Embedded')); const touchTargets = [ android, apple, firmware ].flatMap(card => card ? Array.from(card.querySelectorAll('button')) : []); return { overflow: document.documentElement.scrollWidth > window.innerWidth, android: !!android && android.textContent.includes('android.operator_guide'), apple: !!apple && apple.textContent.includes('apple.operator_guide'), firmware: !!firmware && firmware.textContent.includes('firmware.operator_guide'), touch: touchTargets.length === 9 && touchTargets.every(node => node.getBoundingClientRect().height >= 43.5), width: window.innerWidth }; })()");
	if (mobileTools.overflow || !mobileTools.android || !mobileTools.apple || !mobileTools.firmware || !mobileTools.touch || mobileTools.width !== 390) {
		throw new Error('Mobile Tool Registry validation failed: ' + JSON.stringify(mobileTools));
	}
	await validateBrand(pageSession, 'tools');
	const mobileToolsPath = await screenshot(pageSession, 'ddk-v200-tools-mobile.png');

	await openPage(pageSession, 'jobs', 390, 844);
	await waitForJobs(pageSession);
	const mobile = await evaluate(pageSession, `(() => ({
		overflow: document.documentElement.scrollWidth > window.innerWidth,
		button: Array.from(document.querySelectorAll('button')).some(node => node.textContent.trim() === 'Discover LAN Hosts' && !node.disabled),
		cellular: Array.from(document.querySelectorAll('button')).some(node => node.textContent.trim() === 'Cellular Snapshot' && !node.disabled),
		capture: Array.from(document.querySelectorAll('button')).some(node => node.textContent.trim() === 'Capture LAN Metadata' && !node.disabled),
		radioDisabled: Array.from(document.querySelectorAll('button')).some(node => node.textContent.trim() === 'RTL-433 Sensor Snapshot' && node.disabled),
		cameraDisabled: Array.from(document.querySelectorAll('button')).some(node => node.textContent.trim() === 'Camera Still Snapshot' && node.disabled),
		gpsDisabled: Array.from(document.querySelectorAll('button')).some(node => node.textContent.trim() === 'GPS / GNSS Position Snapshot' && node.disabled),
		canDisabled: Array.from(document.querySelectorAll('button')).some(node => node.textContent.trim() === 'Passive CAN Frame Snapshot' && node.disabled),
		width: window.innerWidth
	}))()`);
	if (mobile.overflow || !mobile.button || !mobile.cellular || !mobile.capture || !mobile.radioDisabled || !mobile.cameraDisabled || !mobile.gpsDisabled || !mobile.canDisabled || mobile.width !== 390) {
		throw new Error(`Mobile Jobs validation failed: ${JSON.stringify(mobile)}`);
	}
	await validateBrand(pageSession, 'jobs');
	const mobilePath = await screenshot(pageSession, 'ddk-v200-jobs-mobile.png');

	if (browserErrors.length) throw new Error(`Browser errors: ${browserErrors.join(' | ')}`);
	if (externalRequests.length) throw new Error(`External browser requests were made: ${[ ...new Set(externalRequests) ].join(' | ')}`);
	console.log('Browser verification passed: /ddk shortcut, five local branded headers and logos, v2 private identity plus full native-CLI handoff modules, serial-aware Overview at 320px, authenticated Nmap/capture controls, and hardware/runtime-gated RTL-433, camera, GPS/GNSS, and passive CAN controls at 1440px and 390px, with no external requests, horizontal overflow, or runtime errors.');
	console.log(`DDK_BROWSER_OVERVIEW=${overviewPath}`);
	console.log(`DDK_BROWSER_DESKTOP=${desktopPath}`);
	console.log(`DDK_BROWSER_TOOLS=${toolsPath}`);
	console.log(`DDK_BROWSER_MOBILE=${mobilePath}`);
	console.log('DDK_BROWSER_TOOLS_MOBILE=' + mobileToolsPath);
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
