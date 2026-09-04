import 'dart:io' show Platform;

/// Vacío = sigue el idioma del sistema operativo.
const kIdiomaSistema = '';

/// Locales `ll_CC` que acepta la API de Spotify (ISO 639-1 + ISO 3166-1).
class IdiomaSpotify {
  const IdiomaSpotify(this.codigo, this.nombre);

  final String codigo;
  final String nombre;
}

const idiomasSpotify = <IdiomaSpotify>[
  IdiomaSpotify('af', 'Afrikáans'),
  IdiomaSpotify('ar_EG', 'Árabe (Egipto)'),
  IdiomaSpotify('ar_MA', 'Árabe (Marruecos)'),
  IdiomaSpotify('ar_SA', 'Árabe (Arabia Saudita)'),
  IdiomaSpotify('bn_BD', 'Bengalí (Bangladés)'),
  IdiomaSpotify('bg_BG', 'Búlgaro'),
  IdiomaSpotify('ca_ES', 'Catalán'),
  IdiomaSpotify('cs_CZ', 'Checo'),
  IdiomaSpotify('da_DK', 'Danés'),
  IdiomaSpotify('de_AT', 'Alemán (Austria)'),
  IdiomaSpotify('de_CH', 'Alemán (Suiza)'),
  IdiomaSpotify('de_DE', 'Alemán (Alemania)'),
  IdiomaSpotify('el_GR', 'Griego'),
  IdiomaSpotify('en_AU', 'Inglés (Australia)'),
  IdiomaSpotify('en_CA', 'Inglés (Canadá)'),
  IdiomaSpotify('en_GB', 'Inglés (Reino Unido)'),
  IdiomaSpotify('en_IE', 'Inglés (Irlanda)'),
  IdiomaSpotify('en_IN', 'Inglés (India)'),
  IdiomaSpotify('en_NZ', 'Inglés (Nueva Zelanda)'),
  IdiomaSpotify('en_US', 'Inglés (Estados Unidos)'),
  IdiomaSpotify('en_ZA', 'Inglés (Sudáfrica)'),
  IdiomaSpotify('es_AR', 'Español (Argentina)'),
  IdiomaSpotify('es_CL', 'Español (Chile)'),
  IdiomaSpotify('es_CO', 'Español (Colombia)'),
  IdiomaSpotify('es_ES', 'Español (España)'),
  IdiomaSpotify('es_MX', 'Español (México)'),
  IdiomaSpotify('es_US', 'Español (Estados Unidos)'),
  IdiomaSpotify('et_EE', 'Estonio'),
  IdiomaSpotify('eu_ES', 'Euskera'),
  IdiomaSpotify('fa_IR', 'Persa'),
  IdiomaSpotify('fi_FI', 'Finés'),
  IdiomaSpotify('fil_PH', 'Filipino'),
  IdiomaSpotify('fr_BE', 'Francés (Bélgica)'),
  IdiomaSpotify('fr_CA', 'Francés (Canadá)'),
  IdiomaSpotify('fr_CH', 'Francés (Suiza)'),
  IdiomaSpotify('fr_FR', 'Francés (Francia)'),
  IdiomaSpotify('gl_ES', 'Gallego'),
  IdiomaSpotify('gu_IN', 'Gujarati'),
  IdiomaSpotify('he_IL', 'Hebreo'),
  IdiomaSpotify('hi_IN', 'Hindi'),
  IdiomaSpotify('hr_HR', 'Croata'),
  IdiomaSpotify('hu_HU', 'Húngaro'),
  IdiomaSpotify('id_ID', 'Indonesio'),
  IdiomaSpotify('is_IS', 'Islandés'),
  IdiomaSpotify('it_CH', 'Italiano (Suiza)'),
  IdiomaSpotify('it_IT', 'Italiano (Italia)'),
  IdiomaSpotify('ja_JP', 'Japonés'),
  IdiomaSpotify('kn_IN', 'Canarés'),
  IdiomaSpotify('ko_KR', 'Coreano'),
  IdiomaSpotify('lt_LT', 'Lituano'),
  IdiomaSpotify('lv_LV', 'Letón'),
  IdiomaSpotify('mk_MK', 'Macedonio'),
  IdiomaSpotify('ml_IN', 'Malayalam'),
  IdiomaSpotify('mr_IN', 'Marathi'),
  IdiomaSpotify('ms_MY', 'Malayo'),
  IdiomaSpotify('nb_NO', 'Noruego Bokmål'),
  IdiomaSpotify('nl_BE', 'Neerlandés (Bélgica)'),
  IdiomaSpotify('nl_NL', 'Neerlandés (Países Bajos)'),
  IdiomaSpotify('no_NO', 'Noruego'),
  IdiomaSpotify('pa_IN', 'Punyabí'),
  IdiomaSpotify('pl_PL', 'Polaco'),
  IdiomaSpotify('pt_BR', 'Portugués (Brasil)'),
  IdiomaSpotify('pt_PT', 'Portugués (Portugal)'),
  IdiomaSpotify('ro_RO', 'Rumano'),
  IdiomaSpotify('ru_RU', 'Ruso'),
  IdiomaSpotify('sk_SK', 'Eslovaco'),
  IdiomaSpotify('sl_SI', 'Esloveno'),
  IdiomaSpotify('sr_RS', 'Serbio'),
  IdiomaSpotify('sv_SE', 'Sueco'),
  IdiomaSpotify('sw_KE', 'Suajili'),
  IdiomaSpotify('ta_IN', 'Tamil'),
  IdiomaSpotify('te_IN', 'Telugu'),
  IdiomaSpotify('th_TH', 'Tailandés'),
  IdiomaSpotify('tr_TR', 'Turco'),
  IdiomaSpotify('uk_UA', 'Ucraniano'),
  IdiomaSpotify('ur_PK', 'Urdu'),
  IdiomaSpotify('vi_VN', 'Vietnamita'),
  IdiomaSpotify('zh_CN', 'Chino (simplificado)'),
  IdiomaSpotify('zh_HK', 'Chino (Hong Kong)'),
  IdiomaSpotify('zh_TW', 'Chino (tradicional)'),
];

final _codigosSpotify = {for (final i in idiomasSpotify) i.codigo};

/// Código ISO 639-1 a partir de un locale (`es_ES` → `es`).
String codigoIdiomaDeLocale(String locale) {
  final l = locale.trim();
  if (l.isEmpty) return 'en';
  final corte = l.indexOf('_');
  final codigo = (corte > 0 ? l.substring(0, corte) : l).toLowerCase();
  return codigo.length >= 2 ? codigo.substring(0, 2) : 'en';
}

String codigoIdiomaDelSistema({String? locale}) {
  final l = (locale ?? Platform.localeName).trim();
  if (l.isEmpty) return 'en';
  final corte = l.indexOf(RegExp(r'[_\-.]'));
  final codigo = (corte > 0 ? l.substring(0, corte) : l).toLowerCase();
  return codigo.length >= 2 ? codigo.substring(0, 2) : 'en';
}

String localeSpotifyDesdePc() {
  final raw = Platform.localeName.replaceAll('-', '_');
  if (_codigosSpotify.contains(raw)) return raw;
  final lang = codigoIdiomaDelSistema();
  for (final i in idiomasSpotify) {
    if (i.codigo.startsWith('${lang}_')) return i.codigo;
  }
  if (_codigosSpotify.contains(lang)) return lang;
  return 'en_US';
}

String localeSpotifyEfectivo(String preferido) {
  if (preferido.isEmpty) return localeSpotifyDesdePc();
  if (_codigosSpotify.contains(preferido)) return preferido;
  return localeSpotifyDesdePc();
}

String paisDeLocale(String locale) {
  final i = locale.indexOf('_');
  if (i <= 0 || i >= locale.length - 1) return '';
  return locale.substring(i + 1).toUpperCase();
}

String localeParaAcceptLanguage(String locale) =>
    locale.replaceAll('_', '-');

IdiomaSpotify? idiomaPorCodigo(String codigo) {
  for (final i in idiomasSpotify) {
    if (i.codigo == codigo) return i;
  }
  return null;
}

String nombreIdiomaPreferido(String preferido) {
  if (preferido.isEmpty) {
    final efectivo = localeSpotifyEfectivo('');
    final auto = idiomaPorCodigo(efectivo);
    return 'Automático (${auto?.nombre ?? efectivo})';
  }
  return idiomaPorCodigo(preferido)?.nombre ?? preferido;
}

List<IdiomaSpotify> idiomasFiltrados(String consulta) {
  final q = consulta.trim().toLowerCase();
  if (q.isEmpty) return idiomasSpotify;
  return [
    for (final i in idiomasSpotify)
      if (i.nombre.toLowerCase().contains(q) ||
          i.codigo.toLowerCase().contains(q))
        i,
  ];
}

/// "Top 50 Global": la editorial de referencia cuando el país del usuario
/// no tiene una propia (o la suya falla).
const kTop50Global = '37i9dQZEVXbMDoHDwVN2tF';

/// Playlists editoriales "Top 50" por país (ISO 3166-1 → id de Spotify).
///
/// Ojo: son playlists editoriales y la Web API en modo desarrollo las
/// niega con 404; solo se pueden leer a través del metadata-sidecar
/// (librespot), que es como las lee el cliente oficial. Los ids son los
/// históricos de Spotify, que llevan años estables; si uno dejara de
/// existir, [playlistTop50ParaLocale] cae a [kTop50Global].
const kTop50PorPais = <String, String>{
  'AR': '37i9dQZEVXbMMy2roB9myp',
  'AT': '37i9dQZEVXbKNHh6NIXu36',
  'AU': '37i9dQZEVXbJPcfkRz0wJ0',
  'BE': '37i9dQZEVXbJNSeeHswcKB',
  'BO': '37i9dQZEVXbJqfMFK4d691',
  'BR': '37i9dQZEVXbMXbN3EUUhlg',
  'CA': '37i9dQZEVXbKj23U1GF4IR',
  'CH': '37i9dQZEVXbJiyhoAPEfMK',
  'CL': '37i9dQZEVXbL0GavIqMTeb',
  'CO': '37i9dQZEVXbOa2lmxNORXQ',
  'CR': '37i9dQZEVXbMZAjGMynsQX',
  'CZ': '37i9dQZEVXbIP3c3fqVrJY',
  'DE': '37i9dQZEVXbJiZcmkrIHGU',
  'DK': '37i9dQZEVXbL3J0k32lWnN',
  'DO': '37i9dQZEVXbKAbrM8g3ygg',
  'EC': '37i9dQZEVXbJlM6nvL1nD1',
  'ES': '37i9dQZEVXbNFJfN1Vw8d9',
  'FI': '37i9dQZEVXbMxcczTSoGwZ',
  'FR': '37i9dQZEVXbIPWwFssbupI',
  'GB': '37i9dQZEVXbLnolsZ8PSNw',
  'GR': '37i9dQZEVXbJqdarpmTJDL',
  'GT': '37i9dQZEVXbLy5tBFyQvd4',
  'HK': '37i9dQZEVXbLwpL8TjsxGG',
  'HN': '37i9dQZEVXbJp9wcIM9Eo5',
  'HU': '37i9dQZEVXbNHwMxAkvmF8',
  'ID': '37i9dQZEVXbObFQZ3JLcXt',
  'IE': '37i9dQZEVXbKM896FDX8L1',
  'IL': '37i9dQZEVXbJ6IpvItkve3',
  'IN': '37i9dQZEVXbLZ52XmnySJg',
  'IS': '37i9dQZEVXbKMzVsSGQ49S',
  'IT': '37i9dQZEVXbIQnj7RRhdSX',
  'JP': '37i9dQZEVXbKXQ4mDTEBXq',
  'KR': '37i9dQZEVXbNxXF4SkHj9F',
  'LT': '37i9dQZEVXbMx56Rdq5lwc',
  'LU': '37i9dQZEVXbKGcyg6TFGx6',
  'LV': '37i9dQZEVXbJWuzDrTxbKS',
  'MA': '37i9dQZEVXbJU9eQpX8gPT',
  'MX': '37i9dQZEVXbO3OYFal6FJd',
  'MY': '37i9dQZEVXbJlfUljuZExa',
  'NI': '37i9dQZEVXbISk8kxnzfCq',
  'NL': '37i9dQZEVXbKCF6dqVpDkS',
  'NO': '37i9dQZEVXbJvfa0Yxg7E7',
  'NZ': '37i9dQZEVXbM8SIrkCiyPal',
  'PA': '37i9dQZEVXbKypXHVwk1f0',
  'PE': '37i9dQZEVXbJfdy5b0KP7W',
  'PH': '37i9dQZEVXbNBz9cRCSFkY',
  'PL': '37i9dQZEVXbN6itCcaLqTt',
  'PT': '37i9dQZEVXbKyJS56d1pgi',
  'PY': '37i9dQZEVXbNOUPGj7tW6T',
  'RO': '37i9dQZEVXbNZbJ6TZELC8',
  'SE': '37i9dQZEVXbLoATJ81JYXz',
  'SG': '37i9dQZEVXbK4gjvS1FjPY',
  'SK': '37i9dQZEVXbKIVTPX9a2Sb',
  'SV': '37i9dQZEVXbLrQBcXqUtaC',
  'TH': '37i9dQZEVXbMnz8KIWSVf9',
  'TR': '37i9dQZEVXbIVYVBNw9D5K',
  'TW': '37i9dQZEVXbMnZEatlMSiu',
  'UA': '37i9dQZEVXbKkidEfWYRuD',
  'US': '37i9dQZEVXbLRQDuF5jeBp',
  'UY': '37i9dQZEVXbMJJi3wgRbAy',
  'VN': '37i9dQZEVXbLdGSmz6xilI',
  'ZA': '37i9dQZEVXbMH2jvi6jvjk',
};

/// El "Top 50" que toca según el idioma de la app (`es_ES` → España).
/// Sin país conocido, el global.
String playlistTop50ParaLocale(String locale) =>
    kTop50PorPais[paisDeLocale(locale)] ?? kTop50Global;
