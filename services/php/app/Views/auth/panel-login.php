<?php $bn = !empty($isBn); ?>
<!DOCTYPE html>
<html lang="<?= $bn ? 'bn' : 'en' ?>">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <?= csrf_meta() ?>
    <title><?= e($panelTitle) ?> <?= $bn ? 'লগইন' : 'Sign In' ?> — <?= e(config('app.name', 'HappyBasic')) ?></title>
    <link rel="icon" type="image/jpeg" href="<?= e(asset('images/logo.jpg')) ?>">
    <style>
        :root { --bg:#f7f8fa; --surface:#fff; --border:#e4e7ec; --border-strong:#d0d5dd; --ink:#0f172a; --ink-2:#475467; --muted:#667085; --accent:#111827; --danger-bg:#fef3f2; --danger:#b42318; --danger-border:#fecdca; }
        * { box-sizing: border-box; }
        body { margin:0; min-height:100vh; display:flex; align-items:center; justify-content:center; padding:16px; background:var(--bg); color:var(--ink); font:14px/1.5 "Noto Sans Bengali","Hind Siliguri","Nirmala UI",system-ui,-apple-system,"Segoe UI",Roboto,sans-serif; }
        .auth { width:100%; max-width:380px; background:var(--surface); border:1px solid var(--border); border-radius:14px; padding:28px 24px; box-shadow:0 8px 30px rgba(15,23,42,.06); }
        .head { display:flex; gap:12px; align-items:center; margin-bottom:22px; }
        .head img { width:44px; height:44px; border-radius:10px; object-fit:cover; }
        h1 { font-size:18px; margin:0; }
        .sub { margin:2px 0 0; color:var(--muted); font-size:13px; }
        .fg { display:flex; flex-direction:column; gap:5px; margin-bottom:14px; }
        label { font-size:12.5px; font-weight:600; color:var(--ink-2); }
        .fg input { width:100%; padding:10px 12px; border:1px solid var(--border-strong); border-radius:8px; font:inherit; color:inherit; background:#fff; }
        .fg input:focus { outline:2px solid #c7d2fe; border-color:#6366f1; }
        .pw { position:relative; }
        .pw input { padding-right:56px; }
        .pw button { position:absolute; right:6px; top:50%; transform:translateY(-50%); border:0; background:none; color:var(--ink-2); font:600 12px system-ui; cursor:pointer; padding:6px; }
        .row { display:flex; align-items:center; gap:8px; margin-bottom:16px; font-weight:500; }
        .err { background:var(--danger-bg); color:var(--danger); border:1px solid var(--danger-border); border-radius:8px; padding:9px 12px; font-size:13px; margin-bottom:14px; }
        .btn { width:100%; padding:11px; border:0; border-radius:8px; background:var(--accent); color:#fff; font:600 14px inherit; cursor:pointer; }
        .btn:disabled { opacity:.6; cursor:wait; }
    </style>
</head>
<body>
<main class="auth">
    <div class="head">
        <img src="<?= e(asset('images/logo.jpg')) ?>" alt="">
        <div>
            <h1><?= e($panelTitle) ?></h1>
            <p class="sub"><?= $bn ? 'আপনার মোবাইল নম্বর দিয়ে সাইন ইন করুন' : 'Sign in with your phone number' ?></p>
        </div>
    </div>
    <form id="panelLoginForm" action="<?= e($action) ?>" data-redirect="<?= e($home) ?>" data-bn="<?= $bn ? '1' : '0' ?>" novalidate>
        <div class="fg">
            <label for="login_phone"><?= $bn ? 'মোবাইল নম্বর' : 'Phone Number' ?></label>
            <input id="login_phone" name="phone" type="tel" inputmode="tel" placeholder="01XXXXXXXXX" autocomplete="username" required>
        </div>
        <div class="fg">
            <label for="login_password"><?= $bn ? 'পাসওয়ার্ড' : 'Password' ?></label>
            <div class="pw">
                <input id="login_password" name="password" type="password" placeholder="<?= $bn ? 'আপনার পাসওয়ার্ড লিখুন' : 'Enter your password' ?>" autocomplete="current-password" required>
                <button type="button" id="togglePw"><?= $bn ? 'দেখুন' : 'Show' ?></button>
            </div>
        </div>
        <label class="row"><input type="checkbox" name="remember" value="1"> <?= $bn ? 'সাইন ইন অবস্থায় থাকুন' : 'Keep me signed in' ?></label>
        <div class="err" id="loginError" hidden></div>
        <button type="submit" class="btn"><?= $bn ? 'সাইন ইন করুন' : 'Sign In' ?></button>
    </form>
</main>
<script>
(() => {
    const form = document.getElementById('panelLoginForm');
    const pw = document.getElementById('login_password');
    const err = document.getElementById('loginError');
    const bn = form.dataset.bn === '1';
    const t = bn
        ? { show: 'দেখুন', hide: 'লুকান', req: 'মোবাইল নম্বর ও পাসওয়ার্ড লিখুন।', busy: 'সাইন ইন হচ্ছে…', submit: 'সাইন ইন করুন', expired: 'সেশন মেয়াদ শেষ। পেজ রিলোড করুন।', fail: 'সাইন ইন ব্যর্থ হয়েছে।' }
        : { show: 'Show', hide: 'Hide', req: 'Please enter your phone number and password.', busy: 'Signing in…', submit: 'Sign In', expired: 'Session expired. Please reload the page.', fail: 'Sign in failed.' };
    document.getElementById('togglePw').addEventListener('click', (e) => {
        const show = pw.type === 'password';
        pw.type = show ? 'text' : 'password';
        e.currentTarget.textContent = show ? t.hide : t.show;
    });
    form.addEventListener('submit', async (e) => {
        e.preventDefault();
        err.hidden = true;
        const phone = form.phone.value.trim();
        if (!phone || !pw.value) { err.textContent = t.req; err.hidden = false; return; }
        const btn = form.querySelector('.btn');
        btn.disabled = true; btn.textContent = t.busy;
        try {
            const res = await fetch(form.action, {
                method: 'POST', credentials: 'same-origin',
                headers: { Accept: 'application/json', 'Content-Type': 'application/json', 'X-Requested-With': 'XMLHttpRequest',
                    'X-CSRF-TOKEN': document.querySelector('meta[name="csrf-token"]')?.content || '' },
                body: JSON.stringify({ phone, password: pw.value, remember: form.remember.checked ? 1 : 0 }),
            });
            const data = await res.json().catch(() => ({}));
            if (!res.ok || data.ok === false) throw new Error(res.status === 419 ? t.expired : (data.message || t.fail));
            window.location.href = data.redirect || form.dataset.redirect;
        } catch (ex) {
            err.textContent = ex.message; err.hidden = false;
            btn.disabled = false; btn.textContent = t.submit;
        }
    });
})();
</script>
</body>
</html>
