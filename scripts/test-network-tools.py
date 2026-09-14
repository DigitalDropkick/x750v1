#!/usr/bin/env python3
"""Network helper parsing, credentials, native argv and transfer lifecycle tests."""
import argparse
import contextlib
import importlib.machinery
import io
import json
from pathlib import Path
import tempfile
import unittest
import sys
from unittest.mock import patch

sys.dont_write_bytecode = True
helper = importlib.machinery.SourceFileLoader("network_tools", "files/usr/libexec/ddk-network-tools").load_module()
VALID = '<nmaprun><host><status state="up"/></host><runstats><finished exit="success"/></runstats></nmaprun>'


class NetworkTests(unittest.TestCase):
    def test_scan_validation_and_ndiff_exit_codes(self):
        with tempfile.TemporaryDirectory() as tmp:
            before, after = Path(tmp)/"before.xml", Path(tmp)/"after.xml"
            before.write_text('<!DOCTYPE nmaprun>\n' + VALID)
            after.write_text(VALID)
            with patch.object(helper, "run", return_value=1) as native, contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(helper.compare(argparse.Namespace(baseline=str(before), current=str(after))), 1)
                self.assertEqual(native.call_args.args[0], ["/usr/bin/ndiff", "--text", str(before), str(after)])
            attacks = ['<!DOCTYPE nmaprun SYSTEM "file:///etc/passwd">' + VALID,
                       '<!DOCTYPE nmaprun [<!ENTITY x SYSTEM "https://example.invalid/">]>' + VALID,
                       '<notnmap/>', '<nmaprun><host/></nmaprun>', VALID.encode('utf-16')]
            for attack in attacks:
                after.write_bytes(attack if isinstance(attack, bytes) else attack.encode())
                with self.assertRaises((ValueError, helper.sys.modules['xml.etree.ElementTree'].ParseError)):
                    helper.validate_scan(after)
            # The permitted doctype can cross a 64KiB read boundary.
            after.write_text(' ' * 65530 + '<!DOCTYPE nmaprun>' + VALID)
            helper.validate_scan(after)

    def test_snmp_credentials_are_private_files_and_not_argv(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); password=root/'secret'; password.write_text('fixture "quoted" \\ value')
            a=argparse.Namespace(workspace=str(root/'workspace'), private_dir=str(root/'private'), host='2001:db8::4', port=161, timeout=2,retries=1,profile='system',oid='.1.3.6.1',version='2c',community=str(password))
            with patch.object(helper, 'run', return_value=0) as native:
                self.assertEqual(helper.snmp(a),0)
                argv=native.call_args.args[0]
                self.assertNotIn(password.read_text(), ' '.join(argv))
                self.assertIn('udp6:[2001:db8::4]:161', argv)
                config=root/'private/snmp.conf'
                self.assertEqual(config.stat().st_mode & 0o777, 0o600)
                self.assertIn('defCommunity "fixture \\"quoted\\" \\\\ value"', config.read_text())
                self.assertEqual(native.call_args.kwargs['env']['SNMPCONFPATH'],str(root/'private'))
                self.assertFalse((root/'workspace/snmp.conf').exists())

    def test_smb_transfer_uses_only_owned_names_and_cleanup_survives_interruption(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)
            a=argparse.Namespace(workspace=str(root/'workspace'),private_dir=str(root/'private'),host='192.0.2.4',port=445,operation='transfer',share='Job files;not-a-command',path='Folder with spaces;not-a-command',username='guest',domain='none',password='none',guest='yes',protocol='SMB2',timeout=3,transfer_mib=1)
            seen=[]
            def native(argv, **_):
                seen.append(argv)
                if 'get ' in argv[-1]:
                    (root/'workspace/probe-download.bin').write_bytes((root/'workspace/probe-upload.bin').read_bytes())
                return 0
            with patch.object(helper,'run',side_effect=native), contextlib.redirect_stdout(io.StringIO()) as report:
                self.assertEqual(helper.smb(a),0)
                state=json.loads((root/'workspace/smb-probe.json').read_text())
                self.assertRegex(state['probe'],r'^orbit-test-[a-f0-9]{32}\.bin$')
                self.assertNotIn(a.share,seen[0][-1]);self.assertNotIn(a.path,seen[0][-1])
                self.assertIn(a.path,seen[0])
                self.assertIn('Transfer verified: PASS',report.getvalue())
                self.assertEqual(helper.smb_cleanup(a.workspace,a.private_dir),0)
                self.assertFalse((root/'workspace/smb-probe.json').exists())
                self.assertTrue(seen[-1][-1].startswith('del orbit-test-'))
            # Worker cleanup is a fresh helper process; a failed deletion retains
            # its precise owned filename for reporting instead of claiming success.
            (root/'workspace/smb-probe.json').write_text(json.dumps(state))
            with patch.object(helper,'run',return_value=1),contextlib.redirect_stdout(io.StringIO()) as report:
                self.assertEqual(helper.smb_cleanup(a.workspace,a.private_dir),1)
                self.assertIn(state['probe'],report.getvalue())
                self.assertTrue((root/'workspace/smb-probe.json').exists())

    def test_secret_line_injection_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp)/'secret';p.write_text('value\ndefVersion 1')
            with self.assertRaises(ValueError):helper.secret(str(p))
        with self.assertRaises(ValueError):helper.quoted('value\nincludeFile /etc/passwd')


if __name__ == '__main__':
    unittest.main()
