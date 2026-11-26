/// Bangla number / money / date helpers — the same output as the PWA (App\Support\Bn and the panels' JS).
const _bnDigits = ['০', '১', '২', '৩', '৪', '৫', '৬', '৭', '৮', '৯'];
const _monthsShort = ['', 'জানু', 'ফেব্রু', 'মার্চ', 'এপ্রিল', 'মে', 'জুন', 'জুলাই', 'আগস্ট', 'সেপ্টে', 'অক্টো', 'নভে', 'ডিসে'];
const _monthsFull = ['', 'জানুয়ারি', 'ফেব্রুয়ারি', 'মার্চ', 'এপ্রিল', 'মে', 'জুন', 'জুলাই', 'আগস্ট', 'সেপ্টেম্বর', 'অক্টোবর', 'নভেম্বর', 'ডিসেম্বর'];
const _weekdays = ['', 'সোমবার', 'মঙ্গলবার', 'বুধবার', 'বৃহস্পতিবার', 'শুক্রবার', 'শনিবার', 'রবিবার'];

const _units = {
  'Carton': 'কার্টন', 'Case': 'কেস', 'Box': 'বক্স', 'Pack': 'প্যাক', 'Dozen': 'ডজন', 'Sack': 'বস্তা', 'Bag': 'ব্যাগ', 'Piece': 'পিস', 'Unit': 'ইউনিট',
};

const _expenseCategories = {
  'Fuel': 'তেল / জ্বালানি', 'Helper': 'হেল্পার', 'Food': 'খাবার', 'Toll & Parking': 'টোল ও পার্কিং', 'Van Repair': 'ভ্যান মেরামত',
  'Mobile / Communication': 'মোবাইল / যোগাযোগ', 'Other': 'অন্যান্য',
};

const _cancelReasons = {
  'Shop Closed': 'দোকান বন্ধ',
  'Owner / Decision Maker Not Available': 'মালিক / দায়িত্বশীল ব্যক্তি নেই',
  'Insufficient Cash / Credit Issue': 'নগদ টাকা কম / বাকি সমস্যা',
  'Old Due Not Cleared': 'আগের বাকি পরিশোধ হয়নি',
  'Ordered by Mistake': 'ভুল করে অর্ডার করা হয়েছিল',
  'Stock Not Needed Now': 'এখন স্টক প্রয়োজন নেই',
  'Already Bought from Another Supplier': 'অন্য সাপ্লায়ার থেকে কিনে ফেলেছে',
  'Price Disagreement': 'দাম নিয়ে মতবিরোধ',
  'Wanted Different Product / Size': 'ভিন্ন পণ্য বা সাইজ চেয়েছে',
  'Product Damaged / Expired in Van': 'ভ্যানে পণ্য নষ্ট / মেয়াদোত্তীর্ণ',
  'Wrong Product Loaded': 'ভুল পণ্য লোড হয়েছে',
  'Shop Not Found / Wrong Location': 'দোকান পাওয়া যায়নি / ভুল লোকেশন',
  'Delivery Too Late': 'ডেলিভারি বেশি দেরি হয়েছে',
  'Road / Area Not Accessible': 'রাস্তা / এলাকায় যাওয়া যাচ্ছে না',
  'Other': 'অন্যান্য',
};

const _statuses = {
  'pending': 'অপেক্ষমান', 'assigned': 'নির্ধারিত', 'dispatched': 'রাস্তায়', 'in_review': 'কনফার্ম বাকি', 'settled': 'সেটেল্ড',
  'delivered': 'ডেলিভার্ড', 'due': 'বাকি', 'partial': 'আংশিক', 'cancelled': 'বাতিল',
};

String bn(Object? v) {
  final b = StringBuffer();
  for (final c in '$v'.runes) {
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
  // en-US grouping like PHP number_format / JS toLocaleString: 1,234,567
  final b = StringBuffer();
  for (var i = 0; i < intPart.length; i++) {
    if (i > 0 && (intPart.length - i) % 3 == 0) b.write(',');
    b.write(intPart[i]);
  }
  return b.toString();
}

/// number_format($v, $decimals) in Bangla digits.
String numFmt(Object? v, [int decimals = 0]) {
  final d = num0(v);
  final fixed = d.abs().toStringAsFixed(decimals);
  final parts = fixed.split('.');
  final sign = d < 0 && double.parse(fixed) != 0 ? '-' : '';
  return bn('$sign${_group(parts[0])}${decimals > 0 ? '.${parts[1]}' : ''}');
}

/// Whole amounts without decimals, others with two (Bn::smartNum / the JS `num`).
String num2(Object? v) {
  final r = (num0(v) * 100).round() / 100;
  return numFmt(r, r == r.roundToDouble() ? 0 : 2);
}

/// JS `toLocaleString('en-US', {maximumFractionDigits: 2})` — the retailer panel's `num`: 12.5 → ১২.৫, 12 → ১২.
String numTrim(Object? v) {
  final r = (num0(v) * 100).round() / 100;
  var t = numFmt(r, 2);
  if (t.contains('.')) t = t.replaceFirst(RegExp(r'[0০]+$'), '').replaceFirst(RegExp(r'\.$'), '');
  return t;
}

/// Retailer panel & app: "৳৩,২১০".
String money(Object? v) => '৳${numTrim(v)}';

/// SR / DSR panels: Bn::money → "৳ ১,২৩৪.০০" (smart: no decimals for whole numbers).
String bnMoney(Object? v, {bool smart = false}) => '৳ ${smart ? num2(v) : numFmt(v, 2)}';

/// Bn::signedMoney → "+৳ ২৫" / "−৳ ৩০".
String signedMoney(Object? v, {bool smart = false}) {
  final d = num0(v);
  return '${d >= 0 ? '+' : '−'}৳ ${smart ? num2(d.abs()) : numFmt(d.abs(), 2)}';
}

/// Bn::num
String bnNum(Object? v, [int decimals = 0]) => numFmt(v, decimals);

String unitBn(String? u) => _units[u] ?? (u ?? '');
String statusBnKey(String? k) => _statuses[(k ?? '').toLowerCase().replaceAll(' ', '_')] ?? (k ?? '');
String expenseCatBn(String? c) => _expenseCategories[c] ?? (c ?? '');
String cancelReasonBn(String? r) {
  if (r == null) return '';
  // "Reason (note)" keeps the note
  final i = r.indexOf(' (');
  final base = i > 0 ? r.substring(0, i) : r;
  final tail = i > 0 ? r.substring(i) : '';
  return '${_cancelReasons[base] ?? base}$tail';
}

/// Bn::unitPcs → "১ ডজন ৩ পিস"
String unitPcsBn(int pcs, int qtyPerUnit, String unit) {
  final q = qtyPerUnit < 1 ? 1 : qtyPerUnit;
  final sign = pcs < 0 ? '-' : '';
  final a = pcs.abs();
  return '$sign${bn(a ~/ q)} ${unitBn(unit)} ${bn(a % q)} পিস';
}

/// Bn::date → "২৫ নভে ২০২৬"
String dateBn(String? ymd) {
  final d = DateTime.tryParse(ymd ?? '');
  if (d == null) return (ymd == null || ymd.trim().isEmpty) ? '—' : bn(ymd);
  return bn('${d.day} ${_monthsShort[d.month]} ${d.year}');
}

/// Bn::fullDate → "বুধবার, ২৫ নভেম্বর ২০২৬"
String fullDateBn(String? ymd) {
  final d = DateTime.tryParse(ymd ?? '');
  if (d == null) return (ymd == null || ymd.trim().isEmpty) ? '—' : bn(ymd);
  return bn('${_weekdays[d.weekday]}, ${d.day} ${_monthsFull[d.month]} ${d.year}');
}

/// Retailer `dateLabel` → "২২ নভেম্বর ২০২৬"
String dateLongBn(String? ymd) {
  final d = DateTime.tryParse(ymd ?? '');
  if (d == null) return ymd ?? '';
  return bn('${d.day} ${_monthsFull[d.month]} ${d.year}');
}

String monthYearBn([String? ymd]) {
  final d = (ymd == null ? null : DateTime.tryParse(ymd)) ?? DateTime.now();
  return bn('${_monthsFull[d.month]} ${d.year}');
}

String weekdayBn(String ymd) {
  final d = DateTime.tryParse(ymd);
  return d == null ? '' : _weekdays[d.weekday];
}

String ymd(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String todayYmd() => ymd(DateTime.now());

String addDays(String ymdStr, int days) {
  final d = DateTime.parse(ymdStr);
  return ymd(DateTime(d.year, d.month, d.day + days));
}

/// Bn::time → "২:০৩ PM"
String timeBn(String? dt) {
  final d = DateTime.tryParse((dt ?? '').replaceFirst(' ', 'T'));
  if (d == null) return '—';
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return bn('$h:${d.minute.toString().padLeft(2, '0')} ${d.hour >= 12 ? 'PM' : 'AM'}');
}

/// Bn::dateTime → "২৪ নভে ২০২৬, ২:০৩ PM"
String dateTimeBn(String? dt) {
  final d = DateTime.tryParse((dt ?? '').replaceFirst(' ', 'T'));
  if (d == null) return '—';
  return '${dateBn(ymd(d))}, ${timeBn(dt)}';
}
