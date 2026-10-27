import 'package:flutter_test/flutter_test.dart';
import 'package:rustproxy_mobile_pass/pass_client.dart';
import 'package:rustproxy_mobile_pass/pass_loop.dart';

void main() {
  test('server addresses become the HTTPS check-in endpoint', () {
    expect(passUri('hermes.example.com').toString(), 'https://hermes.example.com/.rust-proxy/mobile-pass');
    expect(passUri(' https://hermes.example.com/app?x=1 ').toString(), 'https://hermes.example.com/.rust-proxy/mobile-pass');
    expect(passUri('https://h.example.com:8443').toString(), 'https://h.example.com:8443/.rust-proxy/mobile-pass');
  });

  test('plain http is refused so the password never travels in the clear', () {
    expect(() => passUri('http://hermes.example.com'), throwsFormatException);
  });

  test('check-ins happen three times per pass, within 20 s to 4 min', () {
    expect(checkEveryFor(90), const Duration(seconds: 30));
    expect(checkEveryFor(600), const Duration(seconds: 200));
    expect(checkEveryFor(30), const Duration(seconds: 20));
    expect(checkEveryFor(3600), const Duration(minutes: 4));
    expect(checkEveryFor(0), const Duration(minutes: 4));
  });
}
