'use strict';

(function() {
	var app = document.getElementById('ddk-app');
	if (!app)
		return;

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

	function button(label, className, handler, disabled, title) {
		return h('button', {
			type: 'button',
			class: 'ddk-button' + (className ? ' ' + className : ''),
			onclick: handler,
			disabled: disabled || null,
			title: title || null
		}, label);
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
		if (!config.session || !Array.isArray(args) || !args.length || args.length > 5 ||
		    args.some(function(value) { return typeof value !== 'string' || value.length > 32772 || !/^[A-Za-z0-9._\/-]+$/.test(value); }))
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

	function uploadFile(reservation, file, progress) {
		return new Promise(function(resolve, reject) {
			var request = new XMLHttpRequest();
			request.open('POST', config.upload, true);
			request.withCredentials = true;
			request.timeout = 0;
			request.upload.addEventListener('progress', function(event) {
				if (event.lengthComputable && progress)
					progress(Math.min(100, Math.round((event.loaded / event.total) * 100)));
			});
			request.addEventListener('load', function() {
				if (request.status < 200 || request.status >= 300) {
					reject(new Error(request.status === 403 ? 'LuCI session or upload ACL rejected the file.' : 'Upload failed with HTTP ' + request.status + '.'));
					return;
				}
				try {
					var reply = JSON.parse(request.responseText || '{}');
					if (reply && reply.failure) { reject(new Error(reply.message || 'Native LuCI upload rejected the file.')); return; }
				}
				catch (_) { reject(new Error('Native LuCI upload returned an invalid response.')); return; }
				resolve();
			});
			request.addEventListener('error', function() { reject(new Error('The authenticated upload connection failed.')); });
			request.addEventListener('timeout', function() { reject(new Error('The authenticated upload exceeded the two-hour browser limit.')); });
			var form = new FormData();
			form.append('sessionid', config.session);
			form.append('filename', reservation.upload_path);
			form.append('filedata', file, file.name);
			request.send(form);
		});
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
	async function waitForSealed(input, progress) {
		while(input.phase === 'sealing') {
			if(progress)progress('Hashing ' + input.original_name + '… ' + formatBytes(input.hash_bytes || 0) + ' / ' + formatBytes(input.size));
			await new Promise(function(resolve){setTimeout(resolve,1500);});
			input=await exec(['upload','finalize',input.id]);
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

	var brandScenes = {
		overview: '/luci-static/resources/ddk/brand/overview.webp',
		tools: '/luci-static/resources/ddk/brand/tools.webp',
		packages: '/luci-static/resources/ddk/brand/packages.webp',
		jobs: '/luci-static/resources/ddk/brand/jobs.webp',
		settings: '/luci-static/resources/ddk/brand/settings.webp'
	};

	function brand(section, description) {
		var scene = brandScenes[config.page] || brandScenes.overview;
		return h('header', { class: 'ddk-brand' },
			h('div', { class: 'ddk-brand-media', 'aria-hidden': 'true' },
				h('img', { src: scene, alt: '', loading: 'eager', decoding: 'async', fetchpriority: 'high' })),
			h('div', { class: 'ddk-brand-mark' },
				h('img', { src: '/luci-static/resources/ddk/brand/dropkick-logo.png', alt: 'Digital Dropkick kick logo', decoding: 'async' })),
			h('div', { class: 'ddk-brand-copy' },
				h('span', { class: 'ddk-eyebrow' }, 'LOCAL REPAIR · SERIOUS SYSTEMS'),
				h('h2', {}, section || 'FIELD CONSOLE'),
				h('p', {}, description || 'GL-X750 field appliance control surface')),
			h('div', { class: 'ddk-appliance-tag' }, h('span', { class: 'ddk-live-dot' }), h('span', {}, 'X750 / v3.0.0')));
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

	function showModal(title, content, actions, onClose) {
		var overlay = h('div', { class: 'ddk-modal', role: 'dialog', 'aria-modal': 'true', 'aria-label': title },
			h('div', { class: 'ddk-modal-panel' },
				h('div', { class: 'ddk-modal-head' }, h('h3', {}, title), button('Close', 'ddk-button-secondary', close)),
				content,
				actions || null));
		function close() { overlay.remove(); if (onClose) onClose(); }
		overlay.addEventListener('click', function(event) { if (event.target === overlay) close(); });
		document.body.appendChild(overlay);
		return { close: close, node: overlay };
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

	function operatorField(field, registry) {
		var control;
		if (field.type === 'boolean') {
			control = h('input', { type: 'checkbox', checked: field.default === true });
		}
		else if (field.type === 'upload_list') {
			control = h('select', { class: 'ddk-input', multiple: true, size: Math.min(8, Math.max(3, (field.options || []).length)) }, (field.options || []).map(function(item) { return h('option', { value: item.value }, item.label); }));
		}
		else if (field.type === 'enum') {
			control = h('select', { class: 'ddk-select' }, (field.options || []).map(function(option) {
				var value = typeof option === 'object' ? option.value : option;
				var label = typeof option === 'object' ? option.label : option;
				return h('option', { value: value, selected: value === field.default }, label || '(automatic)');
			}));
		}
		else if (field.type === 'target_list' || field.type === 'integer_list' || field.type === 'multiline') {
			var textareaValue = field.type === 'multiline' ? (field.default || '') : (field.default || []).join('\n');
			control = h('textarea', { class: 'ddk-input ddk-textarea', rows: field.rows || 3, placeholder: field.placeholder || '' }, textareaValue);
		}
		else {
			control = h('input', {
				class: 'ddk-input',
				type: field.type === 'integer' || field.type === 'number' ? 'number' : field.type === 'secret' ? 'password' : 'text',
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
		var wrapper = h('label', { class: 'ddk-operator-field' + (field.type === 'boolean' ? ' ddk-operator-check' : '') },
			h('span', { class: 'ddk-operator-label' }, field.label),
			control,
			field.help ? h('small', {}, field.help) : null);
		if (field.suggestions && field.suggestions.length) {
			var listId='ddk-suggestions-'+field.name, search=h('input',{class:'ddk-input',list:listId,placeholder:'Find an installed script','aria-label':'Find an installed script'});
			wrapper.appendChild(h('div',{},search,h('datalist',{id:listId},field.suggestions.map(function(value){return h('option',{value:value});})),button('Add script','',function(){var value=search.value.trim();if(field.suggestions.indexOf(value)<0)return;var values=control.value.split(/\r?\n/).filter(Boolean);if(values.indexOf(value)<0)values.push(value);control.value=values.join('\n');search.value='';})));
		}
		registry[field.name] = { field: field, control: control, wrapper: wrapper };
		return wrapper;
	}

	function applyOperatorConditions(registry) {
		function matches(condition) {
			if (condition.any) return condition.any.some(matches);
			if (condition.all) return condition.all.every(matches);
			if (!registry[condition.field]) return true;
			var source=registry[condition.field].control, value=source.type==='checkbox' ? source.checked : source.value;
			return condition.values ? condition.values.indexOf(value)>=0 : condition.equals!==undefined ? value===condition.equals : value!==condition.not_equals;
		}
		Object.keys(registry).forEach(function(name) { var entry=registry[name];entry.wrapper.hidden=entry.field.show_when ? !matches(entry.field.show_when) : false; });
	}

	function collectOperatorOptions(registry) {
		var options = {};
		Object.keys(registry).forEach(function(name) {
			var entry = registry[name], field = entry.field, control = entry.control;
			if (entry.wrapper.hidden) { options[name] = field.default; return; }
			if (field.type === 'boolean') options[name] = control.checked;
			else if (field.type === 'upload_list') options[name] = Array.from(control.selectedOptions).map(function(item) { return item.value; });
			else if (field.type === 'integer' || field.type === 'number') options[name] = Number(control.value);
			else if (field.type === 'target_list') options[name] = control.value.split(/\r?\n/).map(function(value) { return value.trim(); }).filter(Boolean);
			else if (field.type === 'integer_list') options[name] = control.value.split(/\r?\n/).map(function(value) { return value.trim(); }).filter(Boolean).map(Number);
			else if (field.type === 'multiline') options[name] = control.value;
			else options[name] = control.value;
		});
		return options;
	}

	async function reviewPreparedAction(prepared, onStarted) {
		var confirmationInput = prepared.confirmation && prepared.confirmation.required ? h('input', {
			class: 'ddk-input', type: 'text', autocomplete: 'off', spellcheck: 'false',
			placeholder: prepared.confirmation.phrase
		}) : null;
		var artifactText = prepared.artifacts && prepared.artifacts.length ? prepared.artifacts.map(function(item) { return item.name; }).join(', ') : 'Decoded job output only';
		var content = h('div', { class: 'ddk-operator-review' },
			row('Action', prepared.action_id),
			row('Exact target', prepared.target_summary),
			row('Wall timeout', prepared.wall_timeout === 0 ? 'Until finished or stopped' : prepared.wall_timeout + ' seconds'),
			row('Artifacts', artifactText),
			h('p', { class: 'ddk-operator-label' }, 'Server-built native invocation'),
			h('pre', {}, prepared.argv_preview),
			prepared.confirmation && prepared.confirmation.required ? h('div', { class: 'ddk-confirmation' },
				h('div', { class: 'ddk-alert' }, prepared.confirmation.reason),
				h('p', {}, 'Type the exact target-bound phrase to continue:'),
				h('code', {}, prepared.confirmation.phrase), confirmationInput) :
				h('div', { class: 'ddk-alert ddk-alert-info' }, 'This information-gathering workflow does not require an extra confirmation.'));
		var startButton;
		var actionButtonClass = prepared.class === 'SECURITY' ? 'ddk-button-security' : prepared.class === 'ACTION' || prepared.class === 'DISRUPTIVE' ? 'ddk-button-action' : '';
		var modal = showModal('Review ' + prepared.label, content,
			h('div', { class: 'ddk-action-row ddk-actions-end' }, startButton = button('Start Native Action', actionButtonClass, async function() {
				startButton.disabled = true;
				try {
					var args = [ 'job', 'start', prepared.prepared_id ];
					if (confirmationInput) args.push(base64urlText(confirmationInput.value));
					var job = await exec(args);
					modal.close();
					if (onStarted) onStarted(job);
					else showModal('Operator Job Started', h('div', {}, h('p', {}, job.metadata.label + ' is running as ' + job.id + '.'), h('p', {}, h('a', { class: 'ddk-button', href: config.base + '/jobs' }, 'Open Jobs & Reports'))));
				}
				catch (error) {
					modal.close();
					showModal('Action Start Rejected', h('div', {}, h('div', { class: 'ddk-alert ddk-alert-error' }, error.message), h('p', {}, 'Prepared requests are single-use. Reopen the action to validate and review a new request.')));
				}
			})), null);
	}

	function operatorPresets(actionId, registry) {
		var key = 'ddk-v3-presets:' + actionId, saved = [];
		try { var parsed = JSON.parse(localStorage.getItem(key) || '[]'); if (Array.isArray(parsed)) saved = parsed.slice(0, 50); } catch (_) {}
		var selector = h('select', { class: 'ddk-input', 'aria-label': 'Saved preset' });
		var name = h('input', { class: 'ddk-input', placeholder: 'Preset name', maxlength: 80, 'aria-label': 'Preset name' });
		function refresh() { selector.replaceChildren.apply(selector, [h('option', {value:''}, 'Choose a saved preset')].concat(saved.map(function(item,index) { return h('option',{value:String(index)},item.name); })));  }
		function persist() { localStorage.setItem(key, JSON.stringify(saved)); refresh(); }
		refresh();
		return h('details', {class:'ddk-operator-advanced'}, h('summary',{},'Presets saved in this browser'),
			h('p',{},'Save settings for repeat visits. Passwords, token seeds, private arguments, and uploaded-file selections are excluded.'),
			selector, h('div',{class:'ddk-action-row'},button('Load','',function() {
				var item = selector.value !== '' && saved[Number(selector.value)]; if (!item) return;
				Object.keys(registry).forEach(function(fieldName) {
					if (!Object.prototype.hasOwnProperty.call(item.options || {},fieldName)) return;
					var entry=registry[fieldName], value=item.options[fieldName];
					if (entry.field.type==='boolean') entry.control.checked=!!value;
					else entry.control.value=Array.isArray(value)?value.join('\n'):String(value);
				}); applyOperatorConditions(registry); name.value=item.name;
			}),button('Remove','',function() { if(selector.value==='')return;saved.splice(Number(selector.value),1);persist(); })),name,
			button('Save current settings','',function() {
				var label=name.value.trim();if(!label)return;
				var options=collectOperatorOptions(registry);
				Object.keys(registry).forEach(function(fieldName) { var f=registry[fieldName].field; if(f.private || f.type==='secret' || f.type==='upload_list' || /upload|input|packages/.test(fieldName)) delete options[fieldName]; });
				saved=saved.filter(function(item){return item.name!==label;});saved.unshift({name:label,options:options});saved=saved.slice(0,50);
				try {persist();name.value='';} catch(error) {showModal('Preset storage',h('p',{},error.message));}
			}));
	}

	async function openOperatorAction(actionId, onStarted, initialOptions) {
		try {
			var schema = await exec([ 'action', 'describe', actionId ]);
			var registry = {}, primary = h('div', { class: 'ddk-operator-grid' }), advanced = h('div', { class: 'ddk-operator-grid' });
			(schema.fields || []).forEach(function(field) { if(initialOptions && Object.prototype.hasOwnProperty.call(initialOptions,field.name)) field.default=initialOptions[field.name]; (field.advanced ? advanced : primary).appendChild(operatorField(field, registry)); });
			Object.keys(registry).forEach(function(name) { registry[name].control.addEventListener('change', function() { applyOperatorConditions(registry); }); });
			applyOperatorConditions(registry);
			var content = h('div', {},
				operatorPresets(actionId, registry),
				schema.availability && schema.availability.missing.length ? h('div', { class: 'ddk-alert' }, 'Some operations need additional software: ' + schema.availability.missing.join(', ') + '. Available operations can still be used.') : null,
				primary,
				advanced.childNodes.length ? h('details', { class: 'ddk-operator-advanced' }, h('summary', {}, 'Advanced native options'), advanced) : null);
			var reviewButton;
			var modal = showModal(schema.label, content,
				h('div', { class: 'ddk-action-row ddk-actions-end' }, reviewButton = button('Validate & Review', 'ddk-button-security', async function() {
					reviewButton.disabled = true;
					try {
						var prepared = await exec([ 'action', 'prepare', actionId, structuredEnvelope(collectOperatorOptions(registry)) ]);
						modal.close();
						await reviewPreparedAction(prepared, onStarted);
					}
					catch (error) {
						reviewButton.disabled = false;
						showModal('Validation Rejected', h('div', { class: 'ddk-alert ddk-alert-error' }, error.message));
					}
				})), null);
		}
		catch (error) { showModal('Operator Action Error', h('div', { class: 'ddk-alert ddk-alert-error' }, error.message)); }
	}

	function confirmLanMetadataCapture() {
		return window.confirm(
			'Start bounded LAN metadata snapshot?\n\n' +
			'Interface: br-lan derived by the router (never browser input)\n' +
			'Traffic: ARP, ICMP, and DHCP metadata only\n' +
			'Privacy: timestamps, MAC addresses, and IP addresses may appear\n' +
			'Safety: non-promiscuous; no DNS, payload dump, PCAP file, or application traffic\n' +
			'Limits: 20 seconds, 128 packets, 96-byte snap length, one active capture\n' +
			'Output: bounded decoded text under /tmp/ddk/jobs/'
		);
	}

	async function startLanMetadataCapture() {
		if (!confirmLanMetadataCapture())
			return null;
		return exec([ 'job', 'start', 'capture.lan_metadata_snapshot' ]);
	}

	function confirmRtl433Snapshot() {
		return window.confirm(
			'Start bounded RTL-433 sensor snapshot?\n\n' +
			'Hardware: one reviewed RTL2832/RTL2838 dongle selected by server-derived USB serial\n' +
			'Profile: receive-only 433.92 MHz, 250 kS/s, automatic gain, standard decoders\n' +
			'Privacy: decoded sensor identifiers, measurements, and timestamps may appear\n' +
			'Safety: no raw I/Q save, custom decoder, config file, network output, or transmitter\n' +
			'Limits: 20 seconds, one tuner job, 64 KiB final text output'
		);
	}

	async function startRtl433Snapshot() {
		if (!confirmRtl433Snapshot())
			return null;
		return exec([ 'job', 'start', 'radio.rtl433_snapshot' ]);
	}

	function confirmCameraSnapshot() {
		return window.confirm(
			'Capture one still frame from the attached UVC camera?\n\n' +
			'Privacy: the frame can contain people, customer property, documents, or location details; confirm authorization and consent first\n' +
			'Hardware: exactly one sysfs-attributed USB UVC camera and one primary capture node, selected by the router\n' +
			'Profile: one 640x480 JPEG, no banner or audio\n' +
			'Safety: no stream, listener, daemon, upload, Motion, RTSP, or persistent copy\n' +
			'Limits: 20 seconds, one camera job, 256 KiB artifact, transient four-hour job retention'
		);
	}

	async function startCameraSnapshot() {
		if (!confirmCameraSnapshot())
			return null;
		return exec([ 'job', 'start', 'camera.still_snapshot' ]);
	}

	function confirmGpsSnapshot() {
		return window.confirm(
			'Read one bounded position snapshot from the attached USB GNSS receiver?\n\n' +
			'Privacy: precise latitude, longitude, altitude, speed, and time may appear; confirm authorization before continuing\n' +
			'Hardware: exactly one sysfs-attributed USB GNSS receiver and one exclusive serial node, selected by the router\n' +
			'Profile: receive-only validated NMEA, 15-second window, 32 KiB raw ceiling\n' +
			'Safety: no gpsd start, serial reconfiguration, NTRIP, network request, receiver command, or persistent location copy\n' +
			'Output: whitelisted position fields only; transient four-hour job retention and excluded from DDK reports'
		);
	}

	async function startGpsSnapshot() {
		if (!confirmGpsSnapshot())
			return null;
		return exec([ 'job', 'start', 'gps.snapshot' ]);
	}

	function confirmCanCapture() {
		return window.confirm(
			'Start one passive CAN frame snapshot?\n\n' +
			'Authorization: capture only an owned or explicitly authorized vehicle, machine, controller, or test bus\n' +
			'Privacy: arbitration IDs and data bytes can expose equipment, sensor, and control state\n' +
			'Interface: exactly one already-up physical canN interface, selected by the router\n' +
			'Profile: receive-only candump, 20-second inactivity/window ceiling, at most 128 frames\n' +
			'Safety: no interface setup, bitrate change, restart, cansend, cangen, or transmit operation\n' +
			'Output: bounded decoded frame text under /tmp/ddk/jobs/'
		);
	}

	async function startCanCapture() {
		if (!confirmCanCapture())
			return null;
		return exec([ 'job', 'start', 'can.capture' ]);
	}

	var privateIdentityActions = {
		'android.identify': {
			name: 'Android USB identity',
			excluded: 'start ADB, open a device transport, or change device state; use the separate structured ADB actions for authorized native work'
		},
		'apple.identify': {
			name: 'Apple mobile USB identity',
			excluded: 'start usbmuxd, pair, trust, open device services, issue recovery commands, restore, or access filesystems'
		},
		'firmware.identify': {
			name: 'firmware programmer USB identity',
			excluded: 'open a programmer transport or change device state; use the separate structured firmware actions for authorized native work'
		}
	};

	function confirmPrivateIdentity(actionId) {
		var policy = privateIdentityActions[actionId];
		if (!policy) return false;
		return window.confirm(
			'Show ' + policy.name + ' metadata?\n\n' +
			'Privacy: USB manufacturer, product, topology, interface classes, drivers, and customer-device serial identifier may appear\n' +
			'Source: sanitized read-only sysfs metadata; no device node is opened\n' +
			'This identity request does not: ' + policy.excluded + '\n' +
			'Retention: authenticated browser response only; not written to jobs, reports, logs, or persistent storage'
		);
	}

	function runPrivateIdentity(actionId, target) {
		if (!confirmPrivateIdentity(actionId)) return;
		runInfo(actionId, target);
	}

	async function startToolJob(actionId) {
		if (actionId !== 'cellular.snapshot')
			throw new Error('The requested tool job did not match the DDK client allowlist.');
		return exec([ 'job', 'start', actionId ]);
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
		var serialSummary = hardware.serial_summary || { total: hardware.serial_devices.length, modem_reserved: 0, reviewed_general_purpose: 0, unreviewed: hardware.serial_devices.length };
		var serialText = serialSummary.total ? serialSummary.total + ' nodes · ' + serialSummary.modem_reserved + ' MODEM RESERVED · ' + serialSummary.reviewed_general_purpose + ' GENERAL' : 'NONE';
		var output = h('section', { class: 'ddk-output' });
		var actions = [
			[ 'Refresh System Status', 'system.refresh' ], [ 'Show Interfaces', 'network.interfaces' ],
			[ 'Show Routes', 'network.routes' ], [ 'Show USB Devices', 'hardware.usb' ],
			[ 'Inspect Serial Attribution', 'serial.inspect' ], [ 'Show Tailscale Status', 'remote.tailscale' ],
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
				card('Hardware Presence', 'LIVE PROBES', [ row('USB devices', hardware.usb_devices.length), row('Serial attribution', serialText), row('Serial nodes', hardware.serial_devices.length ? hardware.serial_devices.join(', ') : 'NONE'), row('Video nodes', hardware.video_devices.length ? hardware.video_devices.join(', ') : 'NONE'), row('UVC camera', hardware.camera ? hardware.camera.reason : 'NOT DETECTED'), row('RTL-SDR', hardware.rtl_sdr ? hardware.rtl_sdr.reason : hardware.classes.rtl_sdr ? 'READY' : 'NOT DETECTED'), row('GPS / GNSS', hardware.gps ? hardware.gps.reason : 'NOT DETECTED'), row('CAN', hardware.can ? hardware.can.reason : 'NOT DETECTED'), row('CAN interfaces', hardware.can_interfaces.length ? hardware.can_interfaces.join(', ') : 'NONE'), row('Android identity', hardware.identity ? hardware.identity.android.reason : 'NOT DETECTED'), row('Apple mobile identity', hardware.identity ? hardware.identity.apple_mobile.reason : 'NOT DETECTED'), row('Programmer identity', hardware.identity ? hardware.identity.programmer.reason : 'NOT DETECTED'), row('Bluetooth controller', hardware.classes.bluetooth ? 'DETECTED' : 'NOT DETECTED'), row('I2C / SPI', hardware.i2c_devices.length + ' / ' + hardware.spi_devices.length) ], 'ddk-card-wide')),
			sectionHeading('Capability Matrix', modules.length + ' modular tool groups'),
			h('div', { class: 'ddk-cap-grid' }, capabilitySummary(modules)),
			sectionHeading('Immediate Read-only Actions', 'Fixed INFO allowlist only'),
			h('section', { class: 'ddk-card ddk-card-full' }, h('div', { class: 'ddk-card-body' },
				h('div', { class: 'ddk-action-row' }, actions.map(function(action) { return button(action[0], 'ddk-button-secondary', function() { runInfo(action[1], output); }); }), h('a', { class: 'ddk-button', href: config.base + '/jobs' }, 'Generate DDK System Report')))),
			output);
	}

	function renderTool(module, output) {
		var packageText = module.software.matched_packages.length ? module.software.matched_packages.join(', ') : 'No matching package';
		var hardwareText = !module.hardware.required ? 'Not required' : module.hardware.present ? module.hardware.detected.join(', ') : 'Missing: ' + module.hardware.missing.join(', ');
		var blockers = (module.actions || []).filter(function(action) {
			return action.enabled !== true && typeof action.unavailable_reason === 'string' && action.unavailable_reason;
		}).map(function(action) {
			return h('p', { class: 'ddk-tool-blocker' }, h('strong', {}, 'Unavailable action: ' + action.id + '. '), action.unavailable_reason);
		});
		var actions = (module.actions || []).map(function(action) {
			var modeCounts = module.mode_counts || {};
			var modeReady = action.hardware_mode === 'normal' ? Number(modeCounts.normal || 0) > 0 : action.hardware_mode === 'recovery' ? Number(modeCounts.recovery || 0) + Number(modeCounts.dfu || 0) > 0 : action.hardware_mode === 'any' ? Number(modeCounts.normal || 0) + Number(modeCounts.recovery || 0) + Number(modeCounts.dfu || 0) > 0 : action.hardware_mode === 'storage' ? !!module.action_ready : action.hardware_mode === 'relay' ? Number(modeCounts.relay || 0) > 0 : action.hardware_mode === 'openocd' || action.hardware_mode === 'avrdude' || action.hardware_mode === 'dfu' || action.hardware_mode === 'serial_programmer' ? Number(modeCounts[action.hardware_mode] || 0) > 0 : true;
			var operatorEnabled = module.console_enabled && action.enabled && action.parameter_schema === 'operator-v1';
			var jobEnabled = module.console_enabled && action.enabled && action.class === 'INFO' && action.execution === 'job' && action.id === 'cellular.snapshot';
			var infoEnabled = module.console_enabled && action.enabled && action.class === 'INFO' && action.execution !== 'job';
			var privateIdentity = infoEnabled && !!privateIdentityActions[action.id];
			var discoveryEnabled = module.console_enabled && action.enabled && action.class === 'SECURITY' && action.id === 'network.nmap_lan_discovery';
			var captureEnabled = module.console_enabled && action.enabled && action.class === 'SECURITY' && action.execution === 'job' && action.id === 'capture.lan_metadata_snapshot';
			var rtl433Action = module.console_enabled && action.enabled && action.class === 'ACTION' && action.execution === 'job' && action.id === 'radio.rtl433_snapshot';
			var rtl433Enabled = rtl433Action && module.hardware.present;
			var cameraAction = module.console_enabled && action.enabled && action.class === 'ACTION' && action.execution === 'job' && action.id === 'camera.still_snapshot';
			var cameraEnabled = cameraAction && module.hardware.present;
			var gpsAction = module.console_enabled && action.enabled && action.class === 'ACTION' && action.execution === 'job' && action.id === 'gps.snapshot';
			var gpsEnabled = gpsAction && module.action_ready;
			var canAction = module.console_enabled && action.enabled && action.class === 'ACTION' && action.execution === 'job' && action.id === 'can.capture';
			var canEnabled = canAction && module.action_ready;
			var handler = privateIdentity ? function() { runPrivateIdentity(action.id, output); } : infoEnabled ? function() { runInfo(action.id, output); } : operatorEnabled ? function() { openOperatorAction(action.id); } : jobEnabled ? async function() {
				try {
					var job = await startToolJob(action.id);
					if (job) showModal('Cellular Snapshot Started', h('div', {}, h('p', {}, 'The bounded read-only job is running as ' + job.id + '.'), h('p', {}, h('a', { class: 'ddk-button', href: config.base + '/jobs' }, 'Open Jobs & Reports'))));
				}
				catch (error) { showModal('Job Error', h('div', { class: 'ddk-alert ddk-alert-error' }, error.message)); }
			} : discoveryEnabled ? function() {
				openOperatorAction(action.id);
			} : captureEnabled ? function() {
				openOperatorAction(action.id);
			} : rtl433Enabled ? async function() {
				try {
					var job = await startRtl433Snapshot();
					if (job) showModal('RTL-433 Snapshot Started', h('div', {}, h('p', {}, 'The bounded receive-only job is running as ' + job.id + '.'), h('p', {}, h('a', { class: 'ddk-button', href: config.base + '/jobs' }, 'Open Jobs & Reports'))));
				}
				catch (error) { showModal('Job Error', h('div', { class: 'ddk-alert ddk-alert-error' }, error.message)); }
			} : cameraEnabled ? async function() {
				try {
					var job = await startCameraSnapshot();
					if (job) showModal('Camera Snapshot Started', h('div', {}, h('p', {}, 'The bounded still-capture job is running as ' + job.id + '.'), h('p', {}, h('a', { class: 'ddk-button', href: config.base + '/jobs' }, 'Open Jobs & Reports'))));
				}
				catch (error) { showModal('Job Error', h('div', { class: 'ddk-alert ddk-alert-error' }, error.message)); }
			} : gpsEnabled ? async function() {
				try {
					var job = await startGpsSnapshot();
					if (job) showModal('GPS / GNSS Snapshot Started', h('div', {}, h('p', {}, 'The bounded receive-only position job is running as ' + job.id + '.'), h('p', {}, h('a', { class: 'ddk-button', href: config.base + '/jobs' }, 'Open Jobs & Reports'))));
				}
				catch (error) { showModal('Job Error', h('div', { class: 'ddk-alert ddk-alert-error' }, error.message)); }
			} : canEnabled ? async function() {
				try {
					var job = await startCanCapture();
					if (job) showModal('Passive CAN Snapshot Started', h('div', {}, h('p', {}, 'The bounded receive-only CAN job is running as ' + job.id + '.'), h('p', {}, h('a', { class: 'ddk-button', href: config.base + '/jobs' }, 'Open Jobs & Reports'))));
				}
				catch (error) { showModal('Job Error', h('div', { class: 'ddk-alert ddk-alert-error' }, error.message)); }
			} : null;
			var disabled = !operatorEnabled && !infoEnabled && !jobEnabled && !discoveryEnabled && !captureEnabled && !rtl433Enabled && !cameraEnabled && !gpsEnabled && !canEnabled;
			var actionButton = button(action.label || action.id.split('.').pop().replace(/_/g,' ').replace(/^./,function(letter){return letter.toUpperCase();}), action.class === 'SECURITY' ? 'ddk-button-security' : action.class === 'ACTION' || action.class === 'DISRUPTIVE' ? 'ddk-button-action' : 'ddk-button-secondary', handler, disabled, action.enabled !== true ? action.unavailable_reason : '');
			actionButton.dataset.action = action.id; return actionButton;
		});
		return h('article', { class: 'ddk-tool' },
			h('div', { class: 'ddk-tool-head' }, h('div', {}, h('span', { class: 'ddk-card-kicker' }, module.category), h('h3', {}, module.name)), statePill(module.state)),
			h('div', { class: 'ddk-tool-body' }, h('p', { class: 'ddk-tool-description' }, module.description), h('p', { class: 'ddk-tool-detail' }, h('strong', {}, 'Software: '), module.software.installed ? 'Installed' : 'Unavailable'), h('p', { class: 'ddk-tool-detail' }, h('strong', {}, 'Packages: '), packageText), h('p', { class: 'ddk-tool-detail' }, h('strong', {}, 'Hardware: '), hardwareText), h('p', { class: 'ddk-tool-detail' }, h('strong', {}, 'Risk: '), module.risk_level), h('p', { class: 'ddk-tool-detail' }, module.help_text), blockers, h('div', { class: 'ddk-tool-actions' }, actions.length ? actions : statePill('NO ACTIONS'))));
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
			return { node: node, module: module, search: [ module.name, module.category, module.description, module.package_names.join(' '), module.expected_binaries.join(' '), module.required_hardware.join(' '), (module.actions || []).map(function(action) { return action.unavailable_reason || ''; }).join(' ') ].join(' ').toLowerCase() };
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
		app.replaceChildren(brand('TOOL REGISTRY', 'Software inventory separated from live hardware presence'), h('div', { class: 'ddk-alert ddk-alert-info' }, 'A manifest can describe a future action, but only the backend allowlist can execute one. Identity buttons remain sysfs-only; separate Operator Mode actions use validated native argv, hardware correlation, resource locks, and confirmation where consequential.'), h('div', { class: 'ddk-toolbar' }, search, category, state), h('div', { class: 'ddk-table-meta' }, count, h('span', {}, 'Hardware probes are read-only')), grid, output);
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
		function saveBlob(blob, filename) {
			var url = URL.createObjectURL(blob);
			var link = h('a', { href: url, download: filename });
			document.body.appendChild(link); link.click(); link.remove(); URL.revokeObjectURL(url);
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
				throw new Error(response.status === 403 ? 'LuCI session or camera-artifact ACL rejected the request.' : 'Camera artifact request failed with HTTP ' + response.status + '.');
			var blob = await response.blob();
			if (blob.size !== expectedSize || blob.size > 262144)
				throw new Error('The downloaded camera artifact did not match its authenticated metadata.');
			return { blob: new Blob([ blob ], { type: 'image/jpeg' }), filename: filename };
		}
		async function viewSnapshot(job, shouldDownload) {
			try {
				var snapshot = await loadSnapshot(job);
				if (shouldDownload) {
					saveBlob(snapshot.blob, snapshot.filename);
					return;
				}
				var url = URL.createObjectURL(snapshot.blob);
				showModal('Camera Still — ' + job.id,
					h('div', { class: 'ddk-snapshot' },
						h('img', { src: url, alt: 'Transient camera still captured by the field console' }),
						h('p', {}, 'Transient /tmp artifact · ' + formatBytes(snapshot.blob.size) + ' · review for private information before sharing.')),
					h('div', { class: 'ddk-action-row ddk-actions-end' }, button('Download JPEG', '', function() { saveBlob(snapshot.blob, snapshot.filename); })),
					function() { URL.revokeObjectURL(url); });
			}
			catch (error) { showModal('Camera Artifact Error', h('div', { class: 'ddk-alert ddk-alert-error' }, error.message)); }
		}
		async function downloadOperatorArtifact(job, artifact) {
			try {
				if (!job || !/^job-\d+-\d+$/.test(job.id) || !artifact || !/^[A-Za-z0-9][A-Za-z0-9_.-]+$/.test(artifact.name) || artifact.name.indexOf('..') >= 0)
					throw new Error('The requested artifact did not match the DDK client allowlist.');
				if (typeof artifact.filename !== 'string' || !/^ddk-job-\d+-\d+-[A-Za-z0-9][A-Za-z0-9_.-]+$/.test(artifact.filename) || artifact.filename.indexOf('..') >= 0)
					throw new Error('The artifact download name did not match the DDK client allowlist.');
				var expectedSize = Number(artifact.size || 0);
				if (!Number.isInteger(expectedSize) || expectedSize <= 0 || expectedSize > 8796093022208)
					throw new Error('The artifact metadata failed its size boundary.');
				var storage = artifact.storage || 'tmp';
				if (storage !== 'tmp' && storage !== 'extroot') throw new Error('The artifact storage class was not recognized.');
				var path = (storage === 'extroot' ? '/overlay/ddk-field-console/artifacts/' + job.id : '/tmp/ddk/jobs/' + job.id) + '/' + artifact.name;
				if (expectedSize > 16777216) {
					var frameName = 'ddk-download-' + Date.now();
					var frame = h('iframe', { name: frameName, hidden: true });
					var form = h('form', { method: 'POST', action: config.download, target: frameName, hidden: true },
						h('input', { type: 'hidden', name: 'sessionid', value: config.session }),
						h('input', { type: 'hidden', name: 'path', value: path }),
						h('input', { type: 'hidden', name: 'filename', value: artifact.filename }));
					document.body.appendChild(frame); document.body.appendChild(form); form.submit();
					setTimeout(function() { form.remove(); }, 1000);
					setTimeout(function() { frame.remove(); }, 2 * 60 * 60 * 1000);
					return;
				}
				var body = new URLSearchParams({ sessionid: config.session, path: path, filename: artifact.filename });
				var response = await fetch(config.download, {
					method: 'POST', credentials: 'same-origin',
					headers: { 'Content-Type': 'application/x-www-form-urlencoded;charset=UTF-8' }, body: body.toString()
				});
				if (!response.ok) throw new Error(response.status === 403 ? 'LuCI session or artifact ACL rejected the request.' : 'Artifact request failed with HTTP ' + response.status + '.');
				var blob = await response.blob();
				if (blob.size !== expectedSize || blob.size > 16777216) throw new Error('The downloaded artifact did not match its authenticated metadata.');
				saveBlob(new Blob([ blob ], { type: artifact.content_type || 'application/octet-stream' }), artifact.filename);
			}
			catch (error) { showModal('Artifact Error', h('div', { class: 'ddk-alert ddk-alert-error' }, error.message)); }
		}
		function openSerialConsole(job) {
			var output=h('pre',{class:'ddk-job-output'},job.stdout || 'Waiting for serial output…');
			var input=h('textarea',{class:'ddk-input',rows:3,'aria-label':'Serial input'});
			var encoding=h('select',{class:'ddk-input','aria-label':'Encoding'},h('option',{value:'text'},'Text'),h('option',{value:'hex'},'Hex bytes'));
			var ending=h('select',{class:'ddk-input','aria-label':'Line ending'},h('option',{value:'crlf'},'CR + LF'),h('option',{value:'cr'},'CR'),h('option',{value:'lf'},'LF'),h('option',{value:'none'},'No line ending'));
			var message=h('p',{}),closed=false,timer;
			async function send() {
				try {var result=await exec(['job','send',job.id,structuredEnvelope({data:input.value,encoding:encoding.value,ending:ending.value})]);message.textContent=result.queued_bytes+' bytes queued';input.value='';}
				catch(error) {message.textContent=error.message;}
			}
			input.addEventListener('keydown',function(event){if(event.key==='Enter' && event.ctrlKey){event.preventDefault();send();}});
			showModal('Serial console · '+job.metadata.target_summary,h('div',{},output,input,h('div',{class:'ddk-action-row'},encoding,ending,button('Send (Ctrl+Enter)','',send)),message),null,function(){closed=true;clearTimeout(timer);});
			async function tick(){try{var state=await exec(['job','status',job.id]);if(closed)return;output.textContent=state.stdout || '';output.scrollTop=output.scrollHeight;if(state.status!=='running'){message.textContent='Session '+state.status;return;}}catch(error){message.textContent=error.message;}if(!closed)timer=setTimeout(tick,750);}
			tick();input.focus();
		}
		function renderJobList(jobs) {
			if (!jobs.length) { jobsNode.replaceChildren(h('div', { class: 'ddk-empty' }, 'No DDK jobs have run since the last reboot or cleanup.')); return; }
			jobsNode.replaceChildren(h('div', { class: 'ddk-job-list' }, jobs.map(function(job) {
				var active = [ 'queued', 'running', 'stopping' ].indexOf(job.status) >= 0;
				var output = (job.stdout ? '[STDOUT]\n' + job.stdout : '') + (job.stderr ? (job.stdout ? '\n\n' : '') + '[STDERR]\n' + job.stderr : '');
				var actions = [];
				if (active && job.metadata.action_id === 'cellular.profile') actions.push(button('Keep Cellular Settings','',async function(){ try{ await exec(['job','confirm-network',job.id]); await refresh(); }catch(error){showModal('Cellular Confirmation',h('p',{},error.message));} }));
				if (active && job.metadata.action_id === 'serial.console') actions.push(button('Open Serial Console', '', function() { openSerialConsole(job); }));
				if (active) actions.push(button('Stop and Keep Results', 'ddk-button-secondary', function() { stopJob(job.id); }));
				if (job.saved) actions.push(button('Export Case', 'ddk-button-secondary', function() { openOperatorAction('cases.export', async function(created) { await refresh(); poll(created.id); }, {case:job.id}); }));
				if (job.saved) actions.push(button('Name Case', 'ddk-button-secondary', async function() { var label=window.prompt('Case name',job.metadata.case_label || ''); if (!label) return; try { await exec(['job','label',job.id,structuredEnvelope({label:label})]); await refresh(); } catch(error) { showModal('Name Case',h('p',{},error.message)); } }));
				if (!active && !job.saved) actions.push(button('Save Across Reboots', 'ddk-button-secondary', async function() { try { await exec([ 'job', 'save', job.id ]); await refresh(); } catch (error) { showModal('Save Job', h('p', {}, error.message)); } }));
				if (!active) actions.push(button('Delete Job and Results', 'ddk-button-secondary', async function() { if (!window.confirm('Delete ' + job.id + ' and its results permanently?')) return; try { await exec([ 'job', 'delete', job.id ]); await refresh(); } catch (error) { showModal('Delete Job', h('p', {}, error.message)); } }));
				if (job.artifact && job.artifact.kind === 'camera_snapshot') {
					actions.push(button('View Snapshot', 'ddk-button-secondary', function() { viewSnapshot(job, false); }));
					actions.push(button('Download JPEG', 'ddk-button-secondary', function() { viewSnapshot(job, true); }));
				}
				(job.artifacts || []).forEach(function(artifact) {
					actions.push(button('Download ' + artifact.name + (artifact.partial ? ' (incomplete)' : ''), 'ddk-button-secondary', function() { downloadOperatorArtifact(job, artifact); }));
					var extension = artifact.name.split('.').pop().toLowerCase();
					var kind = ['pcap','pcapng','cap'].indexOf(extension)>=0 ? 'capture_input' : ['raw','img','squashfs','sqfs'].indexOf(extension)>=0 ? 'storage_image' : ['bin','hex','elf','uf2','dfu','fw','rom'].indexOf(extension)>=0 ? 'device_input' : ['txt','json','cfg','exe','dll','so','apk','zip'].indexOf(extension)>=0 ? 'forensics_input' : null;
					if (kind) actions.push(button('Reuse ' + artifact.name, 'ddk-button-secondary', async function() {
						try { var input=await exec(['job','reuse',job.id,artifact.name,kind]);var message=h('p',{},'Preparing input…');var modal=showModal('Preparing input',message);input=await waitForSealed(input,function(value){message.textContent=value;});modal.close();showModal('Input ready',h('p',{},input.original_name + ' is now available in tool input selectors. No download or re-upload is needed.')); }
						catch(error) {showModal('Reuse result',h('p',{},error.message));}
					}));
				});
				return h('article', { class: 'ddk-job', 'data-job':job.id }, h('div', { class: 'ddk-job-head' }, h('h4', {}, job.metadata.case_label || job.metadata.label || job.metadata.action_id || job.id), statePill(job.status)), h('p', { class: 'ddk-job-meta' }, (job.saved ? 'SAVED · ' : '') + job.id + ' · PID ' + (job.pid || 'pending') + ' · ' + (job.metadata.class || 'INFO')), output ? h('pre', { class: 'ddk-job-output' }, output) : null, actions.length ? h('div', { class: 'ddk-action-row' }, actions) : null);
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
        async function start(action) {
            if (action !== 'report.system') { openOperatorAction(action,async function(job){await refresh();poll(job.id);});return; }
            try {var job=await exec(['job','start',action]);await refresh();poll(job.id);}catch(error){showModal('Start Job',h('p',{},error.message));}
        }
		async function stopJob(id) { try { await exec([ 'job', 'stop', id ]); await refresh(); poll(id); } catch (error) { showModal('Job Error', h('div', { class: 'ddk-alert ddk-alert-error' }, error.message)); } }
		app.replaceChildren(
			brand('JOBS & CASES', 'Run tools, keep results, and return to saved work'),
			h('div', { class: 'ddk-alert ddk-alert-info' }, 'Two jobs may run at once. Stop keeps partial results. Save a finished job to preserve it across reboots, name the case, export it, or reuse an artifact as input. Unsaved job cleanup is configurable in Settings.'),
            sectionHeading('Start a workflow','Open a tool, select its target, and review the operation'),
            h('div',{class:'ddk-action-row'},
                button('Network Discovery','ddk-button-security',function(){start('network.nmap_lan_discovery');}),
                button('ARP Discovery','ddk-button-security',function(){start('network.arp_scan');}),
                button('Android Tools','ddk-button-action',function(){start('android.operator');}),
                button('Packet Capture','ddk-button-action',function(){start('capture.ring');}),
                button('Loss and Latency','',function(){start('network.fping');}),
                button('Serial Console','',function(){start('serial.console');}),
                button('Cellular Diagnostics','',function(){start('cellular.diagnostics');}),
                button('Recovery Imaging','',function(){start('storage.ddrescue');}),
                button('System Report','ddk-button-secondary',function(){start('report.system');}),
                h('a',{class:'ddk-button ddk-button-secondary',href:config.base+'/tools'},'All Tools'),
                button('Refresh','ddk-button-secondary',refresh)),
			sectionHeading('Jobs', 'Only DDK-owned worker PIDs can be stopped · artifacts require authenticated access'), jobsNode,
			sectionHeading('Reports', 'Authenticated view/download · 24-hour retention'), reportsNode);
		var jobs = await refresh(); jobs.forEach(function(job) { if ([ 'queued', 'running', 'stopping' ].indexOf(job.status) >= 0) poll(job.id); });
	}

	async function renderSettings() {
		var uploadKinds = {
			forensics_input: { label: 'Forensic analysis input', maximum: 8796093022208, extensions: '.bin, .exe, .dll, .elf, .so, .apk, .zip, .img, .raw, .txt, .rules, .yar, .yara, .json, .cfg, .pcap, .pcapng' },
			capture_input: { label: 'Packet replay capture', maximum: 8796093022208, extensions: '.pcap, .pcapng, .cap' },
			firmware_image: { label: 'Firmware / programmer image', maximum: 8796093022208, extensions: '.bin, .hex, .elf, .uf2, .dfu, .fw, .rom, .img' },
			storage_image: { label: 'Storage / recovery image', maximum: 8796093022208, extensions: '.raw, .img, .bin, .dd, .squashfs, .sqfs' },
			android_package: { label: 'Android package', maximum: 8796093022208, extensions: '.apk, .apks, .zip' },
			android_backup: { label: 'Android ADB backup', maximum: 8796093022208, extensions: '.ab' },
			apple_restore: { label: 'Apple IPSW restore archive', maximum: 8796093022208, extensions: '.ipsw, .zip' },
			apple_recovery_input: { label: 'Apple recovery / DFU input', maximum: 8796093022208, extensions: '.bin, .img, .dfu, .ibss, .ibec, .payload, .txt, .script, .cfg' },
			apple_ticket: { label: 'Apple AP ticket', maximum: 1048576, extensions: '.shsh, .ticket, .bin, .plist' },
			device_input: { label: 'Device workflow input', maximum: 8796093022208, extensions: '.bin, .hex, .elf, .uf2, .dfu, .fw, .rom, .img, .cfg, .json, .zip, .tar, .gz' }
		};
		var kindSelect = h('select', { class: 'ddk-select' }, Object.keys(uploadKinds).map(function(kind) {
			return h('option', { value: kind }, uploadKinds[kind].label);
		}));
		var fileInput = h('input', { class: 'ddk-input', type: 'file' });
		var uploadStatus = h('div', { class: 'ddk-alert ddk-alert-info' }, 'Choose a file to upload. Available router storage determines how much it can hold. Files become ready for use after their integrity check finishes.');
		var uploadsNode = h('div', { class: 'ddk-job-list' }, h('div', { class: 'ddk-empty' }, 'Loading sealed inputs…'));
		var uploadButton;

		function selectedUploadPolicy() { return uploadKinds[kindSelect.value]; }
		function updateUploadHint() {
			var policy = selectedUploadPolicy();
			uploadStatus.className = 'ddk-alert ddk-alert-info';
			uploadStatus.textContent = 'Allowed: ' + policy.extensions + ' · maximum ' + formatBytes(policy.maximum) + ' · inactive reservations expire after one hour; active transfers are retained.';
		}
		function renderUploads(uploads) {
			if (!uploads.length) {
				uploadsNode.replaceChildren(h('div', { class: 'ddk-empty' }, 'No sealed Operator Mode input files are retained.'));
				return;
			}
			var uploadNodes = uploads.map(function(upload) {
				var removeButton;
				return h('article', { class: 'ddk-job' },
					h('div', { class: 'ddk-job-head' }, h('h4', {}, upload.original_name), statePill((upload.phase || 'sealed').toUpperCase())),
					h('p', { class: 'ddk-job-meta' }, upload.id + ' · ' + upload.kind + ' · ' + formatBytes(upload.size)),
					row('SHA-256', upload.sha256),
					upload.phase==='sealing' ? row('Hash progress',formatBytes(upload.hash_bytes || 0)+' / '+formatBytes(upload.size)) : null,
					row('Expires', new Date(Number(upload.expires_at) * 1000).toLocaleString()),
					h('div', { class: 'ddk-action-row' }, removeButton = button('Delete Sealed Input', 'ddk-button-secondary', async function() {
						if (!window.confirm('Delete sealed DDK input?\n\nFile: ' + upload.original_name + '\nID: ' + upload.id + '\nSHA-256: ' + upload.sha256 + '\n\nThis cannot be undone.')) return;
						removeButton.disabled = true;
						try { await exec([ 'upload', 'delete', upload.id ]); await refreshUploads(); }
						catch (error) { removeButton.disabled = false; showModal('Upload Delete Rejected', h('div', { class: 'ddk-alert ddk-alert-error' }, error.message)); }
					})));
			});
			uploadsNode.replaceChildren.apply(uploadsNode, uploadNodes);
		}
		async function refreshUploads() {
			try { renderUploads(await exec([ 'upload', 'list' ])); }
			catch (error) { uploadsNode.replaceChildren(h('div', { class: 'ddk-alert ddk-alert-error' }, error.message)); }
		}
		async function stageUpload() {
			var file = fileInput.files && fileInput.files[0];
			var policy = selectedUploadPolicy();
			if (!file) { showModal('Upload Input Required', h('div', { class: 'ddk-alert ddk-alert-error' }, 'Choose one local file first.')); return; }
			if (!Number.isSafeInteger(file.size) || file.size < 1 || file.size > policy.maximum) {
				showModal('Upload Size Rejected', h('div', { class: 'ddk-alert ddk-alert-error' }, 'The selected file must be between 1 byte and ' + formatBytes(policy.maximum) + '.'));
				return;
			}
			uploadButton.disabled = true;
			var reservation = null;
			try {
				uploadStatus.className = 'ddk-alert ddk-alert-info';
				uploadStatus.textContent = 'Reserving an isolated DDK path…';
				reservation = await exec([ 'upload', 'reserve', kindSelect.value, structuredEnvelope({ name: file.name, size: file.size }) ]);
				await uploadFile(reservation, file, function(percent) { uploadStatus.textContent = 'Uploading ' + file.name + '… ' + percent + '%'; });
				uploadStatus.textContent = 'Validating size, signature, and SHA-256 on the router…';
				var sealed = await exec([ 'upload', 'finalize', reservation.id ]);
				sealed = await waitForSealed(sealed,function(value){uploadStatus.textContent=value;});
				uploadStatus.textContent = 'Sealed ' + sealed.original_name + ' as ' + sealed.id + ' · SHA-256 ' + sealed.sha256;
				fileInput.value = '';
				await refreshUploads();
			}
			catch (error) {
				uploadStatus.className = 'ddk-alert ddk-alert-error';
				uploadStatus.textContent = error.message;
				if (reservation) {
					try { await exec([ 'upload', 'delete', reservation.id ]); } catch (_) {}
				}
			}
			finally { uploadButton.disabled = false; }
		}
        var retained = await exec(['settings','get']);
        var retainHours=h('input',{class:'ddk-input',type:'number',min:0,max:87600,value:retained.job_hours});
        var retainCount=h('input',{class:'ddk-input',type:'number',min:0,max:10000,value:retained.job_count});
        var inputHours=h('input',{class:'ddk-input',type:'number',min:0,max:87600,value:retained.input_hours});
        var retainedStatus=h('p',{});
        var retentionCard=card('Jobs and saved cases','RETENTION',[
            h('p',{},'Saved cases remain until you delete them. Stop keeps partial results; Save Across Reboots preserves the job as a case. Unsaved jobs use the cleanup settings below. Zero disables that cleanup limit.'),
            h('div',{class:'ddk-upload-grid'},h('label',{},'Unsaved job age (hours)',retainHours),h('label',{},'Unsaved job count',retainCount),h('label',{},'New sealed input lifetime (hours)',inputHours)),
            button('Save Retention Settings','',async function(){try{await exec(['settings','set',structuredEnvelope({job_hours:Number(retainHours.value),job_count:Number(retainCount.value),input_hours:Number(inputHours.value)})]);retainedStatus.textContent='Saved. Job cleanup applies on the next refresh; input lifetime applies to newly sealed inputs.';}catch(error){retainedStatus.textContent=error.message;}}),retainedStatus
        ],'ddk-card-full');
        kindSelect.addEventListener('change', updateUploadHint);
        uploadButton = button('Upload & Seal Input', 'ddk-button-action', stageUpload);
        app.replaceChildren(brand('SETTINGS','Case storage and reusable input files'),retentionCard,
            card('Upload input files','SEALED INPUT',[
                h('div',{class:'ddk-upload-grid'},h('label',{},'Input kind',kindSelect),h('label',{},'Local file',fileInput)),uploadStatus,
                h('div',{class:'ddk-action-row'},uploadButton,button('Refresh Inputs','ddk-button-secondary',refreshUploads)),
                h('p',{},'Up to 64 sealed inputs are retained. Jobs can reuse their saved results directly. Available storage is checked before each operation.'),uploadsNode
            ],'ddk-card-full'),
            card('Running tools','V3',[
                h('p',{},'Choose a workflow in Tools, select its target and operation, then review the command preview. Readiness is checked for the operation you choose. Missing hardware does not hide the controls.'),
                h('p',{},'Two jobs can run concurrently on this 121 MB router. Operations lock the selected device or resource. Streaming and capture sessions have adjustable output budgets and can run until stopped. Outputs reserve free space for the router.'),
                h('p',{},'Access uses your authenticated LuCI session. Temporary helpers belong to their jobs and are stopped with them. No background dashboard service is needed.')
            ],'ddk-card-full'));

		updateUploadHint();
		await refreshUploads();
	}

	var renderers = { overview: renderOverview, tools: renderTools, packages: renderPackages, jobs: renderJobs, settings: renderSettings };
	Promise.resolve(renderers[config.page] || renderOverview).then(function(renderer) { return renderer(); }).catch(showError);
})();
