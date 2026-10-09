// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $RecordsTable extends Records with TableInfo<$RecordsTable, RecordRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityMeta = const VerificationMeta('entity');
  @override
  late final GeneratedColumn<String> entity = GeneratedColumn<String>(
    'entity',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fieldsMeta = const VerificationMeta('fields');
  @override
  late final GeneratedColumn<String> fields = GeneratedColumn<String>(
    'fields',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _clocksMeta = const VerificationMeta('clocks');
  @override
  late final GeneratedColumn<String> clocks = GeneratedColumn<String>(
    'clocks',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _baseFieldsMeta = const VerificationMeta(
    'baseFields',
  );
  @override
  late final GeneratedColumn<String> baseFields = GeneratedColumn<String>(
    'base_fields',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  static const VerificationMeta _baseClocksMeta = const VerificationMeta(
    'baseClocks',
  );
  @override
  late final GeneratedColumn<String> baseClocks = GeneratedColumn<String>(
    'base_clocks',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _serverSeqMeta = const VerificationMeta(
    'serverSeq',
  );
  @override
  late final GeneratedColumn<int> serverSeq = GeneratedColumn<int>(
    'server_seq',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _deletedMeta = const VerificationMeta(
    'deleted',
  );
  @override
  late final GeneratedColumn<bool> deleted = GeneratedColumn<bool>(
    'deleted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("deleted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _dirtyMeta = const VerificationMeta('dirty');
  @override
  late final GeneratedColumn<bool> dirty = GeneratedColumn<bool>(
    'dirty',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("dirty" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _hasConflictMeta = const VerificationMeta(
    'hasConflict',
  );
  @override
  late final GeneratedColumn<bool> hasConflict = GeneratedColumn<bool>(
    'has_conflict',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("has_conflict" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _syncErrorMeta = const VerificationMeta(
    'syncError',
  );
  @override
  late final GeneratedColumn<String> syncError = GeneratedColumn<String>(
    'sync_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sortKeyMeta = const VerificationMeta(
    'sortKey',
  );
  @override
  late final GeneratedColumn<String> sortKey = GeneratedColumn<String>(
    'sort_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _ownerIdMeta = const VerificationMeta(
    'ownerId',
  );
  @override
  late final GeneratedColumn<String> ownerId = GeneratedColumn<String>(
    'owner_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    entity,
    fields,
    clocks,
    baseFields,
    baseClocks,
    version,
    serverSeq,
    deleted,
    dirty,
    hasConflict,
    syncError,
    updatedAt,
    sortKey,
    ownerId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'records';
  @override
  VerificationContext validateIntegrity(
    Insertable<RecordRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('entity')) {
      context.handle(
        _entityMeta,
        entity.isAcceptableOrUnknown(data['entity']!, _entityMeta),
      );
    } else if (isInserting) {
      context.missing(_entityMeta);
    }
    if (data.containsKey('fields')) {
      context.handle(
        _fieldsMeta,
        fields.isAcceptableOrUnknown(data['fields']!, _fieldsMeta),
      );
    } else if (isInserting) {
      context.missing(_fieldsMeta);
    }
    if (data.containsKey('clocks')) {
      context.handle(
        _clocksMeta,
        clocks.isAcceptableOrUnknown(data['clocks']!, _clocksMeta),
      );
    } else if (isInserting) {
      context.missing(_clocksMeta);
    }
    if (data.containsKey('base_fields')) {
      context.handle(
        _baseFieldsMeta,
        baseFields.isAcceptableOrUnknown(data['base_fields']!, _baseFieldsMeta),
      );
    }
    if (data.containsKey('base_clocks')) {
      context.handle(
        _baseClocksMeta,
        baseClocks.isAcceptableOrUnknown(data['base_clocks']!, _baseClocksMeta),
      );
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    }
    if (data.containsKey('server_seq')) {
      context.handle(
        _serverSeqMeta,
        serverSeq.isAcceptableOrUnknown(data['server_seq']!, _serverSeqMeta),
      );
    }
    if (data.containsKey('deleted')) {
      context.handle(
        _deletedMeta,
        deleted.isAcceptableOrUnknown(data['deleted']!, _deletedMeta),
      );
    }
    if (data.containsKey('dirty')) {
      context.handle(
        _dirtyMeta,
        dirty.isAcceptableOrUnknown(data['dirty']!, _dirtyMeta),
      );
    }
    if (data.containsKey('has_conflict')) {
      context.handle(
        _hasConflictMeta,
        hasConflict.isAcceptableOrUnknown(
          data['has_conflict']!,
          _hasConflictMeta,
        ),
      );
    }
    if (data.containsKey('sync_error')) {
      context.handle(
        _syncErrorMeta,
        syncError.isAcceptableOrUnknown(data['sync_error']!, _syncErrorMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('sort_key')) {
      context.handle(
        _sortKeyMeta,
        sortKey.isAcceptableOrUnknown(data['sort_key']!, _sortKeyMeta),
      );
    }
    if (data.containsKey('owner_id')) {
      context.handle(
        _ownerIdMeta,
        ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  RecordRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RecordRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      entity: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity'],
      )!,
      fields: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}fields'],
      )!,
      clocks: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}clocks'],
      )!,
      baseFields: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}base_fields'],
      )!,
      baseClocks: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}base_clocks'],
      )!,
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
      serverSeq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}server_seq'],
      )!,
      deleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}deleted'],
      )!,
      dirty: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}dirty'],
      )!,
      hasConflict: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}has_conflict'],
      )!,
      syncError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sync_error'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
      sortKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sort_key'],
      )!,
      ownerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_id'],
      ),
    );
  }

  @override
  $RecordsTable createAlias(String alias) {
    return $RecordsTable(attachedDatabase, alias);
  }
}

class RecordRow extends DataClass implements Insertable<RecordRow> {
  final String id;
  final String entity;

  /// 当前字段（明文 JSON）。
  final String fields;

  /// 字段 → 最后修改的 HLC（JSON）。
  final String clocks;

  /// 最后一次与服务端一致时的字段与时钟：用于判断本地改了哪些字段、生成文本补丁。
  final String baseFields;
  final String baseClocks;
  final int version;
  final int serverSeq;
  final bool deleted;

  /// 有尚未推送的本地修改。
  final bool dirty;

  /// 服务端返回冲突，修订历史中有落败的版本可供查看。
  final bool hasConflict;

  /// 推送被拒绝的错误码；再次修改后清除并重试。
  final String? syncError;

  /// 本地最后修改时间（毫秒）。
  final int updatedAt;

  /// 派生列，便于查询：工作日志为日期，附件为空。
  final String sortKey;

  /// 派生列：附件所属记录。
  final String? ownerId;
  const RecordRow({
    required this.id,
    required this.entity,
    required this.fields,
    required this.clocks,
    required this.baseFields,
    required this.baseClocks,
    required this.version,
    required this.serverSeq,
    required this.deleted,
    required this.dirty,
    required this.hasConflict,
    this.syncError,
    required this.updatedAt,
    required this.sortKey,
    this.ownerId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['entity'] = Variable<String>(entity);
    map['fields'] = Variable<String>(fields);
    map['clocks'] = Variable<String>(clocks);
    map['base_fields'] = Variable<String>(baseFields);
    map['base_clocks'] = Variable<String>(baseClocks);
    map['version'] = Variable<int>(version);
    map['server_seq'] = Variable<int>(serverSeq);
    map['deleted'] = Variable<bool>(deleted);
    map['dirty'] = Variable<bool>(dirty);
    map['has_conflict'] = Variable<bool>(hasConflict);
    if (!nullToAbsent || syncError != null) {
      map['sync_error'] = Variable<String>(syncError);
    }
    map['updated_at'] = Variable<int>(updatedAt);
    map['sort_key'] = Variable<String>(sortKey);
    if (!nullToAbsent || ownerId != null) {
      map['owner_id'] = Variable<String>(ownerId);
    }
    return map;
  }

  RecordsCompanion toCompanion(bool nullToAbsent) {
    return RecordsCompanion(
      id: Value(id),
      entity: Value(entity),
      fields: Value(fields),
      clocks: Value(clocks),
      baseFields: Value(baseFields),
      baseClocks: Value(baseClocks),
      version: Value(version),
      serverSeq: Value(serverSeq),
      deleted: Value(deleted),
      dirty: Value(dirty),
      hasConflict: Value(hasConflict),
      syncError: syncError == null && nullToAbsent
          ? const Value.absent()
          : Value(syncError),
      updatedAt: Value(updatedAt),
      sortKey: Value(sortKey),
      ownerId: ownerId == null && nullToAbsent
          ? const Value.absent()
          : Value(ownerId),
    );
  }

  factory RecordRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RecordRow(
      id: serializer.fromJson<String>(json['id']),
      entity: serializer.fromJson<String>(json['entity']),
      fields: serializer.fromJson<String>(json['fields']),
      clocks: serializer.fromJson<String>(json['clocks']),
      baseFields: serializer.fromJson<String>(json['baseFields']),
      baseClocks: serializer.fromJson<String>(json['baseClocks']),
      version: serializer.fromJson<int>(json['version']),
      serverSeq: serializer.fromJson<int>(json['serverSeq']),
      deleted: serializer.fromJson<bool>(json['deleted']),
      dirty: serializer.fromJson<bool>(json['dirty']),
      hasConflict: serializer.fromJson<bool>(json['hasConflict']),
      syncError: serializer.fromJson<String?>(json['syncError']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      sortKey: serializer.fromJson<String>(json['sortKey']),
      ownerId: serializer.fromJson<String?>(json['ownerId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'entity': serializer.toJson<String>(entity),
      'fields': serializer.toJson<String>(fields),
      'clocks': serializer.toJson<String>(clocks),
      'baseFields': serializer.toJson<String>(baseFields),
      'baseClocks': serializer.toJson<String>(baseClocks),
      'version': serializer.toJson<int>(version),
      'serverSeq': serializer.toJson<int>(serverSeq),
      'deleted': serializer.toJson<bool>(deleted),
      'dirty': serializer.toJson<bool>(dirty),
      'hasConflict': serializer.toJson<bool>(hasConflict),
      'syncError': serializer.toJson<String?>(syncError),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'sortKey': serializer.toJson<String>(sortKey),
      'ownerId': serializer.toJson<String?>(ownerId),
    };
  }

  RecordRow copyWith({
    String? id,
    String? entity,
    String? fields,
    String? clocks,
    String? baseFields,
    String? baseClocks,
    int? version,
    int? serverSeq,
    bool? deleted,
    bool? dirty,
    bool? hasConflict,
    Value<String?> syncError = const Value.absent(),
    int? updatedAt,
    String? sortKey,
    Value<String?> ownerId = const Value.absent(),
  }) => RecordRow(
    id: id ?? this.id,
    entity: entity ?? this.entity,
    fields: fields ?? this.fields,
    clocks: clocks ?? this.clocks,
    baseFields: baseFields ?? this.baseFields,
    baseClocks: baseClocks ?? this.baseClocks,
    version: version ?? this.version,
    serverSeq: serverSeq ?? this.serverSeq,
    deleted: deleted ?? this.deleted,
    dirty: dirty ?? this.dirty,
    hasConflict: hasConflict ?? this.hasConflict,
    syncError: syncError.present ? syncError.value : this.syncError,
    updatedAt: updatedAt ?? this.updatedAt,
    sortKey: sortKey ?? this.sortKey,
    ownerId: ownerId.present ? ownerId.value : this.ownerId,
  );
  RecordRow copyWithCompanion(RecordsCompanion data) {
    return RecordRow(
      id: data.id.present ? data.id.value : this.id,
      entity: data.entity.present ? data.entity.value : this.entity,
      fields: data.fields.present ? data.fields.value : this.fields,
      clocks: data.clocks.present ? data.clocks.value : this.clocks,
      baseFields: data.baseFields.present
          ? data.baseFields.value
          : this.baseFields,
      baseClocks: data.baseClocks.present
          ? data.baseClocks.value
          : this.baseClocks,
      version: data.version.present ? data.version.value : this.version,
      serverSeq: data.serverSeq.present ? data.serverSeq.value : this.serverSeq,
      deleted: data.deleted.present ? data.deleted.value : this.deleted,
      dirty: data.dirty.present ? data.dirty.value : this.dirty,
      hasConflict: data.hasConflict.present
          ? data.hasConflict.value
          : this.hasConflict,
      syncError: data.syncError.present ? data.syncError.value : this.syncError,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      sortKey: data.sortKey.present ? data.sortKey.value : this.sortKey,
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RecordRow(')
          ..write('id: $id, ')
          ..write('entity: $entity, ')
          ..write('fields: $fields, ')
          ..write('clocks: $clocks, ')
          ..write('baseFields: $baseFields, ')
          ..write('baseClocks: $baseClocks, ')
          ..write('version: $version, ')
          ..write('serverSeq: $serverSeq, ')
          ..write('deleted: $deleted, ')
          ..write('dirty: $dirty, ')
          ..write('hasConflict: $hasConflict, ')
          ..write('syncError: $syncError, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('sortKey: $sortKey, ')
          ..write('ownerId: $ownerId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    entity,
    fields,
    clocks,
    baseFields,
    baseClocks,
    version,
    serverSeq,
    deleted,
    dirty,
    hasConflict,
    syncError,
    updatedAt,
    sortKey,
    ownerId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RecordRow &&
          other.id == this.id &&
          other.entity == this.entity &&
          other.fields == this.fields &&
          other.clocks == this.clocks &&
          other.baseFields == this.baseFields &&
          other.baseClocks == this.baseClocks &&
          other.version == this.version &&
          other.serverSeq == this.serverSeq &&
          other.deleted == this.deleted &&
          other.dirty == this.dirty &&
          other.hasConflict == this.hasConflict &&
          other.syncError == this.syncError &&
          other.updatedAt == this.updatedAt &&
          other.sortKey == this.sortKey &&
          other.ownerId == this.ownerId);
}

class RecordsCompanion extends UpdateCompanion<RecordRow> {
  final Value<String> id;
  final Value<String> entity;
  final Value<String> fields;
  final Value<String> clocks;
  final Value<String> baseFields;
  final Value<String> baseClocks;
  final Value<int> version;
  final Value<int> serverSeq;
  final Value<bool> deleted;
  final Value<bool> dirty;
  final Value<bool> hasConflict;
  final Value<String?> syncError;
  final Value<int> updatedAt;
  final Value<String> sortKey;
  final Value<String?> ownerId;
  final Value<int> rowid;
  const RecordsCompanion({
    this.id = const Value.absent(),
    this.entity = const Value.absent(),
    this.fields = const Value.absent(),
    this.clocks = const Value.absent(),
    this.baseFields = const Value.absent(),
    this.baseClocks = const Value.absent(),
    this.version = const Value.absent(),
    this.serverSeq = const Value.absent(),
    this.deleted = const Value.absent(),
    this.dirty = const Value.absent(),
    this.hasConflict = const Value.absent(),
    this.syncError = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.sortKey = const Value.absent(),
    this.ownerId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RecordsCompanion.insert({
    required String id,
    required String entity,
    required String fields,
    required String clocks,
    this.baseFields = const Value.absent(),
    this.baseClocks = const Value.absent(),
    this.version = const Value.absent(),
    this.serverSeq = const Value.absent(),
    this.deleted = const Value.absent(),
    this.dirty = const Value.absent(),
    this.hasConflict = const Value.absent(),
    this.syncError = const Value.absent(),
    required int updatedAt,
    this.sortKey = const Value.absent(),
    this.ownerId = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       entity = Value(entity),
       fields = Value(fields),
       clocks = Value(clocks),
       updatedAt = Value(updatedAt);
  static Insertable<RecordRow> custom({
    Expression<String>? id,
    Expression<String>? entity,
    Expression<String>? fields,
    Expression<String>? clocks,
    Expression<String>? baseFields,
    Expression<String>? baseClocks,
    Expression<int>? version,
    Expression<int>? serverSeq,
    Expression<bool>? deleted,
    Expression<bool>? dirty,
    Expression<bool>? hasConflict,
    Expression<String>? syncError,
    Expression<int>? updatedAt,
    Expression<String>? sortKey,
    Expression<String>? ownerId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (entity != null) 'entity': entity,
      if (fields != null) 'fields': fields,
      if (clocks != null) 'clocks': clocks,
      if (baseFields != null) 'base_fields': baseFields,
      if (baseClocks != null) 'base_clocks': baseClocks,
      if (version != null) 'version': version,
      if (serverSeq != null) 'server_seq': serverSeq,
      if (deleted != null) 'deleted': deleted,
      if (dirty != null) 'dirty': dirty,
      if (hasConflict != null) 'has_conflict': hasConflict,
      if (syncError != null) 'sync_error': syncError,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (sortKey != null) 'sort_key': sortKey,
      if (ownerId != null) 'owner_id': ownerId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RecordsCompanion copyWith({
    Value<String>? id,
    Value<String>? entity,
    Value<String>? fields,
    Value<String>? clocks,
    Value<String>? baseFields,
    Value<String>? baseClocks,
    Value<int>? version,
    Value<int>? serverSeq,
    Value<bool>? deleted,
    Value<bool>? dirty,
    Value<bool>? hasConflict,
    Value<String?>? syncError,
    Value<int>? updatedAt,
    Value<String>? sortKey,
    Value<String?>? ownerId,
    Value<int>? rowid,
  }) {
    return RecordsCompanion(
      id: id ?? this.id,
      entity: entity ?? this.entity,
      fields: fields ?? this.fields,
      clocks: clocks ?? this.clocks,
      baseFields: baseFields ?? this.baseFields,
      baseClocks: baseClocks ?? this.baseClocks,
      version: version ?? this.version,
      serverSeq: serverSeq ?? this.serverSeq,
      deleted: deleted ?? this.deleted,
      dirty: dirty ?? this.dirty,
      hasConflict: hasConflict ?? this.hasConflict,
      syncError: syncError ?? this.syncError,
      updatedAt: updatedAt ?? this.updatedAt,
      sortKey: sortKey ?? this.sortKey,
      ownerId: ownerId ?? this.ownerId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (entity.present) {
      map['entity'] = Variable<String>(entity.value);
    }
    if (fields.present) {
      map['fields'] = Variable<String>(fields.value);
    }
    if (clocks.present) {
      map['clocks'] = Variable<String>(clocks.value);
    }
    if (baseFields.present) {
      map['base_fields'] = Variable<String>(baseFields.value);
    }
    if (baseClocks.present) {
      map['base_clocks'] = Variable<String>(baseClocks.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (serverSeq.present) {
      map['server_seq'] = Variable<int>(serverSeq.value);
    }
    if (deleted.present) {
      map['deleted'] = Variable<bool>(deleted.value);
    }
    if (dirty.present) {
      map['dirty'] = Variable<bool>(dirty.value);
    }
    if (hasConflict.present) {
      map['has_conflict'] = Variable<bool>(hasConflict.value);
    }
    if (syncError.present) {
      map['sync_error'] = Variable<String>(syncError.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (sortKey.present) {
      map['sort_key'] = Variable<String>(sortKey.value);
    }
    if (ownerId.present) {
      map['owner_id'] = Variable<String>(ownerId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RecordsCompanion(')
          ..write('id: $id, ')
          ..write('entity: $entity, ')
          ..write('fields: $fields, ')
          ..write('clocks: $clocks, ')
          ..write('baseFields: $baseFields, ')
          ..write('baseClocks: $baseClocks, ')
          ..write('version: $version, ')
          ..write('serverSeq: $serverSeq, ')
          ..write('deleted: $deleted, ')
          ..write('dirty: $dirty, ')
          ..write('hasConflict: $hasConflict, ')
          ..write('syncError: $syncError, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('sortKey: $sortKey, ')
          ..write('ownerId: $ownerId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncMetaTable extends SyncMeta with TableInfo<$SyncMetaTable, MetaRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncMetaTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_meta';
  @override
  VerificationContext validateIntegrity(
    Insertable<MetaRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  MetaRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MetaRow(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $SyncMetaTable createAlias(String alias) {
    return $SyncMetaTable(attachedDatabase, alias);
  }
}

class MetaRow extends DataClass implements Insertable<MetaRow> {
  final String key;
  final String value;
  const MetaRow({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  SyncMetaCompanion toCompanion(bool nullToAbsent) {
    return SyncMetaCompanion(key: Value(key), value: Value(value));
  }

  factory MetaRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MetaRow(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  MetaRow copyWith({String? key, String? value}) =>
      MetaRow(key: key ?? this.key, value: value ?? this.value);
  MetaRow copyWithCompanion(SyncMetaCompanion data) {
    return MetaRow(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MetaRow(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MetaRow && other.key == this.key && other.value == this.value);
}

class SyncMetaCompanion extends UpdateCompanion<MetaRow> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const SyncMetaCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncMetaCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<MetaRow> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncMetaCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return SyncMetaCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncMetaCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalFilesTable extends LocalFiles
    with TableInfo<$LocalFilesTable, LocalFileRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalFilesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pathMeta = const VerificationMeta('path');
  @override
  late final GeneratedColumn<String> path = GeneratedColumn<String>(
    'path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ownerEntityMeta = const VerificationMeta(
    'ownerEntity',
  );
  @override
  late final GeneratedColumn<String> ownerEntity = GeneratedColumn<String>(
    'owner_entity',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ownerIdMeta = const VerificationMeta(
    'ownerId',
  );
  @override
  late final GeneratedColumn<String> ownerId = GeneratedColumn<String>(
    'owner_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fileNameMeta = const VerificationMeta(
    'fileName',
  );
  @override
  late final GeneratedColumn<String> fileName = GeneratedColumn<String>(
    'file_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mimeMeta = const VerificationMeta('mime');
  @override
  late final GeneratedColumn<String> mime = GeneratedColumn<String>(
    'mime',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sizeMeta = const VerificationMeta('size');
  @override
  late final GeneratedColumn<int> size = GeneratedColumn<int>(
    'size',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sha256Meta = const VerificationMeta('sha256');
  @override
  late final GeneratedColumn<String> sha256 = GeneratedColumn<String>(
    'sha256',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _errorMeta = const VerificationMeta('error');
  @override
  late final GeneratedColumn<String> error = GeneratedColumn<String>(
    'error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    path,
    state,
    ownerEntity,
    ownerId,
    fileName,
    mime,
    size,
    sha256,
    error,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_files';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalFileRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('path')) {
      context.handle(
        _pathMeta,
        path.isAcceptableOrUnknown(data['path']!, _pathMeta),
      );
    } else if (isInserting) {
      context.missing(_pathMeta);
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    } else if (isInserting) {
      context.missing(_stateMeta);
    }
    if (data.containsKey('owner_entity')) {
      context.handle(
        _ownerEntityMeta,
        ownerEntity.isAcceptableOrUnknown(
          data['owner_entity']!,
          _ownerEntityMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_ownerEntityMeta);
    }
    if (data.containsKey('owner_id')) {
      context.handle(
        _ownerIdMeta,
        ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_ownerIdMeta);
    }
    if (data.containsKey('file_name')) {
      context.handle(
        _fileNameMeta,
        fileName.isAcceptableOrUnknown(data['file_name']!, _fileNameMeta),
      );
    } else if (isInserting) {
      context.missing(_fileNameMeta);
    }
    if (data.containsKey('mime')) {
      context.handle(
        _mimeMeta,
        mime.isAcceptableOrUnknown(data['mime']!, _mimeMeta),
      );
    } else if (isInserting) {
      context.missing(_mimeMeta);
    }
    if (data.containsKey('size')) {
      context.handle(
        _sizeMeta,
        size.isAcceptableOrUnknown(data['size']!, _sizeMeta),
      );
    } else if (isInserting) {
      context.missing(_sizeMeta);
    }
    if (data.containsKey('sha256')) {
      context.handle(
        _sha256Meta,
        sha256.isAcceptableOrUnknown(data['sha256']!, _sha256Meta),
      );
    } else if (isInserting) {
      context.missing(_sha256Meta);
    }
    if (data.containsKey('error')) {
      context.handle(
        _errorMeta,
        error.isAcceptableOrUnknown(data['error']!, _errorMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalFileRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalFileRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      path: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}path'],
      )!,
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      ownerEntity: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_entity'],
      )!,
      ownerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_id'],
      )!,
      fileName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_name'],
      )!,
      mime: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mime'],
      )!,
      size: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}size'],
      )!,
      sha256: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sha256'],
      )!,
      error: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}error'],
      ),
    );
  }

  @override
  $LocalFilesTable createAlias(String alias) {
    return $LocalFilesTable(attachedDatabase, alias);
  }
}

class LocalFileRow extends DataClass implements Insertable<LocalFileRow> {
  final String id;
  final String path;

  /// pending（待上传）/ uploaded（已上传）/ cached（已下载）。
  final String state;
  final String ownerEntity;
  final String ownerId;
  final String fileName;
  final String mime;
  final int size;
  final String sha256;
  final String? error;
  const LocalFileRow({
    required this.id,
    required this.path,
    required this.state,
    required this.ownerEntity,
    required this.ownerId,
    required this.fileName,
    required this.mime,
    required this.size,
    required this.sha256,
    this.error,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['path'] = Variable<String>(path);
    map['state'] = Variable<String>(state);
    map['owner_entity'] = Variable<String>(ownerEntity);
    map['owner_id'] = Variable<String>(ownerId);
    map['file_name'] = Variable<String>(fileName);
    map['mime'] = Variable<String>(mime);
    map['size'] = Variable<int>(size);
    map['sha256'] = Variable<String>(sha256);
    if (!nullToAbsent || error != null) {
      map['error'] = Variable<String>(error);
    }
    return map;
  }

  LocalFilesCompanion toCompanion(bool nullToAbsent) {
    return LocalFilesCompanion(
      id: Value(id),
      path: Value(path),
      state: Value(state),
      ownerEntity: Value(ownerEntity),
      ownerId: Value(ownerId),
      fileName: Value(fileName),
      mime: Value(mime),
      size: Value(size),
      sha256: Value(sha256),
      error: error == null && nullToAbsent
          ? const Value.absent()
          : Value(error),
    );
  }

  factory LocalFileRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalFileRow(
      id: serializer.fromJson<String>(json['id']),
      path: serializer.fromJson<String>(json['path']),
      state: serializer.fromJson<String>(json['state']),
      ownerEntity: serializer.fromJson<String>(json['ownerEntity']),
      ownerId: serializer.fromJson<String>(json['ownerId']),
      fileName: serializer.fromJson<String>(json['fileName']),
      mime: serializer.fromJson<String>(json['mime']),
      size: serializer.fromJson<int>(json['size']),
      sha256: serializer.fromJson<String>(json['sha256']),
      error: serializer.fromJson<String?>(json['error']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'path': serializer.toJson<String>(path),
      'state': serializer.toJson<String>(state),
      'ownerEntity': serializer.toJson<String>(ownerEntity),
      'ownerId': serializer.toJson<String>(ownerId),
      'fileName': serializer.toJson<String>(fileName),
      'mime': serializer.toJson<String>(mime),
      'size': serializer.toJson<int>(size),
      'sha256': serializer.toJson<String>(sha256),
      'error': serializer.toJson<String?>(error),
    };
  }

  LocalFileRow copyWith({
    String? id,
    String? path,
    String? state,
    String? ownerEntity,
    String? ownerId,
    String? fileName,
    String? mime,
    int? size,
    String? sha256,
    Value<String?> error = const Value.absent(),
  }) => LocalFileRow(
    id: id ?? this.id,
    path: path ?? this.path,
    state: state ?? this.state,
    ownerEntity: ownerEntity ?? this.ownerEntity,
    ownerId: ownerId ?? this.ownerId,
    fileName: fileName ?? this.fileName,
    mime: mime ?? this.mime,
    size: size ?? this.size,
    sha256: sha256 ?? this.sha256,
    error: error.present ? error.value : this.error,
  );
  LocalFileRow copyWithCompanion(LocalFilesCompanion data) {
    return LocalFileRow(
      id: data.id.present ? data.id.value : this.id,
      path: data.path.present ? data.path.value : this.path,
      state: data.state.present ? data.state.value : this.state,
      ownerEntity: data.ownerEntity.present
          ? data.ownerEntity.value
          : this.ownerEntity,
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
      fileName: data.fileName.present ? data.fileName.value : this.fileName,
      mime: data.mime.present ? data.mime.value : this.mime,
      size: data.size.present ? data.size.value : this.size,
      sha256: data.sha256.present ? data.sha256.value : this.sha256,
      error: data.error.present ? data.error.value : this.error,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalFileRow(')
          ..write('id: $id, ')
          ..write('path: $path, ')
          ..write('state: $state, ')
          ..write('ownerEntity: $ownerEntity, ')
          ..write('ownerId: $ownerId, ')
          ..write('fileName: $fileName, ')
          ..write('mime: $mime, ')
          ..write('size: $size, ')
          ..write('sha256: $sha256, ')
          ..write('error: $error')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    path,
    state,
    ownerEntity,
    ownerId,
    fileName,
    mime,
    size,
    sha256,
    error,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalFileRow &&
          other.id == this.id &&
          other.path == this.path &&
          other.state == this.state &&
          other.ownerEntity == this.ownerEntity &&
          other.ownerId == this.ownerId &&
          other.fileName == this.fileName &&
          other.mime == this.mime &&
          other.size == this.size &&
          other.sha256 == this.sha256 &&
          other.error == this.error);
}

class LocalFilesCompanion extends UpdateCompanion<LocalFileRow> {
  final Value<String> id;
  final Value<String> path;
  final Value<String> state;
  final Value<String> ownerEntity;
  final Value<String> ownerId;
  final Value<String> fileName;
  final Value<String> mime;
  final Value<int> size;
  final Value<String> sha256;
  final Value<String?> error;
  final Value<int> rowid;
  const LocalFilesCompanion({
    this.id = const Value.absent(),
    this.path = const Value.absent(),
    this.state = const Value.absent(),
    this.ownerEntity = const Value.absent(),
    this.ownerId = const Value.absent(),
    this.fileName = const Value.absent(),
    this.mime = const Value.absent(),
    this.size = const Value.absent(),
    this.sha256 = const Value.absent(),
    this.error = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalFilesCompanion.insert({
    required String id,
    required String path,
    required String state,
    required String ownerEntity,
    required String ownerId,
    required String fileName,
    required String mime,
    required int size,
    required String sha256,
    this.error = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       path = Value(path),
       state = Value(state),
       ownerEntity = Value(ownerEntity),
       ownerId = Value(ownerId),
       fileName = Value(fileName),
       mime = Value(mime),
       size = Value(size),
       sha256 = Value(sha256);
  static Insertable<LocalFileRow> custom({
    Expression<String>? id,
    Expression<String>? path,
    Expression<String>? state,
    Expression<String>? ownerEntity,
    Expression<String>? ownerId,
    Expression<String>? fileName,
    Expression<String>? mime,
    Expression<int>? size,
    Expression<String>? sha256,
    Expression<String>? error,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (path != null) 'path': path,
      if (state != null) 'state': state,
      if (ownerEntity != null) 'owner_entity': ownerEntity,
      if (ownerId != null) 'owner_id': ownerId,
      if (fileName != null) 'file_name': fileName,
      if (mime != null) 'mime': mime,
      if (size != null) 'size': size,
      if (sha256 != null) 'sha256': sha256,
      if (error != null) 'error': error,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalFilesCompanion copyWith({
    Value<String>? id,
    Value<String>? path,
    Value<String>? state,
    Value<String>? ownerEntity,
    Value<String>? ownerId,
    Value<String>? fileName,
    Value<String>? mime,
    Value<int>? size,
    Value<String>? sha256,
    Value<String?>? error,
    Value<int>? rowid,
  }) {
    return LocalFilesCompanion(
      id: id ?? this.id,
      path: path ?? this.path,
      state: state ?? this.state,
      ownerEntity: ownerEntity ?? this.ownerEntity,
      ownerId: ownerId ?? this.ownerId,
      fileName: fileName ?? this.fileName,
      mime: mime ?? this.mime,
      size: size ?? this.size,
      sha256: sha256 ?? this.sha256,
      error: error ?? this.error,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (path.present) {
      map['path'] = Variable<String>(path.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (ownerEntity.present) {
      map['owner_entity'] = Variable<String>(ownerEntity.value);
    }
    if (ownerId.present) {
      map['owner_id'] = Variable<String>(ownerId.value);
    }
    if (fileName.present) {
      map['file_name'] = Variable<String>(fileName.value);
    }
    if (mime.present) {
      map['mime'] = Variable<String>(mime.value);
    }
    if (size.present) {
      map['size'] = Variable<int>(size.value);
    }
    if (sha256.present) {
      map['sha256'] = Variable<String>(sha256.value);
    }
    if (error.present) {
      map['error'] = Variable<String>(error.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalFilesCompanion(')
          ..write('id: $id, ')
          ..write('path: $path, ')
          ..write('state: $state, ')
          ..write('ownerEntity: $ownerEntity, ')
          ..write('ownerId: $ownerId, ')
          ..write('fileName: $fileName, ')
          ..write('mime: $mime, ')
          ..write('size: $size, ')
          ..write('sha256: $sha256, ')
          ..write('error: $error, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $RecordsTable records = $RecordsTable(this);
  late final $SyncMetaTable syncMeta = $SyncMetaTable(this);
  late final $LocalFilesTable localFiles = $LocalFilesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    records,
    syncMeta,
    localFiles,
  ];
}

typedef $$RecordsTableCreateCompanionBuilder = RecordsCompanion Function({
  required String id,
  required String entity,
  required String fields,
  required String clocks,
  Value<String> baseFields,
  Value<String> baseClocks,
  Value<int> version,
  Value<int> serverSeq,
  Value<bool> deleted,
  Value<bool> dirty,
  Value<bool> hasConflict,
  Value<String?> syncError,
  required int updatedAt,
  Value<String> sortKey,
  Value<String?> ownerId,
  Value<int> rowid,
});
typedef $$RecordsTableUpdateCompanionBuilder = RecordsCompanion Function({
  Value<String> id,
  Value<String> entity,
  Value<String> fields,
  Value<String> clocks,
  Value<String> baseFields,
  Value<String> baseClocks,
  Value<int> version,
  Value<int> serverSeq,
  Value<bool> deleted,
  Value<bool> dirty,
  Value<bool> hasConflict,
  Value<String?> syncError,
  Value<int> updatedAt,
  Value<String> sortKey,
  Value<String?> ownerId,
  Value<int> rowid,
});

class $$RecordsTableFilterComposer
    extends Composer<_$AppDatabase, $RecordsTable> {
  $$RecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entity => $composableBuilder(
    column: $table.entity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fields => $composableBuilder(
    column: $table.fields,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get clocks => $composableBuilder(
    column: $table.clocks,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get baseFields => $composableBuilder(
    column: $table.baseFields,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get baseClocks => $composableBuilder(
    column: $table.baseClocks,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get serverSeq => $composableBuilder(
    column: $table.serverSeq,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get hasConflict => $composableBuilder(
    column: $table.hasConflict,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get syncError => $composableBuilder(
    column: $table.syncError,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sortKey => $composableBuilder(
    column: $table.sortKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$RecordsTableOrderingComposer
    extends Composer<_$AppDatabase, $RecordsTable> {
  $$RecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entity => $composableBuilder(
    column: $table.entity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fields => $composableBuilder(
    column: $table.fields,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get clocks => $composableBuilder(
    column: $table.clocks,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get baseFields => $composableBuilder(
    column: $table.baseFields,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get baseClocks => $composableBuilder(
    column: $table.baseClocks,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get serverSeq => $composableBuilder(
    column: $table.serverSeq,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get hasConflict => $composableBuilder(
    column: $table.hasConflict,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get syncError => $composableBuilder(
    column: $table.syncError,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sortKey => $composableBuilder(
    column: $table.sortKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$RecordsTableAnnotationComposer
    extends Composer<_$AppDatabase, $RecordsTable> {
  $$RecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get entity =>
      $composableBuilder(column: $table.entity, builder: (column) => column);

  GeneratedColumn<String> get fields =>
      $composableBuilder(column: $table.fields, builder: (column) => column);

  GeneratedColumn<String> get clocks =>
      $composableBuilder(column: $table.clocks, builder: (column) => column);

  GeneratedColumn<String> get baseFields => $composableBuilder(
    column: $table.baseFields,
    builder: (column) => column,
  );

  GeneratedColumn<String> get baseClocks => $composableBuilder(
    column: $table.baseClocks,
    builder: (column) => column,
  );

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<int> get serverSeq =>
      $composableBuilder(column: $table.serverSeq, builder: (column) => column);

  GeneratedColumn<bool> get deleted =>
      $composableBuilder(column: $table.deleted, builder: (column) => column);

  GeneratedColumn<bool> get dirty =>
      $composableBuilder(column: $table.dirty, builder: (column) => column);

  GeneratedColumn<bool> get hasConflict => $composableBuilder(
    column: $table.hasConflict,
    builder: (column) => column,
  );

  GeneratedColumn<String> get syncError =>
      $composableBuilder(column: $table.syncError, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get sortKey =>
      $composableBuilder(column: $table.sortKey, builder: (column) => column);

  GeneratedColumn<String> get ownerId =>
      $composableBuilder(column: $table.ownerId, builder: (column) => column);
}

class $$RecordsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $RecordsTable,
          RecordRow,
          $$RecordsTableFilterComposer,
          $$RecordsTableOrderingComposer,
          $$RecordsTableAnnotationComposer,
          $$RecordsTableCreateCompanionBuilder,
          $$RecordsTableUpdateCompanionBuilder,
          (RecordRow, BaseReferences<_$AppDatabase, $RecordsTable, RecordRow>),
          RecordRow,
          PrefetchHooks Function()
        > {
  $$RecordsTableTableManager(_$AppDatabase db, $RecordsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RecordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RecordsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> entity = const Value.absent(),
                Value<String> fields = const Value.absent(),
                Value<String> clocks = const Value.absent(),
                Value<String> baseFields = const Value.absent(),
                Value<String> baseClocks = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<int> serverSeq = const Value.absent(),
                Value<bool> deleted = const Value.absent(),
                Value<bool> dirty = const Value.absent(),
                Value<bool> hasConflict = const Value.absent(),
                Value<String?> syncError = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<String> sortKey = const Value.absent(),
                Value<String?> ownerId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RecordsCompanion(
                id: id,
                entity: entity,
                fields: fields,
                clocks: clocks,
                baseFields: baseFields,
                baseClocks: baseClocks,
                version: version,
                serverSeq: serverSeq,
                deleted: deleted,
                dirty: dirty,
                hasConflict: hasConflict,
                syncError: syncError,
                updatedAt: updatedAt,
                sortKey: sortKey,
                ownerId: ownerId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String entity,
                required String fields,
                required String clocks,
                Value<String> baseFields = const Value.absent(),
                Value<String> baseClocks = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<int> serverSeq = const Value.absent(),
                Value<bool> deleted = const Value.absent(),
                Value<bool> dirty = const Value.absent(),
                Value<bool> hasConflict = const Value.absent(),
                Value<String?> syncError = const Value.absent(),
                required int updatedAt,
                Value<String> sortKey = const Value.absent(),
                Value<String?> ownerId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RecordsCompanion.insert(
                id: id,
                entity: entity,
                fields: fields,
                clocks: clocks,
                baseFields: baseFields,
                baseClocks: baseClocks,
                version: version,
                serverSeq: serverSeq,
                deleted: deleted,
                dirty: dirty,
                hasConflict: hasConflict,
                syncError: syncError,
                updatedAt: updatedAt,
                sortKey: sortKey,
                ownerId: ownerId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$RecordsTable, RecordRow>(table),
                  BaseReferences<_$AppDatabase, $RecordsTable, RecordRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$RecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $RecordsTable,
      RecordRow,
      $$RecordsTableFilterComposer,
      $$RecordsTableOrderingComposer,
      $$RecordsTableAnnotationComposer,
      $$RecordsTableCreateCompanionBuilder,
      $$RecordsTableUpdateCompanionBuilder,
      (RecordRow, BaseReferences<_$AppDatabase, $RecordsTable, RecordRow>),
      RecordRow,
      PrefetchHooks Function()
    >;
typedef $$SyncMetaTableCreateCompanionBuilder = SyncMetaCompanion Function({
  required String key,
  required String value,
  Value<int> rowid,
});
typedef $$SyncMetaTableUpdateCompanionBuilder = SyncMetaCompanion Function({
  Value<String> key,
  Value<String> value,
  Value<int> rowid,
});

class $$SyncMetaTableFilterComposer
    extends Composer<_$AppDatabase, $SyncMetaTable> {
  $$SyncMetaTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncMetaTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncMetaTable> {
  $$SyncMetaTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncMetaTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncMetaTable> {
  $$SyncMetaTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$SyncMetaTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SyncMetaTable,
          MetaRow,
          $$SyncMetaTableFilterComposer,
          $$SyncMetaTableOrderingComposer,
          $$SyncMetaTableAnnotationComposer,
          $$SyncMetaTableCreateCompanionBuilder,
          $$SyncMetaTableUpdateCompanionBuilder,
          (MetaRow, BaseReferences<_$AppDatabase, $SyncMetaTable, MetaRow>),
          MetaRow,
          PrefetchHooks Function()
        > {
  $$SyncMetaTableTableManager(_$AppDatabase db, $SyncMetaTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncMetaTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncMetaTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncMetaTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> key = const Value.absent(),
            Value<String> value = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) => SyncMetaCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback: ({
            required String key,
            required String value,
            Value<int> rowid = const Value.absent(),
          }) => SyncMetaCompanion.insert(key: key, value: value, rowid: rowid),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SyncMetaTable, MetaRow>(table),
                  BaseReferences<_$AppDatabase, $SyncMetaTable, MetaRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncMetaTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SyncMetaTable,
      MetaRow,
      $$SyncMetaTableFilterComposer,
      $$SyncMetaTableOrderingComposer,
      $$SyncMetaTableAnnotationComposer,
      $$SyncMetaTableCreateCompanionBuilder,
      $$SyncMetaTableUpdateCompanionBuilder,
      (MetaRow, BaseReferences<_$AppDatabase, $SyncMetaTable, MetaRow>),
      MetaRow,
      PrefetchHooks Function()
    >;
typedef $$LocalFilesTableCreateCompanionBuilder = LocalFilesCompanion Function({
  required String id,
  required String path,
  required String state,
  required String ownerEntity,
  required String ownerId,
  required String fileName,
  required String mime,
  required int size,
  required String sha256,
  Value<String?> error,
  Value<int> rowid,
});
typedef $$LocalFilesTableUpdateCompanionBuilder = LocalFilesCompanion Function({
  Value<String> id,
  Value<String> path,
  Value<String> state,
  Value<String> ownerEntity,
  Value<String> ownerId,
  Value<String> fileName,
  Value<String> mime,
  Value<int> size,
  Value<String> sha256,
  Value<String?> error,
  Value<int> rowid,
});

class $$LocalFilesTableFilterComposer
    extends Composer<_$AppDatabase, $LocalFilesTable> {
  $$LocalFilesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ownerEntity => $composableBuilder(
    column: $table.ownerEntity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fileName => $composableBuilder(
    column: $table.fileName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mime => $composableBuilder(
    column: $table.mime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get size => $composableBuilder(
    column: $table.size,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sha256 => $composableBuilder(
    column: $table.sha256,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get error => $composableBuilder(
    column: $table.error,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalFilesTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalFilesTable> {
  $$LocalFilesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ownerEntity => $composableBuilder(
    column: $table.ownerEntity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fileName => $composableBuilder(
    column: $table.fileName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mime => $composableBuilder(
    column: $table.mime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get size => $composableBuilder(
    column: $table.size,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sha256 => $composableBuilder(
    column: $table.sha256,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get error => $composableBuilder(
    column: $table.error,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalFilesTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalFilesTable> {
  $$LocalFilesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get path =>
      $composableBuilder(column: $table.path, builder: (column) => column);

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<String> get ownerEntity => $composableBuilder(
    column: $table.ownerEntity,
    builder: (column) => column,
  );

  GeneratedColumn<String> get ownerId =>
      $composableBuilder(column: $table.ownerId, builder: (column) => column);

  GeneratedColumn<String> get fileName =>
      $composableBuilder(column: $table.fileName, builder: (column) => column);

  GeneratedColumn<String> get mime =>
      $composableBuilder(column: $table.mime, builder: (column) => column);

  GeneratedColumn<int> get size =>
      $composableBuilder(column: $table.size, builder: (column) => column);

  GeneratedColumn<String> get sha256 =>
      $composableBuilder(column: $table.sha256, builder: (column) => column);

  GeneratedColumn<String> get error =>
      $composableBuilder(column: $table.error, builder: (column) => column);
}

class $$LocalFilesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LocalFilesTable,
          LocalFileRow,
          $$LocalFilesTableFilterComposer,
          $$LocalFilesTableOrderingComposer,
          $$LocalFilesTableAnnotationComposer,
          $$LocalFilesTableCreateCompanionBuilder,
          $$LocalFilesTableUpdateCompanionBuilder,
          (
            LocalFileRow,
            BaseReferences<_$AppDatabase, $LocalFilesTable, LocalFileRow>,
          ),
          LocalFileRow,
          PrefetchHooks Function()
        > {
  $$LocalFilesTableTableManager(_$AppDatabase db, $LocalFilesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalFilesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalFilesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalFilesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> path = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<String> ownerEntity = const Value.absent(),
                Value<String> ownerId = const Value.absent(),
                Value<String> fileName = const Value.absent(),
                Value<String> mime = const Value.absent(),
                Value<int> size = const Value.absent(),
                Value<String> sha256 = const Value.absent(),
                Value<String?> error = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalFilesCompanion(
                id: id,
                path: path,
                state: state,
                ownerEntity: ownerEntity,
                ownerId: ownerId,
                fileName: fileName,
                mime: mime,
                size: size,
                sha256: sha256,
                error: error,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String path,
                required String state,
                required String ownerEntity,
                required String ownerId,
                required String fileName,
                required String mime,
                required int size,
                required String sha256,
                Value<String?> error = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalFilesCompanion.insert(
                id: id,
                path: path,
                state: state,
                ownerEntity: ownerEntity,
                ownerId: ownerId,
                fileName: fileName,
                mime: mime,
                size: size,
                sha256: sha256,
                error: error,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$LocalFilesTable, LocalFileRow>(table),
                  BaseReferences<_$AppDatabase, $LocalFilesTable, LocalFileRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalFilesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LocalFilesTable,
      LocalFileRow,
      $$LocalFilesTableFilterComposer,
      $$LocalFilesTableOrderingComposer,
      $$LocalFilesTableAnnotationComposer,
      $$LocalFilesTableCreateCompanionBuilder,
      $$LocalFilesTableUpdateCompanionBuilder,
      (
        LocalFileRow,
        BaseReferences<_$AppDatabase, $LocalFilesTable, LocalFileRow>,
      ),
      LocalFileRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$RecordsTableTableManager get records =>
      $$RecordsTableTableManager(_db, _db.records);
  $$SyncMetaTableTableManager get syncMeta =>
      $$SyncMetaTableTableManager(_db, _db.syncMeta);
  $$LocalFilesTableTableManager get localFiles =>
      $$LocalFilesTableTableManager(_db, _db.localFiles);
}
