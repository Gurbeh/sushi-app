import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

import 'package:fladder/sushi/sushi_help_content.dart';
import 'package:fladder/util/localization_helper.dart';

@RoutePage()
class SushiHelpScreen extends StatelessWidget {
  const SushiHelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.localized.sushiHelpTitle)),
      body: const SafeArea(child: SushiHelpContent()),
    );
  }
}
