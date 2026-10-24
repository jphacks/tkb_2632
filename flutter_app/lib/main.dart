import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'browser_gateway.dart' if (dart.library.io) 'native_gateway_stub.dart';
import 'controller.dart';
import 'models.dart';
import 'capture.dart';

const coral = Color(0xFFFF836B);
const cream = Color(0xFFFFFAF7);
const ink = Color(0xFF403631);
const muted = Color(0xFF94847C);

void main() =>
    runApp(ShotRelayApp(controller: RelayController(createGateway())));

class ShotRelayApp extends StatefulWidget {
  final RelayController controller;
  final bool poll;
  const ShotRelayApp({super.key, required this.controller, this.poll = true});
  @override
  State<ShotRelayApp> createState() => _ShotRelayAppState();
}

class _ShotRelayAppState extends State<ShotRelayApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.initialize(poll: widget.poll);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    widget.controller.active = state == AppLifecycleState.resumed;
    if (widget.controller.active && widget.controller.user != null)
      widget.controller.refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'ShotRelay',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      fontFamily: 'NotoSansJP',
      scaffoldBackgroundColor: cream,
      colorScheme: ColorScheme.fromSeed(
        seedColor: coral,
        primary: coral,
        surface: Colors.white,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: cream,
        foregroundColor: ink,
        centerTitle: true,
        elevation: 0,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.all(18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFEEDFD7)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFEEDFD7)),
        ),
      ),
    ),
    home: AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final c = widget.controller;
        if (c.loading)
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        if (c.user == null) return LoginScreen(c: c);
        if (c.roomCode == null) return PairScreen(c: c);
        return HomeScreen(c: c);
      },
    ),
  );
}

Future<bool> perform(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
    return true;
  } catch (e) {
    if (context.mounted)
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    return false;
  }
}

void openScreen(BuildContext context, Widget screen) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
void goHome(BuildContext context) =>
    Navigator.of(context).popUntil((r) => r.isFirst);

class AppPage extends StatelessWidget {
  final String title;
  final RelayController c;
  final Widget child;
  final Widget? bottom;
  const AppPage({
    super.key,
    required this.title,
    required this.c,
    required this.child,
    this.bottom,
  });
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        title,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
      ),
      actions: [
        IconButton(
          tooltip: '最新の状態に更新',
          onPressed: c.busy ? null : () => c.refresh(),
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            children: [
              if (c.error != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  color: const Color(0xFFFFEFCE),
                  child: Text(c.error!, style: const TextStyle(fontSize: 12)),
                ),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    ),
    bottomNavigationBar: bottom == null
        ? null
        : SafeArea(
            child: Center(
              heightFactor: 1,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                  child: bottom,
                ),
              ),
            ),
          ),
  );
}

class SoftCard extends StatelessWidget {
  final Widget child;
  final Color color;
  const SoftCard({super.key, required this.child, this.color = Colors.white});
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    margin: const EdgeInsets.only(bottom: 16),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: const Color(0xFFF0E3DD)),
    ),
    child: child,
  );
}

class Intro extends StatelessWidget {
  final String title, subtitle;
  const Intro(this.title, this.subtitle, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            color: ink,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          subtitle,
          style: const TextStyle(color: muted, fontSize: 13, height: 1.8),
        ),
      ],
    ),
  );
}

class LoginScreen extends StatefulWidget {
  final RelayController c;
  const LoginScreen({super.key, required this.c});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final name = TextEditingController();
  final form = GlobalKey<FormState>();
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (!form.currentState!.validate()) return;
    await perform(
      context,
      () => widget.c.mutate('login', {'name': name.text.trim()}),
    );
  }

  @override
  Widget build(BuildContext context) => AppPage(
    title: 'ShotRelay',
    c: widget.c,
    child: ListView(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
      children: [
        Container(
          alignment: Alignment.centerLeft,
          margin: const EdgeInsets.only(bottom: 28),
          child: const CircleAvatar(
            radius: 38,
            backgroundColor: Color(0xFFFFE9DF),
            child: Icon(Icons.camera_alt_rounded, size: 38, color: coral),
          ),
        ),
        const Intro('ふたりの「好き」を、\n撮るたびに。', '撮る。選ぶ。相手を知る。\nいつもの写真が、もっと楽しくなるカメラ。'),
        Form(
          key: form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                key: const Key('name-input'),
                controller: name,
                maxLength: 24,
                decoration: const InputDecoration(
                  labelText: 'あなたの名前',
                  hintText: 'りおちゃん',
                ),
                textInputAction: TextInputAction.done,
                validator: (v) =>
                    v == null || v.trim().isEmpty ? '名前を入力してください' : null,
                onFieldSubmitted: (_) => submit(),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: widget.c.busy ? null : submit,
                child: Text(widget.c.busy ? 'はじめています…' : 'はじめる'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          '2台のiPhoneで、お互いにこのURLを開いてね。',
          style: TextStyle(fontSize: 12, color: muted),
        ),
      ],
    ),
  );
}

class PairScreen extends StatefulWidget {
  final RelayController c;
  const PairScreen({super.key, required this.c});
  @override
  State<PairScreen> createState() => _PairScreenState();
}

class _PairScreenState extends State<PairScreen> {
  bool sharingConsent = false;
  final code = TextEditingController();
  final form = GlobalKey<FormState>();
  @override
  void dispose() {
    code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppPage(
    title: 'ふたりをつなぐ',
    c: widget.c,
    child: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Intro(
          '${widget.c.user!.name}さん、\n一緒に撮る相手を招待しよう。',
          'ひとりが部屋を作って、もうひとりがコードで参加します。',
        ),
        CheckboxListTile(
          value: sharingConsent,
          onChanged: widget.c.busy
              ? null
              : (v) => setState(() => sharingConsent = v ?? false),
          title: const Text(
            '送った写真をペアの相手と共有することを確認しました。',
            style: TextStyle(fontSize: 12),
          ),
          contentPadding: EdgeInsets.zero,
        ),
        SoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.favorite_border_rounded, color: coral, size: 36),
              const SizedBox(height: 14),
              const Text(
                '新しくペアを作る',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: (widget.c.busy || !sharingConsent)
                    ? null
                    : () =>
                          perform(context, () => widget.c.mutate('rooms', {})),
                child: const Text('招待コードを作る'),
              ),
            ],
          ),
        ),
        SoftCard(
          child: Form(
            key: form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '招待された人はこちら',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: code,
                  maxLength: 6,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '6桁の招待コード'),
                  validator: (v) => RegExp(r'^\d{6}$').hasMatch(v?.trim() ?? '')
                      ? null
                      : '6桁の数字を入力してください',
                ),
                OutlinedButton(
                  onPressed: (widget.c.busy || !sharingConsent)
                      ? null
                      : () {
                          if (form.currentState!.validate())
                            perform(
                              context,
                              () => widget.c.mutate('join', {
                                'code': code.text.trim(),
                              }),
                            );
                        },
                  child: const Text('ペアに参加する'),
                ),
              ],
            ),
          ),
        ),
        const Text(
          '送った写真は、ペアの相手だけが見られます。\nお互いに共有してよい写真で試してください。',
          style: TextStyle(fontSize: 12, color: muted, height: 1.8),
        ),
      ],
    ),
  );
}

class HomeScreen extends StatelessWidget {
  final RelayController c;
  const HomeScreen({super.key, required this.c});
  @override
  Widget build(BuildContext context) => AppPage(
    title: 'ShotRelay',
    c: c,
    child: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        SoftCard(
          color: const Color(0xFFFFEFE7),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _avatar(c.user!.name, const Color(0xFFFFD9CB)),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 14),
                    child: Icon(Icons.favorite, color: coral, size: 20),
                  ),
                  _avatar(c.partner?.name ?? '?', const Color(0xFFE0EADD)),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                '${c.user!.name} ＆ ${c.partner?.name ?? '相手を待っています'}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 20,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                c.partner == null ? 'このコードを相手に伝えてね' : '今日も、ふたりで撮ってみよう。',
                style: const TextStyle(color: muted, fontSize: 12),
              ),
              SelectableText(
                c.roomCode!,
                style: const TextStyle(
                  letterSpacing: 5,
                  fontSize: 25,
                  color: Color(0xFF9E6D59),
                ),
              ),
            ],
          ),
        ),
        FilledButton.icon(
          onPressed: c.partner == null
              ? null
              : () => openScreen(context, CaptureScreen(c: c)),
          icon: const Icon(Icons.camera_alt_rounded),
          label: const Text('撮影をはじめる'),
        ),
        const SizedBox(height: 24),
        if (c.guesses.isNotEmpty)
          SoftCard(
            color: const Color(0xFFFFEFE7),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '相手が「好き！」を選んでくれたよ',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                const Text('どの写真か、当ててみよう。', style: TextStyle(color: muted)),
                TextButton(
                  onPressed: () => openScreen(
                    context,
                    RoundScreen(c: c, roundId: c.guesses.first.id),
                  ),
                  child: const Text('予想ゲームへ →'),
                ),
              ],
            ),
          ),
        _menu(
          context,
          Icons.photo_library_outlined,
          'ふたりのアルバム',
          '${c.rounds.length}セット · 選ぶ前の写真もここに',
          () => openScreen(context, AlbumScreen(c: c)),
        ),
        _menu(
          context,
          Icons.mark_email_unread_outlined,
          '届いた写真',
          c.unread == 0 ? '相手が撮ってくれた写真を見る' : '${c.unread}セットのお気に入りを選べます',
          () => openScreen(context, AlbumScreen(c: c, receivedOnly: true)),
        ),
        _menu(
          context,
          Icons.insights_rounded,
          'ふたりの撮影カルテ',
          'これまでに伝わった「好き」を見る',
          () => openScreen(context, ProfileScreen(c: c)),
        ),
        const SizedBox(height: 18),
        const Text(
          'AIが「いい写真」を決めるのではなく、\nあなたが選んだ「好き」を、相手へ。',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: muted, height: 1.8),
        ),
      ],
    ),
  );
  Widget _avatar(String name, Color color) => CircleAvatar(
    radius: 32,
    backgroundColor: color,
    child: Text(
      name.isEmpty ? '?' : name.characters.first,
      style: const TextStyle(fontSize: 24, color: ink),
    ),
  );
  Widget _menu(
    BuildContext context,
    IconData icon,
    String title,
    String sub,
    VoidCallback tap,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Icon(icon, color: coral),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
        subtitle: Text(sub, style: const TextStyle(fontSize: 11, color: muted)),
        trailing: const Icon(Icons.chevron_right),
        onTap: tap,
      ),
    ),
  );
}

class AlbumScreen extends StatefulWidget {
  final RelayController c;
  final bool receivedOnly;
  const AlbumScreen({super.key, required this.c, this.receivedOnly = false});
  @override
  State<AlbumScreen> createState() => _AlbumScreenState();
}

class _AlbumScreenState extends State<AlbumScreen> {
  bool favoritesOnly = false;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.c,
    builder: (context, _) {
      final c = widget.c;
      final rounds = (widget.receivedOnly ? c.received : c.rounds)
          .where((r) => !favoritesOnly || r.favoriteId != null)
          .toList();
      return AppPage(
        title: widget.receivedOnly ? '届いた写真' : 'ふたりのアルバム',
        c: c,
        child: RefreshIndicator(
          onRefresh: c.refresh,
          child: ListView(
            padding: const EdgeInsets.all(20),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              Wrap(
                spacing: 10,
                children: [
                  ChoiceChip(
                    label: const Text('すべて'),
                    selected: !favoritesOnly,
                    onSelected: (_) => setState(() => favoritesOnly = false),
                  ),
                  ChoiceChip(
                    label: const Text('お気に入り'),
                    selected: favoritesOnly,
                    onSelected: (_) => setState(() => favoritesOnly = true),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (rounds.isEmpty)
                const EmptyState(
                  Icons.photo_library_outlined,
                  'まだ写真はありません',
                  '撮って、送って、ふたりの記録をはじめよう。',
                ),
              for (final r in rounds)
                GestureDetector(
                  onTap: () =>
                      openScreen(context, RoundScreen(c: c, roundId: r.id)),
                  child: SoftCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                r.timeLabel,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            _status(r, c),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            for (final id
                                in (favoritesOnly
                                    ? [r.favoriteId!]
                                    : r.photos.take(3)))
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.all(3),
                                  child: AspectRatio(
                                    aspectRatio: .8,
                                    child: PhotoView(
                                      c: c,
                                      roundId: r.id,
                                      photoId: id,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          r.subjectId == c.user?.id ? '撮ってもらった写真' : '自分が撮った写真',
                          style: const TextStyle(color: muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
  Widget _status(PhotoRound r, RelayController c) {
    final text = r.status == 'selecting'
        ? (r.subjectId == c.user?.id ? '好き！を返そう' : '相手の選択待ち')
        : r.status == 'guessing'
        ? (r.photographerId == c.user?.id ? '予想してみる' : '相手の予想待ち')
        : '好き！が届きました';
    return Text(text, style: const TextStyle(fontSize: 10, color: coral));
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  const EmptyState(this.icon, this.title, this.subtitle, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 50),
    child: Column(
      children: [
        Icon(icon, size: 54, color: coral),
        const SizedBox(height: 20),
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 19),
        ),
        const SizedBox(height: 12),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(color: muted, fontSize: 12, height: 1.8),
        ),
      ],
    ),
  );
}

class PhotoView extends StatefulWidget {
  final RelayController c;
  final String roundId, photoId;
  final BoxFit fit;
  const PhotoView({
    super.key,
    required this.c,
    required this.roundId,
    required this.photoId,
    this.fit = BoxFit.cover,
  });
  @override
  State<PhotoView> createState() => _PhotoViewState();
}

class _PhotoViewState extends State<PhotoView> {
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(14),
    child: ColoredBox(
      color: const Color(0xFFF3EAE3),
      child: FutureBuilder<Uint8List>(
        future: widget.c.photo(widget.roundId, widget.photoId),
        builder: (context, snapshot) {
          if (snapshot.hasError)
            return Center(
              child: TextButton(
                onPressed: () => setState(
                  () => widget.c.retryPhoto(widget.roundId, widget.photoId),
                ),
                child: const Text('再読み込み', style: TextStyle(fontSize: 11)),
              ),
            );
          if (!snapshot.hasData)
            return const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          return Image.memory(
            snapshot.data!,
            fit: widget.fit,
            gaplessPlayback: true,
            width: double.infinity,
            height: double.infinity,
            errorBuilder: (_, _, _) =>
                const Center(child: Icon(Icons.broken_image_outlined)),
          );
        },
      ),
    ),
  );
}

class RoundScreen extends StatefulWidget {
  final RelayController c;
  final String roundId;
  const RoundScreen({super.key, required this.c, required this.roundId});
  @override
  State<RoundScreen> createState() => _RoundScreenState();
}

class _RoundScreenState extends State<RoundScreen> {
  String? chosen;
  final Set<String> reasons = {};
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.c,
    builder: (context, _) {
      final c = widget.c, r = c.round(widget.roundId);
      if (r == null)
        return AppPage(
          title: '写真',
          c: c,
          child: const EmptyState(
            Icons.photo_outlined,
            '写真が見つかりません',
            'ホームに戻って、もう一度お試しください。',
          ),
        );
      final mine = r.photographerId == c.user?.id;
      if (r.status == 'revealed') return _result(context, c, r, mine);
      final selecting = !mine && r.status == 'selecting';
      final guessing = mine && r.status == 'guessing';
      return AppPage(
        title: selecting
            ? 'お気に入りを選ぶ'
            : guessing
            ? 'どれが好きだと思う？'
            : '写真が届くまで',
        c: c,
        bottom: selecting
            ? FilledButton.icon(
                onPressed: c.busy || chosen == null
                    ? null
                    : () => perform(
                        context,
                        () => c.mutate('rounds/${r.id}/favorite', {
                          'photoId': chosen,
                          'reasons': reasons.toList(),
                        }),
                      ),
                icon: const Icon(Icons.favorite),
                label: Text(c.busy ? '送っています…' : 'これ好き！を返す'),
              )
            : guessing
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: c.busy || chosen == null
                          ? null
                          : () => perform(
                              context,
                              () => c.mutate('rounds/${r.id}/guess', {
                                'photoId': chosen,
                                'skip': false,
                              }),
                            ),
                      child: Text(c.busy ? '答え合わせ中…' : 'この写真だと思う！'),
                    ),
                  ),
                  TextButton(
                    onPressed: c.busy
                        ? null
                        : () => perform(
                            context,
                            () => c.mutate('rounds/${r.id}/guess', {
                              'skip': true,
                            }),
                          ),
                    child: const Text('予想せずに、結果を見る'),
                  ),
                ],
              )
            : null,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Intro(
              selecting
                  ? 'あなたの「好き」を、\nひとつ教えて。'
                  : guessing
                  ? '相手が選んだのは、\nどの一枚？'
                  : mine
                  ? '相手の「好き」を\n待っています。'
                  : '「好き！」を送りました。',
              selecting
                  ? '点数はつけなくて大丈夫。気に入った一枚を選んでね。'
                  : guessing
                  ? '正解数は競いません。相手を少し知るための答え合わせ。'
                  : mine
                  ? '相手がお気に入りを選ぶと、この画面が変わります。'
                  : '撮った人が予想を終えたら、ふたりで答え合わせ。',
            ),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: r.photos.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: guessing ? 3 : 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: .72,
              ),
              itemBuilder: (context, i) {
                final id = r.photos[i];
                return Semantics(
                  label: '写真${i + 1}を選ぶ',
                  selected: chosen == id,
                  button: true,
                  child: GestureDetector(
                    onTap: selecting || guessing
                        ? () => setState(() => chosen = id)
                        : () => _enlarge(context, c, r.id, id),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: chosen == id ? coral : Colors.transparent,
                          width: 3,
                        ),
                      ),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          PhotoView(c: c, roundId: r.id, photoId: id),
                          Positioned(
                            left: 6,
                            bottom: 6,
                            child: CircleAvatar(
                              radius: 14,
                              backgroundColor: chosen == id
                                  ? coral
                                  : Colors.white,
                              child: Text(
                                String.fromCharCode(65 + i),
                                style: TextStyle(
                                  color: chosen == id ? Colors.white : ink,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            right: 0,
                            top: 0,
                            child: IconButton(
                              tooltip: '写真${i + 1}を拡大',
                              onPressed: () => _enlarge(context, c, r.id, id),
                              icon: const Icon(
                                Icons.zoom_in,
                                color: Colors.white,
                                shadows: [Shadow(blurRadius: 5)],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
            if (selecting) ...[
              const SizedBox(height: 24),
              const Text(
                '好きな理由も、よければ。',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final t in reasonTags)
                    FilterChip(
                      label: Text(t),
                      selected: reasons.contains(t),
                      onSelected: (v) => setState(() {
                        v ? reasons.add(t) : reasons.remove(t);
                      }),
                    ),
                ],
              ),
            ],
            if (!selecting && !guessing) ...[
              const SizedBox(height: 20),
              if (r.favoriteId != null)
                Text(
                  '選んだ理由：${r.reasons.isEmpty ? '入力なし' : r.reasons.join('・')}',
                  style: const TextStyle(color: muted),
                ),
              TextButton(
                onPressed: () => goHome(context),
                child: const Text('ホームに戻る'),
              ),
            ],
          ],
        ),
      );
    },
  );
  void _enlarge(
    BuildContext context,
    RelayController c,
    String roundId,
    String photoId,
  ) => showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      child: AspectRatio(
        aspectRatio: .7,
        child: Stack(
          children: [
            Positioned.fill(
              child: PhotoView(
                c: c,
                roundId: roundId,
                photoId: photoId,
                fit: BoxFit.contain,
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                tooltip: '閉じる',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: coral),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  Widget _result(
    BuildContext context,
    RelayController c,
    PhotoRound r,
    bool mine,
  ) {
    final skipped = r.answer?['skipped'] == true,
        correct = r.answer?['correct'] == true;
    return AppPage(
      title: 'ふたりの答え合わせ',
      c: c,
      bottom: FilledButton.icon(
        onPressed: c.partner == null
            ? null
            : () => Navigator.pushReplacement(
                context,
                MaterialPageRoute<void>(builder: (_) => CaptureScreen(c: c)),
              ),
        icon: const Icon(Icons.camera_alt),
        label: const Text('この「好き」を、次の一枚へ'),
      ),
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Intro(
            !mine
                ? 'あなたの「好き」が、\n相手に届きました。'
                : skipped
                ? '相手は、この一枚が好き。'
                : correct
                ? 'その一枚、\n相手も好きだった！'
                : 'そうなんだ！\nこの一枚が好きなんだね。',
            'ふたりの好みを、少しずつ。',
          ),
          if (r.favoriteId != null)
            AspectRatio(
              aspectRatio: .85,
              child: PhotoView(
                c: c,
                roundId: r.id,
                photoId: r.favoriteId!,
                fit: BoxFit.contain,
              ),
            ),
          const SizedBox(height: 20),
          SoftCard(
            color: const Color(0xFFFFEEE6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '♥  これ好き！',
                  style: TextStyle(
                    color: coral,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  r.reasons.isEmpty
                      ? '理由を言葉にしなくても、「好き」は伝わったよ。'
                      : r.reasons.join(' / '),
                  style: const TextStyle(height: 1.8),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => goHome(context),
            child: const Text('ホームに戻る'),
          ),
        ],
      ),
    );
  }
}

class ProfileScreen extends StatelessWidget {
  final RelayController c;
  const ProfileScreen({super.key, required this.c});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (context, _) {
      // 正解が公開されたセットだけで集計し、予想前の理由は漏らさない。
      final visible = c.rounds
          .where(
            (r) =>
                r.photographerId == c.user?.id &&
                r.status == 'revealed' &&
                r.favoriteId != null,
          )
          .toList();
      final counts = {
        for (final tag in reasonTags)
          tag: visible.where((r) => r.reasons.contains(tag)).length,
      };
      return AppPage(
        title: 'ふたりの撮影カルテ',
        c: c,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Intro(
              '${c.partner?.name ?? '相手'}が選んだ、\nこれまでの「好き」。',
              '診断ではなく、実際に返してくれた理由の記録。',
            ),
            if (visible.isEmpty)
              const EmptyState(
                Icons.favorite_border,
                'まだ、これから。',
                '写真を撮って、「好き！」を返してもらおう。',
              ),
            for (final e in counts.entries.where((e) => e.value > 0))
              SoftCard(
                child: Row(
                  children: [
                    const Icon(Icons.favorite, color: coral, size: 22),
                    const SizedBox(width: 12),
                    Expanded(child: Text(e.key)),
                    Text(
                      '${e.value}回',
                      style: const TextStyle(
                        color: coral,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            const SoftCard(
              color: Color(0xFFF0F4ED),
              child: Text(
                '次の撮影では、前に選んでくれた一枚を思い出してみよう。\n\n人物の大きさ・位置の自動分析や、カメラのガイド枠は今後追加する予定です。',
                style: TextStyle(fontSize: 12, height: 1.9),
              ),
            ),
            for (final r in visible.take(4))
              GestureDetector(
                onTap: () =>
                    openScreen(context, RoundScreen(c: c, roundId: r.id)),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: AspectRatio(
                    aspectRatio: 1.2,
                    child: PhotoView(
                      c: c,
                      roundId: r.id,
                      photoId: r.favoriteId!,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}
