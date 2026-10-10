import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/jk_tokens.g.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/sync/sync_providers.dart';
import '../../shared/ui/conflict_banner.dart';
import '../../shared/ui/jk_feedback.dart';
import '../../shared/ui/jk_states.dart';
import '../../shared/ui/markdown_editor.dart';
import '../attachments/attachment_images.dart';
import '../attachments/attachment_providers.dart';
import '../attachments/attachment_viewers.dart';
import 'editor/body_sync.dart';
import 'editor/rich_editor_controller.dart';
import 'editor/rich_editor_view.dart';
import 'editor/rich_toolbar.dart';
import 'note_info_sheet.dart';
import 'note_models.dart';
import 'note_repository.dart';

/// 选择要插入正文的图片（测试中替换）。用户取消时返回空列表。
final imagePickerProvider = Provider<Future<List<PlatformFile>> Function()>(
  (_) =>
      () => FilePicker.pickFiles(type: FileType.image),
);

/// 用系统浏览器（或邮件、电话应用）打开链接（测试中替换）。
final launchLinkProvider = Provider<Future<bool> Function(Uri)>(
  (_) =>
      (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);

/// 笔记编辑页：标题 + 正文（Markdown 或富文本），修改即自动保存到本机（1 秒防抖）。
class NoteEditorPage extends ConsumerStatefulWidget {
  const NoteEditorPage({super.key, required this.id});

  final String id;

  @override
  ConsumerState<NoteEditorPage> createState() => _NoteEditorPageState();
}

class _NoteEditorPageState extends ConsumerState<NoteEditorPage>
    with WidgetsBindingObserver {
  static const _autosave = Duration(seconds: 1);

  late final NoteRepository _repo;
  final _title = TextEditingController();
  final _bodyFocus = FocusNode();
  Timer? _titleTimer;
  String _savedTitle = '';

  BodySync? _body;
  NoteFormat _format = NoteFormat.markdown;
  TextEditingController? _md;
  RichEditorController? _rich;
  bool _loaded = false;
  bool _deleting = false;
  bool _leaving = false;
  bool _switching = false;
  bool _tooLong = false;

  @override
  void initState() {
    super.initState();
    _repo = ref.read(noteRepositoryProvider);
    _title.addListener(_onTitle);
    WidgetsBinding.instance.addObserver(this);
  }

  void _load(Note n) {
    _savedTitle = n.title;
    _title.text = n.title;
    _body = BodySync(
      initial: n.body,
      autosave: _autosave,
      save: (b) => _repo.update(widget.id, body: b),
      canSave: (b) => b.runes.length <= maxNoteBodyLength,
      show: _show,
      onConflict: () {
        if (mounted) {
          showJkToast(context, '其他设备同时修改了这里，已保留你的输入，对方的版本可在修订历史中查看');
        }
      },
    );
    _openEditor(n.format);
    _loaded = true;
    // 新建的笔记直接开始输入
    if (n.title.isEmpty && n.body.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusBody();
      });
    }
  }

  // ---- 正文编辑器 ----

  /// 以 BodySync 中的最新内容打开编辑器。
  void _openEditor(NoteFormat format) {
    _format = format;
    final sync = _body!;
    if (format == NoteFormat.markdown) {
      _md = TextEditingController(text: sync.local)
        ..addListener(() => sync.edited(_md!.text));
      return;
    }
    // 立即初始化（页面就绪后发送），其间到达的替换会更新初始化内容
    _rich = RichEditorController(
      onChange: _onRichChange,
      onSetApplied: sync.applied,
      onSetRejected: sync.rejected,
      loadImage: _loadImage,
      onError: (m) => debugPrint('编辑器: $m'),
    )..init(markdown: sync.local, placeholder: '开始记录…', theme: _theme(context));
  }

  /// 富文本编辑器的输入。超过正文上限时提示删减，BodySync 不会保存（服务端会拒绝，整篇笔记无法同步）。
  void _onRichChange(String body) {
    final tooLong = body.runes.length > maxNoteBodyLength;
    if (tooLong && !_tooLong && mounted) {
      showJkToast(context, '正文超过 10 万字，删减后才能继续保存', kind: JkToastKind.error);
    }
    _tooLong = tooLong;
    _body?.edited(body);
  }

  void _closeEditor() {
    _md?.dispose();
    _md = null;
    _rich?.dispose();
    _rich = null;
  }

  Map<String, Object> _theme(BuildContext context) => editorTheme(
    context.jkColors,
    dark: Theme.of(context).brightness == Brightness.dark,
  );

  /// 在编辑器中显示新内容（其他设备的修改或合并结果）。
  void _show(String body) {
    final md = _md;
    if (md != null) {
      _setText(md, body);
      _body?.applied();
    } else {
      unawaited(_rich?.setMarkdown(body));
    }
  }

  /// 替换文本，光标尽量留在原来的文字旁边。
  static void _setText(TextEditingController c, String text) {
    final old = c.text;
    var cursor = c.selection.baseOffset;
    var i = 0;
    final n = old.length < text.length ? old.length : text.length;
    while (i < n && old.codeUnitAt(i) == text.codeUnitAt(i)) {
      i++;
    }
    if (cursor > i) cursor += text.length - old.length;
    c.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: cursor.clamp(0, text.length)),
    );
  }

  void _focusBody() {
    if (_md != null) {
      _bodyFocus.requestFocus();
    } else {
      unawaited(_rich?.focus());
    }
  }

  Future<String?> _loadImage(String id) async {
    final file = await ref.read(attachmentServiceProvider).open(id);
    return imageDataUrl(file);
  }

  /// 拆除编辑器前：等待已发出的替换得到确认，取回富文本编辑器中尚未送达的输入。
  Future<void> _detachEditor() async {
    final body = _body;
    if (body == null) return;
    await body.settled();
    body.detach(await _rich?.flush());
  }

  /// 保存全部修改（离开页面、进入后台、切换编辑方式时）。
  Future<void> _saveAll() async {
    if (!_loaded) return;
    await _detachEditor();
    await _body?.flush(force: true);
    await _flushTitle();
  }

  Future<void> _switchFormat() async {
    if (_switching || _body == null) return;
    _switching = true;
    try {
      final next = _format == NoteFormat.markdown
          ? NoteFormat.rich
          : NoteFormat.markdown;
      await _detachEditor();
      if (!mounted || !_loaded) return;
      setState(() {
        _closeEditor();
        _openEditor(next);
      });
      await _repo.update(widget.id, format: next);
    } on Object catch (e) {
      debugPrint('切换编辑方式失败: $e');
      if (mounted) {
        showJkToast(context, '切换失败，请重试', kind: JkToastKind.error);
      }
    } finally {
      _switching = false;
    }
  }

  // ---- 标题 ----

  void _onTitle() {
    if (!_loaded) return;
    _titleTimer?.cancel();
    _titleTimer = Timer(_autosave, () => unawaited(_flushTitle()));
  }

  Future<void> _flushTitle() async {
    _titleTimer?.cancel();
    if (!_loaded) return;
    final t = _title.text.trim();
    if (t == _savedTitle) return;
    _savedTitle = t;
    await _repo.update(widget.id, title: t);
  }

  // ---- 其他设备的修改 ----

  void _onRemote(Note? prev, Note? next) {
    if (next == null) {
      if (prev != null && mounted && !_deleting) {
        _stop();
        showJkToast(context, '这篇笔记已在其他设备上删除');
        context.pop();
      }
      return;
    }
    if (!_loaded) {
      if (!_deleting) setState(() => _load(next));
      return;
    }
    if (next.title != _savedTitle && _title.text.trim() == _savedTitle) {
      _savedTitle = next.title;
      _title.text = next.title;
    }
    _body?.remote(next.body);
  }

  /// 笔记已删除：之后不再保存。
  void _stop() {
    _loaded = false;
    _titleTimer?.cancel();
    _body?.close();
  }

  // ---- 操作 ----

  Future<void> _insertImage() async {
    final picked = await ref.read(imagePickerProvider)();
    final f = picked.firstOrNull;
    final path = f?.path;
    if (f == null || path == null || !mounted) return;
    final String id;
    try {
      id = await ref
          .read(attachmentServiceProvider)
          .add(
            ownerEntity: 'note',
            ownerId: widget.id,
            source: File(path),
            fileName: f.name,
          );
    } on Object catch (e) {
      debugPrint('插入图片失败: $e');
      if (mounted) {
        showJkToast(context, '插入图片失败：$e', kind: JkToastKind.error);
      }
      return;
    }
    if (!mounted) return;
    final alt = f.name.replaceAll(RegExp(r'[\[\]]'), '');
    final md = _md;
    if (md != null) {
      insertMarkdownBlock(md, '![$alt](attachment:$id)');
    } else {
      await _rich?.insertImage(id, alt);
    }
  }

  Future<void> _openLink(String href) async {
    final uri = Uri.tryParse(href);
    if (uri == null || !isSafeLink(href)) {
      showJkToast(context, '只支持打开 http、https、mailto、tel 链接');
      return;
    }
    final ok = await showJkConfirm(
      context,
      title: '打开链接',
      message: '将用其他应用打开：\n$href',
      confirmLabel: '打开',
    );
    if (!ok || !mounted) return;
    if (!await ref.read(launchLinkProvider)(uri) && mounted) {
      showJkToast(context, '没有可以打开该链接的应用');
    }
  }

  Future<void> _delete() async {
    final ok = await showJkConfirm(
      context,
      title: '删除笔记',
      message: '删除后其他设备上也会删除，附件一并删除。',
      confirmLabel: '删除',
      destructive: true,
    );
    if (!ok || !mounted) return;
    _deleting = true;
    try {
      await _repo.delete(widget.id);
    } on Object catch (e) {
      debugPrint('删除笔记失败: $e');
      _deleting = false;
      if (mounted) showJkToast(context, '删除失败，请重试', kind: JkToastKind.error);
      return;
    }
    _stop();
    if (mounted) context.pop();
  }

  /// 新建后什么都没写就离开：删除这篇空笔记，不同步到其他设备。
  Future<bool> _discardIfEmpty() async {
    final n = await _repo.get(widget.id);
    if (n == null ||
        n.title.trim().isNotEmpty ||
        n.body.trim().isNotEmpty ||
        n.tags.isNotEmpty ||
        n.worklogIds.isNotEmpty ||
        n.favorite ||
        n.pinned) {
      return false;
    }
    final files = await ref
        .read(attachmentServiceProvider)
        .watch(widget.id)
        .first;
    if (files.isNotEmpty) return false;
    _deleting = true;
    _stop();
    await _repo.delete(widget.id);
    return true;
  }

  Future<void> _leave() async {
    if (_leaving) return;
    _leaving = true;
    try {
      if (_loaded) {
        await _saveAll();
        await _discardIfEmpty();
      }
    } on Object catch (e) {
      // 保存失败也允许离开，不能把用户困在编辑页；未保存的内容会在 dispose 时再试一次
      debugPrint('离开笔记时保存失败: $e');
      if (mounted) {
        showJkToast(context, '部分修改没有保存成功', kind: JkToastKind.error);
      }
    }
    if (mounted) context.pop();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 进入后台时立即保存：Android 可能在后台直接结束进程，不会走到 dispose
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      unawaited(
        _saveAll().catchError((Object e) => debugPrint('进入后台时保存失败: $e')),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // 离开页面时立即保存尚未落盘的输入（富文本编辑器中尚未送达的输入已在离开前取回）
    if (_loaded) {
      unawaited(
        _body
            ?.flush(force: true)
            .catchError((Object e) => debugPrint('保存正文失败: $e')),
      );
      unawaited(_flushTitle());
    }
    _titleTimer?.cancel();
    _body?.dispose();
    _title.dispose();
    _bodyFocus.dispose();
    _closeEditor();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 切换深浅主题时同步给富文本编辑器（页面就绪前更新初始化消息）
    unawaited(_rich?.setTheme(_theme(context)));
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      noteProvider(widget.id),
      (prev, next) => _onRemote(prev?.value, next.value),
    );
    final async = ref.watch(noteProvider(widget.id));
    final note = async.value;
    // 首次读到笔记时打开编辑器（需要主题，不能放在 initState 中）
    if (note != null && !_loaded && !_deleting) _load(note);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_leave());
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            note?.displayTitle ?? '笔记',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: note == null ? null : _actions(note),
          bottom: note == null ? null : _Status(note: note),
        ),
        body: switch (async) {
          AsyncData(value: null) => const JkEmptyState(
            icon: Icon(Icons.inventory_2_outlined),
            title: '笔记不存在',
            message: '可能已在其他设备上删除',
          ),
          AsyncData(value: final n?) when _loaded => _editor(n),
          AsyncError() => JkErrorState(
            message: '读取笔记失败',
            onRetry: () => ref.invalidate(noteProvider(widget.id)),
          ),
          _ => const Padding(
            padding: EdgeInsets.all(JkTokens.spacingLg),
            child: JkSkeleton(lines: 6),
          ),
        },
      ),
    );
  }

  List<Widget> _actions(Note n) => [
    IconButton(
      key: const Key('note-format'),
      tooltip: _format == NoteFormat.markdown ? '切换到富文本' : '切换到 Markdown',
      icon: Icon(
        _format == NoteFormat.markdown ? Icons.text_fields : Icons.code,
      ),
      onPressed: _switchFormat,
    ),
    IconButton(
      key: const Key('note-info'),
      tooltip: '文件夹、标签、关联与附件',
      icon: Badge(
        isLabelVisible: n.tags.isNotEmpty || n.worklogIds.isNotEmpty,
        smallSize: 6,
        child: const Icon(Icons.info_outline),
      ),
      onPressed: () => showNoteInfo(context, n.id),
    ),
    PopupMenuButton<String>(
      key: const Key('note-menu'),
      tooltip: '更多',
      onSelected: (v) => switch (v) {
        'favorite' => _repo.update(n.id, favorite: !n.favorite),
        'pin' => _repo.update(n.id, pinned: !n.pinned),
        'revisions' => context.push('/notes/${n.id}/revisions'),
        _ => _delete(),
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'favorite',
          child: Text(n.favorite ? '取消收藏' : '收藏'),
        ),
        PopupMenuItem(value: 'pin', child: Text(n.pinned ? '取消置顶' : '置顶')),
        const PopupMenuItem(value: 'revisions', child: Text('修订历史')),
        const PopupMenuItem(value: 'delete', child: Text('删除')),
      ],
    ),
  ];

  Widget _editor(Note n) {
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(
        JkTokens.spacingLg,
        JkTokens.spacingSm,
        JkTokens.spacingLg,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (n.hasConflict)
            ConflictBanner(
              key: const Key('note-conflict'),
              onTap: () => context.push('/notes/${n.id}/revisions'),
            ),
          TextField(
            key: const Key('note-title'),
            controller: _title,
            maxLength: maxNoteTitleLength,
            style: Theme.of(context).textTheme.titleLarge,
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => _focusBody(),
            decoration: const InputDecoration(
              hintText: '标题',
              counterText: '',
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: false,
            ),
          ),
        ],
      ),
    );
    final md = _md;
    final rich = _rich;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 840),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            if (md != null)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    JkTokens.spacingLg,
                    0,
                    JkTokens.spacingLg,
                    JkTokens.spacingLg,
                  ),
                  child: MarkdownEditor(
                    controller: md,
                    focusNode: _bodyFocus,
                    expand: true,
                    fieldKey: const Key('note-body'),
                    hint: '开始记录，支持 Markdown',
                    imageBuilder: markdownImage,
                    extraTools: [
                      IconButton(
                        key: const Key('note-insert-image'),
                        tooltip: '插入图片',
                        icon: const Icon(Icons.image_outlined, size: 20),
                        onPressed: _insertImage,
                      ),
                    ],
                  ),
                ),
              )
            else if (rich != null) ...[
              Expanded(child: ref.watch(richEditorViewProvider)(context, rich)),
              RichToolbar(
                controller: rich,
                onInsertImage: _insertImage,
                onOpenLink: _openLink,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 标题栏下方的同步状态（单独一行：大字号时标题栏放不下两行）。
class _Status extends ConsumerWidget implements PreferredSizeWidget {
  const _Status({required this.note});

  final Note note;

  @override
  Size get preferredSize => const Size.fromHeight(24);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final phase = ref.watch(syncStatusProvider).value?.phase;
    final status = switch (note) {
      Note(syncError: _?) => '同步失败：内容未被服务器接受',
      Note(pending: true) when phase == SyncPhase.offline => '已保存在本机，联网后自动同步',
      Note(pending: true) => '已保存在本机，等待同步',
      _ => '已同步',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        JkTokens.spacingLg,
        0,
        JkTokens.spacingLg,
        JkTokens.spacingXs,
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          status,
          key: const Key('note-sync-status'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textScaler: MediaQuery.textScalerOf(context)
              .clamp(maxScaleFactor: 1.3),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: note.syncError != null
                ? context.jkColors.error
                : context.jkColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
