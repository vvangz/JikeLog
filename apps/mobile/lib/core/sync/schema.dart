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
  };

  static FieldSpec field(String entity, String name) =>
      specs[entity]?[name] ?? const FieldSpec();
}
