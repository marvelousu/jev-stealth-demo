import tempfile
from pathlib import Path
import unittest

from prepare_distribution import public_url, stage_client, archive_client


class DistributionTests(unittest.TestCase):
    def test_dotted_version_preserves_previous_archive(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            old = root / 'client-v5.zip'
            old.write_bytes(b'previous release')
            destination = root / 'client-v5.1'
            destination.mkdir()
            (destination / 'README.txt').write_text('demo', encoding='utf-8')
            archive = archive_client(destination)
            self.assertEqual(archive.name, 'client-v5.1.zip')
            self.assertEqual(old.read_bytes(), b'previous release')
            with self.assertRaises(FileExistsError):
                archive_client(destination)

    def test_rejects_credentials_and_local_or_unencrypted_targets(self):
        for url in (
            'http://demo.example.org', 'https://key@demo.example.org',
            'https://demo.example.org?key=secret', 'https://demo.example.org#key',
            'https://localhost', 'https://127.0.0.1', 'https://192.168.1.10',
            'https://[::1]', 'https://demo.local', 'https://demo.invalid',
            'https://demo.example.org:8789', 'https://demo.example.org/\nsetting',
        ):
            with self.subTest(url=url), self.assertRaises(ValueError):
                public_url(url)

    def test_clean_bundle_has_only_game_and_audio(self):
        with tempfile.TemporaryDirectory() as temporary:
            destination = Path(temporary) / 'client'
            stage_client(destination, 'https://demo.example.org/relay/')
            files = {p.relative_to(destination).as_posix() for p in destination.rglob('*') if p.is_file()}
            self.assertEqual(files, {
                'project.godot', 'main.tscn', 'main.gd', 'level.gd',
                'tactics.gd', 'replay.gd', 'mission.gd', 'briefing.gd', 'decision_history.gd', 'decision_gate.gd', 'mission_feedback.gd',
                'explanation.gd', 'tactical_view.gd',
                'courtyard.gd', 'courtyard.tscn', 'courtyard_replay.gd',
                'audio/alert.wav', 'audio/noise.wav', 'audio/pickup.wav',
                'audio/shot.wav', 'audio/smoke.wav',
                'audio/bgm.ogg',
            })
            self.assertFalse(any(path.startswith(('qa/', 'backend/')) for path in files))
            self.assertIn('service_url="https://demo.example.org/relay"', (destination / 'project.godot').read_text(encoding='utf-8'))
            with self.assertRaises(FileExistsError):
                stage_client(destination, 'https://demo.example.org')


if __name__ == '__main__':
    unittest.main()
