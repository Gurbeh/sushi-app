package oxtelegram

import (
	"context"
	"fmt"
	"log"
	"strings"
	"time"

	"github.com/gotd/td/tg"
)

const textReplyWaitTimeout = 30 * time.Second

// SendTextToUsername resolves [username] and sends a plain text message.
// Prefer [SendTextAndWaitReply] for the Sushi `/initbot` handshake.
func (c *Client) SendTextToUsername(ctx context.Context, username, text string) error {
	_, err := c.sendTextToUsername(ctx, username, text)
	return err
}

// SendTextAndWaitReply sends [text] to @[username] and waits for the next text reply from that
// peer whose body starts with '!' (Sushi wire framing, docs/03). Used for `/initbot <corr>`.
//
// Starts the bot DM when empty (messages.startBot) so Telegram allows the bot to answer.
func (c *Client) SendTextAndWaitReply(ctx context.Context, username, text string) (string, error) {
	username = strings.TrimPrefix(strings.TrimSpace(username), "@")
	text = strings.TrimSpace(text)
	if username == "" || text == "" {
		return "", fmt.Errorf("username and text required")
	}

	peer, userID, err := c.resolveInputPeerUser(ctx, username)
	if err != nil {
		return "", err
	}

	if err := c.ensureBotDialog(ctx, peer, userID, username); err != nil {
		log.Printf("oxtelegram: ensureBotDialog @%s: %v (continuing send)", username, err)
	}

	waitCh := c.registerTextWaiter(userID)
	defer c.unregisterTextWaiter(userID, waitCh)

	api := c.API()
	if api == nil {
		return "", fmt.Errorf("client not configured")
	}
	if _, err := api.MessagesSendMessage(ctx, &tg.MessagesSendMessageRequest{
		Peer:     peer,
		Message:  text,
		RandomID: cryptoRandomID(),
	}); err != nil {
		return "", fmt.Errorf("MessagesSendMessage: %w", err)
	}

	timeout := textReplyWaitTimeout
	if deadline, ok := ctx.Deadline(); ok {
		if rem := time.Until(deadline); rem > 0 && rem < timeout {
			timeout = rem
		}
	}
	timer := time.NewTimer(timeout)
	defer timer.Stop()

	select {
	case reply := <-waitCh:
		if reply == "" {
			return "", fmt.Errorf("empty text reply from @%s", username)
		}
		return reply, nil
	case <-ctx.Done():
		return "", ctx.Err()
	case <-timer.C:
		return "", fmt.Errorf("timed out waiting for reply from @%s", username)
	}
}

func (c *Client) sendTextToUsername(ctx context.Context, username, text string) (*tg.InputPeerUser, error) {
	username = strings.TrimPrefix(strings.TrimSpace(username), "@")
	text = strings.TrimSpace(text)
	if username == "" || text == "" {
		return nil, fmt.Errorf("username and text required")
	}
	peer, _, err := c.resolveInputPeerUser(ctx, username)
	if err != nil {
		return nil, err
	}
	api := c.API()
	if api == nil {
		return nil, fmt.Errorf("client not configured")
	}
	if _, err := api.MessagesSendMessage(ctx, &tg.MessagesSendMessageRequest{
		Peer:     peer,
		Message:  text,
		RandomID: cryptoRandomID(),
	}); err != nil {
		return nil, fmt.Errorf("MessagesSendMessage: %w", err)
	}
	return peer, nil
}

func (c *Client) resolveInputPeerUser(ctx context.Context, username string) (*tg.InputPeerUser, int64, error) {
	api := c.API()
	if api == nil {
		return nil, 0, fmt.Errorf("client not configured")
	}
	resolved, err := api.ContactsResolveUsername(ctx, &tg.ContactsResolveUsernameRequest{
		Username: strings.TrimPrefix(username, "@"),
	})
	if err != nil {
		return nil, 0, fmt.Errorf("ContactsResolveUsername: %w", err)
	}
	var user *tg.User
	for _, u := range resolved.Users {
		if candidate, ok := u.(*tg.User); ok {
			user = candidate
			break
		}
	}
	if user == nil {
		return nil, 0, fmt.Errorf("username did not resolve to a user")
	}
	peer := &tg.InputPeerUser{UserID: user.ID, AccessHash: user.AccessHash}
	c.rememberProviderPeer(peer)
	return peer, user.ID, nil
}

func (c *Client) ensureBotDialog(ctx context.Context, peer *tg.InputPeerUser, userID int64, username string) error {
	api := c.API()
	if api == nil {
		return fmt.Errorf("client not configured")
	}
	has, err := c.dialogHasMessages(ctx, api, peer)
	if err != nil {
		log.Printf("oxtelegram: dialog check @%s: %v", username, err)
	}
	if has {
		return nil
	}
	_, err = api.MessagesStartBot(ctx, &tg.MessagesStartBotRequest{
		Bot:        &tg.InputUser{UserID: userID, AccessHash: peer.AccessHash},
		Peer:       peer,
		RandomID:   cryptoRandomID(),
		StartParam: "sushi",
	})
	if err != nil {
		return fmt.Errorf("MessagesStartBot: %w", err)
	}
	log.Printf("oxtelegram: startBot @%s ok bot=%d", username, userID)
	return nil
}

// --- text reply waiters (keyed by peer user id) ---

func (c *Client) ensureTextWaiterMaps() {
	if c.textWaiters == nil {
		c.textWaiters = make(map[int64]chan string)
	}
	if c.textArrived == nil {
		c.textArrived = make(map[int64]string)
	}
}

func (c *Client) registerTextWaiter(peerID int64) chan string {
	ch := make(chan string, 1)
	c.textMu.Lock()
	defer c.textMu.Unlock()
	c.ensureTextWaiterMaps()
	if early, ok := c.textArrived[peerID]; ok {
		delete(c.textArrived, peerID)
		ch <- early
		return ch
	}
	if existing, ok := c.textWaiters[peerID]; ok {
		return existing
	}
	c.textWaiters[peerID] = ch
	return ch
}

func (c *Client) unregisterTextWaiter(peerID int64, ch chan string) {
	c.textMu.Lock()
	defer c.textMu.Unlock()
	if cur, ok := c.textWaiters[peerID]; ok && cur == ch {
		delete(c.textWaiters, peerID)
	}
}

// deliverTextReply routes an incoming '!' framed reply to a waiter, or buffers one early arrival.
func (c *Client) deliverTextReply(fromUserID int64, text string) {
	text = strings.TrimSpace(text)
	if fromUserID == 0 || text == "" || text[0] != '!' {
		return
	}
	c.textMu.Lock()
	defer c.textMu.Unlock()
	c.ensureTextWaiterMaps()
	if ch, ok := c.textWaiters[fromUserID]; ok {
		delete(c.textWaiters, fromUserID)
		select {
		case ch <- text:
		default:
		}
		return
	}
	// Buffer one early arrival (send raced ahead of register — unlikely but safe).
	c.textArrived[fromUserID] = text
}

func textFromPrivateMessage(msg tg.MessageClass) (text string, fromUserID int64, ok bool) {
	m, isMsg := msg.(*tg.Message)
	if !isMsg || m == nil {
		return "", 0, false
	}
	text = strings.TrimSpace(m.Message)
	if text == "" {
		return "", 0, false
	}
	switch p := m.PeerID.(type) {
	case *tg.PeerUser:
		fromUserID = p.UserID
	default:
		// Only private DMs matter for initbot.
		return "", 0, false
	}
	// Outgoing messages also have PeerUser — skip our own sends (Out flag).
	if m.Out {
		return "", 0, false
	}
	return text, fromUserID, true
}
