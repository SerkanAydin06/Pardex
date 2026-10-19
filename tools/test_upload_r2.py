import hashlib
import json
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock
from upload_r2 import upload

class UploadTest(unittest.TestCase):
    @mock.patch('upload_r2.shutil.which', return_value='/usr/local/bin/aws')
    def test_publication_order_and_failures(self, _which):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'packages').mkdir()
            digest = hashlib.sha256(b'game').hexdigest()
            name = digest + '.zip'
            package = root / 'packages' / name
            package.write_bytes(b'game')
            art = hashlib.sha256(b'png').hexdigest() + '.png'
            (root / 'packages' / art).write_bytes(b'png')
            manifest = {'schema':1, 'launcher':{}, 'games':[{'package':{
                'url':'https://example.workers.dev/packages/'+name, 'sha256':digest, 'size':4},
                'screenshots':[{'url':'https://example.workers.dev/packages/'+art, 'sha256':art[:64], 'size':3}]}]}
            (root / 'channel.json').write_text(json.dumps(manifest))
            calls = []
            uploaded = set()
            def run(command, check, capture_output=False):
                calls.append(command)
                if 'head-object' in command:
                    self.assertFalse(check)
                    key = command[command.index('--key') + 1]
                    return subprocess.CompletedProcess(command, 0 if key in uploaded else 255)
                self.assertTrue(check)
                return subprocess.CompletedProcess(command, 0)
            copies = lambda: [c for c in calls if 'cp' in c]
            args = (root, 'https://example.workers.dev', 'a'*32)
            upload(*args, run=run, sleep=lambda _s: None)
            self.assertEqual(len(copies()), 3)
            self.assertIn('s3://pardex-releases/packages/'+name, copies()[0])
            self.assertIn('s3://pardex-releases/packages/'+art, copies()[1])
            self.assertIn('image/png', copies()[1])
            self.assertIn('s3://pardex-releases/channel.json', copies()[2])
            # Packages already in R2 are not uploaded again; the catalog always is.
            calls.clear()
            uploaded.update({'packages/'+name, 'packages/'+art})
            upload(*args, run=run, sleep=lambda _s: None)
            self.assertEqual(len(copies()), 1)
            self.assertIn('s3://pardex-releases/channel.json', copies()[0])
            uploaded.clear()
            # A dropped connection is retried; the catalog is published afterwards.
            calls.clear()
            failures = [1]
            def flaky(command, check, capture_output=False):
                if 'cp' in command and failures and 'packages/'+name in ' '.join(command):
                    failures.pop()
                    calls.append(command)
                    raise subprocess.CalledProcessError(1, command)
                return run(command, check, capture_output)
            upload(*args, run=flaky, sleep=lambda _s: None)
            self.assertEqual(len([c for c in copies() if 'packages/'+name in ' '.join(c)]), 2)
            self.assertIn('s3://pardex-releases/channel.json', copies()[-1])
            # Still failing after all attempts: the catalog is never published.
            calls.clear()
            def fail(command, check, capture_output=False):
                if 'head-object' in command:
                    return run(command, check, capture_output)
                calls.append(command)
                raise subprocess.CalledProcessError(1, command)
            with self.assertRaises(subprocess.CalledProcessError):
                upload(*args, run=fail, sleep=lambda _s: None)
            self.assertFalse(any('channel.json' in ' '.join(c) for c in copies()))
            self.assertEqual(len(copies()), 3)  # three attempts for the first package
            calls.clear()
            package.write_bytes(b'evil')
            with self.assertRaises(ValueError):
                upload(*args, run=run)
            self.assertEqual(calls, [])
            with self.assertRaises(ValueError):
                upload(root, 'https://wrong.workers.dev', 'a'*32, run=run)

if __name__ == '__main__':
    unittest.main()
