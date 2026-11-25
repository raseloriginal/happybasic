(() => {
    'use strict';
    const H = window.HappyAdmin;

    H.registerPage(() => {
        const page = document.getElementById('adminAppPage');
        if (!page) return;
        const base = page.dataset.baseUrl;
        const csrf = document.querySelector('meta[name="csrf-token"]')?.content || '';

        document.getElementById('copyShareUrl')?.addEventListener('click', async () => {
            const v = document.getElementById('appShareUrl').value;
            try { await navigator.clipboard.writeText(v); H.showToast('Link copied.'); } catch { document.getElementById('appShareUrl').select(); }
        });

        document.getElementById('appUploadForm')?.addEventListener('submit', async (e) => {
            e.preventDefault();
            const btn = document.getElementById('appUploadBtn');
            try {
                await H.withButtonLoading(btn, 'Uploading…', async () => {
                    const res = await fetch(base, {
                        method: 'POST',
                        credentials: 'same-origin',
                        headers: { Accept: 'application/json', 'X-Requested-With': 'XMLHttpRequest', 'X-CSRF-TOKEN': csrf },
                        body: new FormData(e.currentTarget),
                    });
                    let data = {};
                    try { data = await res.json(); } catch { /* non-JSON */ }
                    if (res.status === 413) throw new Error('File too big for the web server (HTTP 413). Raise nginx client_max_body_size to 100m, and PHP upload_max_filesize / post_max_size.');
                    if (!res.ok || data.ok === false) throw new Error(data.message || `Upload failed (HTTP ${res.status}). Usually the server size limit: raise nginx client_max_body_size, PHP upload_max_filesize and post_max_size to 100M.`);
                    H.showToast(data.message);
                    window.location.reload();
                });
            } catch (err) {
                H.showToast(err.message);
            }
        });

        page.addEventListener('click', async (e) => {
            const st = e.target.closest('[data-release-status]');
            const del = e.target.closest('[data-release-delete]');
            try {
                if (st) {
                    await H.api('PATCH', `${base}/${st.dataset.releaseStatus}/status`, { status: st.dataset.to });
                    window.location.reload();
                } else if (del && window.confirm('Delete this build and its APK file?')) {
                    await H.api('DELETE', `${base}/${del.dataset.releaseDelete}`);
                    window.location.reload();
                }
            } catch (err) {
                H.showToast(err.message);
            }
        });
    });
})();
