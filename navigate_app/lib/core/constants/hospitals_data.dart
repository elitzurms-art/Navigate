/// בית חולים עם מיקום גאוגרפי
class Hospital {
  final String name;
  final String classification;
  final double lat;
  final double lng;

  const Hospital({
    required this.name,
    required this.classification,
    required this.lat,
    required this.lng,
  });

  bool get isTraumaCenter => classification.contains('על-אזורי');
}

/// רשימת בתי חולים בישראל
const List<Hospital> kIsraelHospitals = [
  Hospital(name: 'רמב"ם', classification: 'כללי - על-אזורי', lat: 32.8343, lng: 34.9896),
  Hospital(name: 'בני ציון', classification: 'כללי - אזורי', lat: 32.8211, lng: 34.9921),
  Hospital(name: 'כרמל', classification: 'כללי - אזורי', lat: 32.7904, lng: 34.9671),
  Hospital(name: 'העמק', classification: 'כללי - אזורי', lat: 32.6110, lng: 35.2936),
  Hospital(name: 'הלל יפה', classification: 'כללי - אזורי', lat: 32.4292, lng: 34.8879),
  Hospital(name: 'מאיר', classification: 'כללי - אזורי', lat: 32.1843, lng: 34.8711),
  Hospital(name: 'בלינסון (רבין)', classification: 'כללי - על-אזורי', lat: 32.0939, lng: 34.8481),
  Hospital(name: 'שניידר', classification: 'ילדים - על-אזורי', lat: 32.0935, lng: 34.8485),
  Hospital(name: 'איכילוב (סוראסקי)', classification: 'כללי - על-אזורי', lat: 32.0804, lng: 34.7893),
  Hospital(name: 'וולפסון', classification: 'כללי - אזורי', lat: 32.0444, lng: 34.7564),
  Hospital(name: 'אסף הרופא (שמיר)', classification: 'כללי - על-אזורי', lat: 31.9510, lng: 34.7933),
  Hospital(name: 'קפלן', classification: 'כללי - אזורי', lat: 31.7979, lng: 34.7890),
  Hospital(name: 'ברזילי', classification: 'כללי - אזורי', lat: 31.6263, lng: 34.5601),
  Hospital(name: 'סורוקה', classification: 'כללי - על-אזורי', lat: 31.2580, lng: 34.8004),
  Hospital(name: 'הדסה עין כרם', classification: 'כללי - על-אזורי', lat: 31.7652, lng: 35.1483),
  Hospital(name: 'הדסה הר הצופים', classification: 'כללי - אזורי', lat: 31.7949, lng: 35.2498),
  Hospital(name: 'שערי צדק', classification: 'כללי - אזורי', lat: 31.7706, lng: 35.1772),
  Hospital(name: 'זיו (רבקה זיו)', classification: 'כללי - אזורי', lat: 32.9661, lng: 35.4964),
  Hospital(name: 'פוריה', classification: 'כללי - אזורי', lat: 32.7227, lng: 35.5403),
  Hospital(name: 'נהריה (גליל מערבי)', classification: 'כללי - אזורי', lat: 33.0117, lng: 35.0951),
  Hospital(name: 'יוספטל', classification: 'כללי - אזורי', lat: 29.5569, lng: 34.9517),
  Hospital(name: 'לניאדו', classification: 'כללי - אזורי', lat: 32.1697, lng: 34.9032),
];
