import json, tempfile, unittest, zipfile
from pathlib import Path
from publish_release import publish

class PublishTest(unittest.TestCase):
    def test_publish_and_preserve_previous_manifest(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory); game=root/'game'; game.mkdir(); (game/'Game.exe').write_bytes(b'fixture')
            out=root/'public'
            spec={'games':[{'id':'fixture','title':'Fixture','version':'1.0.0','directory':str(game),'executable':'Game.exe'}]}
            manifest=publish(spec,'https://distribution.invalid',out)
            package=manifest['games'][0]['package']
            with zipfile.ZipFile(out/'packages'/package['url'].split('/')[-1]) as archive:
                self.assertEqual(archive.read('Game.exe'),b'fixture')
            previous=(out/'channel.json').read_bytes()
            spec['games'][0]['executable']='../outside.exe'
            with self.assertRaises(ValueError): publish(spec,'https://distribution.invalid',out)
            self.assertEqual((out/'channel.json').read_bytes(),previous)
            self.assertEqual(json.loads(previous)['games'][0]['version'],'1.0.0')
    def test_reject_insecure_host(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(ValueError): publish({},'http://example.com',Path(directory))

if __name__=='__main__': unittest.main()
