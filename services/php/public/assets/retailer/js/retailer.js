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

    // ---- Notifications: mark as seen after the page has been shown ----
    const seen = document.querySelector('[data-mark-seen]');
    if (seen) setTimeout(() => post(seen.dataset.markSeen).catch(() => {}), 1500);

    // ---- Invoices ----
    const dataEl = document.getElementById('invData');
    const tabs = document.getElementById('invTabs');
    const card = document.getElementById('invCard');
    if (!dataEl || !tabs || !card) return;

    const D = JSON.parse(dataEl.textContent);
    const mode = document.body.dataset.mode; // 'order' | 'delivery'
    const orders = D.orders;
    if (!orders.length) {
        tabs.hidden = true;
        card.outerHTML = '<div class="card empty"><b>এই দিনে কোনো ইনভয়েস নেই</b></div>';
        document.querySelector('.actions')?.remove();
        return;
    }

    const orderInvoice = (o) => {
        const rows = o.items.map((it, n) =>
            `<div class="itrow"><span class="n">${bn(n + 1)}</span><div class="nm"><b>${esc(it.name)}</b>` +
            `<small>${num(it.pcs)} পিস × ${money(it.rate)}${it.mrp != null ? ' · MRP ' + money(it.mrp) : ''}</small></div>` +
            `<div class="rt"><b>${money(it.amount)}</b>${it.gain != null ? `<span class="gain">+${money(it.gain)}</span>` : ''}</div></div>`).join('');
        return `
            <div class="inv-brand"><span class="logo-sq"><svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="2.4" stroke-linecap="round"><path d="M6 5v14M18 5v14M6 12h12"/></svg></span>
                <div><h2>Happy Bangladesh</h2><p>${esc([o.partner.name, o.partner.phone].filter(Boolean).join(' · '))}</p></div>
                <div class="inv-title"><b>INVOICE</b><span class="badge badge-${o.tone}">${esc(o.status)}</span></div></div>
            <div class="inv-meta"><div class="bill-to"><small>বিল টু</small><b>${esc(o.shop.name)}</b><span>${esc(o.shop.address)}</span><span>${esc(o.shop.phone)}</span></div>
                <div class="meta-kv"><div><span>ইনভয়েস নং</span><b>${o.code}</b></div><div><span>তারিখ</span><span>${esc(D.dateLabel)}</span></div>
                <div><span>কোম্পানি</span><span>${esc(o.company)}</span></div><div><span>SR</span><span>${esc(o.sr)}</span></div>
                <div><span>ডেলিভারি</span><span>${esc(o.dm || '—')}</span></div></div></div>
            <div class="itlist">${rows}</div>
            <div class="inv-totals"><div class="tot"><span>সাবটোটাল</span><span>${money(o.subtotal)}</span></div>
                <div class="tot"><span>${o.damage > 0 ? 'ড্যামেজ কর্তন' : 'ছাড়'}</span><span>${money(o.damage)}</span></div>
                <div class="tot grand"><b>মোট</b><b>${money(o.total)}</b></div>
                ${o.paid > 0 ? `<div class="tot"><span>নগদ পরিশোধ</span><span>${money(o.paid)}</span></div>` : ''}
                ${o.due > 0 ? `<div class="tot"><span>বাকি</span><span>${money(o.due)}</span></div>` : ''}
                ${o.profit != null ? `<div class="profit"><div><b>আপনার লাভ</b><small>সব MRP-তে বেচলে</small></div><strong>+${money(o.profit)}</strong></div>` : ''}</div>
            <p class="words">কথায়: ${esc(o.words)}</p>
            <div class="sigs"><div>গ্রাহকের স্বাক্ষর</div><div>ডেলিভারি ম্যান</div></div>
            <p class="fine">মাল বুঝে নিয়ে স্বাক্ষর করুন · নষ্ট বা কম হলে ২৪ ঘণ্টার মধ্যে জানান · ধন্যবাদ</p>`;
    };

    const deliveryInvoice = (o) => {
        if (o.stage !== 'arrived') {
            return `<div class="empty"><b>মাল এখনো আসেনি</b><p>${esc(o.status)} · ডেলিভারি ইনভয়েস মাল পৌঁছালে এখানে দেখা যাবে।</p></div>`;
        }
        const rows = o.items.map((it) =>
            `<div class="itrow"><span class="n"></span><div class="nm"><b>${esc(it.name)}</b>` +
            `<small>${num(it.pcs)} পিস × ${money(it.rate)} কেনা${it.mrp != null ? ' · MRP ' + money(it.mrp) : ''}</small>` +
            `${it.short > 0 ? `<small class="short">${num(it.short)}টি কম · ভ্যানে ছিল না</small>` : ''}</div>` +
            `<div class="rt"><b>${money(it.pcs * it.rate)}</b>${it.gain != null ? `<span class="gain">লাভ ${money(it.gain)}</span>` : ''}</div></div>`).join('');
        return `
            <div class="di-head"><div><h2>${esc(o.company)} · ${esc(o.partner.name)}</h2><p>Happy Bangladesh</p></div>
                <div class="di-r"><h2>ডেলিভারি ইনভয়েস</h2><p>${o.code}</p></div></div>
            <div class="kv"><span>দোকান</span><b>${esc(o.shop.name)}</b></div>
            <div class="kv"><span>ডেলিভারি</span><span>${esc(o.dm || '—')}${o.time ? ' · ' + bn(o.time) : ''}</span></div>
            <div class="kv"><span>তারিখ</span><span>${esc(D.dateLabel)}</span></div>
            <div class="itlist">${rows}</div>
            <div class="tot"><span>আমার কেনা (বিল)</span><b>${money(o.total)}</b></div>
            ${o.mrp_total != null ? `<div class="tot"><span>MRP-তে বিক্রি করলে</span><span>${money(o.mrp_total)}</span></div>` : ''}
            ${o.profit != null ? `<div class="tot grand"><b>আমার লাভ</b><b class="gain">${money(o.profit)}</b></div>` : ''}
            ${o.damage > 0 ? `<div class="tot"><span>ড্যামেজ কর্তন</span><span>${money(o.damage)}</span></div>` : ''}
            <div class="tot"><span>নগদ দিয়েছেন</span><span>${money(o.paid)}</span></div>
            ${o.due > 0 ? `<div class="tot muted-row"><span>নোট: বাকি রইল</span><span>${money(o.due)}</span></div>` : ''}
            <div class="otp">মাল পেয়েছেন</div>`;
    };

    let cur = Math.max(0, orders.findIndex((o) => o.id === D.selected));
    const tip = document.getElementById('invTip');

    const render = (i) => {
        cur = i;
        const o = orders[i];
        card.innerHTML = mode === 'delivery' ? deliveryInvoice(o) : orderInvoice(o);
        tabs.querySelectorAll('.tab').forEach((t, n) => t.classList.toggle('is-on', n === i));
        if (tip) {
            const show = mode === 'delivery' && o.stage === 'arrived' && o.profit_per_100 != null;
            tip.hidden = !show;
            if (show) tip.querySelector('[data-per100]').textContent = money(o.profit_per_100);
        }
    };

    tabs.innerHTML = orders.map((o, i) => `<button type="button" class="tab" data-i="${i}">${esc(o.company)} · ${esc(o.sr)}</button>`).join('');
    tabs.hidden = orders.length < 2;
    tabs.addEventListener('click', (e) => { const b = e.target.closest('.tab'); if (b) render(+b.dataset.i); });
    render(cur);
})();
