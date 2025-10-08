import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:users/core/constants/global.dart';

import '../../../auth/presentation/screens/login_screen.dart';

class DrawerScreen extends StatelessWidget {
  const DrawerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = firebaseAuth.currentUser?.uid;

    if (uid == null) {
      return _DrawerShell(child: const _DrawerContent(displayName: 'Guest'));
    }

    final ref = FirebaseDatabase.instance.ref().child('users').child(uid);

    return _DrawerShell(
      child: StreamBuilder<DatabaseEvent>(
        stream: ref.onValue,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const _DrawerSkeleton();
          }
          if (!snap.hasData || snap.data!.snapshot.value == null) {
            return const _DrawerContent(displayName: 'Guest');
          }
          final data = snap.data!.snapshot.value;
          String name = 'Guest';
          if (data is Map && data['name'] != null) {
            name = data['name'].toString().trim();
          }
          return _DrawerContent(displayName: name);
        },
      ),
    );
  }
}

class _DrawerShell extends StatelessWidget {
  final Widget child;
  const _DrawerShell({required this.child});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width * 0.82;
    final dark = MediaQuery.of(context).platformBrightness == Brightness.dark;

    // خلفية مودرن متدرّجة + نُعومة خفيفة
    final bg = BoxDecoration(
      gradient: LinearGradient(
        colors: dark
            ? [const Color(0xFF0F0F12), const Color(0xFF13151A)]
            : [const Color(0xFFF7F9FB), const Color(0xFFFFFFFF)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    );

    return SizedBox(
      width: width,
      child: Drawer(
        elevation: 0,
        backgroundColor: Colors.transparent,
        child: Container(
          decoration: bg,
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 24),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class _DrawerContent extends StatelessWidget {
  final String displayName;
  const _DrawerContent({required this.displayName});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final primary = dark ? const Color(0xFF9D6BFF) : const Color(0xFF1F6BFF);
    final onBg = dark ? Colors.white : const Color(0xFF10121A);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ===== Header (Glass + Gradient) =====
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              children: [
                // Gradient overlay
                Container(
                  height: 140,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        primary.withOpacity(.95),
                        primary.withOpacity(.70),
                        primary.withOpacity(.55),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                ),
                // Glass blur
                BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                  child: Container(
                    height: 140,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(dark ? .05 : .12),
                      border: Border.all(
                        color: Colors.white.withOpacity(.15),
                        width: 1,
                      ),
                    ),
                  ),
                ),
                // Content
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 36,
                          backgroundColor: Colors.white.withOpacity(.25),
                          backgroundImage:
                          const AssetImage("assets/users_image/person.png"),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                "Welcome 👋",
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: Colors.white.withOpacity(.85),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleLarge?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: .2,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  _Chip(
                                    label: "Verified",
                                    icon: Icons.verified_rounded,
                                    bg: Colors.white.withOpacity(.18),
                                    fg: Colors.white,
                                  ),
                                  const SizedBox(width: 8),
                                  _Chip(
                                    label: "Gold",
                                    icon: Icons.star_rate_rounded,
                                    bg: Colors.amber.withOpacity(.22),
                                    fg: Colors.white,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              ],
            ),
          ),
        ),

        const SizedBox(height: 6),

        // ===== Section: Account =====
        _SectionHeader(title: "Account"),
        _NavTile(icon: Icons.person_outline, title: 'Edit Profile', onTap: () {}),
        _NavTile(icon: Icons.history_rounded, title: 'Your Trips', onTap: () {}),
        _NavTile(icon: Icons.card_giftcard_outlined, title: 'Free Trips', trailingBadge: "2", onTap: () {}),
        _Divider(),

        // ===== Section: Payments =====
        _SectionHeader(title: "Payments & Alerts"),
        _NavTile(icon: Icons.account_balance_wallet_outlined, title: 'Payment', onTap: () {}),
        _NavTile(icon: Icons.notifications_none_rounded, title: 'Notifications', onTap: () {}),
        _Divider(),

        // ===== Section: Help =====
        _SectionHeader(title: "Help"),
        _NavTile(icon: Icons.help_outline_rounded, title: 'Help & Support', onTap: () {}),

        const SizedBox(height: 28),

        // ===== Logout Button =====
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () async {
                await firebaseAuth.signOut();
                // تجاهل إذا كان السياق غير مركّب
                if (!context.mounted) return;
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Sign out'),
            ),
          ),
        ),
      ],
    );
  }
}

class _NavTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? trailingBadge;
  final VoidCallback? onTap;

  const _NavTile({
    required this.icon,
    required this.title,
    this.trailingBadge,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;

    final tileBg = dark ? Colors.white.withOpacity(.06) : const Color(0xFFF1F4F8);
    final iconColor = dark ? Colors.white : const Color(0xFF0F172A);
    final chevron = dark ? Colors.white70 : Colors.black45;
    final textColor = dark ? Colors.white : const Color(0xFF0F172A);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Material(
        color: tileBg,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: dark ? Colors.white.withOpacity(.08) : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      if (!dark)
                        BoxShadow(
                          color: Colors.black.withOpacity(.05),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                    ],
                  ),
                  child: Icon(icon, color: iconColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: textColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (trailingBadge != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF22C55E),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      trailingBadge!,
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                  ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right_rounded, color: chevron),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Text(
        title,
        style: theme.textTheme.labelLarge?.copyWith(
          color: dark ? Colors.white70 : const Color(0xFF475569),
          letterSpacing: .4,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Divider(
        height: 24,
        thickness: .8,
        color: dark ? Colors.white10 : const Color(0xFFE6EAF0),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color bg;
  final Color fg;
  const _Chip({required this.label, required this.icon, required this.bg, required this.fg});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(.2), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: .2),
          ),
        ],
      ),
    );
  }
}

class _DrawerSkeleton extends StatelessWidget {
  const _DrawerSkeleton();

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final sk = dark ? Colors.white12 : Colors.grey.shade200;

    Widget bar({double h = 52}) => Container(
      height: h,
      decoration: BoxDecoration(color: sk, borderRadius: BorderRadius.circular(14)),
    );

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          bar(h: 140),
          const SizedBox(height: 14),
          bar(),
          const SizedBox(height: 10),
          bar(),
          const SizedBox(height: 10),
          bar(),
        ],
      ),
    );
  }
}
