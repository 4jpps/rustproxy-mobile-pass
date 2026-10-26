import 'package:flutter_test/flutter_test.dart';
import 'package:rustproxy_mobile_pass/pass_client.dart';

void main() {
  test('server addresses become the HTTPS check-in endpoint', () {
    expect(passUri('hermes.example.com').toString(), 'https://hermes.example.com/.rust-proxy/mobile-pass');
    expect(passUri(' https://hermes.example.com/app?x=1 ').toString(), 'https://hermes.example.com/.rust-proxy/mobile-pass');
    expect(passUri('https://h.example.com:8443').toString(), 'https://h.example.com:8443/.rust-proxy/mobile-pass');
  });

  test('plain http is refused so the password never travels in the clear', () {
    expect(() => passUri('http://hermes.example.com'), throwsFormatException);
  });
}
