from pathlib import Path

p = Path(r"c:\Users\Aryan\Documents\Projects\Personal\sushi\sushi-app\lib\screens\library\library_screen.dart")
text = p.read_text(encoding="utf-8")
text = text.replace("import 'package:fladder/oxplayer/oxplayer_config.dart';\n", "")
text = text.replace(
    """    if (OxplayerConfig.isEnabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fetchOnMount());
    }""",
    """    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchOnMount());""",
)
text = text.replace(
    "refreshOnStart: OxplayerConfig.isEnabled ? !libraryCached : true,",
    "refreshOnStart: !libraryCached,",
)
old = """                            if (!OxplayerConfig.isEnabled) ...[
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 4.0),
                                child: VerticalDivider(),
                              ),
                              ElevatedButton.icon(
                                onPressed: () => showRefreshPopup(context, selectedView.id, selectedView.name),
                                label: Text(context.localized.scanLibrary),
                                icon: const Icon(IconsaxPlusLinear.refresh),
                              ),
                            ],
"""
assert old in text, "scan block not found"
text = text.replace(old, "")
old2 = """          if (!OxplayerConfig.isEnabled)
            ItemActionButton(
              label: Text(context.localized.scanLibrary),
              icon: const Icon(IconsaxPlusLinear.refresh),
              action: () => showRefreshPopup(context, view.id, view.name),
            ),
"""
assert old2 in text, "action scan not found"
text = text.replace(old2, "")
# Library tab removed from HomeTabs — drop scrollOf(HomeTabs.library) if present
text = text.replace("scrollOf(context, HomeTabs.library)", "PrimaryScrollController.of(context)")
p.write_text(text, encoding="utf-8")
print("OxplayerConfig left:", "OxplayerConfig" in text)
print("HomeTabs.library left:", "HomeTabs.library" in text)
