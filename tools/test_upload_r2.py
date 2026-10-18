import hashlib
import json
import subprocess
import tempfile
import unittest
from pathlib import Path
from upload_r2 import upload

class UploadTest(unittest.TestCase):
    def test_publication_order_and_failures(self):
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
                'cover':{'url':'https://example.workers.dev/packages/'+art, 'sha256':art[:64], 'size':3}}]}
            (root / 'channel.json').write_text(json.dumps(manifest))
            calls = []
            def run(command, check):
                self.assertTrue(check)
                calls.append(command)
            args = (root, 'https://example.workers.dev', 'a'*32)
            upload(*args, run=run)
            self.assertEqual(len(calls), 3)
            self.assertIn('s3://pardex-releases/packages/'+name, calls[0])
            self.assertIn('s3://pardex-releases/packages/'+art, calls[1])
            self.assertIn('image/png', calls[1])
            self.assertIn('s3://pardex-releases/channel.json', calls[2])
            calls.clear()
            def fail(command, check):
                calls.append(command)
                raise subprocess.CalledProcessError(1, command)
            with self.assertRaises(subprocess.CalledProcessError):
                upload(*args, run=fail)
            self.assertEqual(len(calls), 1)  # Catalog never published after failure.
            calls.clear()
            package.write_bytes(b'evil')
            with self.assertRaises(ValueError):
                upload(*args, run=run)
            self.assertEqual(calls, [])
            with self.assertRaises(ValueError):
                upload(root, 'https://wrong.workers.dev', 'a'*32, run=run)

if __name__ == '__main__':
    unittest.main()
