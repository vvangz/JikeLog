import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/api/models.dart';
import '../features/account/account_page.dart';
import '../features/account/devices_page.dart';
import '../features/account/security_pages.dart';
import '../features/auth/auth_controller.dart';
import '../features/auth/login_page.dart';
import '../features/auth/register_pages.dart';
import '../features/consent/consent_controller.dart';
import '../features/consent/consent_page.dart';
import '../features/modules/module_page.dart';
import '../features/settings/about_page.dart';
import '../features/settings/settings_page.dart';
import '../shared/ui/jk_logo.dart';
import 'shell/app_shell.dart';
import 'shell/destinations.dart';

/// 未登录时可访问的页面。
const _publicPaths = {
  '/login',
  '/register',
  '/register/complete',
  '/password/reset',
};

/// 默认进入的模块。
const homePath = '/worklog';

/// 路由守卫（纯函数，便于测试）：
/// 未同意隐私政策 → 同意页；恢复登录态中 → 启动页；未登录 → 登录页；已登录访问登录类页面 → 首页。
String? redirectFor({
  required bool consented,
  required AuthState auth,
  required String location,
}) {
  if (!consented) return location == '/consent' ? null : '/consent';
  if (auth is AuthLoading) return location == '/splash' ? null : '/splash';
  final isPublic = _publicPaths.contains(location);
  if (auth is SignedOut) return isPublic ? null : '/login';
  if (isPublic ||
      location == '/splash' ||
      location == '/consent' ||
      location == '/') {
    return homePath;
  }
  return null;
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref
    // 只在登录状态类别变化时刷新路由；账号资料更新（改昵称、绑定手机号）不应打断当前页面的导航
    ..listen(authControllerProvider, (prev, next) {
      if (prev.runtimeType != next.runtimeType) refresh.value++;
    })
    ..listen(consentControllerProvider, (_, _) => refresh.value++)
    ..onDispose(refresh.dispose);

  final router = GoRouter(
    initialLocation: homePath,
    refreshListenable: refresh,
    redirect: (context, state) {
      // 未同意隐私政策前不读取登录态，避免提前触发会话恢复（网络请求）
      final consented = ref.read(consentControllerProvider);
      return redirectFor(
        consented: consented,
        auth: consented
            ? ref.read(authControllerProvider)
            : const AuthLoading(),
        location: state.matchedLocation,
      );
    },
    routes: [
      GoRoute(path: '/', redirect: (_, _) => homePath),
      GoRoute(path: '/consent', builder: (_, _) => const ConsentPage()),
      GoRoute(path: '/splash', builder: (_, _) => const _SplashPage()),
      GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
      GoRoute(path: '/register', builder: (_, _) => const RegisterPage()),
      GoRoute(
        path: '/register/complete',
        redirect: (_, state) =>
            state.extra is SmsRegistrationRequired ? null : '/login',
        builder: (_, state) => CompleteRegistrationPage(
          pending: state.extra! as SmsRegistrationRequired,
        ),
      ),
      GoRoute(
        path: '/password/reset',
        builder: (_, _) => const ResetPasswordPage(),
      ),
      ShellRoute(
        builder: (context, state, child) =>
            AppShell(location: state.matchedLocation, child: child),
        routes: [
          for (final d in moduleDestinations)
            GoRoute(
              path: d.path,
              pageBuilder: (_, _) =>
                  NoTransitionPage(child: ModulePage(destination: d)),
            ),
          GoRoute(
            path: '/settings',
            pageBuilder: (_, _) =>
                const NoTransitionPage(child: SettingsPage()),
          ),
          GoRoute(
            path: '/account',
            pageBuilder: (_, _) => const NoTransitionPage(child: AccountPage()),
          ),
        ],
      ),
      // 子页面全屏打开，自带返回栏
      GoRoute(path: '/settings/about', builder: (_, _) => const AboutPage()),
      GoRoute(path: '/account/phone', builder: (_, _) => const PhonePage()),
      GoRoute(
        path: '/account/password',
        builder: (_, _) => const ChangePasswordPage(),
      ),
      GoRoute(path: '/account/devices', builder: (_, _) => const DevicesPage()),
      GoRoute(
        path: '/account/delete',
        builder: (_, _) => const DeleteAccountPage(),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

class _SplashPage extends StatelessWidget {
  const _SplashPage();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: JkLogo(size: 64)));
}
