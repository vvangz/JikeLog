import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'ledger_models.dart';

/// 预置分类 ID 的命名空间（UUIDv5）。
const _namespace = '6f4e3700-1c2b-5d7a-9e10-4a1b2c3d4e5f';

/// 预置分类。
class PresetCategory {
  const PresetCategory(
    this.key,
    this.name,
    this.kind,
    this.icon, {
    this.parent,
  });

  /// 代号：与账号 ID 一起确定分类 ID，不随名称改变。
  final String key;
  final String name;
  final CategoryKind kind;
  final String icon;

  /// 上级预置分类的代号。
  final String? parent;
}

/// 转账手续费计入的支出分类代号。
const feeCategoryKey = 'expense.fee';

const presetCategories = <PresetCategory>[
  PresetCategory('expense.food', '餐饮', CategoryKind.expense, 'restaurant'),
  PresetCategory(
    'expense.food.breakfast',
    '早餐',
    CategoryKind.expense,
    'restaurant',
    parent: 'expense.food',
  ),
  PresetCategory(
    'expense.food.lunch',
    '午餐',
    CategoryKind.expense,
    'restaurant',
    parent: 'expense.food',
  ),
  PresetCategory(
    'expense.food.dinner',
    '晚餐',
    CategoryKind.expense,
    'restaurant',
    parent: 'expense.food',
  ),
  PresetCategory(
    'expense.food.snack',
    '零食饮料',
    CategoryKind.expense,
    'local_cafe',
    parent: 'expense.food',
  ),
  PresetCategory(
    'expense.transport',
    '交通',
    CategoryKind.expense,
    'directions_bus',
  ),
  PresetCategory(
    'expense.transport.transit',
    '公交地铁',
    CategoryKind.expense,
    'directions_bus',
    parent: 'expense.transport',
  ),
  PresetCategory(
    'expense.transport.taxi',
    '打车',
    CategoryKind.expense,
    'local_taxi',
    parent: 'expense.transport',
  ),
  PresetCategory(
    'expense.transport.car',
    '加油停车',
    CategoryKind.expense,
    'local_gas_station',
    parent: 'expense.transport',
  ),
  PresetCategory(
    'expense.shopping',
    '购物',
    CategoryKind.expense,
    'shopping_bag',
  ),
  PresetCategory(
    'expense.shopping.daily',
    '日用品',
    CategoryKind.expense,
    'shopping_bag',
    parent: 'expense.shopping',
  ),
  PresetCategory(
    'expense.shopping.clothes',
    '服饰',
    CategoryKind.expense,
    'checkroom',
    parent: 'expense.shopping',
  ),
  PresetCategory(
    'expense.shopping.digital',
    '数码',
    CategoryKind.expense,
    'devices',
    parent: 'expense.shopping',
  ),
  PresetCategory('expense.housing', '居住', CategoryKind.expense, 'home'),
  PresetCategory(
    'expense.housing.rent',
    '房租房贷',
    CategoryKind.expense,
    'home',
    parent: 'expense.housing',
  ),
  PresetCategory(
    'expense.housing.utilities',
    '水电燃气',
    CategoryKind.expense,
    'bolt',
    parent: 'expense.housing',
  ),
  PresetCategory(
    'expense.housing.property',
    '物业',
    CategoryKind.expense,
    'apartment',
    parent: 'expense.housing',
  ),
  PresetCategory(
    'expense.phone',
    '通讯网络',
    CategoryKind.expense,
    'phone_android',
  ),
  PresetCategory('expense.fun', '娱乐', CategoryKind.expense, 'sports_esports'),
  PresetCategory(
    'expense.health',
    '医疗',
    CategoryKind.expense,
    'local_hospital',
  ),
  PresetCategory('expense.education', '学习', CategoryKind.expense, 'school'),
  PresetCategory('expense.gift', '人情', CategoryKind.expense, 'card_giftcard'),
  PresetCategory('expense.travel', '旅行', CategoryKind.expense, 'flight'),
  PresetCategory(feeCategoryKey, '手续费', CategoryKind.expense, 'receipt_long'),
  PresetCategory('expense.other', '其他支出', CategoryKind.expense, 'more_horiz'),
  PresetCategory('income.salary', '工资', CategoryKind.income, 'payments'),
  PresetCategory('income.bonus', '奖金', CategoryKind.income, 'emoji_events'),
  PresetCategory('income.invest', '理财收益', CategoryKind.income, 'trending_up'),
  PresetCategory('income.parttime', '兼职', CategoryKind.income, 'work'),
  PresetCategory('income.gift', '红包礼金', CategoryKind.income, 'redeem'),
  PresetCategory('income.other', '其他收入', CategoryKind.income, 'more_horiz'),
];

/// 预置分类在某个账号下的 ID：多台设备各自初始化时得到同一个 ID（ADR-009）。
String presetCategoryId(String userId, String key) =>
    const Uuid().v5(_namespace, 'jikelog:ledger:$userId:$key');

/// 分类图标：图标名 → Material 图标；未知的名称显示为默认图标。
const categoryIcons = <String, IconData>{
  'restaurant': Icons.restaurant,
  'local_cafe': Icons.local_cafe,
  'directions_bus': Icons.directions_bus,
  'local_taxi': Icons.local_taxi,
  'local_gas_station': Icons.local_gas_station,
  'shopping_bag': Icons.shopping_bag_outlined,
  'checkroom': Icons.checkroom,
  'devices': Icons.devices_other,
  'home': Icons.home_outlined,
  'bolt': Icons.bolt,
  'apartment': Icons.apartment,
  'phone_android': Icons.phone_android,
  'sports_esports': Icons.sports_esports_outlined,
  'local_hospital': Icons.local_hospital_outlined,
  'school': Icons.school_outlined,
  'card_giftcard': Icons.card_giftcard,
  'flight': Icons.flight,
  'receipt_long': Icons.receipt_long,
  'more_horiz': Icons.more_horiz,
  'payments': Icons.payments_outlined,
  'emoji_events': Icons.emoji_events_outlined,
  'trending_up': Icons.trending_up,
  'work': Icons.work_outline,
  'redeem': Icons.redeem,
  'pets': Icons.pets,
  'child_care': Icons.child_care,
  'fitness': Icons.fitness_center,
  'beauty': Icons.face_retouching_natural,
};

IconData categoryIcon(String name) =>
    categoryIcons[name] ?? Icons.label_outline;

/// 账户类型的图标。
IconData accountIcon(AccountType t) => switch (t) {
  AccountType.cash => Icons.payments_outlined,
  AccountType.debit => Icons.credit_card,
  AccountType.credit => Icons.credit_score,
  AccountType.alipay => Icons.account_balance_wallet_outlined,
  AccountType.wechat => Icons.chat_bubble_outline,
  AccountType.other => Icons.savings_outlined,
};
