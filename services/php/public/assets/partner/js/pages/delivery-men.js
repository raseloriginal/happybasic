(() => {
    'use strict';
    const H = window.HappyPartner;

    H.registerPage(() => {
        const grid = document.getElementById('dsrGrid');
        if (!grid) return;

        const searchInput = document.getElementById('dsrSearch');
        const countEl = document.getElementById('dsrCount');
        const emptyEl = document.getElementById('dsrEmpty');
        const form = document.getElementById('dsrForm');
        const pwForm = document.getElementById('dsrPasswordForm');

        searchInput?.addEventListener('input', () => {
            const q = searchInput.value.trim().toLowerCase();
            let visible = 0;
            grid.querySelectorAll('[data-dsr-card]').forEach((card) => {
                const ok = !q || (card.dataset.search || '').includes(q);
                card.hidden = !ok;
                if (ok) visible++;
            });
            if (countEl) countEl.textContent = H.bnNum(visible);
            if (emptyEl) emptyEl.hidden = visible > 0;
        });

        const photoInput = document.getElementById('dsrPhotoInput');
        let photoTarget = null;
        photoInput?.addEventListener('change', () => {
            const file = photoInput.files[0];
            if (!file || !photoTarget) return;
            const fd = new FormData();
            fd.append('photo', file);
            const { dsr, btn } = photoTarget;
            H.submitAction(btn, null, 'আপলোড হচ্ছে…', () => H.api('POST', H.url(`/partner/delivery-men/${dsr.id}/photo`), fd));
        });

        function openForm(dsr) {
            form.reset();
            H.formError(form, '');
            form.elements.id.value = dsr ? dsr.id : '';
            form.elements.status.value = dsr ? dsr.status : 'Active';
            form.elements.name.value = dsr ? dsr.name : '';
            form.elements.salary.value = dsr ? dsr.salary : '';
            form.elements.daily_wage.value = dsr ? dsr.daily_wage : '';
            form.elements.number.value = dsr ? dsr.phone : '';
            form.querySelector('[data-create-only]').hidden = !!dsr;
            document.getElementById('dsrModalTitle').textContent = dsr ? `সম্পাদনা: ${dsr.name}` : 'ডেলিভারিম্যান (DSR) যোগ করুন';
            H.openModal('dsrModal');
        }

        document.querySelector('[data-dsr-add]')?.addEventListener('click', () => openForm(null));

        grid.addEventListener('click', async (e) => {
            const card = e.target.closest('[data-dsr-card]');
            if (!card) return;
            const dsr = JSON.parse(card.dataset.dsr);
            const base = H.url(`/partner/delivery-men/${dsr.id}`);

            if (e.target.closest('[data-dsr-edit]')) {
                openForm(dsr);
            } else if (e.target.closest('[data-dsr-photo]')) {
                photoTarget = { dsr, btn: e.target.closest('button') };
                photoInput.value = '';
                photoInput.click();
            } else if (e.target.closest('[data-dsr-reset]')) {
                pwForm.reset();
                H.formError(pwForm, '');
                pwForm.elements.id.value = dsr.id;
                document.getElementById('dsrPasswordSub').textContent = `${dsr.name} (${H.bnDigits(dsr.number)})-এর নতুন পাসওয়ার্ড`;
                H.openModal('dsrPasswordModal');
            } else if (e.target.closest('[data-dsr-status]')) {
                const next = dsr.status === 'Active' ? 'Inactive' : 'Active';
                if (next === 'Inactive' && !window.confirm(`${dsr.name}-কে নিষ্ক্রিয় করবেন? তিনি লগ আউট হয়ে যাবেন এবং লগইন করতে পারবেন না।`)) return;
                await H.submitAction(e.target.closest('button'), null, 'সংরক্ষণ হচ্ছে…', () => H.api('PATCH', `${base}/status`, { status: next }));
            } else if (e.target.closest('[data-dsr-delete]')) {
                if (!window.confirm(`${dsr.name}-কে মুছে ফেলবেন? তাঁর লগইন মুছে যাবে, তবে আগের ট্রিপের হিসাব থাকবে।`)) return;
                await H.submitAction(e.target.closest('button'), null, 'মুছে ফেলা হচ্ছে…', () => H.api('DELETE', base));
            }
        });

        form?.addEventListener('submit', (e) => {
            e.preventDefault();
            const fd = new FormData(form);
            const id = fd.get('id');
            const body = {
                name: String(fd.get('name') || '').trim(),
                salary: fd.get('salary'),
                daily_wage: fd.get('daily_wage'),
                number: String(fd.get('number') || '').trim(),
                status: fd.get('status'),
            };
            if (!id) body.password = fd.get('password');
            const btn = form.querySelector('button[type="submit"]');
            H.submitAction(btn, form, 'সংরক্ষণ হচ্ছে…', () => (id
                ? H.api('PUT', H.url(`/partner/delivery-men/${id}`), body)
                : H.api('POST', H.url('/partner/delivery-men'), body)));
        });

        pwForm?.addEventListener('submit', (e) => {
            e.preventDefault();
            const id = pwForm.elements.id.value;
            const btn = pwForm.querySelector('button[type="submit"]');
            H.submitAction(btn, pwForm, 'রিসেট হচ্ছে…', () => H.api('POST', H.url(`/partner/delivery-men/${id}/password`), {
                password: pwForm.elements.password.value,
            }), { reload: false });
        });
    });
})();
