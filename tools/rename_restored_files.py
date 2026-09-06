#!/usr/bin/env python3
"""Rename ox/oxplayer symbols in restored Dart files without touching control flow."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parent.parent

FILES = [
    "lib/providers/home_preferences_provider.dart",
    "lib/providers/library_search_provider.dart",
    "lib/util/item_base_model/play_item_helpers.dart",
    "lib/screens/login/login_screen_credentials.dart",
    "lib/screens/shared/media/season_row.dart",
    "lib/screens/video_player/components/video_player_options_sheet.dart",
    "lib/fake/fake_jellyfin_open_api.dart",
]

# Ordered: longer / more specific first
REPLACEMENTS = [
    ("package:fladder/oxplayer/", "package:fladder/sushi/"),
    ("OxplayerConfig", "SushiConfig"),
    ("OxplayerEnv", "SushiEnv"),
    ("OxplayerRead", "SushiRead"),
    ("OxplayerPlaybackTelemetry", "SushiPlaybackTelemetry"),
    ("OxplayerPlaybackPrefetch", "SushiPlaybackPrefetch"),
    ("OxplayerStreamLog", "SushiStreamLog"),
    ("OxplayerPlaybackRepair", "SushiPlaybackRepair"),
    ("OxplayerNativePlayback", "SushiNativePlayback"),
    ("OxHomeDashboardOrder", "SushiHomeDashboardOrder"),
    ("OxLabeledIranFlag", "SushiLabeledIranFlag"),
    ("oxplayerNavigateAfterLogin", "sushiNavigateAfterLogin"),
    ("oxplayerOpenNativePlayerEarly", "sushiOpenNativePlayerEarly"),
    ("oxplayer_provider_read", "sushi_provider_read"),
    ("oxplayer_playback_prefetch", "sushi_playback_prefetch"),
    ("oxplayer_native_playback", "sushi_native_playback"),
    ("oxplayer_stream_log", "sushi_stream_log"),
    ("oxplayer_playback_repair", "sushi_playback_repair"),
    ("oxplayer_playback_telemetry", "sushi_playback_telemetry"),
    ("oxplayer_library_search", "sushi_library_search"),
    ("oxplayer_pending_route", "sushi_pending_route"),
    ("oxplayer_seerr_auto_config", "sushi_seerr_auto_config"),
    ("oxplayer_config", "sushi_config"),
    ("oxplayer_env", "sushi_env"),
    ("ox_home_dashboard_order", "sushi_home_dashboard_order"),
    ("ox_labeled_iran_flag", "sushi_labeled_iran_flag"),
    ("oxLibrarySearch", "sushiLibrarySearch"),
    ("oxSeasonShowWatchedTick", "sushiSeasonShowWatchedTick"),
    ("oxSeasonPosterCountText", "sushiSeasonPosterCountText"),
    ("oxFilter", "sushiFilter"),
    ("oxSynthetic", "sushiSynthetic"),
    # leftover ox_ file stem refs in imports already handled via package path + oxplayer_
]

# Function/call renames that start with ox (not oxplayer)
OX_CALL = re.compile(r"\box([A-Z][A-Za-z0-9_]*)")


def transform(text: str) -> str:
    for a, b in REPLACEMENTS:
        text = text.replace(a, b)
    # oxFoo -> sushiFoo (camelCase helpers)
    text = OX_CALL.sub(r"sushi\1", text)
    # widgets/ox_ -> widgets/sushi_
    text = text.replace("widgets/ox_", "widgets/sushi_")
    text = text.replace("sushi_sushi_", "sushi_")
    return text


def main() -> None:
    for rel in FILES:
        path = ROOT / rel
        if not path.exists():
            print("MISSING", rel)
            continue
        old = path.read_text(encoding="utf-8")
        new = transform(old)
        if new != old:
            path.write_text(new, encoding="utf-8", newline="\n")
            print("EDIT", rel)
        else:
            print("same", rel)

    # Fix riverpod generated name collision: sushiItemFlagsProvider -> sushiCatalogItemFlagsProvider
    g = ROOT / "lib/sushi/providers/sushi_catalog_item_flags.g.dart"
    t = g.read_text(encoding="utf-8")
    n = (
        t.replace("sushiItemFlagsProvider", "sushiCatalogItemFlagsProvider")
        .replace("_$sushiItemFlagsHash", "_$sushiCatalogItemFlagsHash")
    )
    if n != t:
        g.write_text(n, encoding="utf-8", newline="\n")
        print("EDIT catalog flags .g.dart")

    # Fix any imports still using old catalog provider name wrongly — leave callers of
    # sushiCatalogItemFlagsProvider as-is; callers of sushiItemFlagsProvider on catalog
    # path need checking separately.


if __name__ == "__main__":
    main()
