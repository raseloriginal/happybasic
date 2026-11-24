(() => {
    'use strict';
    const H = window.HappyPartner;

    H.registerPage(() => {
        const app = document.getElementById('dsrMonitorApp');
        const base = app?.dataset.base;
        if (!app || !base) return;

        // add advance / short / over / payment
        const entryForm = document.getElementById('entryForm');
        entryForm?.addEventListener('submit', (e) => {
            e.preventDefault();
            const f = entryForm.elements;
            H.submitAction(entryForm.querySelector('button[type="submit"]'), entryForm, 'সংরক্ষণ হচ্ছে…', () => H.api('POST', `${base}/entries`, {
                type: f.type.value, amount: f.amount.value, date: f.date.value, note: f.note.value,
            }));
        });

        // set one calendar day by hand
        const dayForm = document.getElementById('dayForm');
        app.addEventListener('click', (e) => {
            const day = e.target.closest('[data-day]');
            if (day && dayForm) {
                dayForm.elements.date.value = day.dataset.day;
                const status = day.dataset.status;
                dayForm.querySelectorAll('input[name="status"]').forEach((r) => { r.checked = r.value === status; });
                document.getElementById('dayModalTitle').textContent = `হাজিরা — ${H.bnDigits(day.dataset.day.split('-').reverse().join('/'))}`;
                H.formError(dayForm, '');
                H.openModal('dayModal');
                return;
            }
            const del = e.target.closest('[data-del-entry]');
            if (del) {
                if (!window.confirm('এই এন্ট্রি মুছে ফেলবেন?')) return;
                H.submitAction(del, null, '…', () => H.api('DELETE', H.url(`/partner/dsr-monitor/entries/${del.dataset.delEntry}/${del.dataset.id}`)));
            }
        });
        dayForm?.addEventListener('submit', (e) => {
            e.preventDefault();
            const status = dayForm.elements.status.value;
            if (!status) { H.formError(dayForm, 'একটি অবস্থা বাছুন।'); return; }
            H.submitAction(dayForm.querySelector('button[type="submit"]'), dayForm, 'সংরক্ষণ হচ্ছে…', () => H.api('POST', `${base}/days`, {
                date: dayForm.elements.date.value, status,
            }));
        });
    });
})();
