<?php

declare(strict_types=1);

namespace App\Support;

use Core\Request;

/**
 * Validates an uploaded JPG/PNG/WebP (max 3 MB) and stores it under public/uploads/<dir>.
 * With $square set, the photo is centre-cropped to a square of that many pixels and saved as a small WebP.
 */
final class ImageUpload
{
    private const TYPES = ['image/jpeg' => 'jpg', 'image/png' => 'png', 'image/webp' => 'webp'];

    /** @return string path relative to public/, e.g. uploads/dsr/abc.jpg */
    public static function store(Request $request, string $field, string $dir, ?int $square = null): string
    {
        $file = $request->file($field);
        if ($file === null || ($file['error'] ?? UPLOAD_ERR_NO_FILE) !== UPLOAD_ERR_OK || !is_uploaded_file($file['tmp_name'])) {
            throw new HttpError('ছবি আপলোড হয়নি। আবার চেষ্টা করুন।', 422);
        }
        if ($file['size'] > 3 * 1024 * 1024) {
            throw new HttpError('ছবি ৩ MB-এর বেশি হতে পারবে না।', 422);
        }
        $ext = self::TYPES[@getimagesize($file['tmp_name'])['mime'] ?? ''] ?? null;
        if ($ext === null) {
            throw new HttpError('ছবি JPG, PNG বা WebP হতে হবে।', 422);
        }

        $abs = base_path("public/uploads/{$dir}");
        if (!is_dir($abs) && !mkdir($abs, 0775, true) && !is_dir($abs)) {
            throw new HttpError('ছবি সংরক্ষণ করা যায়নি।', 500);
        }
        // Random name per upload: a new photo is a new URL, so it can be cached for a long time.
        $base = bin2hex(random_bytes(12));
        if ($square !== null && self::resizeSquare($file['tmp_name'], "{$abs}/{$base}.webp", $square)) {
            return "uploads/{$dir}/{$base}.webp";
        }

        $name = $base . '.' . $ext;
        if (!move_uploaded_file($file['tmp_name'], "{$abs}/{$name}")) {
            throw new HttpError('ছবি সংরক্ষণ করা যায়নি।', 500);
        }

        return "uploads/{$dir}/{$name}";
    }

    private static function resizeSquare(string $src, string $dest, int $size): bool
    {
        if (!function_exists('imagecreatetruecolor') || !function_exists('imagewebp')) {
            return false;
        }
        $data = @file_get_contents($src);
        $img = $data === false ? false : @imagecreatefromstring($data);
        if ($img === false) {
            return false;
        }

        // Phone photos are often stored rotated; honour the EXIF orientation.
        $orientation = function_exists('exif_read_data') ? (int) (@exif_read_data($src)['Orientation'] ?? 1) : 1;
        $angle = [3 => 180, 6 => -90, 8 => 90][$orientation] ?? 0;
        if ($angle !== 0 && ($rotated = imagerotate($img, $angle, 0)) !== false) {
            $img = $rotated;
        }

        $w = imagesx($img);
        $h = imagesy($img);
        $side = min($w, $h);
        $out = imagecreatetruecolor($size, $size);
        imagealphablending($out, true);
        imagefill($out, 0, 0, imagecolorallocate($out, 255, 255, 255));
        imagecopyresampled($out, $img, 0, 0, intdiv($w - $side, 2), intdiv($h - $side, 2), $size, $size, $side, $side);

        return imagewebp($out, $dest, 80);
    }
}
