/* Orbit companion presentation. The existing console owns all tool execution. */
'use strict';
(function () {
	var query = new URLSearchParams(location.search),
		native = navigator.userAgent.indexOf('DDKOrbit/') >= 0;
	var active = native || query.get('orbit') === '1';
	try {
		if (query.get('orbit') === '0') sessionStorage.removeItem('ddk-orbit');
		else if (active) sessionStorage.setItem('ddk-orbit', '1');
		active = native || active || sessionStorage.getItem('ddk-orbit') === '1';
	} catch (_) {}
	if (!active) return;
	document.documentElement.dataset.orbit = 'true';
	if (native) document.documentElement.dataset.orbitNative = 'true';
	var connection = 'connecting',
		lastResponse = null;
	function element(tag, cls, text) {
		var el = document.createElement(tag);
		el.className = cls || '';
		if (text != null) el.textContent = text;
		return el;
	}
	function nativeMessage(type) {
		if (native && window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.orbit)
			window.webkit.messageHandlers.orbit.postMessage({ type: type });
	}
	function updateConnection() {
		var labels = {
			connecting: 'Connecting',
			connected: 'Router linked',
			offline: 'Connection lost',
			authentication: 'Sign in needed',
			error: 'Request failed',
		};
		var badge = document.querySelector('.orbit-connection');
		if (badge) {
			badge.dataset.state = connection;
			badge.textContent = labels[connection];
		}
		var banner = document.querySelector('.orbit-reconnect');
		if (banner) banner.hidden = connection === 'connected' || connection === 'connecting';
	}
	window.addEventListener('ddk:connection', function (event) {
		connection = event.detail.state;
		if (connection === 'connected') lastResponse = new Date();
		updateConnection();
	});
	function connectionDetails() {
		if (native) {
			nativeMessage('connection');
			return;
		}
		var dialog = element('dialog', 'orbit-dialog');
		dialog.setAttribute('aria-label', 'Connection details');
		dialog.append(
			element('span', 'ddk-eyebrow', 'YOUR APPLIANCE'),
			element('h2', '', 'Connection'),
			element('p', '', location.host),
			element(
				'p',
				'',
				lastResponse
					? 'Last response: ' + lastResponse.toLocaleTimeString()
					: 'Waiting for a router response.',
			),
			element(
				'p',
				'',
				'Join the router’s Wi-Fi for local access, or use your Tailscale connection remotely. Jobs continue on the router while your phone is away.',
			),
			element(
				'p',
				'',
				'To keep Orbit on your iPhone: open this page in Safari, choose Share, then Add to Home Screen and Open as Web App.',
			),
		);
		var dashboard = element('a', 'ddk-button ddk-button-secondary', 'Use dashboard appearance');
		var url = new URL(location.href);
		url.searchParams.set('orbit', '0');
		dashboard.href = url.pathname + url.search + url.hash;
		var close = element('button', 'ddk-button ddk-button-primary', 'Done');
		close.type = 'button';
		close.onclick = function () {
			dialog.close();
		};
		dialog.append(dashboard, close);
		document.body.append(dialog);
		dialog.addEventListener('close', function () {
			dialog.remove();
			document.querySelector('.orbit-connection').focus();
		});
		dialog.showModal();
		close.focus();
	}
	function setup() {
		if (document.querySelector('.orbit-masthead')) return;
		var head = element('header', 'orbit-masthead');
		var mark = element('div', 'orbit-wordmark');
		mark.append(element('span', 'orbit-logomark', '◎'), element('div', 'orbit-brand-name', 'ORBIT'));
		mark.lastChild.append(element('small', '', 'DIGITAL DROPKICK'));
		var badge = element('button', 'orbit-connection', 'Connecting');
		badge.type = 'button';
		badge.onclick = connectionDetails;
		badge.setAttribute('aria-label', 'Connection status and settings');
		badge.setAttribute('aria-live', 'polite');
		head.append(mark, badge);
		document.body.prepend(head);
		var banner = element('div', 'orbit-reconnect');
		banner.hidden = true;
		banner.setAttribute('role', 'status');
		banner.append(element('span', '', 'Your work stays on the router. Reconnect to refresh its status.'));
		var retry = element('button', 'ddk-button ddk-button-secondary', 'Reconnect');
		retry.type = 'button';
		retry.onclick = function () {
			if (native) nativeMessage('reconnect');
			else location.reload();
		};
		banner.append(retry);
		head.after(banner);
		new MutationObserver(function () {
			var modalOpen = document.body.classList.contains('ddk-modal-open');
			head.inert = modalOpen;
			banner.inert = modalOpen;
		}).observe(document.body, { attributes: true, attributeFilter: ['class'] });
		document.addEventListener(
			'click',
			function (event) {
				var link = event.target.closest('a[href]');
				if (!link || !link.href) return;
				var target = new URL(link.href, location.href);
				if (
					target.origin === location.origin &&
					target.pathname.startsWith('/cgi-bin/luci/admin/ddk/') &&
					!target.searchParams.has('orbit')
				) {
					target.searchParams.set('orbit', '1');
					link.href = target.pathname + target.search + target.hash;
				}
			},
			true,
		);
		updateConnection();
	}
	function decorate() {
		setup();
		document.title = 'Orbit · ' + (document.querySelector('.ddk-brand h1')?.textContent || 'Field Console');
		var links = document.querySelectorAll('.ddk-nav-links a');
		['Home', 'Tools', 'Jobs', 'Files', 'Packages', 'Setup'].forEach(function (label, index) {
			if (links[index])
				Array.from(links[index].childNodes).forEach(function (n) {
					if (n.nodeType === 3) n.textContent = label;
				});
		});
		var hero = document.querySelector('.ddk-hero');
		if (hero && !hero.dataset.orbit) {
			hero.dataset.orbit = 'true';
			hero.querySelector('.ddk-eyebrow').textContent = 'FIELD OPERATIONS / GL-X750';
			hero
				.querySelector('h2')
				.replaceChildren(
					document.createTextNode('Your next mission.'),
					element('span', '', 'All systems within reach.'),
				);
			hero.querySelector('.ddk-hero-copy > p').textContent = 'Your complete toolkit. Ready for the field.';
			var visual = hero.querySelector('.ddk-hero-visual');
			visual.replaceChildren(
				element('div', 'orbit-planet'),
				element('div', 'orbit-ring orbit-ring-a'),
				element('div', 'orbit-ring orbit-ring-b'),
				element('div', 'orbit-satellite'),
			);
			var metrics = document.querySelector('.ddk-health-strip');
			if (metrics) {
				var telemetry = element('details', 'orbit-telemetry');
				var summary = element('summary', '', 'Appliance status');
				var values = metrics.querySelectorAll('strong');
				summary.append(
					element(
						'span',
						'',
						values[3].textContent.split(' / ')[0] + ' running · ' + values[2].textContent + ' free',
					),
				);
				metrics.before(telemetry);
				telemetry.append(summary, metrics);
			}
		}
		updateConnection();
		nativeMessage('ready');
	}
	window.addEventListener('ddk:rendered', decorate);
	document.addEventListener('DOMContentLoaded', setup);
})();
