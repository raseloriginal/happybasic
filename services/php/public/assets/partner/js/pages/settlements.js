(() => {
    'use strict';
    const H = window.HappyPartner;

    function fmtMoney(n) {
        return H.formatMoney(n);
    }

    H.registerPage(() => {
        const tabs = document.querySelectorAll('[data-settlement-tab]');
        const panels = document.querySelectorAll('[data-settlement-panel]');
        if (!tabs.length) return;

        // 1. Trip card switching
        tabs.forEach((btn) => {
            btn.addEventListener('click', () => {
                const target = btn.getAttribute('data-settlement-tab');
                tabs.forEach((b) => {
                    const active = b.getAttribute('data-settlement-tab') === target;
                    b.classList.toggle('is-active', active);
                    b.setAttribute('aria-selected', active ? 'true' : 'false');
                });
                panels.forEach((p) => {
                    p.hidden = p.getAttribute('data-settlement-panel') !== target;
                });
            });
        });

        // 2. Retailer dues modal
        const duesTitle = document.getElementById('stDuesTitle');
        const duesSub = document.getElementById('stDuesSubtitle');
        const duesBody = document.getElementById('stDuesBody');

        document.querySelectorAll('[data-open-dues]').forEach((btn) => {
            btn.addEventListener('click', () => {
                const payload = JSON.parse(btn.getAttribute('data-open-dues') || '{}');
                if (duesTitle) {
                    duesTitle.textContent = `আজ বাকি দেওয়া — ${fmtMoney(payload.total || 0)}`;
                }
                if (duesSub) {
                    const shops = Number(payload.shops || 0);
                    duesSub.textContent = `${payload.trip || ''} · ${H.bnNum(shops)} দোকান · কনফার্ম করলে দোকানের বাকি খাতায় যোগ হবে`;
                }
                if (duesBody) {
                    const rows = Array.isArray(payload.rows) ? payload.rows : [];
                    duesBody.innerHTML = rows.length
                        ? rows.map((d) => `
                            <tr>
                                <td>
                                    <div class="cell-primary">${H.escapeHtml(d.retailer)}</div>
                                    <div class="cell-sub tabular">${H.escapeHtml(H.bnDigits(d.phone || d.area || ''))}</div>
                                </td>
                                <td class="mono">${H.escapeHtml(H.bnDigits(d.order_id))}</td>
                                <td class="text-right tabular">${fmtMoney(d.order_total)}</td>
                                <td class="text-right tabular">${fmtMoney(d.paid)}</td>
                                <td class="text-right tabular"><strong class="is-warn">${fmtMoney(d.due)}</strong></td>
                            </tr>`).join('')
                        : '<tr><td colspan="5" class="muted small" style="padding:18px;text-align:center;">এই ট্রিপে কোনো বাকি নেই।</td></tr>';
                }
                H.openModal('stDuesModal');
            });
        });

        // 3. Per-trip interactive controls
        panels.forEach((panel) => {
            const expectedCash = Number(panel.dataset.expectedCash || 0);
            const cashInput = panel.querySelector('[data-cash-input]');
            const cashCustomWrap = panel.querySelector('[data-cash-custom-wrap]');
            const cashCustomToggle = panel.querySelector('[data-cash-custom-toggle]');
            const cashLiveDiff = panel.querySelector('[data-cash-live-diff]');
            const cashChoices = panel.querySelectorAll('[data-cash-choice]');
            const dmgInput = panel.querySelector('[data-damage-input]');
            const dmgDisplay = panel.querySelector('[data-damage-display]');
            const dmgNote = panel.querySelector('[data-damage-note]');
            const summaryEl = panel.querySelector('[data-action-summary]');

            function getCashReceived() {
                if (!cashInput) return expectedCash;
                const val = Number(cashInput.value);
                return Number.isFinite(val) && val >= 0 ? Math.round((val + Number.EPSILON) * 100) / 100 : 0;
            }

            function getDamageAmount() {
                if (!dmgInput) return 0;
                const val = Number(dmgInput.value);
                return Number.isFinite(val) && val >= 0 ? Math.round((val + Number.EPSILON) * 100) / 100 : 0;
            }

            function getReturnsMap() {
                const map = {};
                let totalPcs = 0;
                panel.querySelectorAll('[data-return-row]').forEach((row) => {
                    const pid = row.getAttribute('data-product-id');
                    const inp = row.querySelector('[data-ret-input]');
                    const max = Number(row.getAttribute('data-max-pcs') || 0);
                    const qty = Math.min(max, Math.max(0, Math.floor(Number(inp?.value || 0))));
                    map[pid] = qty;
                    totalPcs += qty;
                });
                return { map, totalPcs };
            }

            function syncLiveState() {
                const cash = getCashReceived();
                const diff = Math.round(((cash - expectedCash) + Number.EPSILON) * 100) / 100;
                if (cashLiveDiff) {
                    if (diff < -0.004) {
                        cashLiveDiff.className = 'badge badge-danger tabular';
                        cashLiveDiff.textContent = `${fmtMoney(Math.abs(diff))} কম`;
                    } else if (diff > 0.004) {
                        cashLiveDiff.className = 'badge badge-warning tabular';
                        cashLiveDiff.textContent = `${fmtMoney(Math.abs(diff))} বেশি`;
                    } else {
                        cashLiveDiff.className = 'badge badge-success tabular';
                        cashLiveDiff.textContent = 'মিলেছে';
                    }
                }

                const dmg = getDamageAmount();
                if (dmgDisplay) {
                    dmgDisplay.textContent = fmtMoney(dmg);
                    dmgDisplay.className = 'tabular ' + (dmg > 0 ? 'is-danger' : 'muted');
                }

                if (summaryEl) {
                    const { totalPcs } = getReturnsMap();
                    summaryEl.innerHTML = `কনফার্ম হচ্ছে <strong>${fmtMoney(cash)}</strong> ক্যাশ · <strong>${H.bnNum(totalPcs)} পিস</strong> স্টকে ফেরত · <strong>${fmtMoney(dmg)}</strong> ড্যামেজ`;
                }
            }

            cashChoices.forEach((btn) => {
                btn.addEventListener('click', () => {
                    const mode = btn.getAttribute('data-cash-choice');
                    cashChoices.forEach((b) => b.classList.toggle('is-active', b === btn));
                    if (mode === 'custom') {
                        if (cashCustomWrap) cashCustomWrap.hidden = false;
                        cashInput?.focus();
                        cashInput?.select();
                    } else {
                        const val = btn.getAttribute('data-cash-value');
                        if (cashInput && val !== null) cashInput.value = val;
                        if (cashCustomWrap) cashCustomWrap.hidden = true;
                    }
                    syncLiveState();
                });
            });

            cashCustomToggle?.addEventListener('click', () => {
                if (!cashCustomWrap) return;
                cashCustomWrap.hidden = !cashCustomWrap.hidden;
                if (!cashCustomWrap.hidden) {
                    cashChoices.forEach((b) => b.classList.remove('is-active'));
                    cashInput?.focus();
                    cashInput?.select();
                }
                syncLiveState();
            });

            cashInput?.addEventListener('input', () => {
                const v = getCashReceived();
                cashChoices.forEach((b) => {
                    const bv = b.getAttribute('data-cash-value');
                    b.classList.toggle('is-active', bv !== null && Math.abs(Number(bv) - v) < 0.005);
                });
                syncLiveState();
            });

            panel.querySelectorAll('[data-return-row]').forEach((row) => {
                const exp = Number(row.getAttribute('data-expected-pcs') || 0);
                const max = Number(row.getAttribute('data-max-pcs') || 0);
                const inp = row.querySelector('[data-ret-input]');
                const diffEl = row.querySelector('[data-ret-diff]');

                const updateRow = (rawVal) => {
                    const val = Math.min(max, Math.max(0, Math.floor(Number(rawVal) || 0)));
                    if (inp) inp.value = String(val);
                    const d = val - exp;
                    if (diffEl) {
                        diffEl.hidden = d === 0;
                        diffEl.textContent = `DM থেকে ${d > 0 ? '+' + H.bnNum(d) : H.bnNum(d)}`;
                        diffEl.className = 'st-ret-diff tabular ' + (d < 0 ? 'is-danger' : (d > 0 ? 'is-warn' : ''));
                    }
                    syncLiveState();
                };

                row.querySelectorAll('[data-ret-step]').forEach((sBtn) => {
                    sBtn.addEventListener('click', () => {
                        const delta = Number(sBtn.getAttribute('data-ret-step') || 0);
                        updateRow((Number(inp?.value || 0)) + delta);
                    });
                });
                inp?.addEventListener('input', () => updateRow(inp.value));
            });

            panel.querySelectorAll('[data-dmg-step]').forEach((sBtn) => {
                sBtn.addEventListener('click', () => {
                    if (!dmgInput) return;
                    const delta = Number(sBtn.getAttribute('data-dmg-step') || 0);
                    const next = Math.max(0, Math.round((getDamageAmount() + delta) * 100) / 100);
                    dmgInput.value = String(next);
                    syncLiveState();
                });
            });
            dmgInput?.addEventListener('input', syncLiveState);

            panel.querySelector('[data-approve]')?.addEventListener('click', async (e) => {
                const btn = e.currentTarget;
                const cash = getCashReceived();
                const { map: returns, totalPcs } = getReturnsMap();
                const dmg = getDamageAmount();
                const note = dmgNote?.value.trim() || '';
                const confirmMsg = `${btn.dataset.code} ট্রিপের সেটেলমেন্ট কনফার্ম করবেন?\n\n`
                    + `• প্রাপ্ত ক্যাশ: ${fmtMoney(cash)}\n`
                    + `• স্টকে ফেরত: ${H.bnNum(totalPcs)} পিস\n`
                    + `• যাচাইকৃত ড্যামেজ: ${fmtMoney(dmg)}\n\n`
                    + `কনফার্ম করলে স্টক, SR O/C, দোকান বাকি ও ড্যামেজ ক্লেইম খাতায় যুক্ত হবে। এটি আর পরিবর্তন করা যাবে না।`;
                if (!window.confirm(confirmMsg)) return;

                await H.submitAction(btn, null, 'কনফার্ম হচ্ছে…', () => H.api('POST', H.url(`/partner/settlements/${btn.dataset.approve}/approve`), {
                    cash_received: cash,
                    returns,
                    damage_amount: dmg,
                    damage_note: note,
                }));
            });

            panel.querySelector('[data-sendback]')?.addEventListener('click', async (e) => {
                const btn = e.currentTarget;
                const note = panel.querySelector('[data-sendback-note]')?.value.trim() || '';
                if (!note) {
                    H.showToast('DM-কে ফেরত পাঠানোর আগে কারণ লিখুন।');
                    panel.querySelector('[data-sendback-note]')?.focus();
                    return;
                }
                await H.submitAction(btn, null, 'পাঠানো হচ্ছে…', () => H.api('POST', H.url(`/partner/settlements/${btn.dataset.sendback}/send-back`), { note }));
            });

            syncLiveState();
        });
    });
})();
