package oxtelegram

import (
	"context"
	"fmt"
	"os"
)

// Subtitle documents are extracted SRT/ASS text (doc 15 §7). A season-pack ZIP slipping
// through would be megabytes crossing gomobile as a Java String — NULs in that path are a
// JNI crash class. Cap well above a real episode file, well below a pack.
const maxSmallDocumentBytes = 8 << 20

// FetchSmallDocument downloads a whole small document (a subtitle file, doc 15 §7) freshly copied
// into this session's own chat with a bot -- the SubtitleFile delivery step's reader-DM copy.
//
// messageID is deliberately ignored: it is the id the Bot API's copyMessage call reported, which is
// that bot's own per-chat message counter, not this (MTProto) session's own message-id space that
// messages.getMessages requires a bare id from -- looking it up directly returned OX_DM_STALE ("has
// no document") for a real, freshly-landed file. This mirrors how a fresh (unresolved) video
// delivery is always resolved: wait for the copy to arrive as a live push (resolveVideoFileByPush)
// and read the real id off that update instead. Callers must arm the delivery waiter for locator
// (ArmDeliveryWaiter) before triggering the server-side copy that leads here, same ordering
// sushi_tdlib_playback_resolver.dart uses for video, so the push cannot land before something is
// listening for it.
func (c *Client) FetchSmallDocument(ctx context.Context, botID, messageID int64, locator, cacheDir string) (string, error) {
	ref, err := c.resolveVideoFileByPush(ctx, locator)
	if err != nil {
		return "", fmt.Errorf("fetch document: %w", err)
	}
	if ref.Size > maxSmallDocumentBytes {
		return "", fmt.Errorf("fetch document: %d bytes exceeds %d cap", ref.Size, maxSmallDocumentBytes)
	}
	session, err := c.OpenDownload(ref, 0, locator, cacheDir)
	if err != nil {
		return "", fmt.Errorf("fetch document: %w", err)
	}
	path := session.LocalPath()
	defer func() {
		session.Cancel()
		_ = os.Remove(path)
		_ = os.Remove(rangesSidecarPath(path))
	}()
	if err := session.EnsureAvailable(ctx, 0, ref.Size); err != nil {
		return "", fmt.Errorf("fetch document: %w", err)
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return "", fmt.Errorf("fetch document: read: %w", err)
	}
	owned := make([]byte, len(data))
	copy(owned, data)
	return string(owned), nil
}
