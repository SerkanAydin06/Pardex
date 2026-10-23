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
            # Artwork and genres are published with the game.
            (root/'cover.png').write_bytes(b'\x89PNG fixture')
            spec['games'][0].update(cover=str(root/'cover.png'), genres=['Bulmaca'], screenshots=[str(root/'cover.png')], long_description='Ayrıntılı açıklama', requirements='Windows', release_notes='İlk sürüm', connection_modes='Tek oyunculu')
            manifest=publish(spec,'https://distribution.invalid',out)
            cover=manifest['games'][0]['cover']
            self.assertTrue(cover['url'].endswith('.png'))
            self.assertTrue((out/'packages'/cover['url'].split('/')[-1]).is_file())
            self.assertEqual(manifest['games'][0]['genres'],['Bulmaca'])
            self.assertEqual(manifest['games'][0]['screenshots'][0], cover)
            self.assertEqual(manifest['games'][0]['long_description'], 'Ayrıntılı açıklama')
            self.assertNotIn('test', manifest['games'][0])
            spec['games'][0]['test'] = True
            self.assertIs(publish(spec,'https://distribution.invalid',out)['games'][0]['test'], True)
            spec['games'][0]['test'] = False
            self.assertNotIn('test', publish(spec,'https://distribution.invalid',out)['games'][0])
            spec['games'][0]['screenshots'] = [str(root/'cover.png')] * 9
            with self.assertRaises(ValueError): publish(spec,'https://distribution.invalid',out)
            spec['games'][0]['screenshots'] = [str(root/'cover.png')]
            (root/'cover.txt').write_text('x')
            spec['games'][0]['cover']=str(root/'cover.txt')
            with self.assertRaises(ValueError): publish(spec,'https://distribution.invalid',out)
            spec['games'][0]['cover']=str(root/'cover.png')
            spec['games'][0]['genres']=['a','b','c','d','e']
            with self.assertRaises(ValueError): publish(spec,'https://distribution.invalid',out)
            spec['games'][0]['genres']=['Bulmaca']
            publish(spec,'https://distribution.invalid',out)
            previous=(out/'channel.json').read_bytes()
            spec['games'][0]['executable']='../outside.exe'
            with self.assertRaises(ValueError): publish(spec,'https://distribution.invalid',out)
            self.assertEqual((out/'channel.json').read_bytes(),previous)
            self.assertEqual(json.loads(previous)['games'][0]['version'],'1.0.0')
    def test_reject_insecure_host(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(ValueError): publish({},'http://example.com',Path(directory))

if __name__=='__main__': unittest.main()
