(() => {
    'use strict';
    const H = window.HappyPartner;

    H.registerPage(() => {
        const grid = document.getElementById('productsGrid');
        if (!grid) return;

        const searchInput = document.getElementById('productSearch');
        const companyFilter = document.getElementById('productCompanyFilter');
        const categoryFilter = document.getElementById('productCategoryFilter');
        const countEl = document.getElementById('productCount');
        const emptyEl = document.getElementById('productsEmpty');
        const form = document.getElementById('productForm');
        const fileInput = document.getElementById('prod_image');
        const previewImg = document.getElementById('productImagePreview');
        const placeholder = document.getElementById('productImagePlaceholder');
        const pricePreview = document.getElementById('productPricePreview');
        let editing = null;

        function filterProducts() {
            const q = (searchInput?.value || '').trim().toLowerCase();
            const cmp = companyFilter?.value || '';
            const cat = categoryFilter?.value || '';
            let visible = 0;
            grid.querySelectorAll('[data-product-card]').forEach((card) => {
                const ok = (!q || (card.dataset.name || '').includes(q))
                    && (!cmp || card.dataset.company === cmp)
                    && (!cat || card.dataset.category === cat);
                card.hidden = !ok;
                if (ok) visible++;
            });
            if (countEl) countEl.textContent = H.bnNum(visible);
            if (emptyEl && grid.children.length) emptyEl.hidden = visible > 0;
        }
        [searchInput, companyFilter, categoryFilter].forEach((el) => el?.addEventListener(el.tagName === 'INPUT' ? 'input' : 'change', filterProducts));

        function setPreview(src) {
            previewImg.hidden = !src;
            previewImg.src = src || '';
            placeholder.hidden = !!src;
        }

        function updatePricePreview() {
            if (!pricePreview) return;
            const margin = Number(form.elements.profit_margin.value || 0);
            if (editing && editing.priced) {
                const qpu = Math.max(1, Number(form.elements.quantity_per_unit.value || editing.qty_per_unit));
                const dealerPc = Math.round(editing.company_price_pc * (1 + margin / 100) * 100) / 100;
                pricePreview.textContent = `সর্বশেষ কোম্পানি মূল্য ${H.formatMoney(editing.company_price_pc)}/পিস → ডিলার মূল্য ${H.formatMoney(dealerPc)}/পিস (${H.formatMoney(dealerPc * qpu)}/${H.bnUnit(form.elements.unit_type.value)})`;
            } else {
                pricePreview.textContent = 'এই পণ্যের প্রথম লট গ্রহণ করলে মূল্য নির্ধারিত হবে।';
            }
        }
        form?.addEventListener('input', updatePricePreview);

        fileInput?.addEventListener('change', () => {
            const file = fileInput.files?.[0];
            if (!file) { setPreview(editing?.image || null); return; }
            const reader = new FileReader();
            reader.onload = () => setPreview(typeof reader.result === 'string' ? reader.result : null);
            reader.readAsDataURL(file);
        });

        function openForm(p) {
            editing = p;
            form.reset();
            H.formError(form, '');
            const f = form.elements;
            f.id.value = p ? p.id : '';
            if (p) {
                f.name.value = p.name;
                f.company_id.value = p.company_id;
                f.category_id.value = p.category_id;
                f.unit_type.value = p.unit_type;
                f.quantity_per_unit.value = p.qty_per_unit;
                f.profit_margin.value = p.dealer_margin;
                f.mrp.value = p.mrp ?? '';
                f.sku.value = p.sku || '';
                f.status.value = p.status;
            }
            f.company_id.disabled = !!(p && p.has_lots);
            f.quantity_per_unit.readOnly = !!(p && p.has_lots);
            form.querySelector('[data-edit-only]').hidden = !p;
            setPreview(p?.image || null);
            document.getElementById('productModalTitle').textContent = p ? `সম্পাদনা: ${p.name}` : 'নতুন পণ্য যোগ করুন';
            updatePricePreview();
            H.openModal('productModal');
        }

        document.querySelector('[data-product-add]')?.addEventListener('click', () => openForm(null));

        grid.addEventListener('click', async (e) => {
            const card = e.target.closest('[data-product-card]');
            if (!card) return;
            const p = JSON.parse(card.dataset.product);
            if (e.target.closest('[data-product-edit]')) {
                openForm(p);
            } else if (e.target.closest('[data-product-delete]')) {
                if (!window.confirm(`"${p.name}" পণ্যটি মুছবেন?`)) return;
                await H.submitAction(e.target.closest('button'), null, 'মুছে ফেলা হচ্ছে…', () => H.api('DELETE', H.url(`/partner/products/${p.id}`)));
            }
        });

        form?.addEventListener('submit', (e) => {
            e.preventDefault();
            const f = form.elements;
            const disabled = f.company_id.disabled;
            f.company_id.disabled = false;
            const fd = new FormData(form);
            f.company_id.disabled = disabled;
            if (!fileInput.files?.length) fd.delete('image');
            if (!fd.get('status')) fd.set('status', 'Active');
            const id = fd.get('id');
            fd.delete('id');
            const btn = form.querySelector('button[type="submit"]');
            H.submitAction(btn, form, 'সংরক্ষণ হচ্ছে…', () => H.api('POST', H.url(id ? `/partner/products/${id}` : '/partner/products'), fd));
        });
    });
})();
