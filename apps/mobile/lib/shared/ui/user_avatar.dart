import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../core/api/models.dart';
import '../../features/account/avatar_service.dart';

/// 通用用户头像组件：已设置自定义头像时展示圆形图片（自动命中本地离线缓存），
/// 未设置或尚未加载完成时平滑回退到首字母头像。
class UserAvatar extends ConsumerWidget {
  const UserAvatar({
    super.key,
    required this.user,
    this.size = 40,
    this.editable = false,
    this.loading = false,
    this.onTap,
    this.backgroundColor,
    this.foregroundColor,
    this.ringColor,
  });

  final User user;
  final double size;
  final bool editable;
  final bool loading;
  final VoidCallback? onTap;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final Color? ringColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.jkColors;
    final bg = backgroundColor ?? c.primaryContainer;
    final fg = foregroundColor ?? c.onPrimaryContainer;
    final version = user.avatarVersion;
    final Uint8List? bytes = version != null && version.isNotEmpty
        ? ref.watch(userAvatarProvider((user.id, version))).value
        : null;

    final initial = user.displayName.isEmpty
        ? 'J'
        : user.displayName.characters.first.toUpperCase();

    Widget circle = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: bg,
        border: ringColor == null
            ? null
            : Border.all(color: ringColor!, width: size >= 44 ? 2 : 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: bytes != null
          ? Image.memory(
              bytes,
              key: Key('user-avatar-image-$version'),
              fit: BoxFit.cover,
              width: size,
              height: size,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) =>
                  _Initial(text: initial, size: size, color: fg),
            )
          : _Initial(text: initial, size: size, color: fg),
    );

    if (loading) {
      circle = Stack(
        alignment: Alignment.center,
        children: [
          circle,
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withValues(alpha: 0.36),
            ),
            alignment: Alignment.center,
            child: SizedBox.square(
              dimension: size * 0.36,
              child: const CircularProgressIndicator(
                strokeWidth: 2.2,
                color: Colors.white,
              ),
            ),
          ),
        ],
      );
    }

    if (editable) {
      final badgeSize = (size * 0.34).clamp(20.0, 26.0);
      circle = SizedBox(
        width: size,
        height: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            circle,
            Positioned(
              right: -1,
              bottom: -1,
              child: Container(
                width: badgeSize,
                height: badgeSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: c.primary,
                  border: Border.all(color: c.surface, width: 2),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.camera_alt_outlined,
                  size: badgeSize * 0.56,
                  color: c.onPrimary,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (onTap == null) return circle;

    return Semantics(
      button: true,
      label: editable ? '更换头像' : '用户头像',
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: loading ? null : onTap,
          child: circle,
        ),
      ),
    );
  }
}

class _Initial extends StatelessWidget {
  const _Initial({required this.text, required this.size, required this.color});

  final String text;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => Center(
    child: Text(
      text,
      style: TextStyle(
        fontSize: (size * 0.42).clamp(11.0, 28.0),
        fontWeight: FontWeight.w600,
        color: color,
        height: 1.0,
      ),
    ),
  );
}
