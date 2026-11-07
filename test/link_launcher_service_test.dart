import 'package:flutter_test/flutter_test.dart';
import 'package:lightchat/services/link_launcher_service.dart';

void main() {
  test('reconoce enlaces .onion por su host', () {
    expect(
      LinkLauncherService.isOnion(
          'http://juhanurmihxlp77nkq76byazcldy2hlmovfu2epvl5ankdibsot4csyd.onion/search?q=x'),
      isTrue,
    );
    expect(LinkLauncherService.isOnion('https://ahmia.fi'), isFalse);
    expect(LinkLauncherService.isOnion('https://example.onion.evil.com/a'),
        isFalse);
  });

  test('solo admite http y https', () {
    expect(LinkLauncherService.isWebUrl('https://example.com'), isTrue);
    expect(LinkLauncherService.isWebUrl('http://x.onion'), isTrue);
    expect(LinkLauncherService.isWebUrl('javascript:alert(1)'), isFalse);
    expect(LinkLauncherService.isWebUrl('mailto:a@b.c'), isFalse);
    expect(LinkLauncherService.isWebUrl('  '), isFalse);
  });

  test('completa el esquema cuando el modelo escribe el host a secas', () {
    expect(LinkLauncherService.normalizeUrl('www.example.com/a'),
        'https://www.example.com/a');
    expect(LinkLauncherService.normalizeUrl('example.com'),
        'https://example.com');
    expect(
      LinkLauncherService.normalizeUrl(
          'juhanurmihxlp77nkq76byazcldy2hlmovfu2epvl5ankdibsot4csyd.onion'),
      'http://juhanurmihxlp77nkq76byazcldy2hlmovfu2epvl5ankdibsot4csyd.onion',
    );
    expect(LinkLauncherService.normalizeUrl('https://example.com'),
        'https://example.com');
  });

  test('descarta lo que no es un enlace web', () {
    expect(LinkLauncherService.normalizeUrl('file:///etc/passwd'), isNull);
    expect(LinkLauncherService.normalizeUrl('javascript:alert(1)'), isNull);
    expect(LinkLauncherService.normalizeUrl('sin puntos'), isNull);
    expect(LinkLauncherService.normalizeUrl(''), isNull);
  });

  test('convierte dominios sueltos en enlaces pulsables', () {
    expect(LinkLauncherService.linkifyMarkdown('amazon.es/dp/B0'),
        '[amazon.es/dp/B0](https://amazon.es/dp/B0)');
    expect(
        LinkLauncherService.linkifyMarkdown(
            'gbkxefzhrrjh5prrbhdlbtgnrrubelyukalgct7jesqrv6b3mjtkb5yd.onion'),
        '[gbkxefzhrrjh5prrbhdlbtgnrrubelyukalgct7jesqrv6b3mjtkb5yd.onion]'
        '(http://gbkxefzhrrjh5prrbhdlbtgnrrubelyukalgct7jesqrv6b3mjtkb5yd.onion)');
    expect(LinkLauncherService.linkifyMarkdown('visita amazon.es.'),
        'visita [amazon.es](https://amazon.es).');
  });

  test('no toca código ni enlaces ya escritos', () {
    expect(LinkLauncherService.linkifyMarkdown('[A](https://amazon.es)'),
        '[A](https://amazon.es)');
    expect(LinkLauncherService.linkifyMarkdown('`amazon.es`'), '`amazon.es`');
    expect(LinkLauncherService.linkifyMarkdown('```\namazon.es\n```'),
        '```\namazon.es\n```');
    expect(LinkLauncherService.linkifyMarkdown('archivo.txt y Node.js'),
        'archivo.txt y Node.js');
  });
}
