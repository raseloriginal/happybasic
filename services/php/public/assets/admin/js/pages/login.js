(() => {
    'use strict';
    const H = window.HappyAdmin;

    H.registerPage(() => {
        const form = document.getElementById('adminLoginForm');
        if (!form) return;

        const pw = document.getElementById('admin_password');
        const toggle = document.getElementById('toggleAdminPassword');
        const errorEl = document.getElementById('adminLoginError');
        const showError = (msg) => {
            errorEl.textContent = msg;
            errorEl.hidden = false;
        };

        toggle?.addEventListener('click', () => {
            const hidden = pw.type === 'password';
            pw.type = hidden ? 'text' : 'password';
            toggle.textContent = hidden ? 'Hide' : 'Show';
        });

        form.addEventListener('submit', async (e) => {
            e.preventDefault();
            errorEl.hidden = true;
            const email = (document.getElementById('admin_email')?.value || '').trim();
            if (!email || !pw.value) {
                showError('Please enter your email and password.');
                return;
            }

            const submitBtn = form.querySelector('button[type="submit"]');
            H.setButtonLoading(submitBtn, true, 'Signing in…');
            try {
                const res = await H.api('POST', form.action, {
                    email,
                    password: pw.value,
                    remember: form.querySelector('[name="remember"]')?.checked ? 1 : 0,
                });
                window.location.href = res.redirect || form.dataset.redirect;
            } catch (err) {
                H.setButtonLoading(submitBtn, false);
                showError(err.message);
            }
        });
    });
})();
