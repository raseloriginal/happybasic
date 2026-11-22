<?php

declare(strict_types=1);

namespace App\Support;

/** Bangla numerals, currency, unit, date, category, reason, and status formatting. */
final class Bn
{
    private const EN = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];
    private const BN = ['০', '১', '২', '৩', '৪', '৫', '৬', '৭', '৮', '৯'];

    private const MONTHS = [
        1 => 'জানু', 2 => 'ফেব্রু', 3 => 'মার্চ', 4 => 'এপ্রিল',
        5 => 'মে', 6 => 'জুন', 7 => 'জুলাই', 8 => 'আগস্ট',
        9 => 'সেপ্টে', 10 => 'অক্টো', 11 => 'নভে', 12 => 'ডিসে',
    ];

    private const MONTHS_FULL = [
        1 => 'জানুয়ারি', 2 => 'ফেব্রুয়ারি', 3 => 'মার্চ', 4 => 'এপ্রিল',
        5 => 'মে', 6 => 'জুন', 7 => 'জুলাই', 8 => 'আগস্ট',
        9 => 'সেপ্টেম্বর', 10 => 'অক্টোবর', 11 => 'নভেম্বর', 12 => 'ডিসেম্বর',
    ];

    private const WEEKDAYS = [
        0 => 'রবিবার',
        1 => 'সোমবার',
        2 => 'মঙ্গলবার',
        3 => 'বুধবার',
        4 => 'বৃহস্পতিবার',
        5 => 'শুক্রবার',
        6 => 'শনিবার',
    ];

    private const UNITS = [
        'Carton' => 'কার্টন',
        'Case' => 'কেস',
        'Box' => 'বক্স',
        'Pack' => 'প্যাক',
        'Dozen' => 'ডজন',
        'Sack' => 'বস্তা',
        'Bag' => 'ব্যাগ',
        'Piece' => 'পিস',
        'Unit' => 'ইউনিট',
    ];

    private const STATUSES = [
        'pending' => 'অপেক্ষমান',
        'assigned' => 'নির্ধারিত',
        'dispatched' => 'রাস্তায়',
        'in_review' => 'কনফার্ম বাকি',
        'settled' => 'সেটেল্ড',
        'delivered' => 'ডেলিভার্ড',
        'due' => 'বাকি',
        'partial' => 'আংশিক',
        'cancelled' => 'বাতিল',
        'active' => 'সক্রিয়',
        'inactive' => 'নিষ্ক্রিয়',
        'lot_purchase' => 'লট ক্রয়',
        'damage_claim' => 'ড্যামেজ ক্লেইম',
        'payment' => 'পেমেন্ট',
        'adjustment' => 'সমন্বয়',
    ];

    private const EXPENSE_CATEGORIES = [
        'Fuel' => 'তেল / জ্বালানি',
        'Helper' => 'হেল্পার',
        'Food' => 'খাবার',
        'Toll & Parking' => 'টোল ও পার্কিং',
        'Van Repair' => 'ভ্যান মেরামত',
        'Mobile / Communication' => 'মোবাইল / যোগাযোগ',
        'Other' => 'অন্যান্য',
    ];

    private const CANCEL_REASONS = [
        'Shop Closed' => 'দোকান বন্ধ',
        'Owner / Decision Maker Not Available' => 'মালিক / দায়িত্বশীল ব্যক্তি নেই',
        'Insufficient Cash / Credit Issue' => 'নগদ টাকা কম / বাকি সমস্যা',
        'Old Due Not Cleared' => 'আগের বাকি পরিশোধ হয়নি',
        'Ordered by Mistake' => 'ভুল করে অর্ডার করা হয়েছিল',
        'Stock Not Needed Now' => 'এখন স্টক প্রয়োজন নেই',
        'Already Bought from Another Supplier' => 'অন্য সাপ্লায়ার থেকে কিনে ফেলেছে',
        'Price Disagreement' => 'দাম নিয়ে মতবিরোধ',
        'Wanted Different Product / Size' => 'ভিন্ন পণ্য বা সাইজ চেয়েছে',
        'Product Damaged / Expired in Van' => 'ভ্যানে পণ্য নষ্ট / মেয়াদোত্তীর্ণ',
        'Wrong Product Loaded' => 'ভুল পণ্য লোড হয়েছে',
        'Shop Not Found / Wrong Location' => 'দোকান পাওয়া যায়নি / ভুল লোকেশন',
        'Delivery Too Late' => 'ডেলিভারি বেশি দেরি হয়েছে',
        'Road / Area Not Accessible' => 'রাস্তা / এলাকায় যাওয়া যাচ্ছে না',
        'Other' => 'অন্যান্য',
    ];

    public static function digits(string|int|float $value): string
    {
        return str_replace(self::EN, self::BN, (string) $value);
    }

    public static function num(int|float $value, int $decimals = 0): string
    {
        return self::digits(number_format((float) $value, $decimals));
    }

    public static function smartNum(float $value): string
    {
        $rounded = round($value, 2);
        $decimals = fmod($rounded, 1.0) === 0.0 ? 0 : 2;

        return self::digits(number_format($rounded, $decimals));
    }

    public static function money(float $value, bool $smart = false): string
    {
        return '৳ ' . ($smart ? self::smartNum($value) : self::num($value, 2));
    }

    public static function signedMoney(float $value, bool $smart = false): string
    {
        $sign = $value >= 0 ? '+' : '−';

        return $sign . '৳ ' . ($smart ? self::smartNum(abs($value)) : self::num(abs($value), 2));
    }

    public static function unitType(string $unit): string
    {
        return self::UNITS[$unit] ?? $unit;
    }

    public static function unitPcs(int $pcs, int $qtyPerUnit, string $unitType): string
    {
        $qpu = max(1, $qtyPerUnit);
        $sign = $pcs < 0 ? '-' : '';
        $pcs = abs($pcs);

        return $sign . self::digits(intdiv($pcs, $qpu)) . ' ' . self::unitType($unitType) . ' ' . self::digits($pcs % $qpu) . ' পিস';
    }

    public static function status(?string $key): string
    {
        $k = strtolower(str_replace(' ', '_', trim((string) $key)));

        return self::STATUSES[$k] ?? (string) $key;
    }

    public static function expenseCategory(string $category): string
    {
        return self::EXPENSE_CATEGORIES[$category] ?? $category;
    }

    public static function cancelReason(string $reason): string
    {
        return self::CANCEL_REASONS[$reason] ?? $reason;
    }

    public static function date(?string $ymd): string
    {
        if ($ymd === null || trim($ymd) === '') {
            return '—';
        }
        $ts = strtotime($ymd);
        if ($ts === false) {
            return self::digits($ymd);
        }
        $d = (int) date('j', $ts);
        $m = self::MONTHS[(int) date('n', $ts)] ?? date('M', $ts);
        $y = date('Y', $ts);

        return self::digits("{$d} {$m} {$y}");
    }

    public static function fullDate(?string $ymd): string
    {
        if ($ymd === null || trim($ymd) === '') {
            return '—';
        }
        $ts = strtotime($ymd);
        if ($ts === false) {
            return self::digits($ymd);
        }
        $w = self::WEEKDAYS[(int) date('w', $ts)] ?? '';
        $d = (int) date('j', $ts);
        $m = self::MONTHS_FULL[(int) date('n', $ts)] ?? date('F', $ts);
        $y = date('Y', $ts);

        return self::digits(($w !== '' ? "{$w}, " : '') . "{$d} {$m} {$y}");
    }

    public static function monthYear(?string $ymd = null): string
    {
        $ts = $ymd ? strtotime($ymd) : time();
        if ($ts === false) {
            $ts = time();
        }
        $m = self::MONTHS_FULL[(int) date('n', $ts)] ?? date('F', $ts);
        $y = date('Y', $ts);

        return self::digits("{$m} {$y}");
    }

    public static function time(?string $datetime): string
    {
        if ($datetime === null || trim($datetime) === '') {
            return '—';
        }
        $ts = strtotime($datetime);
        if ($ts === false) {
            return self::digits($datetime);
        }

        return self::digits(date('g:i A', $ts));
    }

    public static function dateTime(?string $datetime): string
    {
        if ($datetime === null || trim($datetime) === '') {
            return '—';
        }
        $ts = strtotime($datetime);
        if ($ts === false) {
            return self::digits($datetime);
        }
        $d = (int) date('j', $ts);
        $m = self::MONTHS[(int) date('n', $ts)] ?? date('M', $ts);
        $y = date('Y', $ts);
        $t = date('g:i A', $ts);

        return self::digits("{$d} {$m} {$y}, {$t}");
    }
}
