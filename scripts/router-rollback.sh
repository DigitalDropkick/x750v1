#!/bin/sh

set -eu
umask 077

backup_path="${1:-}"

fail() {
	printf 'ROLLBACK REFUSED: %s\n' "$1" >&2
	exit 1
}

allowed_target() {
	case "$1" in
		*..*|*[!A-Za-z0-9_./-]*) return 1 ;;
	esac
	case "$1" in
		/usr/share/luci/menu.d/ddk-field-console.json) return 0 ;;
		/usr/share/rpcd/acl.d/ddk-field-console.json) return 0 ;;
		/usr/lib/lua/luci/view/ddk/*) return 0 ;;
		/www/luci-static/resources/ddk/*) return 0 ;;
		/www/ddk/gl_home.html) return 0 ;;
		# Retained only so backups from pre-template DDK builds remain removable.
		/www/luci-static/resources/view/ddk/*) return 0 ;;
		/usr/libexec/ddk-console|/usr/libexec/ddk-job-worker|/usr/libexec/ddk-apple-worker|/usr/libexec/ddk-phase3-worker|/usr/libexec/ddk-phase4-worker) return 0 ;;
		/usr/share/ddk-field-console/*) return 0 ;;
		*) return 1 ;;
	esac
}

if [ -z "$backup_path" ]; then
	[ -f /root/ddk-backups/ddk-field-console-latest ] || fail 'latest-backup pointer is missing'
	backup_path="$(cat /root/ddk-backups/ddk-field-console-latest)"
fi

case "$backup_path" in /root/ddk-backups/*) ;; *) fail 'backup path is outside /root/ddk-backups' ;; esac
backup_name="${backup_path#/root/ddk-backups/}"
case "$backup_name" in
	[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]T[0-9][0-9][0-9][0-9][0-9][0-9]Z-field-console-v1|\
	[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]T[0-9][0-9][0-9][0-9][0-9][0-9]Z-field-console-v1-[0-9]*) ;;
	*) fail 'backup name does not match a DDK Field Console backup' ;;
esac
case "$backup_name" in *..*|*/*|*[!A-Za-z0-9_.-]*) fail 'backup name contains unsafe characters' ;; esac

[ -d "$backup_path" ] || fail 'backup directory does not exist'
[ -f "$backup_path/existing.list" ] || fail 'existing-file manifest is missing'
[ -f "$backup_path/new.list" ] || fail 'new-file manifest is missing'

while IFS= read -r target; do
	[ -n "$target" ] || continue
	allowed_target "$target" || fail "existing-file target is outside the allowlist: $target"
	backup_file="$backup_path/files$target"
	[ -f "$backup_file" ] || [ -L "$backup_file" ] || fail "backup copy is missing: $target"
	temporary="$target.ddk-rollback-$$"
	mkdir -p "$(dirname "$target")"
	cp -p "$backup_file" "$temporary"
	mv "$temporary" "$target"
done < "$backup_path/existing.list"

while IFS= read -r target; do
	[ -n "$target" ] || continue
	allowed_target "$target" || fail "new-file target is outside the allowlist: $target"
	rm -f -- "$target"
done < "$backup_path/new.list"

rmdir /usr/lib/lua/luci/view/ddk 2>/dev/null || true
rmdir /www/luci-static/resources/view/ddk 2>/dev/null || true
rmdir /www/luci-static/resources/ddk 2>/dev/null || true
rmdir /www/ddk 2>/dev/null || true
rmdir /usr/share/ddk-field-console/tools 2>/dev/null || true
rmdir /usr/share/ddk-field-console 2>/dev/null || true
[ -d /tmp/luci-indexcache ] || rm -f /tmp/luci-indexcache
/etc/init.d/rpcd reload

printf 'Restored DDK backup: %s\n' "$backup_path"
printf '%s\n' 'Rollback completed. rpcd ACLs were reloaded; no service was restarted and no configuration file was changed.'
