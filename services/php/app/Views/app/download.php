<!DOCTYPE html>
<html lang="bn">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>হ্যাপি বাংলাদেশ — অ্যাপ ডাউনলোড</title>
    <link rel="icon" type="image/jpeg" href="<?= e(asset('images/logo.jpg')) ?>">
    <style>
        *{box-sizing:border-box}body{margin:0;min-height:100vh;display:grid;place-items:center;background:#f4f7f5;font-family:system-ui,'Noto Sans Bengali',sans-serif;color:#17231c}
        .card{width:min(92vw,420px);background:#fff;border-radius:20px;padding:32px 24px;text-align:center;box-shadow:0 10px 40px rgba(0,0,0,.08)}
        img{width:84px;height:84px;border-radius:20px;object-fit:cover}h1{font-size:22px;margin:16px 0 4px}p{color:#5b6b61;margin:6px 0}
        .btn{display:block;margin:22px 0 8px;padding:15px;border-radius:14px;background:#1f9d55;color:#fff;font-weight:700;font-size:17px;text-decoration:none}
        .note{font-size:13px;text-align:left;background:#f4f7f5;border-radius:12px;padding:12px 14px;margin-top:18px;line-height:1.7}
    </style>
</head>
<body>
<div class="card">
    <img src="<?= e(asset('images/logo.jpg')) ?>" alt="">
    <h1>হ্যাপি বাংলাদেশ অ্যাপ</h1>
    <p>SR · DSR · দোকান — একটাই অ্যাপ</p>
    <?php if ($release): ?>
        <a class="btn" href="<?= e(url('/app/download')) ?>">ডাউনলোড করুন (Android)</a>
        <p>সংস্করণ <?= e($release['version_name']) ?> · <?= e(number_format($release['apk_size'] / 1048576, 1)) ?> MB</p>
        <?php if ($release['notes']): ?><p><?= e($release['notes']) ?></p><?php endif; ?>
        <div class="note">
            ১. ডাউনলোড শেষে ফাইলটি খুলুন।<br>
            ২. "অজানা উৎস থেকে ইনস্টল" চাইলে অনুমতি দিন।<br>
            ৩. অ্যাপ খুলে আপনার ফোন নম্বর ও পাসওয়ার্ড দিয়ে লগইন করুন।
        </div>
    <?php else: ?>
        <p>অ্যাপ এখনো প্রকাশ করা হয়নি। কিছুক্ষণ পর আবার দেখুন।</p>
    <?php endif; ?>
</div>
</body>
</html>
