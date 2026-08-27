import 'package:flutter_test/flutter_test.dart';
import 'package:fladder/sushi/sushi_bot_login_code.dart';

void main() {
  const token = '123456789:AAFq7v9dR3n8xyzABCDEFGHIJKLMNOPQRSTU';

  test('encode/decode round-trip', () {
    final code = sushiEncodeBotLoginCode(token);
    expect(code, startsWith('s1.'));
    expect(sushiTryParseBotLoginCode(code), token);
  });

  test('rejects junk', () {
    expect(sushiTryParseBotLoginCode(''), isNull);
    expect(sushiTryParseBotLoginCode('s1.'), isNull);
    expect(sushiTryParseBotLoginCode(token), isNull);
    expect(sushiTryParseBotLoginCode('hello'), isNull);
  });
}
