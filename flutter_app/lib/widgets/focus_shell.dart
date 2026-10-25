import 'package:flutter/material.dart';

import '../screens/partner_albums_screen.dart';

// ホームとアルバムを切り替える下部タブ。
// 通知一覧はホーム右上のベル（NotificationBell）から開く。
class FocusShell extends StatefulWidget {
  const FocusShell({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  State<FocusShell> createState() => _FocusShellState();
}

class _FocusShellState extends State<FocusShell> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          widget.child,
          const PartnerAlbumsScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'ホーム',
          ),
          NavigationDestination(
            icon: Icon(Icons.photo_library_outlined),
            selectedIcon: Icon(Icons.photo_library),
            label: 'アルバム',
          ),
        ],
      ),
    );
  }
}
