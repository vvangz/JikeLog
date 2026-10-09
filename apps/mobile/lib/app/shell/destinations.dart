import '../../shared/ui/jk_icon.dart';

/// 侧栏中的一个入口。
class Destination {
  const Destination({
    required this.path,
    required this.label,
    required this.icon,
    this.description = '',
  });

  final String path;
  final String label;
  final JkIcons icon;

  /// 模块主界面尚未实现时空状态中的说明。
  final String description;
}

/// 侧栏上方：四个核心模块。
const moduleDestinations = [
  Destination(
    path: '/worklog',
    label: '工作日志',
    icon: JkIcons.worklog,
    description: '记录每天的工作地点、内容与附件，支持随时修改，内容加密传输。将在 v0.3.0 开放。',
  ),
  Destination(
    path: '/notes',
    label: '笔记',
    icon: JkIcons.notes,
    description: '支持 Markdown 与富文本、代码块、表格、待办清单，可关联到工作日志。将在 v0.4.0 开放。',
  ),
  Destination(
    path: '/memos',
    label: '备忘录',
    icon: JkIcons.memos,
    description: '设定日期时间与提前提醒，与日历关联，到点推送提醒。将在 v0.5.0 开放。',
  ),
  Destination(
    path: '/ledger',
    label: '记账',
    icon: JkIcons.ledger,
    description: '记录收入、支出、转账与借贷，查看分类占比和账户余额。将在 v0.6.0 开放。',
  ),
];

/// 侧栏下方：通用入口。
const generalDestinations = [
  Destination(path: '/settings', label: '设置', icon: JkIcons.settings),
  Destination(path: '/account', label: '帐号', icon: JkIcons.account),
];

const allDestinations = [...moduleDestinations, ...generalDestinations];

/// 当前路径所属的入口（子页面归属于其上级入口）。
Destination? destinationFor(String location) {
  for (final d in allDestinations) {
    if (location == d.path || location.startsWith('${d.path}/')) return d;
  }
  return null;
}
