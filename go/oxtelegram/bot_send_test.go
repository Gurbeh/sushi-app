package oxtelegram

import (
	"fmt"
	"testing"

	"github.com/gotd/td/tgerr"
)

func TestIsUserIsBot(t *testing.T) {
	t.Parallel()

	if isUserIsBot(nil) {
		t.Fatal("nil")
	}
	if !isUserIsBot(tgerr.New(400, "USER_IS_BOT")) {
		t.Fatal("rpc")
	}
	if !isUserIsBot(fmt.Errorf("MessagesSendMessage: rpc error code 400: USER_IS_BOT")) {
		t.Fatal("wrapped string")
	}
	if isUserIsBot(fmt.Errorf("PEER_FLOOD")) {
		t.Fatal("other error")
	}
}
