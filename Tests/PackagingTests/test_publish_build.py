"""Exercise artifact publication against a temporary local bare repository, never GitHub."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[2] / 'scripts' / 'publish-build.sh'


class PublishBuildTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.repo = self.root / 'source'
        self.repo.mkdir()
        self.remote = self.root / 'remote.git'
        self.run_git('init', '--bare', str(self.remote))
        self.run_git('init', '-b', 'solo-island')
        self.run_git('config', 'user.name', 'Packaging Test')
        self.run_git('config', 'user.email', 'test@example.invalid')
        (self.repo / 'scripts').mkdir()
        shutil.copy(SCRIPT, self.repo / 'scripts' / 'publish-build.sh')
        (self.repo / 'source.txt').write_text('preserve me')
        self.run_git('add', '.')
        self.run_git('commit', '-m', 'Fixture')
        self.run_git('remote', 'add', 'origin', str(self.remote))
        self.run_git('push', 'origin', 'HEAD:solo-island')
        self.sha = self.run_git('rev-parse', 'HEAD').strip()
        (self.repo / 'dist').mkdir()
        (self.repo / 'dist' / 'SoloIsland.dmg').write_bytes(b'fixture, not a real disk image')
        self.env = dict(os.environ, GITHUB_ACTIONS='true', GITHUB_EVENT_NAME='push',
                        GITHUB_REF='refs/heads/solo-island', GITHUB_SHA=self.sha,
                        GITHUB_REPOSITORY='fixture/solo', GITHUB_RUN_ID='1',
                        RUNNER_TEMP=str(self.root), BUILD_RESULT='success')
        (self.root / 'solo-build.log').write_text('build log fixture')

    def run_git(self, *args):
        return subprocess.check_output(['git', *args], cwd=self.repo, stderr=subprocess.DEVNULL, text=True)

    def publish(self, **overrides):
        return subprocess.run(['bash', 'scripts/publish-build.sh'], cwd=self.repo,
                              env=dict(self.env, **overrides), text=True, capture_output=True)

    def inspect(self, filename):
        self.run_git('fetch', 'origin', 'solo-island-builds')
        return self.run_git('show', 'FETCH_HEAD:' + filename)

    def test_success_publishes_dmg_and_checksum_without_modifying_source(self):
        # Old recordings can remain in dist on a reused checkout. They must never
        # return to the artifact branch after the promo cleanup.
        for filename in ('SoloIsland-opening.gif', 'SoloIsland-focus-motion.gif',
                         'SoloIsland-focus-motion.json', 'SoloIsland-interactions.zip',
                         'SoloIsland-interactions.zip.part-aa',
                         'SoloIsland-interactions.zip.sha256',
                         'SoloIsland-promo-vertical.mp4', 'soundtrack.wav'):
            (self.repo / 'dist' / filename).write_bytes(b'old recording fixture')
        (self.repo / 'dist' / 'SoloIsland-preview.png').write_bytes(b'still preview fixture')
        index_before = (self.repo / '.git' / 'index').read_bytes()
        result = self.publish()
        self.assertEqual(result.returncode, 0, result.stderr)
        info = json.loads(self.inspect('build-info.json'))
        self.assertEqual(info['result'], 'success')
        self.assertEqual(info['source_commit'], self.sha)
        self.assertIn('fixture, not a real disk image', self.inspect('SoloIsland.dmg'))
        self.assertIn('  SoloIsland.dmg', self.inspect('SoloIsland.dmg.sha256'))
        self.assertEqual(set(self.run_git('ls-tree', '--name-only', 'FETCH_HEAD').splitlines()),
                         {'SoloIsland.dmg', 'SoloIsland.dmg.sha256', 'preview.png',
                          'build-info.json', 'build.log'})
        self.assertEqual((self.repo / '.git' / 'index').read_bytes(), index_before)
        self.assertEqual(self.run_git('rev-parse', 'HEAD').strip(), self.sha)
        self.assertEqual((self.repo / 'source.txt').read_text(), 'preserve me')

    def test_failed_build_replaces_previous_output_without_stale_dmg(self):
        self.assertEqual(self.publish().returncode, 0)
        result = self.publish(BUILD_RESULT='failure')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(self.inspect('build-info.json'))['result'], 'failure')
        self.assertEqual(self.inspect('build.log'), 'build log fixture')
        names = self.run_git('ls-tree', '--name-only', 'FETCH_HEAD').splitlines()
        self.assertNotIn('SoloIsland.dmg', names)
        self.assertEqual(len(self.run_git('rev-list', 'FETCH_HEAD').splitlines()), 2)

    def test_stale_source_cannot_publish(self):
        result = self.publish(GITHUB_SHA='0' * 40)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('skipping stale', result.stdout)
        self.assertEqual(self.run_git('ls-remote', 'origin', 'refs/heads/solo-island-builds'), '')

    def test_local_execution_is_rejected(self):
        self.assertNotEqual(self.publish(GITHUB_ACTIONS='false').returncode, 0)
        self.assertEqual(self.run_git('ls-remote', 'origin', 'refs/heads/solo-island-builds'), '')


if __name__ == '__main__':
    unittest.main()
