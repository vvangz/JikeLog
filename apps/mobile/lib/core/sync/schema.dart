/// 客户端视角的实体定义，与服务端 `internal/syncer/schema.go` 对应。
library;

/// 字段特性。
class FieldSpec {
  const FieldSpec({this.sensitive = false, this.text = false});

  /// 敏感字段：传输时用加密会话加密（ADR-006）。
  final bool sensitive;

  /// 长文本：并发修改时推送补丁，由服务端合并。
  final bool text;
}

abstract final class Entities {
  static const worklog = 'worklog';
  static const attachment = 'attachment';
  static const note = 'note';
  static const noteFolder = 'note_folder';
  static const memo = 'memo';
  static const ledgerAccount = 'ledger_account';
  static const ledgerCategory = 'ledger_category';
  static const ledgerLoan = 'ledger_loan';
  static const ledgerEntry = 'ledger_entry';

  static const specs = <String, Map<String, FieldSpec>>{
    worklog: {
      'date': FieldSpec(),
      'location': FieldSpec(sensitive: true),
      'content': FieldSpec(sensitive: true, text: true),
    },
    attachment: {
      'ownerEntity': FieldSpec(),
      'ownerId': FieldSpec(),
      'fileName': FieldSpec(sensitive: true),
      'mime': FieldSpec(),
      'size': FieldSpec(),
      'sha256': FieldSpec(),
    },
    // 笔记（ADR-007）：两种格式的正文都是 Markdown；标签与关联的工作日志为多行文本
    note: {
      'title': FieldSpec(sensitive: true),
      'body': FieldSpec(sensitive: true, text: true),
      'format': FieldSpec(),
      'folderId': FieldSpec(),
      'favorite': FieldSpec(),
      'pinned': FieldSpec(),
      'tags': FieldSpec(sensitive: true, text: true),
      'worklogs': FieldSpec(text: true),
    },
    noteFolder: {'name': FieldSpec(sensitive: true), 'parentId': FieldSpec()},
    // 备忘录（ADR-008）：只有内容加密，时间与提醒供服务端按时推送
    memo: {
      'content': FieldSpec(sensitive: true, text: true),
      'at': FieldSpec(),
      'allDay': FieldSpec(),
      'reminders': FieldSpec(),
      'done': FieldSpec(),
    },
    // 记账（ADR-009）：金额、名称、对方与备注加密
    ledgerAccount: {
      'name': FieldSpec(sensitive: true),
      'type': FieldSpec(),
      'initialBalance': FieldSpec(sensitive: true),
      'archived': FieldSpec(),
      'sortOrder': FieldSpec(),
    },
    ledgerCategory: {
      'name': FieldSpec(sensitive: true),
      'kind': FieldSpec(),
      'parentId': FieldSpec(),
      'icon': FieldSpec(),
      'archived': FieldSpec(),
      'sortOrder': FieldSpec(),
    },
    ledgerLoan: {
      'direction': FieldSpec(),
      'counterparty': FieldSpec(sensitive: true),
      'dueDate': FieldSpec(),
      'note': FieldSpec(sensitive: true, text: true),
      'settled': FieldSpec(),
    },
    ledgerEntry: {
      'type': FieldSpec(),
      'amount': FieldSpec(sensitive: true),
      'fee': FieldSpec(sensitive: true),
      'date': FieldSpec(),
      'accountId': FieldSpec(),
      'toAccountId': FieldSpec(),
      'categoryId': FieldSpec(),
      'loanId': FieldSpec(),
      'note': FieldSpec(sensitive: true, text: true),
    },
  };

  static FieldSpec field(String entity, String name) =>
      specs[entity]?[name] ?? const FieldSpec();
}
