package oxtelegram

import (
	"context"
	"fmt"
	"strings"

	"github.com/gotd/td/tg"
)

// SendTextToUsername resolves [username] and sends a plain text message.
// Intended for the Sushi `/initbot` handshake (init-bot). Not yet wired through pigeon —
// Flutter still stubs until OxTdlibBridgeApi gains sendTextMessage.
func (c *Client) SendTextToUsername(ctx context.Context, username, text string) error {
	username = strings.TrimPrefix(strings.TrimSpace(username), "@")
	text = strings.TrimSpace(text)
	if username == "" || text == "" {
		return fmt.Errorf("username and text required")
	}
	api := c.API()
	if api == nil {
		return fmt.Errorf("client not configured")
	}
	resolved, err := api.ContactsResolveUsername(ctx, &tg.ContactsResolveUsernameRequest{
		Username: username,
	})
	if err != nil {
		return fmt.Errorf("ContactsResolveUsername: %w", err)
	}
	var user *tg.User
	for _, u := range resolved.Users {
		if candidate, ok := u.(*tg.User); ok {
			user = candidate
			break
		}
	}
	if user == nil {
		return fmt.Errorf("username did not resolve to a user")
	}
	peer := &tg.InputPeerUser{UserID: user.ID, AccessHash: user.AccessHash}
	_, err = api.MessagesSendMessage(ctx, &tg.MessagesSendMessageRequest{
		Peer:     peer,
		Message:  text,
		RandomID: cryptoRandomID(),
	})
	if err != nil {
		return fmt.Errorf("MessagesSendMessage: %w", err)
	}
	return nil
}
