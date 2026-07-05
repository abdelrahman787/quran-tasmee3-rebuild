/// Complete Quran metadata and Uthmani ayah text for all 114 surahs.
///
/// Surah metadata (names, ayah counts, revelation type) is compiled in as
/// a const list. The full 6236-ayah Uthmani text is loaded at runtime from
/// `assets/quran/quran_uthmani.json` — a compact JSON file (~1.4 MB)
/// produced from the AlQuran Cloud API.
library;

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:quran_tasmee3_core/recitation/matching_engine.dart';
import 'package:quran_tasmee3_core/recitation/normalizer.dart';

/// Metadata for one surah.
class SurahMeta {
  final int number;
  final String name;
  final String englishName;
  final String englishTranslation;
  final int ayahCount;
  final String revelationType; // Meccan or Medinan

  const SurahMeta({
    required this.number,
    required this.name,
    required this.englishName,
    required this.englishTranslation,
    required this.ayahCount,
    required this.revelationType,
  });
}

/// One ayah with its Uthmani text (for display) and word breakdown.
class AyahData {
  final int surah;
  final int ayah;
  final String uthmaniText;
  final int page;

  const AyahData({
    required this.surah,
    required this.ayah,
    required this.uthmaniText,
    required this.page,
  });

  /// Split the ayah into individual words for the recitation scope.
  List<ExpectedWord> toExpectedWords() {
    final words = uthmaniText.split(' ').where((w) => w.isNotEmpty).toList();
    return List.generate(words.length, (i) {
      final normalized = normalizeForMatch(words[i]);
      return ExpectedWord(
        wordId: '$surah:$ayah:$i',
        surah: surah,
        ayah: ayah,
        wordIndex: i,
        norm: normalized,
        display: words[i],
      );
    });
  }
}

/// The 114 surah metadata entries (name, ayah count, etc.).
class QuranData {
  QuranData._();

  static const List<SurahMeta> surahs = [
    SurahMeta(number: 1, name: 'الفاتحة', englishName: 'Al-Fatihah', englishTranslation: 'The Opening', ayahCount: 7, revelationType: 'Meccan'),
    SurahMeta(number: 2, name: 'البقرة', englishName: 'Al-Baqarah', englishTranslation: 'The Cow', ayahCount: 286, revelationType: 'Medinan'),
    SurahMeta(number: 3, name: 'آل عمران', englishName: 'Aal-i-Imran', englishTranslation: 'The Family of Imran', ayahCount: 200, revelationType: 'Medinan'),
    SurahMeta(number: 4, name: 'النساء', englishName: 'An-Nisa', englishTranslation: 'The Women', ayahCount: 176, revelationType: 'Medinan'),
    SurahMeta(number: 5, name: 'المائدة', englishName: 'Al-Maidah', englishTranslation: 'The Table', ayahCount: 120, revelationType: 'Medinan'),
    SurahMeta(number: 6, name: 'الأنعام', englishName: 'Al-Anam', englishTranslation: 'The Cattle', ayahCount: 165, revelationType: 'Meccan'),
    SurahMeta(number: 7, name: 'الأعراف', englishName: 'Al-Araf', englishTranslation: 'The Heights', ayahCount: 206, revelationType: 'Meccan'),
    SurahMeta(number: 8, name: 'الأنفال', englishName: 'Al-Anfal', englishTranslation: 'The Spoils of War', ayahCount: 75, revelationType: 'Medinan'),
    SurahMeta(number: 9, name: 'التوبة', englishName: 'At-Tawbah', englishTranslation: 'The Repentance', ayahCount: 129, revelationType: 'Medinan'),
    SurahMeta(number: 10, name: 'يونس', englishName: 'Yunus', englishTranslation: 'Jonah', ayahCount: 109, revelationType: 'Meccan'),
    SurahMeta(number: 11, name: 'هود', englishName: 'Hud', englishTranslation: 'Hud', ayahCount: 123, revelationType: 'Meccan'),
    SurahMeta(number: 12, name: 'يوسف', englishName: 'Yusuf', englishTranslation: 'Joseph', ayahCount: 111, revelationType: 'Meccan'),
    SurahMeta(number: 13, name: 'الرعد', englishName: 'Ar-Rad', englishTranslation: 'The Thunder', ayahCount: 43, revelationType: 'Medinan'),
    SurahMeta(number: 14, name: 'إبراهيم', englishName: 'Ibrahim', englishTranslation: 'Abraham', ayahCount: 52, revelationType: 'Meccan'),
    SurahMeta(number: 15, name: 'الحجر', englishName: 'Al-Hijr', englishTranslation: 'The Rocky Tract', ayahCount: 99, revelationType: 'Meccan'),
    SurahMeta(number: 16, name: 'النحل', englishName: 'An-Nahl', englishTranslation: 'The Bee', ayahCount: 128, revelationType: 'Meccan'),
    SurahMeta(number: 17, name: 'الإسراء', englishName: 'Al-Isra', englishTranslation: 'The Night Journey', ayahCount: 111, revelationType: 'Meccan'),
    SurahMeta(number: 18, name: 'الكهف', englishName: 'Al-Kahf', englishTranslation: 'The Cave', ayahCount: 110, revelationType: 'Meccan'),
    SurahMeta(number: 19, name: 'مريم', englishName: 'Maryam', englishTranslation: 'Mary', ayahCount: 98, revelationType: 'Meccan'),
    SurahMeta(number: 20, name: 'طه', englishName: 'Ta-Ha', englishTranslation: 'Ta-Ha', ayahCount: 135, revelationType: 'Meccan'),
    SurahMeta(number: 21, name: 'الأنبياء', englishName: 'Al-Anbiya', englishTranslation: 'The Prophets', ayahCount: 112, revelationType: 'Meccan'),
    SurahMeta(number: 22, name: 'الحج', englishName: 'Al-Hajj', englishTranslation: 'The Pilgrimage', ayahCount: 78, revelationType: 'Medinan'),
    SurahMeta(number: 23, name: 'المؤمنون', englishName: 'Al-Muminun', englishTranslation: 'The Believers', ayahCount: 118, revelationType: 'Meccan'),
    SurahMeta(number: 24, name: 'النور', englishName: 'An-Nur', englishTranslation: 'The Light', ayahCount: 64, revelationType: 'Medinan'),
    SurahMeta(number: 25, name: 'الفرقان', englishName: 'Al-Furqan', englishTranslation: 'The Criterion', ayahCount: 77, revelationType: 'Meccan'),
    SurahMeta(number: 26, name: 'الشعراء', englishName: 'Ash-Shuara', englishTranslation: 'The Poets', ayahCount: 227, revelationType: 'Meccan'),
    SurahMeta(number: 27, name: 'النمل', englishName: 'An-Naml', englishTranslation: 'The Ant', ayahCount: 93, revelationType: 'Meccan'),
    SurahMeta(number: 28, name: 'القصص', englishName: 'Al-Qasas', englishTranslation: 'The Stories', ayahCount: 88, revelationType: 'Meccan'),
    SurahMeta(number: 29, name: 'العنكبوت', englishName: 'Al-Ankabut', englishTranslation: 'The Spider', ayahCount: 69, revelationType: 'Meccan'),
    SurahMeta(number: 30, name: 'الروم', englishName: 'Ar-Rum', englishTranslation: 'The Romans', ayahCount: 60, revelationType: 'Meccan'),
    SurahMeta(number: 31, name: 'لقمان', englishName: 'Luqman', englishTranslation: 'Luqman', ayahCount: 34, revelationType: 'Meccan'),
    SurahMeta(number: 32, name: 'السجدة', englishName: 'As-Sajdah', englishTranslation: 'The Prostration', ayahCount: 30, revelationType: 'Meccan'),
    SurahMeta(number: 33, name: 'الأحزاب', englishName: 'Al-Ahzab', englishTranslation: 'The Clans', ayahCount: 73, revelationType: 'Medinan'),
    SurahMeta(number: 34, name: 'سبأ', englishName: 'Saba', englishTranslation: 'Sheba', ayahCount: 54, revelationType: 'Meccan'),
    SurahMeta(number: 35, name: 'فاطر', englishName: 'Fatir', englishTranslation: 'The Originator', ayahCount: 45, revelationType: 'Meccan'),
    SurahMeta(number: 36, name: 'يس', englishName: 'Ya-Sin', englishTranslation: 'Ya Sin', ayahCount: 83, revelationType: 'Meccan'),
    SurahMeta(number: 37, name: 'الصافات', englishName: 'As-Saffat', englishTranslation: 'Those Ranged in Ranks', ayahCount: 182, revelationType: 'Meccan'),
    SurahMeta(number: 38, name: 'ص', englishName: 'Sad', englishTranslation: 'The Letter Sad', ayahCount: 88, revelationType: 'Meccan'),
    SurahMeta(number: 39, name: 'الزمر', englishName: 'Az-Zumar', englishTranslation: 'The Groups', ayahCount: 75, revelationType: 'Meccan'),
    SurahMeta(number: 40, name: 'غافر', englishName: 'Ghafir', englishTranslation: 'The Forgiver', ayahCount: 85, revelationType: 'Meccan'),
    SurahMeta(number: 41, name: 'فصلت', englishName: 'Fussilat', englishTranslation: 'Explained in Detail', ayahCount: 54, revelationType: 'Meccan'),
    SurahMeta(number: 42, name: 'الشورى', englishName: 'Ash-Shura', englishTranslation: 'The Consultation', ayahCount: 53, revelationType: 'Meccan'),
    SurahMeta(number: 43, name: 'الزخرف', englishName: 'Az-Zukhruf', englishTranslation: 'The Ornaments of Gold', ayahCount: 89, revelationType: 'Meccan'),
    SurahMeta(number: 44, name: 'الدخان', englishName: 'Ad-Dukhan', englishTranslation: 'The Smoke', ayahCount: 59, revelationType: 'Meccan'),
    SurahMeta(number: 45, name: 'الجاثية', englishName: 'Al-Jathiyah', englishTranslation: 'The Crouching', ayahCount: 37, revelationType: 'Meccan'),
    SurahMeta(number: 46, name: 'الأحقاف', englishName: 'Al-Ahqaf', englishTranslation: 'The Wind-Curved Sandhills', ayahCount: 35, revelationType: 'Meccan'),
    SurahMeta(number: 47, name: 'محمد', englishName: 'Muhammad', englishTranslation: 'Muhammad', ayahCount: 38, revelationType: 'Medinan'),
    SurahMeta(number: 48, name: 'الفتح', englishName: 'Al-Fath', englishTranslation: 'The Victory', ayahCount: 29, revelationType: 'Medinan'),
    SurahMeta(number: 49, name: 'الحجرات', englishName: 'Al-Hujurat', englishTranslation: 'The Rooms', ayahCount: 18, revelationType: 'Medinan'),
    SurahMeta(number: 50, name: 'ق', englishName: 'Qaf', englishTranslation: 'The Letter Qaf', ayahCount: 45, revelationType: 'Meccan'),
    SurahMeta(number: 51, name: 'الذاريات', englishName: 'Adh-Dhariyat', englishTranslation: 'The Winnowing Winds', ayahCount: 60, revelationType: 'Meccan'),
    SurahMeta(number: 52, name: 'الطور', englishName: 'At-Tur', englishTranslation: 'The Mount', ayahCount: 49, revelationType: 'Meccan'),
    SurahMeta(number: 53, name: 'النجم', englishName: 'An-Najm', englishTranslation: 'The Star', ayahCount: 62, revelationType: 'Meccan'),
    SurahMeta(number: 54, name: 'القمر', englishName: 'Al-Qamar', englishTranslation: 'The Moon', ayahCount: 55, revelationType: 'Meccan'),
    SurahMeta(number: 55, name: 'الرحمن', englishName: 'Ar-Rahman', englishTranslation: 'The Beneficent', ayahCount: 78, revelationType: 'Medinan'),
    SurahMeta(number: 56, name: 'الواقعة', englishName: 'Al-Waqiah', englishTranslation: 'The Inevitable', ayahCount: 96, revelationType: 'Meccan'),
    SurahMeta(number: 57, name: 'الحديد', englishName: 'Al-Hadid', englishTranslation: 'The Iron', ayahCount: 29, revelationType: 'Medinan'),
    SurahMeta(number: 58, name: 'المجادلة', englishName: 'Al-Mujadila', englishTranslation: 'The Pleading Woman', ayahCount: 22, revelationType: 'Medinan'),
    SurahMeta(number: 59, name: 'الحشر', englishName: 'Al-Hashr', englishTranslation: 'The Exile', ayahCount: 24, revelationType: 'Medinan'),
    SurahMeta(number: 60, name: 'الممتحنة', englishName: 'Al-Mumtahanah', englishTranslation: 'The Tested One', ayahCount: 13, revelationType: 'Medinan'),
    SurahMeta(number: 61, name: 'الصف', englishName: 'As-Saff', englishTranslation: 'The Ranks', ayahCount: 14, revelationType: 'Medinan'),
    SurahMeta(number: 62, name: 'الجمعة', englishName: 'Al-Jumuah', englishTranslation: 'The Congregation', ayahCount: 11, revelationType: 'Medinan'),
    SurahMeta(number: 63, name: 'المنافقون', englishName: 'Al-Munafiqun', englishTranslation: 'The Hypocrites', ayahCount: 11, revelationType: 'Medinan'),
    SurahMeta(number: 64, name: 'التغابن', englishName: 'At-Taghabun', englishTranslation: 'The Mutual Disillusion', ayahCount: 18, revelationType: 'Medinan'),
    SurahMeta(number: 65, name: 'الطلاق', englishName: 'At-Talaq', englishTranslation: 'The Divorce', ayahCount: 12, revelationType: 'Medinan'),
    SurahMeta(number: 66, name: 'التحريم', englishName: 'At-Tahrim', englishTranslation: 'The Prohibition', ayahCount: 12, revelationType: 'Medinan'),
    SurahMeta(number: 67, name: 'الملك', englishName: 'Al-Mulk', englishTranslation: 'The Sovereignty', ayahCount: 30, revelationType: 'Meccan'),
    SurahMeta(number: 68, name: 'القلم', englishName: 'Al-Qalam', englishTranslation: 'The Pen', ayahCount: 52, revelationType: 'Meccan'),
    SurahMeta(number: 69, name: 'الحاقة', englishName: 'Al-Haqqah', englishTranslation: 'The Reality', ayahCount: 52, revelationType: 'Meccan'),
    SurahMeta(number: 70, name: 'المعارج', englishName: 'Al-Maarij', englishTranslation: 'The Ascending Stairways', ayahCount: 44, revelationType: 'Meccan'),
    SurahMeta(number: 71, name: 'نوح', englishName: 'Nuh', englishTranslation: 'Noah', ayahCount: 28, revelationType: 'Meccan'),
    SurahMeta(number: 72, name: 'الجن', englishName: 'Al-Jinn', englishTranslation: 'The Jinn', ayahCount: 28, revelationType: 'Meccan'),
    SurahMeta(number: 73, name: 'المزمل', englishName: 'Al-Muzzammil', englishTranslation: 'The Enshrouded One', ayahCount: 20, revelationType: 'Meccan'),
    SurahMeta(number: 74, name: 'المدثر', englishName: 'Al-Muddaththir', englishTranslation: 'The Cloaked One', ayahCount: 56, revelationType: 'Meccan'),
    SurahMeta(number: 75, name: 'القيامة', englishName: 'Al-Qiyamah', englishTranslation: 'The Resurrection', ayahCount: 40, revelationType: 'Meccan'),
    SurahMeta(number: 76, name: 'الإنسان', englishName: 'Al-Insan', englishTranslation: 'Man', ayahCount: 31, revelationType: 'Medinan'),
    SurahMeta(number: 77, name: 'المرسلات', englishName: 'Al-Mursalat', englishTranslation: 'The Emissaries', ayahCount: 50, revelationType: 'Meccan'),
    SurahMeta(number: 78, name: 'النبأ', englishName: 'An-Naba', englishTranslation: 'The Tidings', ayahCount: 40, revelationType: 'Meccan'),
    SurahMeta(number: 79, name: 'النازعات', englishName: 'An-Naziat', englishTranslation: 'Those Who Drag Forth', ayahCount: 46, revelationType: 'Meccan'),
    SurahMeta(number: 80, name: 'عبس', englishName: 'Abasa', englishTranslation: 'He Frowned', ayahCount: 42, revelationType: 'Meccan'),
    SurahMeta(number: 81, name: 'التكوير', englishName: 'At-Takwir', englishTranslation: 'The Overthrowing', ayahCount: 29, revelationType: 'Meccan'),
    SurahMeta(number: 82, name: 'الانفطار', englishName: 'Al-Infitar', englishTranslation: 'The Cleaving', ayahCount: 19, revelationType: 'Meccan'),
    SurahMeta(number: 83, name: 'المطففين', englishName: 'Al-Mutaffifin', englishTranslation: 'The Defrauding', ayahCount: 36, revelationType: 'Meccan'),
    SurahMeta(number: 84, name: 'الانشقاق', englishName: 'Al-Inshiqaq', englishTranslation: 'The Sundering', ayahCount: 25, revelationType: 'Meccan'),
    SurahMeta(number: 85, name: 'البروج', englishName: 'Al-Buruj', englishTranslation: 'The Mansions of the Stars', ayahCount: 22, revelationType: 'Meccan'),
    SurahMeta(number: 86, name: 'الطارق', englishName: 'At-Tariq', englishTranslation: 'The Morning Star', ayahCount: 17, revelationType: 'Meccan'),
    SurahMeta(number: 87, name: 'الأعلى', englishName: 'Al-Ala', englishTranslation: 'The Most High', ayahCount: 19, revelationType: 'Meccan'),
    SurahMeta(number: 88, name: 'الغاشية', englishName: 'Al-Ghashiyah', englishTranslation: 'The Overwhelming', ayahCount: 26, revelationType: 'Meccan'),
    SurahMeta(number: 89, name: 'الفجر', englishName: 'Al-Fajr', englishTranslation: 'The Dawn', ayahCount: 30, revelationType: 'Meccan'),
    SurahMeta(number: 90, name: 'البلد', englishName: 'Al-Balad', englishTranslation: 'The City', ayahCount: 20, revelationType: 'Meccan'),
    SurahMeta(number: 91, name: 'الشمس', englishName: 'Ash-Shams', englishTranslation: 'The Sun', ayahCount: 15, revelationType: 'Meccan'),
    SurahMeta(number: 92, name: 'الليل', englishName: 'Al-Layl', englishTranslation: 'The Night', ayahCount: 21, revelationType: 'Meccan'),
    SurahMeta(number: 93, name: 'الضحى', englishName: 'Ad-Duha', englishTranslation: 'The Morning Hours', ayahCount: 11, revelationType: 'Meccan'),
    SurahMeta(number: 94, name: 'الشرح', englishName: 'Ash-Sharh', englishTranslation: 'The Relief', ayahCount: 8, revelationType: 'Meccan'),
    SurahMeta(number: 95, name: 'التين', englishName: 'At-Tin', englishTranslation: 'The Fig', ayahCount: 8, revelationType: 'Meccan'),
    SurahMeta(number: 96, name: 'العلق', englishName: 'Al-Alaq', englishTranslation: 'The Clot', ayahCount: 19, revelationType: 'Meccan'),
    SurahMeta(number: 97, name: 'القدر', englishName: 'Al-Qadr', englishTranslation: 'The Power', ayahCount: 5, revelationType: 'Meccan'),
    SurahMeta(number: 98, name: 'البينة', englishName: 'Al-Bayyinah', englishTranslation: 'The Clear Proof', ayahCount: 8, revelationType: 'Medinan'),
    SurahMeta(number: 99, name: 'الزلزلة', englishName: 'Az-Zalzalah', englishTranslation: 'The Earthquake', ayahCount: 8, revelationType: 'Medinan'),
    SurahMeta(number: 100, name: 'العاديات', englishName: 'Al-Adiyat', englishTranslation: 'The Courser', ayahCount: 11, revelationType: 'Meccan'),
    SurahMeta(number: 101, name: 'القارعة', englishName: 'Al-Qariah', englishTranslation: 'The Calamity', ayahCount: 11, revelationType: 'Meccan'),
    SurahMeta(number: 102, name: 'التكاثر', englishName: 'At-Takathur', englishTranslation: 'The Rivalry in World Increase', ayahCount: 8, revelationType: 'Meccan'),
    SurahMeta(number: 103, name: 'العصر', englishName: 'Al-Asr', englishTranslation: 'The Declining Day', ayahCount: 3, revelationType: 'Meccan'),
    SurahMeta(number: 104, name: 'الهمزة', englishName: 'Al-Humazah', englishTranslation: 'The Traducer', ayahCount: 9, revelationType: 'Meccan'),
    SurahMeta(number: 105, name: 'الفيل', englishName: 'Al-Fil', englishTranslation: 'The Elephant', ayahCount: 5, revelationType: 'Meccan'),
    SurahMeta(number: 106, name: 'قريش', englishName: 'Quraysh', englishTranslation: 'Quraysh', ayahCount: 4, revelationType: 'Meccan'),
    SurahMeta(number: 107, name: 'الماعون', englishName: 'Al-Maun', englishTranslation: 'The Small Kindnesses', ayahCount: 7, revelationType: 'Meccan'),
    SurahMeta(number: 108, name: 'الكوثر', englishName: 'Al-Kawthar', englishTranslation: 'The Abundance', ayahCount: 3, revelationType: 'Meccan'),
    SurahMeta(number: 109, name: 'الكافرون', englishName: 'Al-Kafirun', englishTranslation: 'The Disbelievers', ayahCount: 6, revelationType: 'Meccan'),
    SurahMeta(number: 110, name: 'النصر', englishName: 'An-Nasr', englishTranslation: 'The Divine Support', ayahCount: 3, revelationType: 'Medinan'),
    SurahMeta(number: 111, name: 'المسد', englishName: 'Al-Masad', englishTranslation: 'The Palm Fiber', ayahCount: 5, revelationType: 'Meccan'),
    SurahMeta(number: 112, name: 'الإخلاص', englishName: 'Al-Ikhlas', englishTranslation: 'The Sincerity', ayahCount: 4, revelationType: 'Meccan'),
    SurahMeta(number: 113, name: 'الفلق', englishName: 'Al-Falaq', englishTranslation: 'The Daybreak', ayahCount: 5, revelationType: 'Meccan'),
    SurahMeta(number: 114, name: 'الناس', englishName: 'An-Nas', englishTranslation: 'Mankind', ayahCount: 6, revelationType: 'Meccan'),
  ];

  /// In-memory ayah text map, populated by [load()] from the JSON asset.
  /// Keyed by `"surah:ayah"` (e.g. `"1:1"`).
  static final Map<String, AyahData> _ayahTexts = {};

  /// Whether the full Quran text has been loaded from the JSON asset.
  static bool _isLoaded = false;

  /// Load all 6236 ayahs from `assets/quran/quran_uthmani.json`.
  /// Must be called once at startup (before any screen that needs ayah text).
  /// Subsequent calls are no-ops.
  static Future<void> load() async {
    if (_isLoaded) return;
    final jsonStr = await rootBundle.loadString('assets/quran/quran_uthmani.json');
    final data = json.decode(jsonStr) as Map<String, dynamic>;
    data.forEach((surahStr, ayahsMap) {
      final surah = int.parse(surahStr);
      final ayahs = ayahsMap as Map<String, dynamic>;
      ayahs.forEach((ayahStr, fields) {
        final ayah = int.parse(ayahStr);
        final f = fields as Map<String, dynamic>;
        _ayahTexts['$surah:$ayah'] = AyahData(
          surah: surah,
          ayah: ayah,
          uthmaniText: f['t'] as String,
          page: f['p'] as int,
        );
      });
    });
    _isLoaded = true;
  }

  /// Whether the full Quran text has been loaded.
  static bool get isLoaded => _isLoaded;

  /// Get surah metadata by number.
  static SurahMeta? getSurah(int number) {
    if (number < 1 || number > surahs.length) return null;
    return surahs[number - 1];
  }

  /// Get ayah text by surah:ayah key.
  static AyahData? getAyah(int surah, int ayah) {
    return _ayahTexts['$surah:$ayah'];
  }

  /// Get all ayat for a surah.
  static List<AyahData> getAyatForSurah(int surah) {
    final meta = getSurah(surah);
    if (meta == null) return [];
    final ayat = <AyahData>[];
    for (var a = 1; a <= meta.ayahCount; a++) {
      final data = _ayahTexts['$surah:$a'];
      if (data != null) ayat.add(data);
    }
    return ayat;
  }

  /// Build the recitation scope (ExpectedWord list) for a surah range.
  static List<ExpectedWord> buildScope(int surah, {int? startAyah, int? endAyah}) {
    final meta = getSurah(surah);
    if (meta == null) return [];
    final start = startAyah ?? 1;
    final end = endAyah ?? meta.ayahCount;
    final scope = <ExpectedWord>[];
    for (var a = start; a <= end; a++) {
      final ayah = _ayahTexts['$surah:$a'];
      if (ayah != null) {
        scope.addAll(ayah.toExpectedWords());
      }
    }
    return scope;
  }
}
