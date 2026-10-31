"""Verify preview isolation against a local bare Git repository."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[2] / 'scripts' / 'publish-preview.sh'


class PublishPreviewTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.repo = self.root / 'source'
        self.repo.mkdir()
        self.remote = self.root / 'remote.git'
        self.git('init', '--bare', str(self.remote))
        self.git('init', '-b', 'solo-island')
        self.git('config', 'user.name', 'Packaging Test')
        self.git('config', 'user.email', 'test@example.invalid')
        (self.repo / 'source.txt').write_text('public source')
        (self.repo / '.gitignore').write_text('dist/\n')
        self.git('add', '.')
        self.git('commit', '-m', 'Public fixture')
        self.public_sha = self.git('rev-parse', 'HEAD').strip()
        self.git('remote', 'add', 'origin', str(self.remote))
        self.git('push', 'origin', 'HEAD:solo-island', 'HEAD:solo-island-builds')
        self.branch = 'preview/notch-test'
        self.git('switch', '-c', self.branch)
        (self.repo / 'scripts').mkdir()
        shutil.copy(SCRIPT, self.repo / 'scripts' / 'publish-preview.sh')
        self.git('add', '.')
        self.git('commit', '-m', 'Preview fixture')
        self.sha = self.git('rev-parse', 'HEAD').strip()
        self.git('push', 'origin', 'HEAD:' + self.branch)
        (self.repo / 'dist').mkdir()
        (self.repo / 'dist' / 'SoloIsland.dmg').write_bytes(b'fixture, not an installer')
        (self.root / 'solo-build.log').write_text('preview log')
        self.env = dict(os.environ, GITHUB_ACTIONS='true', GITHUB_EVENT_NAME='push',
                        GITHUB_REF='refs/heads/' + self.branch, GITHUB_SHA=self.sha,
                        GITHUB_REPOSITORY='fixture/solo', GITHUB_RUN_ID='1',
                        RUNNER_TEMP=str(self.root), BUILD_RESULT='success')

    def git(self, *args):
        return subprocess.check_output(['git', *args], cwd=self.repo,
                                       stderr=subprocess.DEVNULL, text=True)

    def publish(self, **overrides):
        return subprocess.run(['bash', 'scripts/publish-preview.sh'], cwd=self.repo,
                              env=dict(self.env, **overrides), text=True, capture_output=True)

    def output(self):
        self.git('fetch', 'origin', self.branch)
        return self.git('rev-parse', 'FETCH_HEAD').strip()

    def assert_public_unchanged(self):
        for branch in ('solo-island', 'solo-island-builds'):
            self.assertEqual(self.git('ls-remote', 'origin', 'refs/heads/' + branch).split()[0],
                             self.public_sha)

    def test_success_preserves_sources_and_public_refs_and_excludes_recordings(self):
        (self.repo / 'dist' / 'SoloIsland-notch-music.png').write_bytes(b'still fixture')
        for name in ('SoloIsland-opening.gif', 'SoloIsland-promo-vertical.mp4', 'soundtrack.wav'):
            (self.repo / 'dist' / name).write_bytes(b'never publish')
        index_before = (self.repo / '.git' / 'index').read_bytes()
        result = self.publish()
        self.assertEqual(result.returncode, 0, result.stderr)
        sha = self.output()
        info = json.loads(self.git('show', sha + ':.preview-build/build-info.json'))
        self.assertEqual(info['source_commit'], self.sha)
        self.assertEqual(info['result'], 'success')
        names = self.git('ls-tree', '-r', '--name-only', sha, '.preview-build').splitlines()
        self.assertEqual(set(names), {'.preview-build/' + name for name in
                         ('SoloIsland.dmg', 'SoloIsland.dmg.sha256', 'SoloIsland-notch-music.png', 'build-info.json', 'build.log')})
        self.assertEqual(self.git('show', sha + ':source.txt'), 'public source')
        self.assertEqual((self.repo / '.git' / 'index').read_bytes(), index_before)
        self.assertEqual(self.git('rev-parse', 'HEAD').strip(), self.sha)
        self.assert_public_unchanged()

    def test_failure_removes_an_older_preview_installer(self):
        self.assertEqual(self.publish().returncode, 0)
        self.git('merge', '--ff-only', self.output())
        (self.repo / 'source.txt').write_text('updated preview')
        self.git('add', 'source.txt')
        self.git('commit', '-m', 'Next preview source')
        sha = self.git('rev-parse', 'HEAD').strip()
        self.git('push', 'origin', 'HEAD:' + self.branch)
        result = self.publish(GITHUB_SHA=sha, BUILD_RESULT='failure')
        self.assertEqual(result.returncode, 0, result.stderr)
        names = self.git('ls-tree', '-r', '--name-only', self.output(), '.preview-build').splitlines()
        self.assertEqual(set(names), {'.preview-build/build-info.json', '.preview-build/build.log'})
        self.assert_public_unchanged()

    def test_local_or_public_branch_publication_is_rejected(self):
        for overrides in ({'GITHUB_ACTIONS': 'false'}, {'GITHUB_REF': 'refs/heads/solo-island'},
                          {'GITHUB_REF': 'refs/heads/solo-island-builds'}):
            with self.subTest(overrides=overrides):
                self.assertNotEqual(self.publish(**overrides).returncode, 0)
        self.assertEqual(self.output(), self.sha)
        self.assert_public_unchanged()

    def test_a_stale_build_does_not_overwrite_new_source(self):
        result = self.publish(GITHUB_SHA='0' * 40)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('skipping stale', result.stdout)
        self.assertEqual(self.output(), self.sha)
        self.assert_public_unchanged()


if __name__ == '__main__':
    unittest.main()
