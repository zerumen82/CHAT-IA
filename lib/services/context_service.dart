import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import '../models/message.dart';
import '../models/chat_message.dart';

/// Servicio para gestión de contexto conversacional
/// Simplificado para chat general (sin programación)
class ContextService {
  static const String _messagesKey = 'chat_messages';
  static const String _userLanguageKey = 'user_language';
  static const String _preferredModelKey = 'preferred_model';
  static const String _ollamaServerKey = 'ollama_server_url';
  static const int _maxContextMessages = 20;
  static const int _maxHistoryMessages = 100;

  /// Detectar idioma automáticamente - VERSIÓN MEJORADA
  /// Ahora con soporte para 8 idiomas y mejor precisión
  static String detectLanguage(String text) {
    if (text.isEmpty) return 'español';

    final lowerText = text.toLowerCase();

    // Palabras clave por idioma (expansionadas)
    final Map<String, List<String>> languageKeywords = {
      // Español - España y Latinoamérica
      'español': [
        'hola', 'buenos', 'buenas', 'días', 'tardes', 'noches',
        'gracias', 'por favor', 'ayuda', 'necesito', 'quiero', 'puedes',
        'cómo', 'qué', 'cuándo', 'dónde', 'por qué', 'quién',
        'está', 'eres', 'tengo', 'hacer', 'hace', 'hacer', 'hecho',
        'muy', 'bien', 'mal', 'grande', 'pequeño', 'nuevo', 'viejo',
        'hoy', 'ayer', 'mañana', 'ahora', 'después', 'antes',
        'si', 'no', 'pero', 'porque', 'cuando', 'donde',
        'con', 'para', 'sin', 'sobre', 'entre', 'hasta', 'desde',
        'este', 'esta', 'esto', 'estos', 'estas', 'ese', 'esa', 'eso',
        'ese', 'esa', 'eso', 'aquel', 'aquella', 'aquello',
        'mi', 'tu', 'su', 'mis', 'tus', 'sus', 'nuestro', 'nuestra',
        'yo', 'tú', 'él', 'ella', 'usted', 'nosotros', 'ellos', 'ellas',
        'tengo', 'tienes', 'tiene', 'tenemos', 'tienen',
        'estoy', 'estás', 'está', 'estamos', 'están',
        'he', 'has', 'ha', 'hemos', 'han',
        'ser', 'estar', 'tener', 'hacer', 'ir', 'ver', 'dar', 'saber',
        'puedo', 'puedes', 'puede', 'podemos', 'pueden',
        'quiero', 'quieres', 'quiere', 'queremos', 'quieren',
        'debe', 'deben', 'debería', 'deberían',
        'comenzar', 'empezar', 'terminar', 'finalizar', 'continuar',
        'hablar', 'escribir', 'leer', 'escuchar', 'mirar',
        'entender', 'comprender', 'saber', 'conocer',
        'pensar', 'creer', 'opinion', 'parecer', 'sentir',
        'trabajar', 'estudiar', 'aprender', 'enseñar',
        'casa', 'familia', 'amigo', 'tiempo', 'día', 'semana', 'mes', 'año',
        'dinero', 'trabajo', 'vida', 'mundo', 'gente', 'personas',
        'problema', 'solución', 'pregunta', 'respuesta', 'información',
        'me', 'te', 'se', 'nos', 'le', 'les', 'lo', 'la', 'los', 'las',
        'me', 'te', 'le', 'nos', 'os',
        'algo', 'alguien', 'algún', 'alguno', 'alguna', 'nada', 'nadie',
        'todo', 'todos', 'toda', 'todas', 'cada',
        'más', 'menos', 'mucho', 'poco', 'bastante', 'demasiado',
        'aquí', 'allí', 'ahí', 'ahora', 'antes', 'después', 'luego',
        'solo', 'solamente', 'solo', 'únicamente', 'también', 'tampoco',
        'tal vez', 'quizá', 'puede ser', 'probablemente', 'ciertamente',
        'ciertamente', 'definitivamente', 'exactamente', 'precisamente',
        'hola', 'adiós', 'bueno', 'vale', 'ok', 'entendido',
        'mientras', 'aunque', 'sin embargo', 'no obstante',
        'además', 'también', 'tampoco', 'ni', 'tampoco',
        'español', 'castellano', 'latinoamericano',
      ],
      // Inglés
      'english': [
        'hello', 'hi', 'hey', 'good', 'morning', 'afternoon', 'evening', 'night',
        'thanks', 'thank', 'please', 'help', 'need', 'want', 'can', 'could',
        'how', 'what', 'when', 'where', 'why', 'who', 'which',
        'is', 'are', 'was', 'were', 'be', 'been', 'being',
        'have', 'has', 'had', 'do', 'does', 'did', 'doing',
        'will', 'would', 'should', 'could', 'may', 'might', 'must',
        'i', 'you', 'he', 'she', 'it', 'we', 'they', 'me', 'him', 'her', 'us', 'them',
        'my', 'your', 'his', 'her', 'its', 'our', 'their',
        'this', 'that', 'these', 'those',
        'am', 'is', 'are', 'was', 'were', 'been', 'being',
        'have', 'has', 'had', 'having',
        'do', 'does', 'did', 'doing',
        'make', 'made', 'get', 'got', 'go', 'went', 'gone', 'come', 'came',
        'see', 'saw', 'seen', 'know', 'knew', 'known', 'think', 'thought',
        'say', 'said', 'tell', 'told', 'ask', 'asked', 'answer', 'answered',
        'work', 'working', 'study', 'study', 'learn', 'learned', 'teach', 'taught',
        'read', 'write', 'speak', 'spoke', 'talk', 'listen', 'hear',
        'understand', 'understood', 'feel', 'felt', 'believe', 'believed',
        'want', 'wish', 'hope', 'like', 'love', 'hate',
        'good', 'bad', 'big', 'small', 'new', 'old', 'young', 'great',
        'very', 'really', 'much', 'many', 'some', 'any', 'all', 'most',
        'not', 'no', 'yes', 'ok', 'okay', 'sure', 'certainly',
        'maybe', 'perhaps', 'probably', 'actually', 'basically',
        'just', 'only', 'also', 'too', 'even', 'still', 'already',
        'here', 'there', 'where', 'when', 'how', 'why',
        'time', 'day', 'week', 'month', 'year', 'today', 'yesterday', 'tomorrow',
        'life', 'world', 'people', 'person', 'thing', 'way', 'day',
        'money', 'job', 'work', 'home', 'family', 'friend',
        'problem', 'question', 'answer', 'idea', 'part', 'place', 'case',
        'week', 'year', 'point', 'fact', 'matter', 'sort', 'kind',
        'english', 'british', 'american', 'australian',
      ],
      // Portugués - Brasil y Portugal
      'português': [
        'olá', 'oi', 'bom', 'boa', 'dia', 'tarde', 'noite',
        'obrigado', 'obrigada', 'por favor', 'ajuda', 'preciso', 'quero',
        'como', 'o que', 'quando', 'onde', 'por que', 'quem', 'qual',
        'sou', 'és', 'é', 'somos', 'são', 'era', 'eram', 'ser', 'estar',
        'tenho', 'tens', 'tem', 'temos', 'têm', 'tinha', 'tinham',
        'fazer', 'fez', 'faço', 'vou', 'fui', 'foi', 'ir', 'era',
        'eu', 'tu', 'ele', 'ela', 'nós', 'vós', 'eles', 'elas',
        'me', 'te', 'se', 'nos', 'vos', 'lhe', 'lhes',
        'meu', 'teu', 'seu', 'nosso', 'vosso', 'seus', 'suas',
        'este', 'esta', 'isto', 'esses', 'essas', 'aquele', 'aquela', 'aquilo',
        'está', 'estão', 'estava', 'estavam', 'estando',
        'há', 'havia', 'ter', 'tinha', 'têm', 'tem',
        'poder', 'posso', 'podes', 'pode', 'podemos', 'podem', 'poderia',
        'querer', 'quero', 'quer', 'querem', 'queria',
        'dever', 'deve', 'devem', 'deveria', 'deveriam',
        'falar', 'dizer', 'escrever', 'ler', 'ouvir', 'ver',
        'entender', 'compreender', 'saber', 'conhecer',
        'pensar', 'acreditar', 'sentir', 'parecer',
        'trabalhar', 'estudar', 'aprender', 'ensinar',
        'casa', 'família', 'amigo', 'tempo', 'dia', 'semana', 'mês', 'ano',
        'dinheiro', 'trabalho', 'vida', 'mundo', 'gente', 'pessoa',
        'problema', 'solução', 'pergunta', 'resposta', 'informação',
        'muito', 'pouco', 'bastante', 'demais', 'mais', 'menos',
        'sim', 'não', 'talvez', 'provavelmente', 'certamente',
        'aqui', 'ali', 'lá', 'agora', 'depois', 'antes', 'então',
        'só', 'somente', 'apenas', 'também', 'tampouco',
        'português', 'brasileiro', 'português',
      ],
      // Francés
      'français': [
        'bonjour', 'bonsoir', 'bonne', 'matin', 'apres', 'nuit',
        'merci', 's\'il vous plaît', 'aide', 'besoin', 'vouloir', 'pouvoir',
        'comment', 'quoi', 'quand', 'où', 'pourquoi', 'qui', 'quel',
        'je', 'tu', 'il', 'elle', 'nous', 'vous', 'ils', 'elles',
        'me', 'te', 'se', 'nous', 'vous', 'leur', 'lui',
        'mon', 'ton', 'son', 'notre', 'votre', 'leur', 'mes', 'tes', 'ses',
        'ce', 'cet', 'cette', 'ces', 'ça', 'celui', 'celle', 'ceux', 'celles',
        'être', 'suis', 'es', 'est', 'sommes', 'êtes', 'sont', 'étais',
        'avoir', 'ai', 'as', 'a', 'avons', 'avez', 'ont', 'avais',
        'faire', 'fais', 'fait', 'faisons', 'font', 'faisait',
        'aller', 'vais', 'vas', 'va', 'allons', 'allez', 'vont',
        'voir', 'vois', 'voit', 'voyons', 'voyez', 'voient',
        'savoir', 'sais', 'sait', 'savez', 'savent', 'savais',
        'penser', 'croire', 'sentir', 'paraître',
        'parler', 'dire', 'écrire', 'lire', 'écouter',
        'comprendre', 'entendre', 'connaître',
        'travailler', 'étudier', 'apprendre', 'enseign',
        'maison', 'famille', 'ami', 'temps', 'jour', 'semaine', 'mois', 'année',
        'argent', 'travail', 'vie', 'monde', 'gens', 'personne',
        'problème', 'solution', 'question', 'réponse', 'information',
        'très', 'bien', 'mal', 'grand', 'petit', 'nouveau', 'vieux',
        'oui', 'non', 'peut-être', 'probablement', 'certainement',
        'ici', 'là', 'ailleurs', 'maintenant', 'après', 'avant',
        'seulement', 'aussi', 'encore', 'déjà',
        'français', 'française',
      ],
      // Italiano
      'italiano': [
        'ciao', 'buongiorno', 'buonasera', 'buonanotte', 'buon',
        'grazie', 'per favore', 'aiuto', 'bisogno', 'volere', 'potere',
        'come', 'cosa', 'quando', 'dove', 'perché', 'chi', 'quale',
        'io', 'tu', 'lui', 'lei', 'noi', 'voi', 'loro',
        'mi', 'ti', 'si', 'ci', 'vi', 'gli', 'le',
        'mio', 'tuo', 'suo', 'nostro', 'vostro', 'miei', 'tue', 'sue',
        'questo', 'quello', 'questa', 'quella', 'questi', 'quelle',
        'essere', 'sono', 'sei', 'è', 'siamo', 'siete', 'sono', 'ero',
        'avere', 'ho', 'hai', 'ha', 'abbiamo', 'avete', 'hanno', 'avevo',
        'fare', 'faccio', 'fai', 'fa', 'facciamo', 'fanno', 'facevo',
        'andare', 'vado', 'vai', 'va', 'andiamo', 'vanno', 'andavo',
        'vedere', 'vedo', 'vedi', 'vede', 'vediamo', 'vedono', 'vedevo',
        'sapere', 'so', 'sai', 'sa', 'sappiamo', 'sanno', 'sapevo',
        'parlare', 'dire', 'scrivere', 'leggere', 'ascoltare',
        'capire', 'comprendere', 'conoscere',
        'pensare', 'credere', 'sentire', 'parere',
        'lavorare', 'studiare', 'imparare', 'insegnare',
        'casa', 'famiglia', 'amico', 'tempo', 'giorno', 'settimana', 'mese', 'anno',
        'soldi', 'lavoro', 'vita', 'mondo', 'gente', 'persona',
        'problema', 'soluzione', 'domanda', 'risposta', 'informazione',
        'molto', 'bene', 'male', 'grande', 'piccolo', 'nuovo', 'vecchio',
        'sì', 'no', 'forse', 'probabilmente', 'certamente',
        'qui', 'là', 'ora', 'dopo', 'prima', 'allora',
        'solo', 'anche', 'ancora', 'già',
        'italiano', 'italiana',
      ],
      // Alemán
      'deutsch': [
        'hallo', 'guten', 'morgen', 'tag', 'abend', 'nacht',
        'danke', 'bitte', 'hilfe', 'brauchen', 'wollen', 'können',
        'wie', 'was', 'wann', 'warum', 'wo', 'wer', 'welcher',
        'ich', 'du', 'er', 'sie', 'es', 'wir', 'ihr', 'mich', 'dich', 'sich',
        'mein', 'dein', 'sein', 'ihr', 'unser', 'euer',
        'dieser', 'jener', 'dies', 'das', 'diese', 'jenen',
        'sein', 'bin', 'bist', 'ist', 'sind', 'seid', 'war', 'waren',
        'haben', 'habe', 'habt', 'hat', 'hatte', 'hatten',
        'machen', 'tun', 'gehen', 'kommen', 'sehen', 'wissen', 'kennen',
        'denken', 'glauben', 'fühlen', 'scheinen',
        'sprechen', 'sagen', 'schreiben', 'lesen', 'hören',
        'verstehen', 'begreifen', 'kennen',
        'arbeiten', 'studieren', 'lernen', 'lehren',
        'haus', 'familie', 'freund', 'zeit', 'tag', 'woche', 'monat', 'jahr',
        'geld', 'arbeit', 'leben', 'welt', 'leute', 'mensch',
        'problem', 'lösung', 'frage', 'antwort', 'information',
        'sehr', 'gut', 'schlecht', 'groß', 'klein', 'neu', 'alt',
        'ja', 'nein', 'vielleicht', 'wahrscheinlich', 'sicher',
        'hier', 'dort', 'jetzt', 'nach', 'vor', 'dann',
        'nur', 'auch', 'noch', 'schon',
        'deutsch', 'deutsche',
      ],
      // Catalán
      'català': [
        'hola', 'bon dia', 'bon vespre', 'bona nit',
        'gràcies', 'si us plau', 'ajuda', 'necessito', 'vull', 'pots',
        'com', 'què', 'quan', 'on', 'per què', 'qui', 'qual',
        'estic', 'estàs', 'està', 'estem', 'esteu', 'estan', 'estava',
        'tinc', 'tens', 'té', 'tenim', 'teniu', 'tenen', 'tenia',
        'fer', 'faig', 'fas', 'fem', 'feu', 'fan', 'feia',
        'anar', 'vaig', 'vas', 'vam', 'vau', 'van',
        'veure', 'veig', 'veiem', 'veuen', 'veia',
        'saber', 'sé', 'sabem', 'saben', 'sabia',
        'parlar', 'dir', 'escriure', 'llegir', 'escoltar',
        'entendre', 'comprendre', 'conèixer',
        'pensar', 'creure', 'sentir', 'parèixer',
        'treballar', 'estudiar', 'aprendre', 'ensenyar',
        'casa', 'família', 'amic', 'temps', 'dia', 'setmana', 'mes', 'any',
        'diners', 'feina', 'vida', 'món', 'gent', 'persona',
        'problema', 'solució', 'pregunta', 'resposta', 'informació',
        'molt', 'bé', 'mal', 'gran', 'petit', 'nou', 'vell',
        'sí', 'no', 'potser', 'probablement', 'certament',
        'aquí', 'allà', 'ara', 'després', 'abans', 'llavors',
        'només', 'també', 'encara', 'ja',
        'català', 'catalana',
      ],
      // Gallego
      'galego': [
        'ola', 'bos días', 'boa tarde', 'boa noite',
        'grazas', 'por favor', 'axuda', 'necesito', 'quiero', 'podes',
        'como', 'que', 'cando', 'onde', 'por que', 'quen', 'cal',
        'son', 'es', 'somos', 'sodes', 'son', 'era',
        'teño', 'tens', 'ten', 'temos', 'tedes', 'teñen', 'tiña',
        'facer', 'fago', 'fas', 'facemos', 'facedes', 'fan', 'facía',
        'ir', 'vou', 'vas', 'imos', 'ides', 'van',
        'ver', 'vexo', 'vemos', 'ven', 'vía',
        'saber', 'sei', 'sabemos', 'saben', 'sabía',
        'falar', 'dic', 'escribir', 'ler', 'escutar',
        'entender', 'comprender', 'coñecer',
        'pensar', 'crer', 'sentir', 'parecer',
        'traballar', 'estudar', 'aprender', 'ensinar',
        'casa', 'familia', 'amigo', 'tempo', 'día', 'semana', 'mes', 'ano',
        'diñeiro', 'traballo', 'vida', 'mundo', 'xente', 'persoa',
        'problema', 'solución', 'pregunta', 'resposta', 'información',
        'moito', 'ben', 'mal', 'grande', 'pequeno', 'novo', 'velho',
        'si', 'non', 'quizais', 'probablemente', 'certamente',
        'aquí', 'alí', 'agora', 'despois', 'antes', 'entón',
        'só', 'tamén', 'aínda', 'xa',
        'galego', 'galega',
      ],
    };

    // Contar coincidencias por idioma
    Map<String, int> languageScores = {};
    
    for (var entry in languageKeywords.entries) {
      int score = 0;
      for (var word in entry.value) {
        if (lowerText.contains(word)) {
          score++;
          // Bonus por palabras más largas (más específicas)
          if (word.length > 4) score += 1;
          if (word.length > 8) score += 2;
        }
      }
      languageScores[entry.key] = score;
    }

    // Encontrar el idioma con mayor puntuación
    String detectedLanguage = 'español'; // Por defecto
    int maxScore = 0;
    
    for (var entry in languageScores.entries) {
      if (entry.value > maxScore) {
        maxScore = entry.value;
        detectedLanguage = entry.key;
      }
    }

    // Si no hay coincidencias claras, devolver español
    if (maxScore < 2) {
      return 'español';
    }

    return detectedLanguage;
  }

  /// Generar contexto inteligente para chat general
  static String generateContext(List<Message> messages, String userLanguage) {
    if (messages.isEmpty) return '';

    final recentMessages = messages.length > _maxContextMessages
        ? messages.sublist(messages.length - _maxContextMessages)
        : messages;

    final contextMessages =
        recentMessages.where((msg) => !msg.isError).toList();

    if (contextMessages.isEmpty) return '';

    String context = 'CONTEXTO DE LA CONVERSACIÓN ANTERIOR:\n\n';

    for (final msg in contextMessages) {
      context += '${msg.isUser ? "Usuario" : "Asistente"}: ${msg.text}\n\n';
    }

    context += 'INSTRUCCIONES IMPORTANTES:\n';
    context += '- Responde SIEMPRE en $userLanguage\n';
    context += '- Mantén la coherencia con el contexto anterior\n';
    context +=
        '- Si el usuario cambia de tema, adapta tu respuesta apropiadamente\n';
    context += '- Responde de manera natural y conversacional\n';
    context += '- Sé amigable y útil en cada respuesta\n\n';

    return context;
  }

  /// Generar contexto para ChatMessage (multimodal)
  static String generateContextFromChatMessages(
      List<ChatMessage> messages, String userLanguage) {
    if (messages.isEmpty) return '';

    final recentMessages = messages.length > _maxContextMessages
        ? messages.sublist(messages.length - _maxContextMessages)
        : messages;

    String context = 'CONTEXTO DE LA CONVERSACIÓN ANTERIOR:\n\n';

    for (final msg in recentMessages) {
      context += '${msg.isUser ? "Usuario" : "Asistente"}: ${msg.text}\n\n';
    }

    context += 'INSTRUCCIONES IMPORTANTES:\n';
    context += '- Responde SIEMPRE en $userLanguage\n';
    context += '- Mantén la coherencia con el contexto anterior\n';
    context += '- Responde de manera natural y conversacional\n\n';

    return context;
  }

  /// Seleccionar modelo automáticamente basado en el contenido
  /// Prioriza modelos uncensored
  static String selectOptimalModel(
      String text, List<String> availableModels, String userLanguage) {
    if (availableModels.isEmpty) return '';

    final lowerText = text.toLowerCase();

    // Detectar tipo de consulta
    bool isCreativeRequest = lowerText.contains('escribir') ||
        lowerText.contains('crear') ||
        lowerText.contains('historia') ||
        lowerText.contains('poema') ||
        lowerText.contains('cuento') ||
        lowerText.contains('write') ||
        lowerText.contains('create') ||
        lowerText.contains('story');

    bool isTechnicalRequest = lowerText.contains('técnico') ||
        lowerText.contains('algoritmo') ||
        lowerText.contains('matemática') ||
        lowerText.contains('ciencia') ||
        lowerText.contains('technical') ||
        lowerText.contains('math');

    bool isImageRequest = lowerText.contains('imagen') ||
        lowerText.contains('foto') ||
        lowerText.contains('ver') ||
        lowerText.contains('image') ||
        lowerText.contains('photo') ||
        lowerText.contains('picture');

    // Si hay solicitud de imagen, buscar modelo multimodal
    if (isImageRequest) {
      for (final model in availableModels) {
        final lowerModel = model.toLowerCase();
        if (lowerModel.contains('vision') ||
            lowerModel.contains('vl') ||
            lowerModel.contains('pixtral')) {
          return model;
        }
      }
    }

    // Priorizar modelos uncensored (Dolphin, Nous-Hermes, WizardLM)
    final uncensoredModels = [
      'dolphin',
      'openhermes',
      'nous-hermes',
      'wizardlm',
      'wizard',
      'uncensored',
    ];

    // Buscar modelo uncensored
    for (final uncensored in uncensoredModels) {
      for (final model in availableModels) {
        if (model.toLowerCase().contains(uncensored)) {
          // Para solicitudes creativas, preferir modelos más creativos
          if (isCreativeRequest && model.toLowerCase().contains('mistral')) {
            return model;
          }
          return model;
        }
      }
    }

    // Para solicitudes técnicas, preferir modelos más grandes
    if (isTechnicalRequest) {
      for (final model in availableModels) {
        final lowerModel = model.toLowerCase();
        if (lowerModel.contains('70b') ||
            lowerModel.contains('mixtral') ||
            lowerModel.contains('llama3')) {
          return model;
        }
      }
    }

    // Preferir modelos en español si están disponibles
    for (final model in availableModels) {
      if (userLanguage == 'español' &&
          model.toLowerCase().contains('spanish')) {
        return model;
      }
    }

    // Por defecto, usar el primer modelo disponible
    return availableModels.first;
  }

  /// Guardar mensajes en almacenamiento local
  static Future<void> saveMessages(List<Message> messages) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final messagesJson = messages.map((msg) => msg.toJson()).toList();
      await prefs.setString(_messagesKey, json.encode(messagesJson));
    } catch (e) {
      debugPrint('Error guardando mensajes: $e');
    }
  }

  /// Cargar mensajes desde almacenamiento local
  static Future<List<Message>> loadMessages() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final messagesString = prefs.getString(_messagesKey);

      if (messagesString != null) {
        final List<dynamic> messagesJson = json.decode(messagesString);
        return messagesJson.map((json) => Message.fromJson(json)).toList();
      }
    } catch (e) {
      debugPrint('Error cargando mensajes: $e');
    }

    return [];
  }

  /// Guardar ChatMessages (multimodal)
  static Future<void> saveChatMessages(List<ChatMessage> messages) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final messagesJson = messages.map((msg) => msg.toJson()).toList();
      await prefs.setString(_messagesKey, json.encode(messagesJson));
    } catch (e) {
      debugPrint('Error guardando chat messages: $e');
    }
  }

  /// Cargar ChatMessages (multimodal)
  static Future<List<ChatMessage>> loadChatMessages() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final messagesString = prefs.getString(_messagesKey);

      if (messagesString != null) {
        final List<dynamic> messagesJson = json.decode(messagesString);
        return messagesJson.map((json) => ChatMessage.fromJson(json)).toList();
      }
    } catch (e) {
      debugPrint('Error cargando chat messages: $e');
    }

    return [];
  }

  /// Guardar idioma preferido del usuario
  static Future<void> saveUserLanguage(String language) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_userLanguageKey, language);
    } catch (e) {
      debugPrint('Error guardando idioma: $e');
    }
  }

  /// Cargar idioma preferido del usuario
  static Future<String> loadUserLanguage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_userLanguageKey) ?? 'español';
    } catch (e) {
      debugPrint('Error cargando idioma: $e');
      return 'español';
    }
  }

  /// Guardar modelo preferido
  static Future<void> savePreferredModel(String model) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_preferredModelKey, model);
    } catch (e) {
      debugPrint('Error guardando modelo: $e');
    }
  }

  /// Cargar modelo preferido
  static Future<String> loadPreferredModel() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_preferredModelKey) ?? '';
    } catch (e) {
      debugPrint('Error cargando modelo: $e');
      return '';
    }
  }

  /// Guardar URL del servidor Ollama
  static Future<void> saveOllamaServerUrl(String url) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_ollamaServerKey, url);
    } catch (e) {
      debugPrint('Error guardando URL del servidor: $e');
    }
  }

  /// Cargar URL del servidor Ollama
  static Future<String> loadOllamaServerUrl() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_ollamaServerKey) ?? 'http://localhost:11434';
    } catch (e) {
      debugPrint('Error cargando URL del servidor: $e');
      return 'http://localhost:11434';
    }
  }

  /// Limpiar historial antiguo
  static List<Message> cleanOldHistory(List<Message> messages) {
    if (messages.length <= _maxHistoryMessages) return messages;

    const keepCount = _maxHistoryMessages ~/ 2;
    final recentMessages = messages.sublist(messages.length - keepCount);
    final olderMessages = messages.sublist(0, messages.length - keepCount);

    // Mantener mensajes importantes (no errores) de la parte antigua
    final importantOlderMessages = olderMessages
        .where((msg) => !msg.isError && msg.text.length > 20)
        .take(keepCount)
        .toList();

    return [...importantOlderMessages, ...recentMessages];
  }

  /// Limpiar historial antiguo de ChatMessages
  static List<ChatMessage> cleanOldChatHistory(List<ChatMessage> messages) {
    if (messages.length <= _maxHistoryMessages) return messages;

    const keepCount = _maxHistoryMessages ~/ 2;
    final recentMessages = messages.sublist(messages.length - keepCount);
    final olderMessages = messages.sublist(0, messages.length - keepCount);

    // Mantener mensajes importantes de la parte antigua
    final importantOlderMessages = olderMessages
        .where((msg) => !msg.isError && msg.text.length > 20)
        .take(keepCount)
        .toList();

    return [...importantOlderMessages, ...recentMessages];
  }

  /// Generar resumen del contexto para modelos con limitaciones
  static String generateContextSummary(List<Message> messages) {
    if (messages.length <= 5) return '';

    final userMessages = messages.where((msg) => msg.isUser).toList();
    String summary = 'RESUMEN DEL CONTEXTO:\n';
    summary += '- Total de intercambios: ${userMessages.length}\n';
    summary += '- Últimos temas discutidos: ';

    if (userMessages.isNotEmpty) {
      final lastTopics = userMessages.length > 3
          ? userMessages.sublist(userMessages.length - 3)
          : userMessages;
      final topicsText = lastTopics
          .map((msg) => msg.text.length > 50
              ? '${msg.text.substring(0, 50)}...'
              : msg.text)
          .join(', ');
      summary += topicsText;
    }

    summary +=
        '\n- El usuario prefiere respuestas en: ${detectLanguage(messages.isNotEmpty ? messages.last.text : '')}\n';

    return summary;
  }

  /// Limpiar todos los datos almacenados
  static Future<void> clearAllData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_messagesKey);
      await prefs.remove(_userLanguageKey);
      await prefs.remove(_preferredModelKey);
      // No eliminar la URL del servidor
    } catch (e) {
      debugPrint('Error limpiando datos: $e');
    }
  }
}
