import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
const cwd = fileURLToPath(new URL('../flutter_app/', import.meta.url));
// WindowsではSDKのflutter.batをシェル経由で起動。コマンドと引数は固定。
const steps = [['pub', 'get'], ['analyze', '--no-fatal-infos', '--no-fatal-warnings'], ['test'], ['build', 'web', '--release', '--no-web-resources-cdn']];
for (const args of steps) {
  console.log(`\n> flutter ${args.join(' ')}`);
  const result = spawnSync('flutter', args, { cwd, stdio: 'inherit', shell: process.platform === 'win32' });
  if (result.error || result.status !== 0) {
    console.error(result.error?.message || 'Flutterの処理が完了しませんでした。上のエラーを確認してください。');
    if (result.error?.code === 'ENOENT') console.error('Flutter SDKをインストールし、VS Codeを開き直してください。');
    process.exit(result.status || 1);
  }
}
console.log('\nFlutter Webをビルドしました。npm startで配信できます。');
