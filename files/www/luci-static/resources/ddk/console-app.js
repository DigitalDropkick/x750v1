'use strict';

(function () {
	var app = document.getElementById('ddk-app');
	if (!app) return;

	var config = {
		page: app.dataset.page || 'overview',
		session: app.dataset.session || '',
		cgi: app.dataset.cgi || '/cgi-bin/cgi-exec',
		download: app.dataset.download || '/cgi-bin/cgi-download',
		upload: app.dataset.upload || '/cgi-bin/cgi-upload',
		base: app.dataset.base || '/cgi-bin/luci/admin/ddk'
	};
	app.removeAttribute('data-session');

	function append(parent, child) {
		if (child == null || child === false) return;
		if (Array.isArray(child)) {
			child.forEach(function (item) {
				append(parent, item);
			});
		} else if (child instanceof Node) {
			parent.appendChild(child);
		} else {
			parent.appendChild(document.createTextNode(String(child)));
		}
	}

	function replace(parent) {
		parent.replaceChildren();
		Array.prototype.slice.call(arguments, 1).forEach(function (child) {
			append(parent, child);
		});
	}

	function h(tag, attrs) {
		var node = document.createElement(tag);
		var children = Array.prototype.slice.call(arguments, 2);
		Object.keys(attrs || {}).forEach(function (key) {
			var value = attrs[key];
			if (value == null || value === false) return;
			if (key.slice(0, 2) === 'on' && typeof value === 'function') node.addEventListener(key.slice(2), value);
			else if (key === 'class') node.className = value;
			else if (value === true) node.setAttribute(key, '');
			else node.setAttribute(key, String(value));
		});
		children.forEach(function (child) {
			append(node, child);
		});
		return node;
	}

	function button(label, className, handler, disabled, title) {
		return h(
			'button',
			{
				type: 'button',
				class: 'ddk-button' + (className ? ' ' + className : ''),
				onclick: handler,
				disabled: disabled || null,
				title: title || null
			},
			label
		);
	}

	function escapeArgument(value) {
		return String(value).replace(/\\/g, '\\\\').replace(/\s/g, '\\$&');
	}

	function base64urlText(value) {
		var bytes = new TextEncoder().encode(String(value));
		var binary = '';
		for (var offset = 0; offset < bytes.length; offset += 8192)
			binary += String.fromCharCode.apply(null, bytes.subarray(offset, offset + 8192));
		return btoa(binary).replace(/\+/g, '-').split('/').join('_').replace(/=+$/g, '');
	}

	function structuredEnvelope(options) {
		var body = JSON.stringify({ version: 1, options: options });
		if (new TextEncoder().encode(body).length > 24576)
			throw new Error('The structured action request exceeds the 24 KiB client limit.');
		return base64urlText(body);
	}

	async function exec(args) {
		if (
			!config.session ||
			!Array.isArray(args) ||
			!args.length ||
			args.length > 5 ||
			args.some(function (value) {
				return typeof value !== 'string' || value.length > 32772 || !/^[A-Za-z0-9._\/-]+$/.test(value);
			})
		)
			throw new Error('The request did not match the DDK client allowlist.');

		var command = escapeArgument('/usr/libexec/ddk-console');
		args.forEach(function (value) {
			command += ' ' + escapeArgument(value);
		});
		var body = new URLSearchParams({ sessionid: config.session, command: command });
		var response;
		try {
			response = await fetch(config.cgi, {
				method: 'POST',
				credentials: 'same-origin',
				headers: { 'Content-Type': 'application/x-www-form-urlencoded;charset=UTF-8' },
				body: body.toString()
			});
		} catch (error) {
			window.dispatchEvent(new CustomEvent('ddk:connection', { detail: { state: 'offline' } }));
			throw error;
		}
		window.dispatchEvent(new CustomEvent('ddk:connection', {
			detail: { state: response.ok ? 'connected' : response.status === 403 ? 'authentication' : 'error' }
		}));
		if (!response.ok)
			throw new Error(
				response.status === 403
					? 'LuCI session or DDK ACL rejected the request.'
					: 'Field Console request failed with HTTP ' + response.status + '.'
			);
		var payload;
		try {
			payload = JSON.parse(await response.text());
		} catch (error) {
			throw new Error('The Field Console returned invalid JSON.');
		}
		if (!payload.ok) throw new Error(payload.message || 'Field Console request failed.');
		return payload.data;
	}

	function uploadFile(reservation, file, progress) {
		return new Promise(function (resolve, reject) {
			var request = new XMLHttpRequest();
			request.open('POST', config.upload, true);
			request.withCredentials = true;
			request.timeout = 0;
			request.upload.addEventListener('progress', function (event) {
				if (event.lengthComputable && progress)
					progress(Math.min(100, Math.round((event.loaded / event.total) * 100)));
			});
			request.addEventListener('load', function () {
				if (request.status < 200 || request.status >= 300) {
					reject(
						new Error(
							request.status === 403
								? 'LuCI session or upload ACL rejected the file.'
								: 'Upload failed with HTTP ' + request.status + '.'
						)
					);
					return;
				}
				try {
					var reply = JSON.parse(request.responseText || '{}');
					if (reply && reply.failure) {
						reject(new Error(reply.message || 'Native LuCI upload rejected the file.'));
						return;
					}
				} catch (_) {
					reject(new Error('Native LuCI upload returned an invalid response.'));
					return;
				}
				resolve();
			});
			request.addEventListener('error', function () {
				reject(new Error('The authenticated upload connection failed.'));
			});
			request.addEventListener('timeout', function () {
				reject(new Error('The authenticated upload timed out. Check the connection and retry.'));
			});
			var form = new FormData();
			form.append('sessionid', config.session);
			form.append('filename', reservation.upload_path);
			form.append('filedata', file, file.name);
			request.send(form);
		});
	}

	function formatBytes(value) {
		var number = Number(value || 0);
		var units = ['B', 'KiB', 'MiB', 'GiB', 'TiB'];
		var index = 0;
		while (number >= 1024 && index < units.length - 1) {
			number /= 1024;
			index++;
		}
		return (index ? number.toFixed(number >= 10 ? 1 : 2) : number.toFixed(0)) + ' ' + units[index];
	}
	async function waitForSealed(input, progress) {
		while (input.phase === 'sealing') {
			if (progress)
				progress(
					'Hashing ' +
						input.original_name +
						'… ' +
						formatBytes(input.hash_bytes || 0) +
						' / ' +
						formatBytes(input.size)
				);
			await new Promise(function (resolve) {
				setTimeout(resolve, 1500);
			});
			input = await exec(['upload', 'finalize', input.id]);
		}
		return input;
	}

	function formatUptime(seconds) {
		var remaining = Math.max(0, Number(seconds || 0));
		var days = Math.floor(remaining / 86400);
		var hours = Math.floor((remaining % 86400) / 3600);
		var minutes = Math.floor((remaining % 3600) / 60);
		return (days ? days + 'd ' : '') + hours + 'h ' + minutes + 'm';
	}

	function stateClass(state) {
		return (
			'ddk-state-' +
			String(state || 'unknown')
				.toLowerCase()
				.replace(/[^a-z0-9]+/g, '-')
				.replace(/^-|-$/g, '')
		);
	}

	function statePill(state) {
		return h('span', { class: 'ddk-state ' + stateClass(state) }, state || 'UNKNOWN');
	}

	function row(label, value, className) {
		return h(
			'div',
			{ class: 'ddk-data-row' + (className ? ' ' + className : '') },
			h('span', { class: 'ddk-data-label' }, label),
			h('span', { class: 'ddk-data-value' }, value == null || value === '' ? '—' : String(value))
		);
	}

	function meter(label, used, total, detail) {
		var percent = total > 0 ? Math.max(0, Math.min(100, Math.round((used / total) * 100))) : 0;
		return h(
			'div',
			{ class: 'ddk-meter' },
			h('div', { class: 'ddk-meter-copy' }, h('span', {}, label), h('span', {}, detail || percent + '%')),
			h('div', { class: 'ddk-meter-track' }, h('span', { style: 'width:' + percent + '%' }))
		);
	}

	function card(title, kicker, content, className) {
		return h(
			'section',
			{ class: 'ddk-card' + (className ? ' ' + className : '') },
			h(
				'div',
				{ class: 'ddk-card-head' },
				h('span', { class: 'ddk-card-kicker' }, kicker || 'STATUS'),
				h('h3', {}, title)
			),
			h('div', { class: 'ddk-card-body' }, content || [])
		);
	}

	var guide = window.DDKGuide;
	var modalStack = [],
		capabilityCache,
		jobsRefresh;
	function icon(name) {
		var paths = {
			home: 'M3 10 12 3l9 7v10H3Z M9 20v-7h6v7',
			tools: 'm14 6 4-4 4 4-4 4 M3 21l12-12 M3 3l5 5 M16 16l5 5 M3 17l4 4',
			jobs: 'M8 5H4v16h16V5h-4 M8 3h8v5H8Z M8 12h8 M8 16h5',
			files: 'M3 7h7l2 2h9v11H3Z M3 7V4h7l2 3h8v2',
			packages: 'm3 7 9-4 9 4v10l-9 4-9-4Z M3 7l9 5 9-5 M12 12v9',
			settings: 'M4 6h16 M4 12h16 M4 18h16 M8 3v6 M16 9v6 M10 15v6',
			search: 'M15 15l6 6 M17 10a7 7 0 1 1-14 0 7 7 0 0 1 14 0',
			arrow: 'M4 12h16 m-6-6 6 6-6 6',
			network: 'M12 3v6 M4 15v-4h16v4 M1 16h6v5H1Z M9 2h6v5H9Z M17 16h6v5h-6Z',
			devices: 'M6 2h12v20H6Z M10 18h4',
			hardware: 'M6 6h12v12H6Z M9 9h6v6H9Z M9 2v4 M15 2v4 M9 18v4 M15 18v4 M2 9h4 M2 15h4 M18 9h4 M18 15h4',
			radio:
				'M12 10v11 M8 21h8 M8 6a6 6 0 0 0 0 8 M16 6a6 6 0 0 1 0 8 M5 3a10 10 0 0 0 0 14 M19 3a10 10 0 0 1 0 14',
			data: 'M3 6c0-4 18-4 18 0v12c0 4-18 4-18 0Z M3 6c0 4 18 4 18 0 M3 12c0 4 18 4 18 0',
			system: 'M3 3h18v14H3Z M7 21h10 M12 17v4 M6 11h3l2-5 3 8 2-3h2',
			star: 'm12 3 3 6 7 1-5 5 1 7-6-4-6 4 1-7-5-5 7-1Z',
			close: 'm6 6 12 12 M6 18 18 6',
			check: 'm4 12 5 5L20 6',
			refresh: 'M20 7a9 9 0 1 0 1 8 M20 2v6h-6',
			activity: 'M2 12h5l3-8 4 16 3-8h5',
			terminal: 'm5 7 5 5-5 5 M13 17h6'
		};
		var svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
		Object.entries({
			viewBox: '0 0 24 24',
			width: 20,
			height: 20,
			fill: 'none',
			stroke: 'currentColor',
			'stroke-width': 1.6,
			'stroke-linecap': 'round',
			'stroke-linejoin': 'round',
			'aria-hidden': 'true'
		}).forEach(function (pair) {
			svg.setAttribute(pair[0], pair[1]);
		});
		var path = document.createElementNS('http://www.w3.org/2000/svg', 'path');
		path.setAttribute('d', paths[name] || paths.tools);
		svg.appendChild(path);
		return svg;
	}
	function link(label, path, className) {
		return h(
			'a',
			{ href: config.base + '/' + path, class: className || 'ddk-button ddk-button-secondary' },
			label
		);
	}
	function readLocal(key, fallback) {
		try {
			var value = JSON.parse(localStorage.getItem(key));
			return Array.isArray(fallback) && !Array.isArray(value) ? fallback : value || fallback;
		} catch (_) {
			return fallback;
		}
	}
	function remember(key, value) {
		try {
			localStorage.setItem(key, JSON.stringify(value));
		} catch (_) {
			toast('Browser storage is unavailable; this preference will last for this visit.');
		}
	}
	function toast(message) {
		var node = h('div', { class: 'ddk-toast', role: 'status' }, message);
		document.body.appendChild(node);
		setTimeout(function () {
			node.remove();
		}, 5000);
	}
	function activeJob(job) {
		return ['queued', 'running', 'stopping'].indexOf(job.status) >= 0;
	}
	function jobTarget(job) {
		var metadata = job.metadata || {},
			options = metadata.options || {};
		if (Array.isArray(options.targets) && options.targets.length)
			return options.targets.join(', ') + (options.interface ? ' · ' + options.interface : '');
		return metadata.target_summary || '';
	}

	function timeText(value) {
		return value
			? new Date(Number(value) * 1000).toLocaleString(undefined, {
					month: 'short',
					day: 'numeric',
					hour: 'numeric',
					minute: '2-digit'
				})
			: 'Pending';
	}
	function brand(section, description) {
		return h(
			'header',
			{ class: 'ddk-brand' },
			h(
				'div',
				{},
				h('span', { class: 'ddk-eyebrow' }, 'DIGITAL DROPKICK / FIELD CONSOLE'),
				h('h1', {}, section),
				h('p', {}, description)
			),
			h('span', { class: 'ddk-appliance-tag' }, 'X750 / v4.1.0-beta.1')
		);
	}
	function sectionHeading(title, detail) {
		return h('div', { class: 'ddk-section-heading' }, h('h2', {}, title), h('p', {}, detail || ''));
	}
	function showError(error) {
		replace(
			app,
			brand('Connection needs attention', 'Your workspace is still on the router.'),
			h('div', { class: 'ddk-alert ddk-alert-error', role: 'alert' }, error.message || String(error)),
			button('Reconnect', '', function () {
				location.reload();
			})
		);
	}
	function setupNavigation() {
		var nav = document.querySelector('.ddk-nav');
		var routes = [
			['overview', 'Overview', 'home'],
			['tools', 'Tool library', 'tools'],
			['jobs', 'Jobs & cases', 'jobs'],
			['settings#inputs', 'Input files', 'files'],
			['packages', 'Packages', 'packages'],
			['settings', 'Settings', 'settings']
		];
		replace(
			nav,
			h(
				'a',
				{ class: 'ddk-nav-home', href: config.base + '/overview' },
				h('img', { src: '/luci-static/resources/ddk/brand/dropkick-logo.png', alt: 'Digital Dropkick' }),
				h(
					'span',
					{},
					h('strong', {}, 'DIGITAL'),
					h('strong', {}, 'DROPKICK'),
					h('small', {}, 'FIELD CONSOLE')
				)
			),
			h('span', { class: 'ddk-nav-label' }, 'WORKSPACE'),
			h(
				'div',
				{ class: 'ddk-nav-links' },
				routes.map(function (route) {
					var active =
						config.page === route[0].split('#')[0] &&
						(config.page !== 'settings' || (location.hash === '#inputs') === (route[0].indexOf('#') >= 0));
					return h(
						'a',
						{
							href: config.base + '/' + route[0],
							class: active ? 'active' : null,
							'aria-current': active ? 'page' : null
						},
						icon(route[2]),
						route[1]
					);
				})
			),
			h(
				'div',
				{ class: 'ddk-nav-bottom' },
				h(
					'div',
					{ class: 'ddk-device-stamp' },
					icon('hardware'),
					h('div', {}, h('strong', {}, 'GL-X750 / SPITZ'), h('small', {}, 'YOUR FIELD WORKSPACE'))
				),
				h(
					'div',
					{ class: 'ddk-nav-exit' },
					h('a', { href: '/cgi-bin/luci/admin' }, 'LuCI ↗'),
					h('a', { href: '/' }, 'GL.iNet ↗')
				)
			)
		);
		var top = h(
			'div',
			{ class: 'ddk-topbar' },
			h(
				'span',
				{},
				'WORKSPACE',
				h('span', { class: 'ddk-topbar-divider' }, '/'),
				routes.find(function (r) {
					return r[0] === config.page;
				})[1]
			),
			button([icon('search'), 'Find a tool', h('kbd', {}, 'Ctrl K')], 'ddk-search-trigger', openSearch)
		);
		app.before(top);
		app.setAttribute('tabindex', '-1');
		document.body.prepend(h('a', { class: 'ddk-skip', href: '#ddk-app' }, 'Skip to workspace'));
		document.addEventListener('keydown', function (event) {
			if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 'k') {
				event.preventDefault();
				if (!modalStack.length) openSearch();
			}
		});
	}
	function showModal(title, content, actions, onClose) {
		var previous = document.activeElement,
			closed = false,
			body = h('div', { class: 'ddk-modal-content' }, content),
			footer = h('div', { class: 'ddk-modal-footer' }, actions);
		var closeButton = button(icon('close'), 'ddk-icon-button', close, false, 'Close dialog');
		closeButton.setAttribute('aria-label', 'Close dialog');
		var overlay = h(
			'div',
			{ class: 'ddk-modal', role: 'dialog', 'aria-modal': 'true', 'aria-label': title },
			h(
				'div',
				{ class: 'ddk-modal-panel' },
				h('div', { class: 'ddk-modal-head' }, h('h2', {}, title), closeButton),
				body,
				footer
			)
		);
		var background = modalStack.length
			? modalStack[modalStack.length - 1].node
			: document.querySelector('.ddk-shell');
		background.inert = true;
		var modal = { node: overlay, body: body, footer: footer, close: close, busy: false };
		modalStack.push(modal);
		document.body.classList.add('ddk-modal-open');
		function close() {
			if (closed) return;
			if (modal.busy) {
				toast('Please wait for the current request to finish.');
				return;
			}
			closed = true;
			overlay.remove();
			modalStack.splice(modalStack.indexOf(modal), 1);
			background.inert = false;
			if (!modalStack.length) document.body.classList.remove('ddk-modal-open');
			if (previous && previous.isConnected) previous.focus({ preventScroll: true });
			if (onClose) onClose();
		}
		overlay.addEventListener('keydown', function (event) {
			if (event.key === 'Escape') {
				event.preventDefault();
				event.stopPropagation();
				close();
			}
			if (event.key === 'Tab') {
				var focusable = Array.from(
					overlay.querySelectorAll('button,a[href],input,select,textarea,summary,[tabindex="0"]')
				).filter(function (n) {
					return !n.disabled && !n.closest('[hidden]') && n.getClientRects().length;
				});
				var first = focusable[0],
					last = focusable[focusable.length - 1];
				if (event.shiftKey && document.activeElement === first) {
					event.preventDefault();
					last.focus();
				} else if (!event.shiftKey && document.activeElement === last) {
					event.preventDefault();
					first.focus();
				}
			}
		});
		overlay.addEventListener('click', function (event) {
			if (event.target === overlay) close();
		});
		document.body.appendChild(overlay);
		closeButton.focus();
		return modal;
	}
	function setError(node, error) {
		node.textContent = error.message || String(error);
		node.hidden = false;
		node.focus();
	}
	function inlineError() {
		return h('div', { class: 'ddk-alert ddk-alert-error', role: 'alert', tabindex: '-1', hidden: true });
	}
	function busyButton(control, label, operation) {
		return async function () {
			if (control.disabled) return;
			var previous = control.textContent;
			control.disabled = true;
			control.textContent = label;
			try {
				return await operation();
			} finally {
				control.disabled = false;
				control.textContent = previous;
			}
		};
	}
	async function capabilities() {
		if (!capabilityCache) capabilityCache = exec(['capabilities']);
		try {
			return await capabilityCache;
		} catch (error) {
			capabilityCache = null;
			throw error;
		}
	}
	async function openSearch() {
		var search = h('input', {
				type: 'search',
				class: 'ddk-input',
				placeholder: 'Try discovery, Android, packet loss, USB…',
				'aria-label': 'Find a tool'
			}),
			results = h('div', { class: 'ddk-search-results' }),
			modal = showModal('Find your next tool', h('div', {}, search, results));
		search.focus();
		try {
			var modules = await capabilities();
			function draw() {
				var list = [];
				modules.forEach(function (m) {
					(m.actions || []).forEach(function (a) {
						if (guide.matches(a.id, search.value)) list.push({ action: a, module: m });
					});
				});
				replace(
					results,
					h('p', { class: 'ddk-muted', role: 'status' }, list.length + ' matching tools'),
					list.map(function (item) {
						var e = guide.entry(item.action.id);
						return button(
							[h('strong', {}, e.name), h('small', {}, e.summary), icon('arrow')],
							'ddk-search-result',
							function () {
								modal.close();
								launchAction(item.action, item.module);
							}
						);
					})
				);
			}
			search.addEventListener('input', draw);
			draw();
		} catch (error) {
			results.textContent = error.message;
		}
	}
	async function launchAction(action, module, initialOptions) {
		if (!action.enabled || (module && !module.console_enabled)) {
			toast(action.unavailable_reason || 'This tool is unavailable.');
			return;
		}
		var recent = readLocal('ddk-recent-tools', []).filter(function (id) {
			return id !== action.id;
		});
		recent.unshift(action.id);
		remember('ddk-recent-tools', recent.slice(0, 12));
		if (action.parameter_schema === 'operator-v1') return openOperatorAction(action.id, null, initialOptions);
		if (action.execution === 'job') {
			try {
				var job = await exec(['job', 'start', action.id]);
				goToJob(job);
			} catch (error) {
				showModal('Unable to start', h('p', {}, error.message));
			}
			return;
		}
		if (privateIdentityActions[action.id] && !confirmPrivateIdentity(action.id)) return;
		var target = h('div', {});
		showModal(guide.entry(action.id).name, target);
		runInfo(action.id, target);
	}
	function goToJob(job) {
		if (config.page === 'jobs' && jobsRefresh) {
			location.hash = job.id;
			jobsRefresh(job.id);
		} else location.href = config.base + '/jobs#' + encodeURIComponent(job.id);
	}
	async function runInfo(actionId, target) {
		replace(target, h('pre', {}, 'Collecting ' + actionId + '…'));
		try {
			var result = await exec(['info', actionId]);
			var suffix = result.truncated ? '\n\n[Output truncated by the 128 KiB safety limit.]' : '';
			replace(
				target,
				h(
					'div',
					{ class: 'ddk-card-head' },
					h('span', { class: 'ddk-card-kicker' }, 'INFO ACTION'),
					h('h3', {}, result.label)
				),
				h('pre', {}, (result.output || 'No output.') + suffix)
			);
		} catch (error) {
			replace(target, h('div', { class: 'ddk-alert ddk-alert-error' }, error.message));
		}
	}

	function operatorField(field, registry) {
		var control;
		if (field.type === 'boolean') {
			control = h('input', { type: 'checkbox', checked: field.default === true });
		} else if (field.type === 'upload_list') {
			control = h(
				'select',
				{ class: 'ddk-input', multiple: true, size: Math.min(8, Math.max(3, (field.options || []).length)) },
				(field.options || []).map(function (item) {
					return h('option', { value: item.value }, item.label);
				})
			);
		} else if (field.type === 'enum') {
			control = h(
				'select',
				{ class: 'ddk-select' },
				(field.options || []).map(function (option) {
					var value = typeof option === 'object' ? option.value : option;
					var label = typeof option === 'object' ? option.label : option;
					return h(
						'option',
						{ value: value, selected: value === field.default },
						typeof option === 'object' ? label || '(automatic)' : guide.friendly(value) || '(automatic)'
					);
				})
			);
		} else if (field.type === 'target_list' || field.type === 'integer_list' || field.type === 'multiline') {
			var textareaValue = field.type === 'multiline' ? field.default || '' : (field.default || []).join('\n');
			control = h(
				'textarea',
				{ class: 'ddk-input ddk-textarea', rows: field.rows || 3, placeholder: field.placeholder || '' },
				textareaValue
			);
		} else {
			control = h('input', {
				class: 'ddk-input',
				type:
					field.type === 'integer' || field.type === 'number'
						? 'number'
						: field.type === 'secret'
							? 'password'
							: 'text',
				autocomplete: field.type === 'secret' ? 'new-password' : null,
				spellcheck: field.type === 'secret' ? 'false' : null,
				value: field.default == null ? '' : field.default,
				min: field.min,
				max: field.max,
				step: field.step,
				placeholder: field.placeholder || ''
			});
		}
		control.name = field.name;
		if (field.type === 'enum' && !control.options.length)
			control.appendChild(h('option', { value: '' }, 'No compatible device or input found'));
		if (field.type === 'enum' && field.default != null) control.value = String(field.default);
		var wrapper = h(
			'label',
			{ class: 'ddk-operator-field' + (field.type === 'boolean' ? ' ddk-operator-check' : '') },
			h('span', { class: 'ddk-operator-label' }, field.label),
			control,
			field.help ? h('small', {}, field.help) : null
		);
		if (field.suggestions && field.suggestions.length) {
			var listId = 'ddk-suggestions-' + field.name,
				search = h('input', {
					class: 'ddk-input',
					list: listId,
					placeholder: 'Find an installed script',
					'aria-label': 'Find an installed script'
				});
			wrapper.appendChild(
				h(
					'div',
					{},
					search,
					h(
						'datalist',
						{ id: listId },
						field.suggestions.map(function (value) {
							return h('option', { value: value });
						})
					),
					button('Add script', '', function () {
						var value = search.value.trim();
						if (field.suggestions.indexOf(value) < 0) return;
						var values = control.value.split(/\r?\n/).filter(Boolean);
						if (values.indexOf(value) < 0) values.push(value);
						control.value = values.join('\n');
						search.value = '';
					})
				)
			);
		}
		registry[field.name] = { field: field, control: control, wrapper: wrapper };
		return wrapper;
	}

	function applyOperatorConditions(registry) {
		function matches(condition) {
			if (condition.any) return condition.any.some(matches);
			if (condition.all) return condition.all.every(matches);
			if (!registry[condition.field]) return true;
			var source = registry[condition.field].control,
				value = source.type === 'checkbox' ? source.checked : source.value;
			return condition.values
				? condition.values.indexOf(value) >= 0
				: condition.equals !== undefined
					? value === condition.equals
					: value !== condition.not_equals;
		}
		Object.keys(registry).forEach(function (name) {
			var entry = registry[name];
			entry.wrapper.hidden = entry.field.show_when ? !matches(entry.field.show_when) : false;
		});
	}

	function collectOperatorOptions(registry) {
		var options = {};
		Object.keys(registry).forEach(function (name) {
			var entry = registry[name],
				field = entry.field,
				control = entry.control;
			if (entry.wrapper.hidden) {
				options[name] = field.default;
				return;
			}
			if (field.type === 'boolean') options[name] = control.checked;
			else if (field.type === 'upload_list')
				options[name] = Array.from(control.selectedOptions).map(function (item) {
					return item.value;
				});
			else if (field.type === 'integer' || field.type === 'number') {
				if (control.value.trim() === '') throw new Error('Enter a number for ' + field.label + '.');
				options[name] = Number(control.value);
			} else if (field.type === 'target_list')
				options[name] = control.value
					.split(/\r?\n/)
					.map(function (value) {
						return value.trim();
					})
					.filter(Boolean);
			else if (field.type === 'integer_list')
				options[name] = control.value
					.split(/\r?\n/)
					.map(function (value) {
						return value.trim();
					})
					.filter(Boolean)
					.map(Number);
			else if (field.type === 'multiline') options[name] = control.value;
			else options[name] = control.value;
		});
		return options;
	}

	function operatorPresets(actionId, registry) {
		var key = 'ddk-v3-presets:' + actionId,
			saved = [];
		try {
			var parsed = JSON.parse(localStorage.getItem(key) || '[]');
			if (Array.isArray(parsed)) saved = parsed;
		} catch (_) {}
		var selector = h('select', { class: 'ddk-input', 'aria-label': 'Saved preset' });
		var name = h('input', {
			class: 'ddk-input',
			placeholder: 'Preset name',
			maxlength: 80,
			'aria-label': 'Preset name'
		});
		function refresh() {
			selector.replaceChildren.apply(
				selector,
				[h('option', { value: '' }, 'Choose a saved preset')].concat(
					saved.map(function (item, index) {
						return h('option', { value: String(index) }, item.name);
					})
				)
			);
		}
		function persist() {
			localStorage.setItem(key, JSON.stringify(saved));
			refresh();
		}
		refresh();
		return h(
			'details',
			{ class: 'ddk-operator-advanced' },
			h('summary', {}, 'Presets saved in this browser'),
			h(
				'p',
				{},
				'Save settings for repeat visits. Passwords, token seeds, private arguments, and uploaded-file selections are excluded.'
			),
			selector,
			h(
				'div',
				{ class: 'ddk-action-row' },
				button('Load', '', function () {
					var item = selector.value !== '' && saved[Number(selector.value)];
					if (!item) return;
					setOptions(registry, item.options || {});
					name.value = item.name;
				}),
				button('Remove', '', function () {
					if (selector.value === '') return;
					saved.splice(Number(selector.value), 1);
					persist();
				})
			),
			name,
			button('Save current settings', '', function () {
				var label = name.value.trim();
				if (!label) return;
				var options = collectOperatorOptions(registry);
				Object.keys(registry).forEach(function (fieldName) {
					var f = registry[fieldName].field;
					if (
						f.private ||
						f.type === 'secret' ||
						f.type === 'upload_list' ||
						/upload|input|packages/.test(fieldName)
					)
						delete options[fieldName];
				});
				saved = saved.filter(function (item) {
					return item.name !== label;
				});
				saved.unshift({ name: label, options: options });
				try {
					persist();
					name.value = '';
				} catch (error) {
					showModal('Preset storage', h('p', {}, error.message));
				}
			})
		);
	}

	function setOptions(registry, options) {
		Object.keys(options || {}).forEach(function (name) {
			var entry = registry[name];
			if (!entry || entry.field.private || entry.field.type === 'secret') return;
			var value = options[name];
			if (entry.field.type === 'boolean') entry.control.checked = !!value;
			else if (entry.field.type === 'upload_list')
				Array.from(entry.control.options).forEach(function (option) {
					option.selected = Array.isArray(value) && value.indexOf(option.value) >= 0;
				});
			else entry.control.value = Array.isArray(value) ? value.join('\n') : String(value == null ? '' : value);
		});
		applyOperatorConditions(registry);
	}
	async function openOperatorAction(actionId, onStarted, initialOptions) {
		var modal = showModal(
			guide.entry(actionId).name,
			h('div', { class: 'ddk-loading' }, 'Loading current options and connected devices…')
		);
		try {
			var schema = await exec(['action', 'describe', actionId]);
			if (!modal.node.isConnected) return;
			var registry = {},
				primary = h('div', { class: 'ddk-operator-grid' }),
				advanced = h('div', { class: 'ddk-operator-grid' }),
				errorBox = inlineError(),
				e = guide.entry(actionId),
				prepared;
			(schema.fields || []).forEach(function (field) {
				var wrapper = operatorField(field, registry);
				(field.advanced ? advanced : primary).appendChild(wrapper);
			});
			setOptions(registry, initialOptions || {});
			Object.keys(registry).forEach(function (name) {
				var entry = registry[name];
				entry.control.id = 'ddk-field-' + name;
				entry.control.addEventListener('change', function () {
					applyOperatorConditions(registry);
				});
				if (entry.field.type !== 'enum' && entry.field.type !== 'upload_list') return;
				var kind = guide.inputKind(actionId, name, {
					operation: registry.operation ? registry.operation.control.value : ''
				});
				if (!kind) return;
				var upload = button([icon('files'), 'Upload a file'], 'ddk-inline-upload', function () {
					var currentKind = guide.inputKind(actionId, name, {
						operation: registry.operation ? registry.operation.control.value : ''
					});
					showUpload(currentKind, async function (input) {
						await refreshChoices();
						if (entry.field.type === 'upload_list') {
							Array.from(entry.control.options).forEach(function (option) {
								if (option.value === input.id) option.selected = true;
							});
						} else entry.control.value = input.id;
						applyOperatorConditions(registry);
						if (entry.control.value !== input.id && entry.field.type !== 'upload_list')
							toast(
								'File uploaded. This operation requires a different input type; choose a compatible operation.'
							);
					});
				});
				entry.wrapper.appendChild(upload);
			});
			async function refreshChoices() {
				var latest = await exec(['action', 'describe', actionId]);
				(latest.fields || []).forEach(function (field) {
					var entry = registry[field.name];
					if (!entry || !field.options) return;
					var selected =
						entry.field.type === 'upload_list'
							? Array.from(entry.control.selectedOptions).map(function (o) {
									return o.value;
								})
							: [entry.control.value];
					replace(
						entry.control,
						(field.options || []).map(function (option) {
							var value = typeof option === 'object' ? option.value : option;
							return h(
								'option',
								{ value: value, selected: selected.indexOf(value) >= 0 },
								typeof option === 'object' ? option.label : guide.friendly(value) || '(automatic)'
							);
						})
					);
					if (entry.field.type !== 'upload_list' && selected.indexOf(entry.control.value) < 0)
						entry.control.value = '';
					entry.field.options = field.options;
				});
				applyOperatorConditions(registry);
			}
			var refresh = button([icon('refresh'), 'Refresh devices & files'], 'ddk-button-secondary');
			refresh.addEventListener(
				'click',
				busyButton(refresh, 'Refreshing…', async function () {
					try {
						await refreshChoices();
						toast('Device and input choices updated.');
					} catch (error) {
						setError(errorBox, error);
					}
				})
			);
			var presets = (guide.presets[actionId] || []).map(function (preset) {
				return button(preset.name, 'ddk-preset', function () {
					setOptions(registry, preset.options);
					toast(preset.name + ' applied. Review the target before starting.');
				});
			});
			var configure = h(
				'div',
				{},
				h('p', { class: 'ddk-form-intro' }, e.summary),
				h(
					'div',
					{ class: 'ddk-form-guide' },
					h('div', {}, h('span', { class: 'ddk-eyebrow' }, 'YOU’LL GET'), h('p', {}, e.output)),
					h('div', {}, h('span', { class: 'ddk-eyebrow' }, 'BEFORE YOU START'), h('p', {}, e.requires))
				),
				schema.availability && schema.availability.missing.length
					? h(
							'div',
							{ class: 'ddk-alert' },
							'Some operations need: ' +
								schema.availability.missing.join(', ') +
								'. You can still configure the tool and use available operations.'
						)
					: null,
				presets.length
					? h('div', { class: 'ddk-presets' }, h('span', { class: 'ddk-muted' }, 'Quick setup'), presets)
					: null,
				primary,
				advanced.childNodes.length
					? h('details', { class: 'ddk-operator-advanced' }, h('summary', {}, 'Advanced options'), advanced)
					: null,
				operatorPresets(actionId, registry)
			);
			var review = button('Review setup →', 'ddk-button-primary');
			review.addEventListener(
				'click',
				busyButton(review, 'Validating…', async function () {
					modal.busy = true;
					errorBox.hidden = true;
					try {
						prepared = await exec([
							'action',
							'prepare',
							actionId,
							structuredEnvelope(collectOperatorOptions(registry))
						]);
						showReview();
					} catch (error) {
						setError(errorBox, error);
					} finally {
						modal.busy = false;
					}
				})
			);
			function showConfigure() {
				replace(modal.body, errorBox, configure);
				replace(modal.footer, refresh, review);
				review.disabled = false;
				modal.body.scrollTop = 0;
			}
			function showReview() {
				var confirmation =
					prepared.confirmation && prepared.confirmation.required
						? h('input', {
								class: 'ddk-input',
								type: 'text',
								autocomplete: 'off',
								spellcheck: 'false',
								'aria-label': 'Confirmation phrase',
								placeholder: prepared.confirmation.phrase
							})
						: null;
				var reviewBody = h(
					'div',
					{ class: 'ddk-review' },
					h('span', { class: 'ddk-eyebrow' }, 'READY TO RUN'),
					h('h3', {}, prepared.label),
					row(
						'Target',
						jobTarget({
							metadata: { target_summary: prepared.target_summary, options: prepared.normalized_options }
						})
					),
					row(
						'Run time',
						prepared.wall_timeout === 0 ? 'Until finished or stopped' : prepared.wall_timeout + ' seconds'
					),
					row(
						'Results',
						(prepared.artifacts || [])
							.map(function (a) {
								return a.name;
							})
							.join(', ') || 'Native text output'
					),
					h(
						'details',
						{ class: 'ddk-operator-advanced' },
						h('summary', {}, 'Server-built native invocation'),
						h('pre', {}, prepared.argv_preview)
					),
					confirmation
						? h(
								'div',
								{ class: 'ddk-confirmation' },
								h('p', {}, prepared.confirmation.reason),
								h(
									'label',
									{},
									'Type this exact phrase to confirm the operation:',
									h('code', {}, prepared.confirmation.phrase),
									confirmation
								)
							)
						: h('p', { class: 'ddk-muted' }, 'The job opens in your results workspace when started.')
				);
				var back = button('← Edit setup', 'ddk-button-secondary', function () {
						errorBox.hidden = true;
						showConfigure();
						review.focus();
					}),
					start = button('Start job', 'ddk-button-primary', null, !!confirmation);
				if (confirmation)
					confirmation.addEventListener('input', function () {
						start.disabled = confirmation.value !== prepared.confirmation.phrase;
					});
				start.addEventListener(
					'click',
					busyButton(start, 'Starting…', async function () {
						modal.busy = true;
						back.disabled = true;
						errorBox.hidden = true;
						try {
							var args = ['job', 'start', prepared.prepared_id];
							if (confirmation) args.push(base64urlText(confirmation.value));
							var job = await exec(args);
							modal.busy = false;
							modal.close();
							if (onStarted) onStarted(job);
							else goToJob(job);
						} catch (error) {
							showConfigure();
							setError(
								errorBox,
								new Error(error.message + ' Your setup is preserved. Review it again to retry.')
							);
						} finally {
							modal.busy = false;
							back.disabled = false;
						}
					})
				);
				replace(modal.body, errorBox, reviewBody);
				replace(modal.footer, back, start);
				modal.body.scrollTop = 0;
				(confirmation || start).focus();
			}
			showConfigure();
			var first = primary.querySelector('input,select,textarea');
			if (first) first.focus();
		} catch (error) {
			replace(
				modal.body,
				h('div', { class: 'ddk-alert ddk-alert-error', role: 'alert' }, error.message),
				button('Try again', '', function () {
					modal.close();
					openOperatorAction(actionId, onStarted, initialOptions);
				})
			);
		}
	}
	var privateIdentityActions = {
		'android.identify': {
			name: 'Android USB identity',
			excluded:
				'start ADB, open a device transport, or change device state; use the separate structured ADB actions for authorized native work'
		},
		'apple.identify': {
			name: 'Apple mobile USB identity',
			excluded:
				'start usbmuxd, pair, trust, open device services, issue recovery commands, restore, or access filesystems'
		},
		'firmware.identify': {
			name: 'firmware programmer USB identity',
			excluded:
				'open a programmer transport or change device state; use the separate structured firmware actions for authorized native work'
		}
	};

	function confirmPrivateIdentity(actionId) {
		var policy = privateIdentityActions[actionId];
		if (!policy) return false;
		return window.confirm(
			'Show ' +
				policy.name +
				' metadata?\n\n' +
				'Privacy: USB manufacturer, product, topology, interface classes, drivers, and customer-device serial identifier may appear\n' +
				'Source: sanitized read-only sysfs metadata; no device node is opened\n' +
				'This identity request does not: ' +
				policy.excluded +
				'\n' +
				'Retention: authenticated browser response only; not written to jobs, reports, logs, or persistent storage'
		);
	}

	function runPrivateIdentity(actionId, target) {
		if (!confirmPrivateIdentity(actionId)) return;
		runInfo(actionId, target);
	}

	function toolTile(action, module, compact) {
		var entry = guide.entry(action.id),
			favorites = readLocal('ddk-favorite-tools', []),
			favorite = favorites.indexOf(action.id) >= 0;
		var star = button(
			icon('star'),
			'ddk-favorite' + (favorite ? ' is-favorite' : ''),
			function () {
				var list = readLocal('ddk-favorite-tools', []),
					index = list.indexOf(action.id);
				if (index >= 0) list.splice(index, 1);
				else list.push(action.id);
				remember('ddk-favorite-tools', list);
				star.classList.toggle('is-favorite', index < 0);
				star.setAttribute('aria-pressed', String(index < 0));
				document.dispatchEvent(new Event('ddk-favorites'));
			},
			false,
			'Favorite ' + entry.name
		);
		star.setAttribute('aria-label', 'Favorite ' + entry.name);
		star.setAttribute('aria-pressed', String(favorite));
		var launch = button(
			[
				h('span', { class: 'ddk-tool-icon' }, icon(entry.group)),
				h('span', { class: 'ddk-tool-copy' }, h('strong', {}, entry.name), h('span', {}, entry.summary)),
				icon('arrow')
			],
			'ddk-tool-launch',
			function () {
				launchAction(action, module);
			},
			!action.enabled,
			action.unavailable_reason
		);
		launch.dataset.action = action.id;
		return h(
			'article',
			{ class: 'ddk-tool-tile' + (compact ? ' ddk-tool-compact' : ''), 'data-tool': action.id },
			launch,
			compact
				? null
				: h(
						'div',
						{ class: 'ddk-tool-foot' },
						h('span', {}, guide.modules[entry.module] ? guide.modules[entry.module].name : entry.module),
						star
					),
			!action.enabled
				? h('p', { class: 'ddk-alert', 'data-unavailable-action': action.id }, action.unavailable_reason)
				: null
		);
	}
	async function renderOverview() {
		var values = await Promise.all([exec(['status']), capabilities(), exec(['job', 'list'])]),
			status = values[0],
			modules = values[1],
			jobs = values[2],
			system = status.system,
			network = status.network,
			hardware = status.hardware,
			actions = {};
		modules.forEach(function (m) {
			m.actions.forEach(function (a) {
				actions[a.id] = { action: a, module: m };
			});
		});
		var active = jobs.filter(activeJob),
			recent = jobs
				.slice()
				.sort(function (a, b) {
					return Number(b.metadata.created_at || 0) - Number(a.metadata.created_at || 0);
				})
				.slice(0, 4);
		var hero = h(
			'section',
			{ class: 'ddk-hero' },
			h(
				'div',
				{ class: 'ddk-hero-copy' },
				h('span', { class: 'ddk-eyebrow' }, 'SMALL DEVICE. SERIOUS CAPABILITY.'),
				h('h2', {}, 'Your field kit.', h('br'), h('span', {}, 'Ready for what’s next.')),
				h(
					'p',
					{},
					'Discover the network. Diagnose the device. Get the evidence you need to move the job forward.'
				),
				h(
					'div',
					{ class: 'ddk-action-row' },
					link(['Open tool library', icon('arrow')], 'tools', 'ddk-button ddk-button-primary'),
					link('View jobs & cases', 'jobs')
				)
			),
			h(
				'div',
				{ class: 'ddk-hero-visual', 'aria-hidden': 'true' },
				h('div', { class: 'ddk-orbit ddk-orbit-one' }),
				h('div', { class: 'ddk-orbit ddk-orbit-two' }),
				h(
					'div',
					{ class: 'ddk-device-illustration' },
					h('span', { class: 'ddk-device-antenna' }),
					h('span', { class: 'ddk-device-antenna second' }),
					h(
						'div',
						{ class: 'ddk-device-face' },
						h('img', { src: '/luci-static/resources/ddk/brand/dropkick-logo.png', alt: '' }),
						h('span', {}, 'FIELD CONSOLE'),
						h('div', { class: 'ddk-device-leds' }, h('i'), h('i'), h('i'))
					)
				),
				h('span', { class: 'ddk-visual-label' }, 'GL-X750 / BUILT TO GO')
			)
		);
		var metrics = h(
			'div',
			{ class: 'ddk-health-strip' },
			h(
				'div',
				{},
				h('span', {}, 'APPLIANCE'),
				h('strong', {}, system.hostname),
				h('small', {}, 'Up ' + formatUptime(system.uptime_seconds))
			),
			h(
				'div',
				{},
				h('span', {}, 'LAN ADDRESS'),
				h('strong', {}, network.lan_ip || 'Unassigned'),
				h('small', {}, network.wan_up ? 'WAN connected' : 'Check WAN connectivity')
			),
			h(
				'div',
				{},
				h('span', {}, 'AVAILABLE STORAGE'),
				h('strong', {}, formatBytes(system.storage.available)),
				h('small', {}, formatBytes(system.memory.available) + ' memory available')
			),
			h(
				'div',
				{},
				h('span', {}, 'RUNNING JOBS'),
				h('strong', {}, active.length + ' / 2'),
				h(
					'small',
					{},
					jobs.filter(function (j) {
						return j.saved;
					}).length + ' saved cases'
				)
			)
		);
		var favorites = readLocal('ddk-favorite-tools', []).filter(function (id) {
			return actions[id];
		});
		replace(
			app,
			brand('Overview', 'Everything you need for the next service call.'),
			hero,
			metrics,
			active.length
				? h(
						'div',
						{ class: 'ddk-active-banner' },
						icon('activity'),
						h(
							'span',
							{},
							active.length +
								' job' +
								(active.length === 1 ? ' is' : 's are') +
								' running. Open the workspace to watch results or stop a session.'
						),
						link('View active jobs', 'jobs?filter=active')
					)
				: null,
			sectionHeading(
				'Start a workflow',
				'A useful starting point. Every native option is still within reach.'
			),
			h(
				'div',
				{ class: 'ddk-quick-grid' },
				guide.quick
					.filter(function (id) {
						return actions[id];
					})
					.map(function (id) {
						return toolTile(actions[id].action, actions[id].module, true);
					})
			),
			favorites.length ? sectionHeading('Your favorites', 'Saved in this browser') : null,
			favorites.length
				? h(
						'div',
						{ class: 'ddk-quick-grid' },
						favorites.map(function (id) {
							return toolTile(actions[id].action, actions[id].module, true);
						})
					)
				: null,
			h(
				'div',
				{ class: 'ddk-overview-bottom' },
				card(
					'Recent work',
					'PICK UP WHERE YOU LEFT OFF',
					recent.length
						? recent.map(function (job) {
								return h(
									'a',
									{ class: 'ddk-recent-job', href: config.base + '/jobs#' + job.id },
									icon('jobs'),
									h(
										'span',
										{},
										h('strong', {}, job.metadata.case_label || guide.entry(job.metadata.action_id).name),
										h('small', {}, jobTarget(job) || job.id)
									),
									statePill(job.status)
								);
							})
						: h(
								'div',
								{ class: 'ddk-empty' },
								icon('jobs'),
								h('h3', {}, 'Your next case starts here'),
								h('p', {}, 'Run a tool to see its live output, keep results, and build a reusable case.')
							)
				),
				card('Appliance at a glance', 'LIVE HARDWARE', [
					row('USB devices', hardware.usb_devices.length),
					row('Serial adapters', (hardware.serial_summary || {}).reviewed_general_purpose || 0),
					row('Camera nodes', hardware.video_devices.length),
					row('CAN interfaces', hardware.can_interfaces.join(', ') || 'None connected'),
					row('Tailscale', status.remote_access.tailscale_ip || 'Unavailable'),
					link('Inspect connected hardware', 'tools?group=hardware')
				])
			),
			h(
				'details',
				{ class: 'ddk-operator-advanced' },
				h('summary', {}, 'System & network details'),
				h(
					'div',
					{ class: 'ddk-two-column' },
					h(
						'div',
						{},
						row('Model', system.model),
						row('OpenWrt', system.openwrt),
						row('Kernel', system.kernel),
						row('Load', system.load.join(' / ')),
						row('Packages', system.package_count),
						row('Swap', system.swap.active ? formatBytes(system.swap.total) + ' active' : 'Inactive')
					),
					h(
						'div',
						{},
						row('WAN interface', network.wan_interface),
						row('WAN address', network.wan_ip),
						row('Default route', network.default_route),
						row('DNS', network.dns.join(', ')),
						row('Interfaces', network.interfaces.length)
					)
				),
				h(
					'div',
					{ class: 'ddk-action-row' },
					[
						'network.interfaces',
						'network.routes',
						'hardware.usb',
						'serial.inspect',
						'remote.tailscale',
						'storage.mounts',
						'system.memory'
					].map(function (id) {
						return button(guide.entry(id).name, 'ddk-button-secondary', function () {
							if (actions[id]) launchAction(actions[id].action, actions[id].module);
							else {
								var target = h('div');
								showModal(guide.entry(id).name, target);
								runInfo(id, target);
							}
						});
					})
				)
			)
		);
	}
	async function renderTools() {
		var modules = await capabilities(),
			params = new URLSearchParams(location.search),
			selectedGroup = params.get('group') || '',
			view = 'all',
			search = h('input', {
				class: 'ddk-input',
				type: 'search',
				placeholder: 'Search by task, tool or hardware…',
				'aria-label': 'Search tool library',
				value: params.get('q') || ''
			}),
			count = h('p', { class: 'ddk-library-count', role: 'status' }),
			grid = h('div', { class: 'ddk-tool-grid' }),
			empty = h(
				'div',
				{ class: 'ddk-empty', hidden: true },
				icon('search'),
				h('h3', {}, 'No matching tools'),
				h('p', {}, 'Try a native tool name, a task, or another category.'),
				button('Clear filters', '', function () {
					search.value = '';
					selectedGroup = '';
					view = 'all';
					filter();
				})
			),
			cards = [];
		modules.forEach(function (module) {
			(module.actions || []).forEach(function (action) {
				var node = toolTile(action, module, false);
				cards.push({ id: action.id, node: node, module: module, entry: guide.entry(action.id) });
			});
		});
		cards.sort(function (a, b) {
			return a.entry.name.localeCompare(b.entry.name);
		});
		cards.forEach(function (c) {
			grid.appendChild(c.node);
		});
		var groups = h(
			'div',
			{ class: 'ddk-library-groups', 'aria-label': 'Tool categories' },
			[{ id: '', name: 'All tools', icon: 'tools' }].concat(guide.groups).map(function (group) {
				var control = button([icon(group.id || 'tools'), group.name], 'ddk-filter', function () {
					selectedGroup = group.id;
					filter();
				});
				control.dataset.group = group.id;
				return control;
			})
		);
		var views = h(
			'div',
			{ class: 'ddk-segments', 'aria-label': 'Tool collection' },
			[
				['all', 'All'],
				['favorites', 'Favorites'],
				['recent', 'Recently used']
			].map(function (item) {
				var control = button(item[1], '', function () {
					view = item[0];
					filter();
				});
				control.dataset.view = item[0];
				return control;
			})
		);
		function filter() {
			var favorites = readLocal('ddk-favorite-tools', []),
				recent = readLocal('ddk-recent-tools', []),
				visible = 0;
			cards.forEach(function (c) {
				var match =
					(!selectedGroup || c.entry.group === selectedGroup) &&
					guide.matches(c.id, search.value) &&
					(view === 'all' || (view === 'favorites' ? favorites : recent).indexOf(c.id) >= 0);
				c.node.hidden = !match;
				if (match) visible++;
			});
			count.textContent = visible + ' of ' + cards.length + ' tools · ' + modules.length + ' modules';
			empty.hidden = visible > 0;
			groups.querySelectorAll('button').forEach(function (b) {
				b.setAttribute('aria-pressed', String(b.dataset.group === selectedGroup));
			});
			views.querySelectorAll('button').forEach(function (b) {
				b.setAttribute('aria-pressed', String(b.dataset.view === view));
			});
		}
		search.addEventListener('input', filter);
		document.addEventListener('ddk-favorites', filter);
		replace(
			app,
			brand('Tool library', 'Find the right tool. Configure it once. Follow the results.'),
			h('div', { class: 'ddk-library-search' }, icon('search'), search),
			groups,
			h('div', { class: 'ddk-library-meta' }, count, views),
			grid,
			empty,
			h(
				'p',
				{ class: 'ddk-muted' },
				'Connect the required hardware, then refresh devices inside the tool. Missing hardware does not hide its configuration.'
			)
		);
		filter();
		var actionId = params.get('action');
		if (actionId) {
			var chosen;
			modules.forEach(function (m) {
				m.actions.forEach(function (a) {
					if (a.id === actionId) chosen = { action: a, module: m };
				});
			});
			if (chosen) launchAction(chosen.action, chosen.module);
		}
	}
	async function renderPackages() {
		var packages = await exec(['packages']),
			page = 0;
		var search = h('input', {
			class: 'ddk-input',
			type: 'search',
			placeholder: 'Search package name or version…'
		});
		var category = h(
			'select',
			{ class: 'ddk-select' },
			[
				'',
				'Applications',
				'LuCI',
				'Kernel',
				'Libraries',
				'Python',
				'Hardware',
				'Networking',
				'Monitoring'
			].map(function (name) {
				return h('option', { value: name }, name || 'All');
			})
		);
		var size = h(
			'select',
			{ class: 'ddk-select' },
			[50, 100, 250, 0].map(function (value) {
				return h('option', { value: value, selected: value === 100 }, value ? value + ' rows' : 'Show all');
			})
		);
		var count = h('span'),
			pageLabel = h('span'),
			tableWrap = h('div', { class: 'ddk-table-wrap' });
		var previous = button('Previous', 'ddk-button-secondary'),
			next = button('Next', 'ddk-button-secondary');
		function render(reset) {
			if (reset) page = 0;
			var query = search.value.toLowerCase();
			var filtered = packages.filter(function (item) {
				return (
					(!category.value || item.category === category.value) &&
					(!query ||
						item.name.toLowerCase().indexOf(query) >= 0 ||
						item.version.toLowerCase().indexOf(query) >= 0)
				);
			});
			var pageSize = Number(size.value),
				pages = pageSize ? Math.max(1, Math.ceil(filtered.length / pageSize)) : 1;
			page = Math.max(0, Math.min(page, pages - 1));
			var visible = pageSize ? filtered.slice(page * pageSize, page * pageSize + pageSize) : filtered;
			var tbody = h(
				'tbody',
				{},
				visible.map(function (item) {
					return h('tr', {}, h('td', {}, item.name), h('td', {}, item.version), h('td', {}, item.category));
				})
			);
			replace(
				tableWrap,
				h(
					'table',
					{ class: 'ddk-table' },
					h('thead', {}, h('tr', {}, h('th', {}, 'Package'), h('th', {}, 'Version'), h('th', {}, 'Type'))),
					tbody
				)
			);
			count.textContent = filtered.length + ' matching / ' + packages.length + ' installed';
			pageLabel.textContent = 'Page ' + (page + 1) + ' of ' + pages;
			previous.disabled = page <= 0;
			next.disabled = page >= pages - 1;
		}
		search.addEventListener('input', function () {
			render(true);
		});
		category.addEventListener('change', function () {
			render(true);
		});
		size.addEventListener('change', function () {
			render(true);
		});
		previous.addEventListener('click', function () {
			page--;
			render(false);
		});
		next.addEventListener('click', function () {
			page++;
			render(false);
		});
		replace(
			app,
			brand('Packages', 'Search the software installed on your appliance.'),
			h('div', { class: 'ddk-toolbar' }, search, category, size),
			h('div', { class: 'ddk-table-meta' }, count, pageLabel),
			tableWrap,
			h('div', { class: 'ddk-action-row ddk-actions-end' }, previous, next)
		);
		render(true);
	}

	function saveBlob(blob, filename) {
		var url = URL.createObjectURL(blob);
		var link = h('a', { href: url, download: filename });
		document.body.appendChild(link);
		link.click();
		link.remove();
		URL.revokeObjectURL(url);
	}
	async function loadSnapshot(job) {
		if (!job || !/^job-\d+-\d+$/.test(job.id) || !job.artifact || job.artifact.kind !== 'camera_snapshot')
			throw new Error('The requested camera artifact did not match the DDK client allowlist.');
		var expectedSize = Number(job.artifact.size || 0);
		if (!Number.isInteger(expectedSize) || expectedSize <= 1024 || expectedSize > 262144)
			throw new Error('The camera artifact metadata failed its size boundary.');
		var filename = 'ddk-camera-' + job.id + '.jpg';
		var path = '/tmp/ddk/jobs/' + job.id + '/snapshot.jpg';
		var body = new URLSearchParams({ sessionid: config.session, path: path, filename: filename });
		var response = await fetch(config.download, {
			method: 'POST',
			credentials: 'same-origin',
			headers: { 'Content-Type': 'application/x-www-form-urlencoded;charset=UTF-8' },
			body: body.toString()
		});
		if (!response.ok)
			throw new Error(
				response.status === 403
					? 'LuCI session or camera-artifact ACL rejected the request.'
					: 'Camera artifact request failed with HTTP ' + response.status + '.'
			);
		var blob = await response.blob();
		if (blob.size !== expectedSize || blob.size > 262144)
			throw new Error('The downloaded camera artifact did not match its authenticated metadata.');
		return { blob: new Blob([blob], { type: 'image/jpeg' }), filename: filename };
	}
	async function viewSnapshot(job, shouldDownload) {
		try {
			var snapshot = await loadSnapshot(job);
			if (shouldDownload) {
				saveBlob(snapshot.blob, snapshot.filename);
				return;
			}
			var url = URL.createObjectURL(snapshot.blob);
			showModal(
				'Camera Still — ' + job.id,
				h(
					'div',
					{ class: 'ddk-snapshot' },
					h('img', { src: url, alt: 'Transient camera still captured by the field console' }),
					h(
						'p',
						{},
						'Transient /tmp artifact · ' +
							formatBytes(snapshot.blob.size) +
							' · review for private information before sharing.'
					)
				),
				h(
					'div',
					{ class: 'ddk-action-row ddk-actions-end' },
					button('Download JPEG', '', function () {
						saveBlob(snapshot.blob, snapshot.filename);
					})
				),
				function () {
					URL.revokeObjectURL(url);
				}
			);
		} catch (error) {
			showModal('Camera Artifact Error', h('div', { class: 'ddk-alert ddk-alert-error' }, error.message));
		}
	}
	async function downloadOperatorArtifact(job, artifact) {
		var preview = arguments[2] === true;
		try {
			if (
				!job ||
				!/^job-\d+-\d+$/.test(job.id) ||
				!artifact ||
				!/^[A-Za-z0-9][A-Za-z0-9_.-]+$/.test(artifact.name) ||
				artifact.name.indexOf('..') >= 0
			)
				throw new Error('The requested artifact did not match the DDK client allowlist.');
			if (
				typeof artifact.filename !== 'string' ||
				!/^ddk-job-\d+-\d+-[A-Za-z0-9][A-Za-z0-9_.-]+$/.test(artifact.filename) ||
				artifact.filename.indexOf('..') >= 0
			)
				throw new Error('The artifact download name did not match the DDK client allowlist.');
			var expectedSize = Number(artifact.size || 0);
			if (!Number.isInteger(expectedSize) || expectedSize <= 0 || expectedSize > 8796093022208)
				throw new Error('The artifact metadata failed its size boundary.');
			var storage = artifact.storage || 'tmp';
			if (storage !== 'tmp' && storage !== 'extroot')
				throw new Error('The artifact storage class was not recognized.');
			var path =
				(storage === 'extroot'
					? '/overlay/ddk-field-console/artifacts/' + job.id
					: '/tmp/ddk/jobs/' + job.id) +
				'/' +
				artifact.name;
			if (expectedSize > 16777216) {
				var frameName = 'ddk-download-' + Date.now();
				var frame = h('iframe', { name: frameName, hidden: true });
				var form = h(
					'form',
					{ method: 'POST', action: config.download, target: frameName, hidden: true },
					h('input', { type: 'hidden', name: 'sessionid', value: config.session }),
					h('input', { type: 'hidden', name: 'path', value: path }),
					h('input', { type: 'hidden', name: 'filename', value: artifact.filename })
				);
				document.body.appendChild(frame);
				document.body.appendChild(form);
				form.submit();
				setTimeout(function () {
					form.remove();
				}, 1000);
				setTimeout(
					function () {
						frame.remove();
					},
					2 * 60 * 60 * 1000
				);
				return;
			}
			var body = new URLSearchParams({ sessionid: config.session, path: path, filename: artifact.filename });
			var response = await fetch(config.download, {
				method: 'POST',
				credentials: 'same-origin',
				headers: { 'Content-Type': 'application/x-www-form-urlencoded;charset=UTF-8' },
				body: body.toString()
			});
			if (!response.ok)
				throw new Error(
					response.status === 403
						? 'LuCI session or artifact ACL rejected the request.'
						: 'Artifact request failed with HTTP ' + response.status + '.'
				);
			var blob = await response.blob();
			if (blob.size !== expectedSize || blob.size > 16777216)
				throw new Error('The downloaded artifact did not match its authenticated metadata.');
			var typed = new Blob([blob], { type: artifact.content_type || 'application/octet-stream' });
			if (preview && ['image/jpeg', 'image/png'].indexOf(artifact.content_type) >= 0) {
				var url = URL.createObjectURL(typed);
				showModal(
					artifact.name,
					h(
						'div',
						{ class: 'ddk-snapshot' },
						h('img', { src: url, alt: 'Image produced by the selected job' })
					),
					button('Download image', '', function () {
						saveBlob(typed, artifact.filename);
					}),
					function () {
						URL.revokeObjectURL(url);
					}
				);
			} else saveBlob(typed, artifact.filename);
		} catch (error) {
			showModal('Artifact Error', h('div', { class: 'ddk-alert ddk-alert-error' }, error.message));
		}
	}
	function openSerialConsole(job) {
		var output = h('pre', { class: 'ddk-job-output' }, job.stdout || 'Waiting for serial output…');
		var input = h('textarea', { class: 'ddk-input', rows: 3, 'aria-label': 'Serial input' });
		var encoding = h(
			'select',
			{ class: 'ddk-input', 'aria-label': 'Encoding' },
			h('option', { value: 'text' }, 'Text'),
			h('option', { value: 'hex' }, 'Hex bytes')
		);
		var ending = h(
			'select',
			{ class: 'ddk-input', 'aria-label': 'Line ending' },
			h('option', { value: 'crlf' }, 'CR + LF'),
			h('option', { value: 'cr' }, 'CR'),
			h('option', { value: 'lf' }, 'LF'),
			h('option', { value: 'none' }, 'No line ending')
		);
		var message = h('p', {}),
			closed = false,
			timer;
		async function send() {
			try {
				var result = await exec([
					'job',
					'send',
					job.id,
					structuredEnvelope({ data: input.value, encoding: encoding.value, ending: ending.value })
				]);
				message.textContent = result.queued_bytes + ' bytes queued';
				input.value = '';
			} catch (error) {
				message.textContent = error.message;
			}
		}
		input.addEventListener('keydown', function (event) {
			if (event.key === 'Enter' && event.ctrlKey) {
				event.preventDefault();
				send();
			}
		});
		showModal(
			'Serial console · ' + jobTarget(job),
			h(
				'div',
				{},
				output,
				input,
				h('div', { class: 'ddk-action-row' }, encoding, ending, button('Send (Ctrl+Enter)', '', send)),
				message
			),
			null,
			function () {
				closed = true;
				clearTimeout(timer);
			}
		);
		async function tick() {
			try {
				var state = await exec(['job', 'status', job.id]);
				if (closed) return;
				output.textContent = state.stdout || '';
				output.scrollTop = output.scrollHeight;
				if (state.status !== 'running') {
					message.textContent = 'Session ' + state.status;
					return;
				}
			} catch (error) {
				message.textContent = error.message;
			}
			if (!closed) timer = setTimeout(tick, 750);
		}
		tick();
		input.focus();
	}
	var uploadKinds = {
		forensics_input: {
			label: 'Forensic analysis input',
			maximum: 8796093022208,
			extensions:
				'.bin, .exe, .dll, .elf, .so, .apk, .zip, .img, .raw, .txt, .rules, .yar, .yara, .json, .cfg, .pcap, .pcapng'
		},
		capture_input: {
			label: 'Packet replay capture',
			maximum: 8796093022208,
			extensions: '.pcap, .pcapng, .cap'
		},
		firmware_image: {
			label: 'Firmware / programmer image',
			maximum: 8796093022208,
			extensions: '.bin, .hex, .elf, .uf2, .dfu, .fw, .rom, .img'
		},
		storage_image: {
			label: 'Storage / recovery image',
			maximum: 8796093022208,
			extensions: '.raw, .img, .bin, .dd, .squashfs, .sqfs'
		},
		android_package: { label: 'Android package', maximum: 8796093022208, extensions: '.apk, .apks, .zip' },
		android_backup: { label: 'Android ADB backup', maximum: 8796093022208, extensions: '.ab' },
		apple_restore: { label: 'Apple IPSW restore archive', maximum: 8796093022208, extensions: '.ipsw, .zip' },
		apple_recovery_input: {
			label: 'Apple recovery / DFU input',
			maximum: 8796093022208,
			extensions: '.bin, .img, .dfu, .ibss, .ibec, .payload, .txt, .script, .cfg'
		},
		apple_ticket: { label: 'Apple AP ticket', maximum: 1048576, extensions: '.shsh, .ticket, .bin, .plist' },
		device_input: {
			label: 'Device workflow input',
			maximum: 8796093022208,
			extensions: '.bin, .hex, .elf, .uf2, .dfu, .fw, .rom, .img, .cfg, .json, .zip, .tar, .gz'
		}
	};
	function jobOutput(job) {
		return (
			(job.stdout ? '[STDOUT]\n' + job.stdout : '') +
			(job.stderr ? (job.stdout ? '\n\n' : '') + '[STDERR]\n' + job.stderr : '')
		);
	}
	async function copyText(text, control) {
		try {
			if (navigator.clipboard && window.isSecureContext) await navigator.clipboard.writeText(text);
			else {
				var node = h('textarea', { class: 'ddk-copy-source' }, text);
				document.body.appendChild(node);
				node.select();
				var copied = document.execCommand('copy');
				node.remove();
				if (!copied) throw new Error('Select the output and copy it with your keyboard.');
			}
			toast('Copied to clipboard.');
		} catch (error) {
			toast(error.message);
		}
		if (control) control.focus();
	}
	function chooseInput(input) {
		var choices = guide.forInput(input.kind, input.id),
			modal = showModal(
				'Use ' + input.original_name,
				h(
					'div',
					{},
					h('p', {}, 'The file is ready. Choose a tool to review its next use.'),
					choices.map(function (choice) {
						return button(
							[
								h('strong', {}, guide.entry(choice.id).name),
								h('small', {}, guide.entry(choice.id).summary),
								icon('arrow')
							],
							'ddk-search-result',
							function () {
								modal.close();
								openOperatorAction(choice.id, null, choice.options);
							}
						);
					})
				)
			);
	}
	async function reuseArtifact(job, artifact) {
		var kind = guide.fileKind(artifact),
			message = h('p', {}, 'Preparing ' + artifact.name + '…'),
			modal = showModal('Prepare an input', message);
		modal.busy = true;
		try {
			var input = await exec(['job', 'reuse', job.id, artifact.name, kind]);
			input = await waitForSealed(input, function (value) {
				message.textContent = value;
			});
			modal.busy = false;
			modal.close();
			chooseInput(input);
		} catch (error) {
			modal.busy = false;
			message.textContent = error.message;
		}
	}
	function summaryNode(job) {
		var analysis = guide.analyze(job),
			source = h(
				'div',
				{ class: 'ddk-result-summary' },
				h('span', { class: 'ddk-eyebrow' }, 'OBSERVED RESULTS'),
				h('h3', {}, analysis.title),
				h('p', {}, analysis.description),
				analysis.errorHint ? h('div', { class: 'ddk-alert' }, analysis.errorHint) : null,
				analysis.metrics.length
					? h(
							'div',
							{ class: 'ddk-result-metrics' },
							analysis.metrics.map(function (m) {
								return h('div', {}, h('strong', {}, m.value), h('span', {}, m.label));
							})
						)
					: null
			);
		if (analysis.rows.length) {
			var shown = 100,
				body = h('tbody'),
				more = button('Show more rows', 'ddk-button-secondary', function () {
					shown += 100;
					draw();
				});
			function draw() {
				replace(
					body,
					analysis.rows.slice(0, shown).map(function (values) {
						return h(
							'tr',
							{},
							values.map(function (value) {
								return h('td', {}, value);
							})
						);
					})
				);
				more.hidden = shown >= analysis.rows.length;
			}
			draw();
			source.append(
				h(
					'div',
					{ class: 'ddk-table-wrap' },
					h(
						'table',
						{ class: 'ddk-table' },
						h(
							'thead',
							{},
							h(
								'tr',
								{},
								analysis.columns.map(function (label) {
									return h('th', {}, label);
								})
							)
						),
						body
					)
				),
				h(
					'small',
					{},
					analysis.rows.length +
						(analysis.rows.length === 1 ? ' row in available output' : ' rows in available output')
				),
				more
			);
		} else if (analysis.hosts.length)
			source.appendChild(
				h(
					'div',
					{ class: 'ddk-host-list' },
					analysis.hosts.map(function (host) {
						return h('code', {}, host);
					})
				)
			);
		if (analysis.note) source.appendChild(h('p', { class: 'ddk-muted' }, analysis.note));
		if (analysis.suggestions.length)
			source.append(
				h(
					'div',
					{ class: 'ddk-next-steps' },
					sectionHeading('Where to go next', 'Suggested tools. Review the target and setup before running.'),
					analysis.suggestions.map(function (next) {
						var e = guide.entry(next.id);
						return button(
							[
								h('strong', {}, e.name),
								h(
									'small',
									{},
									e.summary +
										(next.options.targets
											? ' ' + next.options.targets.length + ' observed target(s) carried forward.'
											: '')
								),
								icon('arrow')
							],
							'ddk-search-result',
							function () {
								openOperatorAction(next.id, null, next.options);
							}
						);
					})
				)
			);
		return source;
	}
	async function renderJobs() {
		var listNode = h('div', { class: 'ddk-job-list' }),
			pane = h('section', { class: 'ddk-job-detail', 'aria-label': 'Selected job' }),
			search = h('input', {
				type: 'search',
				class: 'ddk-input',
				placeholder: 'Find a case, tool or target…',
				'aria-label': 'Search jobs'
			}),
			count = h('span', { class: 'ddk-muted', role: 'status' }),
			errorBox = inlineError(),
			jobs = [],
			selected = location.hash.slice(1),
			filter = new URLSearchParams(location.search).get('filter') || 'all',
			timer,
			busy = false,
			currentSignature = '',
			listSignature = '',
			outputNode,
			summaryContainer,
			filesContainer,
			currentJob,
			tab = 'summary',
			follow = true;
		var refresh = button([icon('refresh'), 'Refresh'], 'ddk-button-secondary', function () {
				refreshJobs();
			}),
			reportButton = button('System report', 'ddk-button-secondary');
		reportButton.addEventListener(
			'click',
			busyButton(reportButton, 'Starting…', async function () {
				try {
					goToJob(await exec(['job', 'start', 'report.system']));
				} catch (error) {
					setError(errorBox, error);
				}
			})
		);
		var filters = h(
			'div',
			{ class: 'ddk-segments', 'aria-label': 'Filter jobs' },
			[
				['all', 'All work'],
				['active', 'Active'],
				['saved', 'Saved cases'],
				['attention', 'Needs attention']
			].map(function (item) {
				var b = button(item[1], '', function () {
					filter = item[0];
					drawList();
				});
				b.dataset.filter = item[0];
				return b;
			})
		);
		function filteredJobs() {
			var q = search.value.toLowerCase().trim();
			return jobs.filter(function (job) {
				return (
					(filter === 'all' ||
						(filter === 'active' && activeJob(job)) ||
						(filter === 'saved' && job.saved) ||
						(filter === 'attention' &&
							['failed', 'stopped', 'timed_out', 'aborted'].indexOf(job.status) >= 0)) &&
					(!q ||
						[
							job.id,
							job.metadata.case_label,
							job.metadata.label,
							jobTarget(job),
							job.metadata.action_id,
							timeText(job.metadata.created_at)
						]
							.join(' ')
							.toLowerCase()
							.indexOf(q) >= 0)
				);
			});
		}
		function select(id) {
			selected = id;
			currentSignature = '';
			history.replaceState(null, '', '#' + id);
			drawList();
			drawDetail();
		}
		function drawList() {
			var visible = filteredJobs();
			filters.querySelectorAll('button').forEach(function (b) {
				b.setAttribute('aria-pressed', String(filter === b.dataset.filter));
			});
			count.textContent = visible.length + ' job' + (visible.length === 1 ? '' : 's');
			var signature =
				JSON.stringify(
					visible.map(function (j) {
						return [j.id, j.status, j.saved, j.metadata.case_label, j.metadata.target_summary];
					})
				) + selected;
			if (signature === listSignature) return;
			listSignature = signature;
			var focused = document.activeElement.closest && document.activeElement.closest('[data-job]'),
				focusId = focused && focused.dataset.job;
			replace(
				listNode,
				visible.length
					? visible.map(function (job) {
							var b = button(
								[
									h(
										'div',
										{ class: 'ddk-job-choice-head' },
										statePill(job.status),
										job.saved ? h('span', { class: 'ddk-saved-mark' }, 'SAVED') : null
									),
									h('strong', {}, job.metadata.case_label || guide.entry(job.metadata.action_id).name),
									h('span', { class: 'ddk-job-target' }, jobTarget(job) || job.id),
									h('small', {}, timeText(job.metadata.created_at))
								],
								'ddk-job-choice' + (job.id === selected ? ' is-selected' : ''),
								function () {
									select(job.id);
								}
							);
							b.dataset.job = job.id;
							b.setAttribute('aria-pressed', String(job.id === selected));
							return b;
						})
					: h(
							'div',
							{ class: 'ddk-empty' },
							icon('jobs'),
							h('h3', {}, 'No jobs here yet'),
							h(
								'p',
								{},
								search.value
									? 'Try another search or filter.'
									: 'Start a tool to collect results. Finished jobs can be saved as cases.'
							),
							link('Open tool library', 'tools')
						)
			);
			if (focusId) {
				var replacement = listNode.querySelector('[data-job="' + focusId + '"]');
				if (replacement) replacement.focus({ preventScroll: true });
			}
		}
		function drawFiles(job) {
			replace(
				filesContainer,
				(job.artifacts || []).length
					? (job.artifacts || []).map(function (artifact) {
							return h(
								'article',
								{ class: 'ddk-result-file' },
								icon('files'),
								h(
									'div',
									{},
									h('strong', {}, artifact.name),
									h('small', {}, formatBytes(artifact.size) + (artifact.partial ? ' · Partial result' : ''))
								),
								h(
									'div',
									{ class: 'ddk-action-row' },
									button('Download', 'ddk-button-secondary', function () {
										downloadOperatorArtifact(job, artifact);
									}),
									['image/jpeg', 'image/png'].indexOf(artifact.content_type) >= 0 && artifact.size <= 16777216
										? button('Preview', 'ddk-button-secondary', function () {
												downloadOperatorArtifact(job, artifact, true);
											})
										: null,
									guide.fileKind(artifact)
										? button('Use as input →', '', function () {
												reuseArtifact(job, artifact);
											})
										: null
								)
							);
						})
					: h(
							'div',
							{ class: 'ddk-empty' },
							h('h3', {}, 'No files available yet'),
							h(
								'p',
								{},
								activeJob(job)
									? 'This tool may create files as it runs or when it finishes.'
									: 'This job has text output only. You can download it from the Output tab.'
							)
						)
			);
			if (job.artifact && job.artifact.kind === 'camera_snapshot')
				filesContainer.appendChild(
					button('View camera snapshot', '', function () {
						viewSnapshot(job, false);
					})
				);
		}
		function drawDetail() {
			var job = jobs.find(function (j) {
				return j.id === selected;
			});
			if (!job) {
				pane.removeAttribute('data-selected-job');
				replace(
					pane,
					h(
						'div',
						{ class: 'ddk-empty' },
						icon('jobs'),
						h('h3', {}, 'Select a job'),
						h('p', {}, 'Summary, live output, files and next steps appear here.')
					)
				);
				currentSignature = '';
				return;
			}
			pane.dataset.selectedJob = job.id;
			currentJob = job;
			var signature = JSON.stringify([
				job.id,
				job.status,
				job.saved,
				job.metadata.case_label,
				(job.artifacts || []).map(function (a) {
					return [a.name, a.size, a.partial];
				})
			]);
			if (signature !== currentSignature) {
				var preservedOutput =
					outputNode && outputNode.dataset.outputJob === job.id ? outputNode.closest('[data-panel=output]') : null;
				var previousFocus = document.activeElement;
				var priorScroll = pane.scrollTop,
					focusedKey = document.activeElement.dataset && document.activeElement.dataset.control;
				currentSignature = signature;
				var title = job.metadata.case_label || guide.entry(job.metadata.action_id).name,
					actions = h('div', { class: 'ddk-action-row' });
				function action(label, handler, key, primary) {
					var b = button(label, primary ? 'ddk-button-primary' : 'ddk-button-secondary');
					b.dataset.control = key;
					b.addEventListener(
						'click',
						busyButton(b, 'Working…', async function () {
							try {
								await handler();
							} catch (error) {
								setError(errorBox, error);
							}
						})
					);
					actions.appendChild(b);
					return b;
				}
				if (activeJob(job))
					action(
						'Stop & keep results',
						async function () {
							await exec(['job', 'stop', job.id]);
							await refreshJobs();
						},
						'stop'
					);
				if (activeJob(job) && job.metadata.action_id === 'serial.console')
					action(
						'Open serial console',
						function () {
							openSerialConsole(job);
						},
						'serial',
						true
					);
				if (activeJob(job) && job.metadata.action_id === 'cellular.profile')
					action(
						'Keep cellular settings',
						async function () {
							await exec(['job', 'confirm-network', job.id]);
							await refreshJobs();
						},
						'cellular',
						true
					);
				if (!activeJob(job) && !job.saved)
					action(
						'Save as case',
						function () {
							nameCase(job);
						},
						'save',
						true
					);
				if (job.saved) {
					action(
						'Export case',
						function () {
							openOperatorAction('cases.export', null, { case: job.id });
						},
						'export'
					);
					action(
						'Rename',
						function () {
							nameCase(job);
						},
						'rename'
					);
				}
				if (guide.catalog[job.metadata.action_id])
					action(
						'Run again',
						function () {
							capabilities()
								.then(function (modules) {
									modules.forEach(function (module) {
										var action = module.actions.find(function (a) {
											return a.id === job.metadata.action_id;
										});
										if (action) launchAction(action, module, job.metadata.options || {});
									});
								})
								.catch(function (error) {
									setError(errorBox, error);
								});
						},
						'rerun'
					);
				if (!activeJob(job))
					action(
						'Delete',
						async function () {
							if (!window.confirm('Permanently delete ' + title + ' and its results?')) return;
							await exec(['job', 'delete', job.id]);
							selected = '';
							await refreshJobs();
						},
						'delete'
					);
				var summaryTab = h('div', { 'data-panel': 'summary' }),
					outputTab = preservedOutput || h('div', { 'data-panel': 'output' }),
					filesTab = h('div', { 'data-panel': 'files' }),
					panels = { summary: summaryTab, output: outputTab, files: filesTab };
				summaryContainer = summaryTab;
				filesContainer = filesTab;
				var tabs = h(
					'div',
					{ class: 'ddk-result-tabs', role: 'tablist', 'aria-label': 'Job result views' },
					[
						['summary', 'Summary'],
						['output', 'Output'],
						['files', 'Files · ' + (job.artifacts || []).length]
					].map(function (item) {
						var b = button(item[1], '', function () {
							tab = item[0];
							updateTabs();
						});
						b.dataset.tab = item[0];
						b.setAttribute('role', 'tab');
						b.id = 'ddk-tab-' + item[0];
						b.setAttribute('aria-controls', 'ddk-panel-' + item[0]);
						return b;
					})
				);
				function updateTabs() {
					tabs.querySelectorAll('button').forEach(function (b) {
						b.setAttribute('aria-selected', String(tab === b.dataset.tab));
						b.tabIndex = tab === b.dataset.tab ? 0 : -1;
					});
					Object.keys(panels).forEach(function (key) {
						panels[key].hidden = tab !== key;
						panels[key].setAttribute('role', 'tabpanel');
						panels[key].id = 'ddk-panel-' + key;
						panels[key].setAttribute('aria-labelledby', 'ddk-tab-' + key);
					});
				}
				tabs.addEventListener('keydown', function (event) {
					if (['ArrowLeft', 'ArrowRight', 'Home', 'End'].indexOf(event.key) < 0) return;
					event.preventDefault();
					var keys = ['summary', 'output', 'files'],
						index = keys.indexOf(tab);
					tab =
						event.key === 'Home'
							? keys[0]
							: event.key === 'End'
								? keys[2]
								: keys[(index + (event.key === 'ArrowRight' ? 1 : 2)) % 3];
					updateTabs();
					tabs.querySelector('[data-tab="' + tab + '"]').focus();
				});
				if (!preservedOutput) {
					outputNode = h('pre', {
						class: 'ddk-job-output',
						tabindex: '0',
						'aria-label': 'Native job output'
					});
					var outputSearch = h('input', {
						class: 'ddk-input',
						type: 'search',
						placeholder: 'Filter output lines…',
						'aria-label': 'Filter output lines'
					});
					outputSearch.addEventListener('input', function () {
						updateOutput();
					});
					outputNode.filterInput = outputSearch;
					var auto = h('input', {
							type: 'checkbox',
							checked: follow,
							onchange: function () {
								follow = auto.checked;
							}
						}),
						copy = button('Copy output', 'ddk-button-secondary', function () {
							copyText(jobOutput(currentJob), copy);
						}),
						download = button('Download text', 'ddk-button-secondary', function () {
							saveBlob(
								new Blob([jobOutput(currentJob)], { type: 'text/plain;charset=utf-8' }),
								'ddk-' + currentJob.id + '-output.txt'
							);
						});
					outputTab.append(
						h(
							'div',
							{ class: 'ddk-output-toolbar' },
							outputSearch,
							h('label', { class: 'ddk-checkbox-label' }, auto, 'Follow output'),
							copy,
							download
						),
						h(
							'p',
							{ class: 'ddk-muted' },
							'Native stdout and stderr. Large jobs may show a bounded preview; download their artifacts for the complete data.'
						),
						outputNode
					);
					outputNode.dataset.outputJob = job.id;
				}
				replace(
					pane,
					h(
						'div',
						{ class: 'ddk-result-head' },
						h(
							'div',
							{},
							h('span', { class: 'ddk-eyebrow' }, job.saved ? 'SAVED CASE' : 'JOB WORKSPACE'),
							h('h2', {}, title),
							h('p', {}, jobTarget(job) || 'System appliance')
						),
						statePill(job.status)
					),
					h('p', { class: 'ddk-job-meta' }, timeText(job.metadata.created_at) + ' · ' + job.id),
					actions,
					tabs,
					summaryTab,
					outputTab,
					filesTab,
					h(
						'details',
						{ class: 'ddk-operator-advanced' },
						h('summary', {}, 'Job details'),
						row('Action', job.metadata.action_id),
						row('Class', job.metadata.class),
						row('Retention', job.saved ? 'Saved across reboots' : 'Unsaved · follows Settings'),
						row('Worker', job.pid || 'Finished')
					)
				);
				updateTabs();
				drawFiles(job);
				pane.scrollTop = priorScroll;
				if (preservedOutput && preservedOutput.contains(previousFocus) && previousFocus.isConnected)
					previousFocus.focus({ preventScroll: true });
				if (focusedKey) {
					var focused = pane.querySelector('[data-control="' + focusedKey + '"]');
					if (focused) focused.focus({ preventScroll: true });
				}
			}
			updateOutput();
			if (
				!summaryContainer.contains(document.activeElement) &&
				!(window.getSelection().toString() && summaryContainer.contains(window.getSelection().anchorNode))
			)
				replace(summaryContainer, summaryNode(job));
		}
		function updateOutput() {
			if (!outputNode || !currentJob) return;
			var raw = jobOutput(currentJob) || 'Waiting for output…',
				query = outputNode.filterInput.value.toLowerCase(),
				text = query
					? raw
							.split('\n')
							.filter(function (line) {
								return line.toLowerCase().indexOf(query) >= 0;
							})
							.join('\n') || 'No matching lines.'
					: raw;
			if (outputNode.textContent === text) return;
			if (window.getSelection().toString() && outputNode.contains(window.getSelection().anchorNode)) return;
			var scroll = outputNode.scrollTop;
			outputNode.textContent = text;
			outputNode.scrollTop = follow ? outputNode.scrollHeight : scroll;
		}
		function nameCase(job) {
			var input = h('input', {
					class: 'ddk-input',
					value: job.metadata.case_label || '',
					maxlength: 160,
					placeholder: 'e.g. Clinic · switch uplink',
					'aria-label': 'Case name'
				}),
				error = inlineError(),
				save = button(job.saved ? 'Save name' : 'Save case', 'ddk-button-primary'),
				modal = showModal(
					job.saved ? 'Name this case' : 'Save this work',
					h(
						'div',
						{},
						h(
							'p',
							{},
							'Keep output and files across router reboots. Give the case a name you can find later.'
						),
						input,
						error
					),
					save
				);
			save.addEventListener(
				'click',
				busyButton(save, 'Saving…', async function () {
					modal.busy = true;
					try {
						if (!job.saved) await exec(['job', 'save', job.id]);
						if (input.value.trim())
							await exec(['job', 'label', job.id, structuredEnvelope({ label: input.value.trim() })]);
						modal.busy = false;
						modal.close();
						await refreshJobs();
					} catch (e) {
						setError(error, e);
					} finally {
						modal.busy = false;
					}
				})
			);
			input.focus();
		}
		async function refreshJobs(forceSelection) {
			if (forceSelection) selected = forceSelection;
			clearTimeout(timer);
			if (busy) return;
			busy = true;
			try {
				jobs = await exec(['job', 'list']);
				errorBox.hidden = true;
				jobs.sort(function (a, b) {
					return (
						Number(activeJob(b)) - Number(activeJob(a)) ||
						Number(b.metadata.created_at || 0) - Number(a.metadata.created_at || 0)
					);
				});
				if (!selected && jobs.length) selected = (filteredJobs()[0] || jobs[0]).id;
				drawList();
				drawDetail();
			} catch (error) {
				setError(errorBox, error);
			} finally {
				busy = false;
				if (jobs.some(activeJob)) timer = setTimeout(refreshJobs, 1800);
			}
		}
		jobsRefresh = refreshJobs;
		window.addEventListener('hashchange', function () {
			selected = location.hash.slice(1);
			currentSignature = '';
			drawList();
			drawDetail();
		});
		search.addEventListener('input', drawList);
		var reports = h('div'),
			reportDetails = h(
				'details',
				{ class: 'ddk-operator-advanced' },
				h('summary', {}, 'System reports'),
				reports
			);
		reportDetails.addEventListener('toggle', async function () {
			if (!reportDetails.open) return;
			try {
				var list = await exec(['report', 'list']);
				replace(
					reports,
					list.length
						? list.map(function (report) {
								return h(
									'div',
									{ class: 'ddk-result-file' },
									h('strong', {}, timeText(report.created_at)),
									h('small', {}, formatBytes(report.size)),
									button('View report', 'ddk-button-secondary', async function () {
										try {
											var result = await exec(['report', 'view', report.id]);
											showModal(
												'System report',
												h('pre', {}, result.content + (result.truncated ? '\n[Preview truncated]' : '')),
												button('Download text', '', function () {
													saveBlob(new Blob([result.content], { type: 'text/plain' }), result.id + '.txt');
												})
											);
										} catch (error) {
											setError(errorBox, error);
										}
									})
								);
							})
						: h('p', {}, 'No system reports yet. Create one with the System report button.')
				);
			} catch (error) {
				reports.textContent = error.message;
			}
		});
		replace(
			app,
			brand('Jobs & cases', 'Live output, useful results, and a clear next step.'),
			h(
				'div',
				{ class: 'ddk-toolbar' },
				search,
				reportButton,
				refresh,
				link('New job →', 'tools', 'ddk-button ddk-button-primary')
			),
			h('div', { class: 'ddk-library-meta' }, filters, count),
			errorBox,
			h('div', { class: 'ddk-jobs-workspace' }, listNode, pane),
			h(
				'p',
				{ class: 'ddk-muted' },
				'Stop keeps partial results. Save a finished job as a case to keep it across reboots. ' +
					'Two jobs can run at once.'
			),
			reportDetails
		);
		await refreshJobs();
	}
	function showUpload(kind, onReady) {
		var kindSelect = h(
				'select',
				{ class: 'ddk-input', 'aria-label': 'Input type' },
				Object.keys(uploadKinds).map(function (value) {
					return h('option', { value: value, selected: value === kind }, uploadKinds[value].label);
				})
			),
			file = h('input', { type: 'file', class: 'ddk-input', 'aria-label': 'Choose file' }),
			status = h('p', { role: 'status' }),
			error = inlineError(),
			upload = button('Upload file', 'ddk-button-primary'),
			modal = showModal(
				'Add an input file',
				h(
					'div',
					{},
					h('p', {}, 'Upload once, then reuse the verified file in compatible tools.'),
					h('label', { class: 'ddk-operator-field' }, 'Input type', kindSelect),
					h('label', { class: 'ddk-operator-field' }, 'File', file),
					status,
					error
				),
				upload
			);
		function hint() {
			file.accept = uploadKinds[kindSelect.value].extensions.replace(/ /g, '');
			status.textContent =
				'Accepted: ' +
				uploadKinds[kindSelect.value].extensions +
				'. Available router storage determines the usable file size.';
		}
		kindSelect.addEventListener('change', hint);
		hint();
		upload.addEventListener(
			'click',
			busyButton(upload, 'Uploading…', async function () {
				var selected = file.files && file.files[0],
					reservation;
				error.hidden = true;
				if (!selected) {
					setError(error, new Error('Choose a file first.'));
					return;
				}
				modal.busy = true;
				kindSelect.disabled = true;
				file.disabled = true;
				try {
					reservation = await exec([
						'upload',
						'reserve',
						kindSelect.value,
						structuredEnvelope({ name: selected.name, size: selected.size })
					]);
					await uploadFile(reservation, selected, function (percent) {
						status.textContent = 'Uploading ' + selected.name + ' · ' + percent + '%';
					});
					status.textContent = 'Checking file integrity…';
					var sealed = await exec(['upload', 'finalize', reservation.id]);
					sealed = await waitForSealed(sealed, function (value) {
						status.textContent = value;
					});
					status.textContent = 'File verified. Updating your file selection…';
					if (onReady) await onReady(sealed);
					modal.busy = false;
					modal.close();
					toast(selected.name + ' is ready.');
					if (!onReady) chooseInput(sealed);
				} catch (e) {
					setError(
						error,
						new Error(
							e.message +
								(reservation
									? ' The input remains visible in Input files; you can inspect or delete it there.'
									: '')
						)
					);
				} finally {
					modal.busy = false;
					kindSelect.disabled = false;
					file.disabled = false;
				}
			})
		);
		file.focus();
	}
	async function renderSettings() {
		var errorBox = inlineError(),
			uploadsNode = h('div', { class: 'ddk-input-files' }),
			search = h('input', {
				class: 'ddk-input',
				type: 'search',
				placeholder: 'Find an input file…',
				'aria-label': 'Search input files'
			}),
			uploads = [],
			timer;
		function drawUploads() {
			var query = search.value.toLowerCase(),
				visible = uploads.filter(function (u) {
					return [u.original_name, u.kind].join(' ').toLowerCase().indexOf(query) >= 0;
				});
			replace(
				uploadsNode,
				visible.length
					? visible.map(function (upload) {
							var state = upload.phase || 'sealed';
							return h(
								'article',
								{ class: 'ddk-input-file' },
								h(
									'div',
									{ class: 'ddk-result-file' },
									icon('files'),
									h(
										'div',
										{},
										h('strong', {}, upload.original_name),
										h('small', {}, (uploadKinds[upload.kind] || {}).label + ' · ' + formatBytes(upload.size))
									),
									statePill(state)
								),
								h(
									'div',
									{ class: 'ddk-action-row' },
									state === 'sealed'
										? button('Use in a tool →', 'ddk-button-primary', function () {
												chooseInput(upload);
											})
										: null,
									state === 'sealing' || state === 'reserved'
										? button('Check integrity', 'ddk-button-secondary', async function () {
												try {
													await exec(['upload', 'finalize', upload.id]);
													await refreshUploads();
												} catch (error) {
													setError(errorBox, error);
												}
											})
										: null,
									button('Delete', 'ddk-button-secondary', async function () {
										if (!window.confirm('Permanently delete input ' + upload.original_name + '?')) return;
										try {
											await exec(['upload', 'delete', upload.id]);
											await refreshUploads();
										} catch (error) {
											setError(errorBox, error);
										}
									})
								),
								h(
									'details',
									{},
									h('summary', {}, 'File details'),
									row('SHA-256', upload.sha256 || 'Integrity check pending'),
									row('Expires', upload.expires_at ? timeText(upload.expires_at) : 'No expiry'),
									row('Input ID', upload.id),
									state === 'sealing'
										? row(
												'Hash progress',
												formatBytes(upload.hash_bytes || 0) + ' / ' + formatBytes(upload.size)
											)
										: null
								)
							);
						})
					: h(
							'div',
							{ class: 'ddk-empty' },
							icon('files'),
							h('h3', {}, query ? 'No matching files' : 'Your reusable inputs live here'),
							h(
								'p',
								{},
								'Upload a capture, image, package or analysis file. You can also upload directly inside a tool.'
							),
							button('Upload a file', 'ddk-button-primary', function () {
								showUpload(null, refreshUploads);
							})
						)
			);
		}
		async function refreshUploads() {
			clearTimeout(timer);
			try {
				uploads = await exec(['upload', 'list']);
				drawUploads();
				if (
					uploads.some(function (u) {
						return u.phase === 'sealing';
					})
				)
					timer = setTimeout(refreshUploads, 2000);
			} catch (error) {
				setError(errorBox, error);
			}
		}
		search.addEventListener('input', drawUploads);
		var retained = await exec(['settings', 'get']),
			fields = {};
		var retentionFields = h(
				'div',
				{ class: 'ddk-operator-grid' },
				[
					['job_hours', 'Unsaved job lifetime (hours)', 87600],
					['job_count', 'Maximum unsaved jobs', 10000],
					['input_hours', 'New input lifetime (hours)', 87600]
				].map(function (item) {
					fields[item[0]] = h('input', {
						class: 'ddk-input',
						type: 'number',
						min: 0,
						max: item[2],
						value: retained[item[0]]
					});
					return h('label', { class: 'ddk-operator-field' }, item[1], fields[item[0]]);
				})
			),
			message = h('p', { role: 'status' }),
			save = button('Save retention settings', 'ddk-button-primary');
		save.addEventListener(
			'click',
			busyButton(save, 'Saving…', async function () {
				try {
					var values = {};
					Object.keys(fields).forEach(function (key) {
						values[key] = Number(fields[key].value);
					});
					await exec(['settings', 'set', structuredEnvelope(values)]);
					message.textContent =
						'Saved. Job cleanup applies on the next refresh. Input lifetime applies to newly uploaded files.';
				} catch (error) {
					setError(errorBox, error);
				}
			})
		);
		var inputs = h(
				'section',
				{ id: 'inputs' },
				sectionHeading('Input files', 'Verified files, ready to use again.'),
				h(
					'div',
					{ class: 'ddk-toolbar' },
					search,
					button('Upload file', 'ddk-button-primary', function () {
						showUpload(null, refreshUploads);
					}),
					button('Refresh', 'ddk-button-secondary', refreshUploads)
				),
				uploadsNode
			),
			retention = h(
				'section',
				{ id: 'retention' },
				card(
					'Keep work on your terms',
					'RETENTION',
					[
						h(
							'p',
							{},
							'Saved cases remain until you delete them. Unsaved jobs and input files follow these settings. Set a limit to zero to disable that cleanup rule.'
						),
						retentionFields,
						save,
						message
					],
					'ddk-card-full'
				)
			);
		replace(
			app,
			brand(
				location.hash === '#inputs' ? 'Input files' : 'Settings',
				location.hash === '#inputs'
					? 'Upload once. Put your files to work.'
					: 'Choose how your field workspace keeps its work.'
			),
			errorBox,
			location.hash === '#inputs' ? [inputs, retention] : [retention, inputs],
			card(
				'About this workspace',
				'FIELD CONSOLE V4',
				[
					h(
						'p',
						{},
						'Local tools, existing LuCI sign-in, and job-owned sessions. Two jobs can run concurrently on the X750. Each tool checks its target and required hardware when you review and start it.'
					),
					h(
						'p',
						{},
						'Favorites and tool presets stay in this browser. Inputs and saved cases live on the router.'
					),
					link('Browse installed packages', 'packages')
				],
				'ddk-card-full'
			)
		);
		await refreshUploads();
		window.addEventListener('hashchange', function () {
			location.reload();
		});
	}

	setupNavigation();
	var renderers = {
		overview: renderOverview,
		tools: renderTools,
		packages: renderPackages,
		jobs: renderJobs,
		settings: renderSettings
	};
	Promise.resolve()
		.then(function () {
			return (renderers[config.page] || renderOverview)();
		})
		.then(function () {
			window.dispatchEvent(new Event('ddk:rendered'));
		})
		.catch(function (error) {
			showError(error);
			window.dispatchEvent(new Event('ddk:rendered'));
		});
})();
