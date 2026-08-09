'use strict';

(function() {
	var app = document.getElementById('ddk-app');
	if (!app)
		return;

	var config = {
		page: app.dataset.page || 'overview',
		session: app.dataset.session || '',
		cgi: app.dataset.cgi || '/cgi-bin/cgi-exec',
		base: app.dataset.base || '/cgi-bin/luci/admin/ddk'
	};
	app.removeAttribute('data-session');

	function append(parent, child) {
		if (child == null || child === false)
			return;
		if (Array.isArray(child)) {
			child.forEach(function(item) { append(parent, item); });
		}
		else if (child instanceof Node) {
			parent.appendChild(child);
		}
		else {
			parent.appendChild(document.createTextNode(String(child)));
		}
	}

	function h(tag, attrs) {
		var node = document.createElement(tag);
		var children = Array.prototype.slice.call(arguments, 2);
		Object.keys(attrs || {}).forEach(function(key) {
			var value = attrs[key];
			if (value == null || value === false)
				return;
			if (key.slice(0, 2) === 'on' && typeof value === 'function')
				node.addEventListener(key.slice(2), value);
			else if (key === 'class')
				node.className = value;
			else if (value === true)
				node.setAttribute(key, '');
			else
				node.setAttribute(key, String(value));
		});
		children.forEach(function(child) { append(node, child); });
		return node;
	}

	function button(label, className, handler, disabled) {
		return h('button', {
			type: 'button',
			class: 'ddk-button' + (className ? ' ' + className : ''),
			onclick: handler,
			disabled: disabled || null
		}, label);
	}

	function escapeArgument(value) {
		return String(value).replace(/\\/g, '\\\\').replace(/\s/g, '\\$&');
	}

	async function exec(args) {
		if (!config.session || !Array.isArray(args) || !args.length ||
		    args.some(function(value) { return typeof value !== 'string' || !/^[A-Za-z0-9._\/-]+$/.test(value); }))
			throw new Error('The request did not match the DDK client allowlist.');

		var command = escapeArgument('/usr/libexec/ddk-console');
		args.forEach(function(value) { command += ' ' + escapeArgument(value); });
		var body = new URLSearchParams({ sessionid: config.session, command: command });
		var response = await fetch(config.cgi, {
			method: 'POST',
			credentials: 'same-origin',
			headers: { 'Content-Type': 'application/x-www-form-urlencoded;charset=UTF-8' },
			body: body.toString()
		});
		if (!response.ok)
			throw new Error(response.status === 403 ? 'LuCI session or DDK ACL rejected the request.' : 'Field Console request failed with HTTP ' + response.status + '.');
		var payload;
		try {
			payload = JSON.parse(await response.text());
		}
		catch (error) {
			throw new Error('The Field Console returned invalid JSON.');
		}
		if (!payload.ok)
			throw new Error(payload.message || 'Field Console request failed.');
		return payload.data;
	}

	function formatBytes(value) {
		var number = Number(value || 0);
		var units = [ 'B', 'KiB', 'MiB', 'GiB', 'TiB' ];
		var index = 0;
		while (number >= 1024 && index < units.length - 1) {
			number /= 1024;
			index++;
		}
		return (index ? number.toFixed(number >= 10 ? 1 : 2) : number.toFixed(0)) + ' ' + units[index];
	}

	function formatUptime(seconds) {
		var remaining = Math.max(0, Number(seconds || 0));
		var days = Math.floor(remaining / 86400);
		var hours = Math.floor((remaining % 86400) / 3600);
		var minutes = Math.floor((remaining % 3600) / 60);
		return (days ? days + 'd ' : '') + hours + 'h ' + minutes + 'm';
	}

	function stateClass(state) {
		return 'ddk-state-' + String(state || 'unknown').toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
	}

	function statePill(state) {
		return h('span', { class: 'ddk-state ' + stateClass(state) }, state || 'UNKNOWN');
	}

	function row(label, value, className) {
		return h('div', { class: 'ddk-data-row' + (className ? ' ' + className : '') },
			h('span', { class: 'ddk-data-label' }, label),
			h('span', { class: 'ddk-data-value' }, value == null || value === '' ? '—' : String(value)));
	}

	function meter(label, used, total, detail) {
		var percent = total > 0 ? Math.max(0, Math.min(100, Math.round((used / total) * 100))) : 0;
		return h('div', { class: 'ddk-meter' },
			h('div', { class: 'ddk-meter-copy' }, h('span', {}, label), h('span', {}, detail || percent + '%')),
			h('div', { class: 'ddk-meter-track' }, h('span', { style: 'width:' + percent + '%' })));
	}

	function card(title, kicker, content, className) {
		return h('section', { class: 'ddk-card' + (className ? ' ' + className : '') },
			h('div', { class: 'ddk-card-head' }, h('span', { class: 'ddk-card-kicker' }, kicker || 'STATUS'), h('h3', {}, title)),
			h('div', { class: 'ddk-card-body' }, content || []));
	}

	function brand(section, description) {
		return h('header', { class: 'ddk-brand' },
			h('div', { class: 'ddk-brand-mark', 'aria-hidden': 'true' }, 'DDK'),
			h('div', { class: 'ddk-brand-copy' },
				h('span', { class: 'ddk-eyebrow' }, 'DIGITAL DROPKICK'),
				h('h2', {}, section || 'FIELD CONSOLE'),
				h('p', {}, description || 'GL-X750 field appliance control surface')),
			h('div', { class: 'ddk-appliance-tag' }, h('span', { class: 'ddk-live-dot' }), h('span', {}, 'X750 / v1.1')));
	}

	function sectionHeading(title, detail) {
		return h('div', { class: 'ddk-section-heading' }, h('h3', {}, title), h('p', {}, detail || ''));
	}

	function showError(error) {
		app.replaceChildren(
			brand('FIELD CONSOLE ERROR', 'The existing GL.iNet configuration was not changed'),
			h('div', { class: 'ddk-alert ddk-alert-error' }, error && error.message ? error.message : String(error)),
			h('div', { class: 'ddk-action-row' }, button('Retry', '', function() { location.reload(); }))
		);
	}

	function showModal(title, content, actions) {
		var overlay = h('div', { class: 'ddk-modal', role: 'dialog', 'aria-modal': 'true', 'aria-label': title },
			h('div', { class: 'ddk-modal-panel' },
				h('div', { class: 'ddk-modal-head' }, h('h3', {}, title), button('Close', 'ddk-button-secondary', close)),
				content,
				actions || null));
		function close() { overlay.remove(); }
		overlay.addEventListener('click', function(event) { if (event.target === overlay) close(); });
		document.body.appendChild(overlay);
	}

	async function runInfo(actionId, target) {
		target.replaceChildren(h('pre', {}, 'Collecting ' + actionId + '…'));
		try {
			var result = await exec([ 'info', actionId ]);
			var suffix = result.truncated ? '\n\n[Output truncated by the 128 KiB safety limit.]' : '';
			target.replaceChildren(
				h('div', { class: 'ddk-card-head' }, h('span', { class: 'ddk-card-kicker' }, 'INFO ACTION'), h('h3', {}, result.label)),
				h('pre', {}, (result.output || 'No output.') + suffix));
		}
		catch (error) {
			target.replaceChildren(h('div', { class: 'ddk-alert ddk-alert-error' }, error.message));
		}
	}

	function confirmLanDiscovery() {
		return window.confirm(
			'Start bounded Nmap LAN host discovery?\n\n' +
			'Target: private br-lan subnet derived by the router (never browser input)\n' +
			'Profile: host discovery only; no port scan or DNS lookup\n' +
			'Limits: at most /24, 64 packets/second, 75 seconds, one active scan\n' +
			'Output: bounded and transient under /tmp/ddk/jobs/'
		);
	}

	async function startLanDiscovery() {
		if (!confirmLanDiscovery())
			return null;
		return exec([ 'job', 'start', 'network.nmap_lan_discovery' ]);
	}

	function capabilitySummary(modules) {
		var order = [ 'Network Diagnostics', 'Wi-Fi', 'Cellular', 'Packet Capture', 'Serial', 'Industrial', 'CAN', 'Bluetooth', 'SDR / Radio', 'GPS', 'Camera', 'Device Repair', 'Firmware Programming', 'Security / Authentication', 'Monitoring', 'Automation', 'Storage / Recovery', 'Hardware', 'USB & Serial' ];
		var groups = {};
		modules.forEach(function(module) { (groups[module.category] = groups[module.category] || []).push(module); });
		return order.filter(function(category) { return groups[category]; }).map(function(category) {
			var states = groups[category].map(function(entry) { return entry.state; });
			var state = states.indexOf('READY') >= 0 ? 'READY' : states.indexOf('READY / NO DEVICE') >= 0 ? 'READY / NO DEVICE' : states.indexOf('NOT CONFIGURED') >= 0 ? 'NOT CONFIGURED' : states.indexOf('HARDWARE REQUIRED') >= 0 ? 'HARDWARE REQUIRED' : 'UNAVAILABLE';
			return h('div', { class: 'ddk-cap' }, h('strong', {}, category), statePill(state));
		});
	}

	async function renderOverview() {
		var status = await exec([ 'status' ]);
		var modules = await exec([ 'capabilities' ]);
		var system = status.system, network = status.network, remote = status.remote_access, hardware = status.hardware;
		var memoryUsed = Math.max(0, system.memory.total - system.memory.available);
		var output = h('section', { class: 'ddk-output' });
		var actions = [
			[ 'Refresh System Status', 'system.refresh' ], [ 'Show Interfaces', 'network.interfaces' ],
			[ 'Show Routes', 'network.routes' ], [ 'Show USB Devices', 'hardware.usb' ],
			[ 'Show Serial Devices', 'hardware.serial' ], [ 'Show Tailscale Status', 'remote.tailscale' ],
			[ 'Show Storage / Mounts', 'storage.mounts' ], [ 'Show Memory / Swap', 'system.memory' ],
			[ 'Package Count', 'packages.count' ]
		];

		app.replaceChildren(
			brand('FIELD CONSOLE', 'Live health, hardware awareness, and allowlisted field diagnostics'),
			system.swap.active ? document.createDocumentFragment() : h('div', { class: 'ddk-alert' }, h('strong', {}, 'SWAP INACTIVE'), h('span', {}, 'The console has not attempted to activate or modify /overlay/ddk-install.swap.')),
			sectionHeading('Appliance Health', 'Generated at router epoch ' + status.generated_at),
			h('div', { class: 'ddk-grid' },
				card('System', 'CORE', [ row('Hostname', system.hostname), row('Model', system.model), row('OpenWrt', system.openwrt), row('Kernel', system.kernel), row('Uptime', formatUptime(system.uptime_seconds)), row('Load average', system.load.join(' / ')), row('Installed packages', system.package_count) ]),
				card('Memory & Storage', 'RESOURCES', [ row('Physical memory', formatBytes(system.memory.total)), row('Available memory', formatBytes(system.memory.available)), meter('Memory pressure', memoryUsed, system.memory.total, formatBytes(memoryUsed) + ' used'), row('Swap total / used', formatBytes(system.swap.total) + ' / ' + formatBytes(system.swap.used)), row('Root free', formatBytes(system.storage.available)), meter('Root storage', system.storage.used, system.storage.total, system.storage.percent + '% used') ]),
				card('Network', 'CONNECTIVITY', [ row('LAN IP', network.lan_ip), row('WAN state', network.wan_up ? 'UP' : 'DOWN'), row('WAN interface', network.wan_interface), row('WAN IP', network.wan_ip), row('Default route', network.default_route), row('DNS', network.dns.join(', ')), row('Attached interfaces', network.interfaces.length) ]),
				card('Remote Access', 'TAILSCALE', [ row('Installed', remote.tailscale_installed ? 'YES' : 'NO'), row('Process', remote.tailscale_running ? 'RUNNING' : 'NOT RUNNING'), row('Tailscale IP', remote.tailscale_ip), row('Version', remote.tailscale_version), h('div', { class: 'ddk-alert ddk-alert-info' }, 'Observation only — no Tailscale setting is read or modified.') ], 'ddk-card-wide'),
				card('Hardware Presence', 'LIVE PROBES', [ row('USB devices', hardware.usb_devices.length), row('Serial devices', hardware.serial_devices.length ? hardware.serial_devices.join(', ') : 'NONE'), row('Video devices', hardware.video_devices.length ? hardware.video_devices.join(', ') : 'NONE'), row('RTL-SDR', hardware.classes.rtl_sdr ? 'DETECTED' : 'NOT DETECTED'), row('CAN interfaces', hardware.can_interfaces.length ? hardware.can_interfaces.join(', ') : 'NONE'), row('Bluetooth controller', hardware.classes.bluetooth ? 'DETECTED' : 'NOT DETECTED'), row('I2C / SPI', hardware.i2c_devices.length + ' / ' + hardware.spi_devices.length) ], 'ddk-card-wide')),
			sectionHeading('Capability Matrix', modules.length + ' modular tool groups'),
			h('div', { class: 'ddk-cap-grid' }, capabilitySummary(modules)),
			sectionHeading('Safe Phase-One Actions', 'Fixed INFO allowlist only'),
			h('section', { class: 'ddk-card ddk-card-full' }, h('div', { class: 'ddk-card-body' },
				h('div', { class: 'ddk-action-row' }, actions.map(function(action) { return button(action[0], 'ddk-button-secondary', function() { runInfo(action[1], output); }); }), h('a', { class: 'ddk-button', href: config.base + '/jobs' }, 'Generate DDK System Report')))),
			output);
	}

	function renderTool(module, output) {
		var packageText = module.software.matched_packages.length ? module.software.matched_packages.join(', ') : 'No matching package';
		var hardwareText = !module.hardware.required ? 'Not required' : module.hardware.present ? module.hardware.detected.join(', ') : 'Missing: ' + module.hardware.missing.join(', ');
		var actions = (module.actions || []).map(function(action) {
			var infoEnabled = module.console_enabled && action.enabled && action.class === 'INFO';
			var discoveryEnabled = module.console_enabled && action.enabled && action.class === 'SECURITY' && action.id === 'network.nmap_lan_discovery';
			var handler = infoEnabled ? function() { runInfo(action.id, output); } : discoveryEnabled ? async function() {
				try {
					var job = await startLanDiscovery();
					if (job) showModal('LAN Discovery Started', h('div', {}, h('p', {}, 'The bounded job is running as ' + job.id + '.'), h('p', {}, h('a', { class: 'ddk-button', href: config.base + '/jobs' }, 'Open Jobs & Reports'))));
				}
				catch (error) { showModal('Job Error', h('div', { class: 'ddk-alert ddk-alert-error' }, error.message)); }
			} : null;
			return button(action.id, discoveryEnabled ? 'ddk-button-security' : 'ddk-button-secondary', handler, !infoEnabled && !discoveryEnabled);
		});
		return h('article', { class: 'ddk-tool' },
			h('div', { class: 'ddk-tool-head' }, h('div', {}, h('span', { class: 'ddk-card-kicker' }, module.category), h('h3', {}, module.name)), statePill(module.state)),
			h('div', { class: 'ddk-tool-body' }, h('p', { class: 'ddk-tool-description' }, module.description), h('p', { class: 'ddk-tool-detail' }, h('strong', {}, 'Software: '), module.software.installed ? 'Installed' : 'Unavailable'), h('p', { class: 'ddk-tool-detail' }, h('strong', {}, 'Packages: '), packageText), h('p', { class: 'ddk-tool-detail' }, h('strong', {}, 'Hardware: '), hardwareText), h('p', { class: 'ddk-tool-detail' }, h('strong', {}, 'Risk: '), module.risk_level), h('p', { class: 'ddk-tool-detail' }, module.help_text), h('div', { class: 'ddk-tool-actions' }, actions.length ? actions : statePill('NO ACTIONS'))));
	}

	async function renderTools() {
		var modules = await exec([ 'capabilities' ]);
		var categories = Array.from(new Set(modules.map(function(module) { return module.category; }))).sort();
		var search = h('input', { class: 'ddk-input', type: 'search', placeholder: 'Search tools, packages, hardware…' });
		var category = h('select', { class: 'ddk-select' }, h('option', { value: '' }, 'All categories'), categories.map(function(name) { return h('option', { value: name }, name); }));
		var states = [ '', 'READY', 'READY / NO DEVICE', 'HARDWARE REQUIRED', 'NOT CONFIGURED', 'UNAVAILABLE' ];
		var state = h('select', { class: 'ddk-select' }, states.map(function(name) { return h('option', { value: name }, name || 'All states'); }));
		var count = h('p', {}, modules.length + ' modules');
		var grid = h('div', { class: 'ddk-tool-grid' });
		var output = h('section', { class: 'ddk-output' });
		var cards = modules.map(function(module) {
			var node = renderTool(module, output); grid.appendChild(node);
			return { node: node, module: module, search: [ module.name, module.category, module.description, module.package_names.join(' '), module.expected_binaries.join(' '), module.required_hardware.join(' ') ].join(' ').toLowerCase() };
		});
		function filter() {
			var query = search.value.toLowerCase(), visible = 0;
			cards.forEach(function(item) {
				var match = (!query || item.search.indexOf(query) >= 0) && (!category.value || item.module.category === category.value) && (!state.value || item.module.state === state.value);
				item.node.hidden = !match; if (match) visible++;
			});
			count.textContent = visible + ' of ' + cards.length + ' modules';
		}
		search.addEventListener('input', filter); category.addEventListener('change', filter); state.addEventListener('change', filter);
		app.replaceChildren(brand('TOOL REGISTRY', 'Software inventory separated from live hardware presence'), h('div', { class: 'ddk-alert ddk-alert-info' }, 'A manifest can describe a future action, but only the backend allowlist can execute one. The reviewed Nmap LAN profile requires explicit confirmation; other SECURITY controls remain disabled.'), h('div', { class: 'ddk-toolbar' }, search, category, state), h('div', { class: 'ddk-table-meta' }, count, h('span', {}, 'Hardware probes are read-only')), grid, output);
	}

	async function renderPackages() {
		var packages = await exec([ 'packages' ]), page = 0;
		var search = h('input', { class: 'ddk-input', type: 'search', placeholder: 'Search package name or version…' });
		var category = h('select', { class: 'ddk-select' }, [ '', 'Applications', 'LuCI', 'Kernel', 'Libraries', 'Python', 'Hardware', 'Networking', 'Monitoring' ].map(function(name) { return h('option', { value: name }, name || 'All'); }));
		var size = h('select', { class: 'ddk-select' }, [ 50, 100, 250, 0 ].map(function(value) { return h('option', { value: value, selected: value === 100 }, value ? value + ' rows' : 'Show all'); }));
		var count = h('span'), pageLabel = h('span'), tableWrap = h('div', { class: 'ddk-table-wrap' });
		var previous = button('Previous', 'ddk-button-secondary'), next = button('Next', 'ddk-button-secondary');
		function render(reset) {
			if (reset) page = 0;
			var query = search.value.toLowerCase();
			var filtered = packages.filter(function(item) { return (!category.value || item.category === category.value) && (!query || item.name.toLowerCase().indexOf(query) >= 0 || item.version.toLowerCase().indexOf(query) >= 0); });
			var pageSize = Number(size.value), pages = pageSize ? Math.max(1, Math.ceil(filtered.length / pageSize)) : 1;
			page = Math.max(0, Math.min(page, pages - 1));
			var visible = pageSize ? filtered.slice(page * pageSize, page * pageSize + pageSize) : filtered;
			var tbody = h('tbody', {}, visible.map(function(item) { return h('tr', {}, h('td', {}, item.name), h('td', {}, item.version), h('td', {}, item.category)); }));
			tableWrap.replaceChildren(h('table', { class: 'ddk-table' }, h('thead', {}, h('tr', {}, h('th', {}, 'Package'), h('th', {}, 'Version'), h('th', {}, 'Type'))), tbody));
			count.textContent = filtered.length + ' matching / ' + packages.length + ' installed'; pageLabel.textContent = 'Page ' + (page + 1) + ' of ' + pages;
			previous.disabled = page <= 0; next.disabled = page >= pages - 1;
		}
		search.addEventListener('input', function() { render(true); }); category.addEventListener('change', function() { render(true); }); size.addEventListener('change', function() { render(true); });
		previous.addEventListener('click', function() { page--; render(false); }); next.addEventListener('click', function() { page++; render(false); });
		app.replaceChildren(brand('PACKAGE INVENTORY', 'All installed packages, separated from the capability dashboard'), h('div', { class: 'ddk-toolbar' }, search, category, size), h('div', { class: 'ddk-table-meta' }, count, pageLabel), tableWrap, h('div', { class: 'ddk-action-row ddk-actions-end' }, previous, next));
		render(true);
	}

	async function renderJobs() {
		var jobsNode = h('div'), reportsNode = h('div'), pollers = {};
		function renderJobList(jobs) {
			if (!jobs.length) { jobsNode.replaceChildren(h('div', { class: 'ddk-empty' }, 'No DDK jobs have run since the last reboot or cleanup.')); return; }
			jobsNode.replaceChildren(h('div', { class: 'ddk-job-list' }, jobs.map(function(job) {
				var active = [ 'queued', 'running', 'stopping' ].indexOf(job.status) >= 0, output = job.stdout || job.stderr;
				return h('article', { class: 'ddk-job' }, h('div', { class: 'ddk-job-head' }, h('h4', {}, job.metadata.label || job.metadata.action_id || job.id), statePill(job.status)), h('p', { class: 'ddk-job-meta' }, job.id + ' · PID ' + (job.pid || 'pending') + ' · ' + (job.metadata.class || 'INFO')), output ? h('pre', { class: 'ddk-job-output' }, output) : null, active ? h('div', { class: 'ddk-action-row' }, button('Stop DDK Job', 'ddk-button-secondary', function() { stopJob(job.id); })) : null);
			})));
		}
		function download(report) {
			var url = URL.createObjectURL(new Blob([ report.content ], { type: 'text/plain;charset=utf-8' }));
			var link = h('a', { href: url, download: report.id + '.txt' }); document.body.appendChild(link); link.click(); link.remove(); URL.revokeObjectURL(url);
		}
		async function viewReport(id, shouldDownload) {
			try { var report = await exec([ 'report', 'view', id ]); if (shouldDownload) download(report); else showModal('DDK System Report — ' + report.id, h('pre', { class: 'ddk-report-view' }, report.content + (report.truncated ? '\n\n[Report view truncated.]' : '')), h('div', { class: 'ddk-action-row ddk-actions-end' }, button('Download', '', function() { download(report); }))); }
			catch (error) { showModal('Report Error', h('div', { class: 'ddk-alert ddk-alert-error' }, error.message)); }
		}
		function renderReportList(reports) {
			if (!reports.length) { reportsNode.replaceChildren(h('div', { class: 'ddk-empty' }, 'No transient DDK reports are available.')); return; }
			reportsNode.replaceChildren(h('div', { class: 'ddk-job-list' }, reports.map(function(report) { return h('article', { class: 'ddk-job' }, h('div', { class: 'ddk-job-head' }, h('h4', {}, report.id), statePill(formatBytes(report.size))), h('p', { class: 'ddk-job-meta' }, 'Transient /tmp report · router epoch ' + report.created_at), h('div', { class: 'ddk-action-row' }, button('View', 'ddk-button-secondary', function() { viewReport(report.id, false); }), button('Download', 'ddk-button-secondary', function() { viewReport(report.id, true); }))); })));
		}
		async function refresh() { var jobs = await exec([ 'job', 'list' ]); var reports = await exec([ 'report', 'list' ]); renderJobList(jobs); renderReportList(reports); return jobs; }
		function poll(id) { if (pollers[id]) return; pollers[id] = setTimeout(async function tick() { try { var job = await exec([ 'job', 'status', id ]); await refresh(); if ([ 'queued', 'running', 'stopping' ].indexOf(job.status) >= 0) pollers[id] = setTimeout(tick, 1200); else delete pollers[id]; } catch (_) { delete pollers[id]; } }, 1200); }
		async function start(action, requiresDiscoveryConfirmation) { try { var job = requiresDiscoveryConfirmation ? await startLanDiscovery() : await exec([ 'job', 'start', action ]); if (!job) return; await refresh(); poll(job.id); } catch (error) { showModal('Job Error', h('div', { class: 'ddk-alert ddk-alert-error' }, error.message)); } }
		async function stopJob(id) { try { await exec([ 'job', 'stop', id ]); await refresh(); poll(id); } catch (error) { showModal('Job Error', h('div', { class: 'ddk-alert ddk-alert-error' }, error.message)); } }
		app.replaceChildren(brand('JOBS & REPORTS', 'Bounded asynchronous work without blocking LuCI'), h('div', { class: 'ddk-alert ddk-alert-info' }, 'Only two DDK jobs may run at once. Outputs are bounded, stored in /tmp, and removed by age/retention cleanup.'), sectionHeading('Start Bounded Job', 'Fixed server-side allowlist'), h('div', { class: 'ddk-action-row' }, button('Run Async Proof', '', function() { start('diagnostic.demo'); }), button('Generate DDK System Report', '', function() { start('report.system'); }), button('Discover LAN Hosts', 'ddk-button-security', function() { start('network.nmap_lan_discovery', true); }), button('Refresh', 'ddk-button-secondary', refresh)), sectionHeading('Jobs', 'Only DDK-owned worker PIDs can be stopped'), jobsNode, sectionHeading('Reports', 'Authenticated view/download · 24-hour retention'), reportsNode);
		var jobs = await refresh(); jobs.forEach(function(job) { if ([ 'queued', 'running', 'stopping' ].indexOf(job.status) >= 0) poll(job.id); });
	}

	function renderSettings() {
		var posture = [
			[ 'Authentication', 'Inherited from the existing LuCI sysauth session. No public DDK endpoint.' ],
			[ 'Network exposure', 'No listener, nginx/uhttpd rule, firewall rule, or WAN binding is created.' ],
			[ 'Action policy', 'Exact server-side action IDs only. Browser command strings and executable paths are rejected.' ],
			[ 'Arguments', 'Only known action IDs and generated DDK job/report IDs are accepted. Nmap target and interface are derived server-side.' ],
			[ 'Jobs', 'Maximum 2 active, 20 retained, 4-hour job cleanup, bounded stdout/stderr.' ],
			[ 'Reports', 'Stored in /tmp, 128 KiB maximum view, 24-hour cleanup, no secret configuration dumps.' ],
			[ 'Idle footprint', 'No DDK daemon, database, timer, analytics, or background poller runs on the router.' ],
			[ 'Configuration', 'This page is deliberately read-only in phase one.' ]
		];
		app.replaceChildren(brand('SETTINGS', 'Production safety posture and operating limits'), h('div', { class: 'ddk-alert ddk-alert-info' }, 'There are no mutable Field Console settings in version 1.1. This is intentional.'), h('div', { class: 'ddk-posture' }, posture.map(function(item) { return h('div', { class: 'ddk-posture-item' }, h('strong', {}, item[0]), h('span', {}, item[1])); })), sectionHeading('Explicitly Disabled', 'Requires future deliberate wiring'), card('Operating Boundaries', 'LOCKED', [ row('DISRUPTIVE actions', 'DISABLED'), row('SECURITY actions', 'ONLY BOUNDED LAN DISCOVERY ENABLED'), row('Arbitrary targets / flags', 'REJECTED'), row('Generic PID stop', 'NOT IMPLEMENTED'), row('Persistent logs', 'NOT IMPLEMENTED'), row('WAN service exposure', 'NOT IMPLEMENTED') ], 'ddk-card-full'));
	}

	var renderers = { overview: renderOverview, tools: renderTools, packages: renderPackages, jobs: renderJobs, settings: renderSettings };
	Promise.resolve(renderers[config.page] || renderOverview).then(function(renderer) { return renderer(); }).catch(showError);
})();
