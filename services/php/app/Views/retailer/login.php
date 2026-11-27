<!DOCTYPE html>
<html lang="bn">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, viewport-fit=cover">
    <?= csrf_meta() ?>
    <title>দোকান লগইন — Happy</title>
    <link rel="icon" type="image/jpeg" href="<?= e(asset('images/logo.jpg')) ?>">
    <meta name="theme-color" content="#1A3FD6">
    <link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Hind+Siliguri:wght@400;500;600;700&family=Inter:wght@400;600;700;800&display=swap">
    <link rel="stylesheet" href="<?= e(asset('retailer/css/retailer.css')) ?>">
</head>
<body>
<div class="shell login-shell">
    <div class="login-hero">
        <img src="<?= e(asset('images/logo.jpg')) ?>" alt="Happy" class="login-logo">
        <h1>Happy Bangladesh</h1>
        <p>দোকান প্যানেল</p>
    </div>
    <form id="loginForm" class="login-card" data-action="<?= e($action) ?>" data-home="<?= e($home) ?>" novalidate>
        <h2>সাইন ইন করুন</h2>
        <p class="muted">আপনার মোবাইল নম্বর দিয়ে প্রবেশ করুন</p>
        <label class="fg"><span>মোবাইল নম্বর</span>
            <input name="phone" type="tel" inputmode="tel" placeholder="01XXXXXXXXX" autocomplete="username"></label>
        <label class="fg"><span>পাসওয়ার্ড</span>
            <div class="pw"><input name="password" type="password" placeholder="আপনার মোবাইল নম্বরই পাসওয়ার্ড" autocomplete="current-password">
            <button type="button" id="togglePw">দেখুন</button></div></label>
        <label class="remember"><input type="checkbox" name="remember" checked> সাইন ইন অবস্থায় থাকুন</label>
        <div class="err" id="err" hidden></div>
        <button class="btn-primary" type="submit">সাইন ইন করুন</button>
    </form>
</div>
<script src="<?= e(asset('retailer/js/retailer.js')) ?>"></script>
</body>
</html>
