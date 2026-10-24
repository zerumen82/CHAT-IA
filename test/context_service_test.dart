import 'package:flutter_test/flutter_test.dart';
import 'package:lightchat/services/context_service.dart';

void main() {
  group('detectLanguage', () {
    const cases = <String, String>{
      // Falsos positivos detectados antes: "mi" en "mission" y "ce" en
      // "difference" hacían responder en español y francés.
      'Summarize the mission statement of the company': 'english',
      'Compare the values and tell me the difference': 'english',
      'What is the best way to learn Flutter?': 'english',
      'Hello, how are you?': 'english',
      'Read the table and answer': 'english',
      'hola, ¿cómo estás?': 'español',
      'Quiero un resumen del Excel': 'español',
      'Analiza el PDF y dime los totales': 'español',
      'Necesito los datos del mes pasado': 'español',
      'Bonjour, comment ça va ?': 'français',
      'Olá, como vai você?': 'português',
      'Bitte hilf mir mit dieser Tabelle': 'deutsch',
    };

    cases.forEach((text, language) {
      test('$language <- $text', () {
        expect(ContextService.detectLanguage(text), language);
      });
    });

    test('keeps Spanish for very short or empty input', () {
      expect(ContextService.detectLanguage(''), 'español');
      expect(ContextService.detectLanguage('ok'), 'español');
      expect(ContextService.detectLanguage('si'), 'español');
    });
  });
}
