/// Bangla number / money / date helpers.
const _bnDigits = ['০', '১', '২', '৩', '৪', '৫', '৬', '৭', '৮', '৯'];
const _months = [
  '', 'জানুয়ারি', 'ফেব্রুয়ারি', 'মার্চ', 'এপ্রিল', 'মে', 'জুন', 'জুলাই', 'আগস্ট', 'সেপ্টেম্বর', 'অক্টোবর', 'নভেম্বর', 'ডিসেম্বর'
];
const _weekdays = ['', 'সোমবার', 'মঙ্গলবার', 'বুধবার', 'বৃহস্পতিবার', 'শুক্রবার', 'শনিবার', 'রবিবার'];

String bn(Object? v) {
  final s = '$v';
  final b = StringBuffer();
  for (final c in s.runes) {
    if (c >= 48 && c <= 57) {
      b.write(_bnDigits[c - 48]);
    } else {
      b.writeCharCode(c);
    }
  }
  return b.toString();
}

/// Server numbers may arrive as int, double or "12.50".
double num0(Object? v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  return double.tryParse('$v') ?? 0;
}

int int0(Object? v) => num0(v).round();

String _group(String intPart) {
  // Indian/Bangladeshi grouping: 12,34,567
  if (intPart.length <= 3) return intPart;
  final last3 = intPart.substring(intPart.length - 3);
  var rest = intPart.substring(0, intPart.length - 3);
  final parts = <String>[];
  while (rest.length > 2) {
    parts.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) parts.insert(0, rest);
  return '${parts.join(',')},$last3';
}

/// 12345.5 -> "১২,৩৪৫.৫০"; whole amounts drop the decimals.
String num2(Object? v) {
  final d = num0(v);
  final neg = d < 0;
  final fixed = d.abs().toStringAsFixed(2);
  final parts = fixed.split('.');
  final dec = parts[1] == '00' ? '' : '.${parts[1]}';
  return bn('${neg ? '-' : ''}${_group(parts[0])}$dec');
}

String money(Object? v) => '৳${num2(v)}';

/// "2026-11-25" -> "২৫ নভেম্বর ২০২৬"
String dateBn(String? ymd) {
  final d = DateTime.tryParse(ymd ?? '');
  if (d == null) return ymd ?? '';
  return '${bn(d.day)} ${_months[d.month]} ${bn(d.year)}';
}

String weekdayBn(String ymd) {
  final d = DateTime.tryParse(ymd);
  return d == null ? '' : _weekdays[d.weekday];
}

String ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String todayYmd() => ymd(DateTime.now());

String addDays(String ymdStr, int days) {
  final d = DateTime.parse(ymdStr);
  return ymd(DateTime(d.year, d.month, d.day + days));
}

/// "2026-11-24 14:03:21" -> "০২:০৩ PM"
String timeBn(String? dt) {
  final d = DateTime.tryParse((dt ?? '').replaceFirst(' ', 'T'));
  if (d == null) return '';
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '${bn(h.toString().padLeft(2, '0'))}:${bn(d.minute.toString().padLeft(2, '0'))} ${d.hour >= 12 ? 'PM' : 'AM'}';
}
