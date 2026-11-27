(() => {
    'use strict';
    const BN = '০১২৩৪৫৬৭৮৯';
    const bn = (v) => String(v).replace(/\d/g, (d) => BN[d]);
    const num = (n) => bn(Number(n).toLocaleString('en-US', { maximumFractionDigits: 2 }));
    const money = (n) => '৳' + num(n);
    const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
    const csrf = () => document.querySelector('meta[name="csrf-token"]')?.content || '';

    async function post(url, body) {
        const res = await fetch(url, {
            method: 'POST', credentials: 'same-origin',
            headers: { Accept: 'application/json', 'Content-Type': 'application/json', 'X-Requested-With': 'XMLHttpRequest', 'X-CSRF-TOKEN': csrf() },
            body: JSON.stringify(body || {}),
        });
        const data = await res.json().catch(() => ({}));
        if (res.status === 401 && data.redirect) { location.href = data.redirect; throw new Error(data.message || ''); }
        if (!res.ok || data.ok === false) throw new Error(res.status === 419 ? 'সেশন মেয়াদ শেষ। পেজ রিলোড করুন।' : (data.message || 'কিছু একটা ভুল হয়েছে।'));
        return data;
    }

    // ---- Login ----
    const form = document.getElementById('loginForm');
    if (form) {
        const err = document.getElementById('err');
        const pw = form.password;
        const btn = form.querySelector('.btn-primary');
        document.getElementById('togglePw').addEventListener('click', (e) => {
            const show = pw.type === 'password';
            pw.type = show ? 'text' : 'password';
            e.currentTarget.textContent = show ? 'লুকান' : 'দেখুন';
        });
        form.addEventListener('submit', async (e) => {
            e.preventDefault();
            err.hidden = true;
            if (!form.phone.value.trim() || !pw.value) {
                err.textContent = 'মোবাইল নম্বর ও পাসওয়ার্ড লিখুন।';
                err.hidden = false;
                return;
            }
            btn.disabled = true; btn.textContent = 'সাইন ইন হচ্ছে…';
            try {
                const data = await post(form.dataset.action, { phone: form.phone.value.trim(), password: pw.value, remember: form.remember.checked ? 1 : 0 });
                location.href = data.redirect || form.dataset.home;
            } catch (ex) {
                err.textContent = ex.message; err.hidden = false;
                btn.disabled = false; btn.textContent = 'সাইন ইন করুন';
            }
        });
        return;
    }

    // ---- Notifications: SR / DM switch; mark as seen after the page has been shown ----
    const seen = document.querySelector('[data-mark-seen]');
    if (seen) setTimeout(() => post(seen.dataset.markSeen).catch(() => {}), 1500);
    document.querySelectorAll('[data-ntab]').forEach((b) => b.addEventListener('click', () => {
        document.querySelectorAll('[data-ntab]').forEach((x) => { const on = x === b; x.classList.toggle('is-on', on); x.setAttribute('aria-selected', on ? 'true' : 'false'); });
        document.querySelectorAll('[data-npanel]').forEach((p) => { p.hidden = p.dataset.npanel !== b.dataset.ntab; });
    }));

    // ---- Invoice buttons ----
    document.querySelector('[data-share]')?.addEventListener('click', () => window.print());
    document.querySelector('[data-report]')?.addEventListener('click', () => alert('সমস্যা জানাতে আপনার ডেলিভারি ম্যান বা SR-কে ফোন করুন।'));

    // ---- Invoices ----
    const dataEl = document.getElementById('invData');
    const tabs = document.getElementById('invTabs');
    const card = document.getElementById('invCard');
    if (!dataEl || !tabs || !card) return;

    const D = JSON.parse(dataEl.textContent);
    const mode = document.body.dataset.mode; // 'order' | 'delivery'
    const orders = D.orders;
    const sub = document.getElementById('invSub');
    const profitCard = document.getElementById('invProfit');
    const signed = (n) => (n < 0 ? '−৳' : '+৳') + num(Math.abs(n));
    if (!orders.length) {
        tabs.hidden = true;
        card.outerHTML = '<div class="card empty"><b>এই দিনে কোনো ইনভয়েস নেই</b></div>';
        document.querySelector('.actions')?.remove();
        return;
    }

    const orderInvoice = (o) => {
        const rows = o.items.map((it) =>
            `<div class="tr"><span class="nm"><b>${esc(it.name)}</b>${it.mrp != null ? `<small>MRP ${money(it.mrp)}</small>` : ''}</span>` +
            `<span>${num(it.pcs)}</span><span>${money(it.rate)}</span>` +
            `<span class="amt"><b>${money(it.amount)}</b>${it.gain != null ? `<span class="gain">${signed(it.gain)}</span>` : ''}</span></div>`).join('');
        const people = [o.company, o.sr === 'রেডি সেল' ? 'রেডি সেল' : 'SR ' + o.sr, o.dm ? 'DM ' + o.dm : ''].filter(Boolean).map(esc).join(' · ');
        return `
            <div class="iv-top"><div><b class="iv-brand">Happy Bangladesh</b><small>${esc([o.partner.name, o.partner.address].filter(Boolean).join(' · '))}</small></div>
                <div class="iv-word"><b>INVOICE</b><span class="badge badge-${esc(o.tone)}">${esc(o.status)}</span></div></div>
            <div class="iv-meta"><span>বিল টু<br><b class="shop">${esc(o.shop.name)}</b>${o.shop.address ? '<br>' + esc(o.shop.address) : ''}</span>
                <span>ইনভয়েস নং <b>${esc(o.code)}</b><br>তারিখ <b>${esc(D.dateLabel)}</b><br>${people}</span></div>
            <div class="tbl"><div class="tr th"><span>বিবরণ</span><span>পিস</span><span>দর</span><span>টাকা · লাভ</span></div>${rows}</div>
            <div class="tots">
                ${o.damage > 0 ? `<div><span>সাবটোটাল</span><b>${money(o.subtotal)}</b></div><div><span>ড্যামেজ কর্তন</span><b>−${money(o.damage)}</b></div>` : ''}
                <div><span>মোট</span><b class="big">${money(o.total)}</b></div>
                ${o.paid > 0 ? `<div><span>নগদ পরিশোধ</span><b>${money(o.paid)}</b></div>` : ''}
                ${o.due > 0 ? `<div><span>বাকি</span><b class="red">${money(o.due)}</b></div>` : ''}</div>
            ${o.profit != null ? `<div class="iv-gain"><span>আপনার লাভ · সব MRP-তে বেচলে</span><b>${signed(o.profit)}</b></div>` : ''}
            <span class="words">কথায়: ${esc(o.words)}</span>`;
    };

    const deliveryInvoice = (o) => {
        if (o.stage !== 'arrived') {
            return `<div class="not-yet"><b>মাল এখনো আসেনি</b>${esc(o.status)} · মাল পৌঁছালে ডেলিভারি ইনভয়েস এখানে দেখা যাবে।</div>`;
        }
        const rows = o.items.map((it) =>
            `<div class="tr"><span class="nm"><b>${esc(it.name)}</b>${it.short > 0 ? `<small class="short">${num(it.short)}টি কম · ভ্যানে ছিল না</small>` : ''}</span>` +
            `<span${it.short > 0 ? ' class="short"' : ''}>${num(it.pcs)}</span><span>${num(it.rate)}</span>` +
            `<span class="mrp">${it.mrp != null ? num(it.mrp) : '—'}</span><b class="g">${it.gain != null ? signed(it.gain) : '—'}</b></div>`).join('');
        return `
            <div class="dv-top"><span>ডেলিভারি <b>${esc(o.dm ? 'DM ' + o.dm : '—')}${o.time ? ' · ' + bn(o.time) : ''}</b></span><span>${esc(D.dateLabel)}</span></div>
            <div class="tbl five"><div class="tr th"><span>পণ্য</span><span>পিস</span><span>কেনা</span><span>MRP</span><span>লাভ</span></div>${rows}</div>
            <div class="tots">
                <div><span>আমার কেনা (বিল)</span><b>${money(o.subtotal)}</b></div>
                ${o.damage > 0 ? `<div><span>ড্যামেজ কর্তন</span><b>−${money(o.damage)}</b></div><div><span>মোট বিল</span><b>${money(o.total)}</b></div>` : ''}
                ${o.mrp_total != null ? `<div><span>MRP-তে বিক্রি করলে</span><b>${money(o.mrp_total)}</b></div>` : ''}
                <div><span>${o.due > 0 ? 'নগদ দিয়েছেন · বাকি রইল' : 'নগদ দিয়েছেন'}</span><b>${money(o.paid)}${o.due > 0 ? ` · <span class="red">${money(o.due)}</span>` : ''}</b></div></div>`;
    };

    let cur = Math.max(0, orders.findIndex((o) => o.id === D.selected));
    const render = (i) => {
        cur = i;
        const o = orders[i];
        card.innerHTML = mode === 'delivery' ? deliveryInvoice(o) : orderInvoice(o);
        const seg = document.querySelector('[data-seg-link]');
        if (seg) { const u = new URL(seg.href, location.href); u.searchParams.set('order', o.id); seg.href = u.toString(); }
        tabs.querySelectorAll('.pill').forEach((t, n) => { t.classList.toggle('is-on', n === i); t.setAttribute('aria-pressed', n === i ? 'true' : 'false'); });
        if (mode === 'delivery') {
            if (sub) sub.textContent = [o.company, o.partner.name, o.code].filter(Boolean).join(' · ');
            const show = o.stage === 'arrived' && o.profit != null;
            if (profitCard) {
                profitCard.hidden = !show;
                if (show) {
                    profitCard.querySelector('[data-profit]').textContent = signed(o.profit);
                    profitCard.querySelector('[data-per100]').textContent = o.profit_per_100 != null ? signed(o.profit_per_100) : '—';
                }
            }
        }
    };

    tabs.innerHTML = orders.map((o, i) => `<button type="button" class="pill" data-i="${i}">${esc(o.company)} · ${esc(o.sr)}</button>`).join('');
    tabs.addEventListener('click', (e) => { const b = e.target.closest('.pill'); if (b) render(+b.dataset.i); });
    render(cur);
})();
