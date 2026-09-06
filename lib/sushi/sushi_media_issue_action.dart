import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/widgets/shared/item_actions.dart';

bool sushiCanReportMediaIssue(WidgetRef ref, ItemBaseModel item) => false;

List<ItemAction> sushiMediaIssueActions(
  BuildContext context,
  WidgetRef ref,
  ItemBaseModel item,
) =>
    const [];
