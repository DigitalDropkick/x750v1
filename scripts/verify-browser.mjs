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
		version: document.body.textContent.includes('X750 / v1.3.0'),
		serial: document.body.textContent.includes('4 nodes · 4 MODEM RESERVED · 0 GENERAL'),
		overflow: document.documentElement.scrollWidth > window.innerWidth,
		login: document.body.textContent.includes('Authorization Required')
	})`);
	if (!shortcut.version || !shortcut.serial || shortcut.overflow || shortcut.login) throw new Error(`Shortcut validation failed: ${JSON.stringify(shortcut)}`);

	await openPage(pageSession, 'overview', 320, 844);
	const compactOverview = await evaluate(pageSession, `(() => ({
		overflow: document.documentElement.scrollWidth > window.innerWidth,
		serial: document.body.textContent.includes('4 nodes · 4 MODEM RESERVED · 0 GENERAL'),
		inspect: Array.from(document.querySelectorAll('button')).some(node => node.textContent.trim() === 'Inspect Serial Attribution' && !node.disabled),
		width: window.innerWidth
	}))()`);
	if (compactOverview.overflow || !compactOverview.serial || !compactOverview.inspect || compactOverview.width !== 320) {
		throw new Error(`Compact Overview validation failed: ${JSON.stringify(compactOverview)}`);
	}
	const overviewPath = await screenshot(pageSession, 'ddk-v130-overview-320.png');

	await openPage(pageSession, 'jobs', 1440, 1000);
	await waitForJobs(pageSession);
	const desktop = await evaluate(pageSession, `(() => {
		const button = Array.from(document.querySelectorAll('button')).find(node => node.textContent.trim() === 'Discover LAN Hosts');
		const cellularButton = Array.from(document.querySelectorAll('button')).find(node => node.textContent.trim() === 'Cellular Snapshot');
		return {
			login: document.body.textContent.includes('Authorization Required'),
			version: document.body.textContent.includes('X750 / v1.3.0'),
			button: !!button,
			enabled: !!button && !button.disabled,
			cellular: !!cellularButton && !cellularButton.disabled,
			securityStyle: !!button && button.classList.contains('ddk-button-security'),
			overflow: document.documentElement.scrollWidth > window.innerWidth,
			buttons: Array.from(document.querySelectorAll('button')).map(node => node.textContent.trim()),
			heading: document.querySelector('.ddk-brand h2')?.textContent || ''
		};
	})()`);
	if (desktop.login || !desktop.version || !desktop.button || !desktop.enabled || !desktop.cellular || !desktop.securityStyle || desktop.overflow) {
		throw new Error(`Desktop Jobs validation failed: ${JSON.stringify(desktop)}`);
	}
	const desktopPath = await screenshot(pageSession, 'ddk-v130-jobs-desktop.png');

	await openPage(pageSession, 'tools', 1440, 1000);
	const tools = await evaluate(pageSession, `(() => {
		const card = Array.from(document.querySelectorAll('.ddk-tool')).find(node => node.textContent.includes('Network Discovery'));
		const button = card && Array.from(card.querySelectorAll('button')).find(node => node.textContent.trim() === 'network.nmap_lan_discovery');
		const cellularCard = Array.from(document.querySelectorAll('.ddk-tool')).find(node => node.textContent.includes('Cellular / Modem'));
		const cellularButton = cellularCard && Array.from(cellularCard.querySelectorAll('button')).find(node => node.textContent.trim() === 'cellular.snapshot');
		const serialCard = Array.from(document.querySelectorAll('.ddk-tool')).find(node => node.textContent.includes('USB & Serial Attribution'));
		const serialButton = serialCard && Array.from(serialCard.querySelectorAll('button')).find(node => node.textContent.trim() === 'serial.inspect');
		return { card: !!card, ready: !!card && card.textContent.includes('READY'), button: !!button, enabled: !!button && !button.disabled, cellularCard: !!cellularCard, cellularReady: !!cellularCard && cellularCard.textContent.includes('READY'), cellularButton: !!cellularButton && !cellularButton.disabled, serialCard: !!serialCard, serialReady: !!serialCard && serialCard.textContent.includes('READY'), serialButton: !!serialButton && !serialButton.disabled };
	})()`);
	if (!tools.card || !tools.ready || !tools.button || !tools.enabled || !tools.cellularCard || !tools.cellularReady || !tools.cellularButton || !tools.serialCard || !tools.serialReady || !tools.serialButton) {
		throw new Error(`Tool Registry validation failed: ${JSON.stringify(tools)}`);
	}
	await evaluate(pageSession, `(() => {
		const cellularCard = Array.from(document.querySelectorAll('.ddk-tool')).find(node => node.textContent.includes('Cellular / Modem'));
		cellularCard.scrollIntoView({ block: 'center' });
		return true;
	})()`);
	await new Promise(resolve => setTimeout(resolve, 200));
	const toolsPath = await screenshot(pageSession, 'ddk-v130-tools-desktop.png');

	await openPage(pageSession, 'jobs', 390, 844);
	await waitForJobs(pageSession);
	const mobile = await evaluate(pageSession, `(() => ({
		overflow: document.documentElement.scrollWidth > window.innerWidth,
		button: Array.from(document.querySelectorAll('button')).some(node => node.textContent.trim() === 'Discover LAN Hosts' && !node.disabled),
		cellular: Array.from(document.querySelectorAll('button')).some(node => node.textContent.trim() === 'Cellular Snapshot' && !node.disabled),
		width: window.innerWidth
	}))()`);
	if (mobile.overflow || !mobile.button || !mobile.cellular || mobile.width !== 390) {
		throw new Error(`Mobile Jobs validation failed: ${JSON.stringify(mobile)}`);
	}
	const mobilePath = await screenshot(pageSession, 'ddk-v130-jobs-mobile.png');

	if (browserErrors.length) throw new Error(`Browser errors: ${browserErrors.join(' | ')}`);
	console.log('Browser verification passed: /ddk shortcut, serial-aware Overview at 320px, authenticated Jobs and Tool Registry at 1440px, Jobs at 390px, no horizontal overflow or runtime errors.');
	console.log(`DDK_BROWSER_OVERVIEW=${overviewPath}`);
	console.log(`DDK_BROWSER_DESKTOP=${desktopPath}`);
	console.log(`DDK_BROWSER_TOOLS=${toolsPath}`);
	console.log(`DDK_BROWSER_MOBILE=${mobilePath}`);
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
