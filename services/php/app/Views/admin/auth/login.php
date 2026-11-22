<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <?= csrf_meta() ?>
    <title><?= e($title ?? 'Admin Sign In') ?> — <?= e(config('app.name', 'HappyBasic')) ?></title>
    <link rel="icon" type="image/jpeg" href="<?= e(asset('images/logo.jpg')) ?>">
    <link rel="stylesheet" href="<?= e(asset('admin/css/admin.css')) ?>">
</head>
<body class="auth-body">
<main class="auth-shell">
    <section class="auth-panel">
        <div class="auth-header">
            <span class="brand-mark brand-mark-lg" aria-hidden="true"><img src="<?= e(asset('images/logo.jpg')) ?>" alt="<?= e(config('app.name', 'HappyBasic')) ?>"></span>
            <div>
                <h1 class="auth-title">Admin Console</h1>
                <p class="auth-subtitle">Sign in to manage <?= e(config('app.name', 'HappyBasic')) ?> operations</p>
            </div>
        </div>

        <form
            id="adminLoginForm"
            class="auth-form"
            method="POST"
            action="<?= e(url('/admin/login')) ?>"
            data-redirect="<?= e(url('/admin/dashboard')) ?>"
            novalidate
        >
            <?= csrf_field() ?>

            <div class="form-group">
                <label for="admin_email">Email</label>
                <input
                    id="admin_email"
                    name="email"
                    type="email"
                    placeholder="admin@example.com"
                    autocomplete="username"
                    required
                >
            </div>

            <div class="form-group">
                <div class="label-row">
                    <label for="admin_password">Password</label>
                </div>
                <div class="input-with-action">
                    <input
                        id="admin_password"
                        name="password"
                        type="password"
                        placeholder="Enter your password"
                        autocomplete="current-password"
                        minlength="4"
                        required
                    >
                    <button type="button" class="input-action-btn" id="toggleAdminPassword" aria-label="Toggle password visibility">Show</button>
                </div>
            </div>

            <div class="auth-row">
                <label class="checkbox-label">
                    <input type="checkbox" name="remember" value="1">
                    <span>Keep me signed in</span>
                </label>
            </div>

            <div class="auth-error" id="adminLoginError" hidden></div>

            <button type="submit" class="btn btn-primary btn-block">Sign In to Admin</button>
        </form>

    </section>

    <p class="auth-footnote muted small">
        Protected workspace · <?= e(config('app.name', 'HappyBasic')) ?> Admin
    </p>
</main>

<script src="<?= e(asset('admin/js/admin.js')) ?>"></script>
<script src="<?= e(asset('admin/js/pages/login.js')) ?>"></script>
</body>
</html>
