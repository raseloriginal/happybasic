<?php $this->extend('partner.layouts.main'); ?>

<?php use App\Support\Bn; ?>

<?php $this->section('topbar_actions'); ?>
<button type="button" class="btn btn-primary btn-sm" data-product-add>
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2"><path d="M12 5v14M5 12h14"/></svg>
    <span>নতুন পণ্য যোগ করুন</span>
</button>
<?php $this->endSection(); ?>

<?php $this->section('content'); ?>
<div class="toolbar-card">
    <div class="toolbar-filters">
        <div class="search-box">
            <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/></svg>
            <input type="search" id="productSearch" placeholder="পণ্যের নাম দিয়ে খুঁজুন…" autocomplete="off">
        </div>
        <select id="productCompanyFilter" class="select-input" aria-label="কোম্পানি ফিল্টার">
            <option value="">সব কোম্পানি</option>
            <?php foreach ($companies as $c): ?>
                <option value="<?= (int) $c['id'] ?>"><?= e($c['name']) ?></option>
            <?php endforeach; ?>
        </select>
        <select id="productCategoryFilter" class="select-input" aria-label="ক্যাটাগরি ফিল্টার">
            <option value="">সব ক্যাটাগরি</option>
            <?php foreach ($categories as $cat): ?>
                <option value="<?= (int) $cat['id'] ?>"><?= e($cat['name']) ?></option>
            <?php endforeach; ?>
        </select>
    </div>
    <span class="muted small tabular"><strong id="productCount"><?= Bn::num(count($products)) ?></strong>টি পণ্য</span>
</div>

<?php if ($companies === []): ?>
    <div class="notice">আপনার অ্যাকাউন্টের সাথে এখনো কোনো কোম্পানি যুক্ত নেই। অ্যাডমিন SR যোগ করলে কোম্পানি যুক্ত হবে।</div>
<?php endif; ?>

<section class="products-grid" id="productsGrid">
    <?php foreach ($products as $p): ?>
        <?php
            $svg = '<svg xmlns="http://www.w3.org/2000/svg" width="240" height="160" viewBox="0 0 240 160">'
                . '<rect width="240" height="160" fill="' . $p['tint'] . '"/>'
                . '<rect x="88" y="42" width="64" height="64" rx="14" fill="#ffffff" stroke="#e4e7ec" stroke-width="2"/>'
                . '<text x="120" y="81" text-anchor="middle" font-family="system-ui,sans-serif" font-size="22" font-weight="700" fill="#0f172a">' . htmlspecialchars($p['code'], ENT_QUOTES, 'UTF-8') . '</text>'
                . '</svg>';
            $imgSrc = $p['image'] ?? 'data:image/svg+xml;utf8,' . rawurlencode($svg);
            $unitBn = Bn::unitType((string) $p['unit_type']);
            $stockBn = Bn::unitPcs((int) $p['stock_pcs'], (int) $p['qty_per_unit'], (string) $p['unit_type']);
            $marginStr = Bn::digits(rtrim(rtrim(number_format($p['dealer_margin'], 2), '0'), '.'));
        ?>
        <article
            class="card product-card <?= $p['status'] === 'Active' ? '' : 'is-muted' ?>"
            data-product-card
            data-name="<?= e(strtolower($p['name'] . ' ' . ($p['sku'] ?? ''))) ?>"
            data-category="<?= (int) $p['category_id'] ?>"
            data-company="<?= (int) $p['company_id'] ?>"
            data-product="<?= e(json_encode($p, JSON_UNESCAPED_UNICODE)) ?>"
        >
            <div class="product-media">
                <img src="<?= e($imgSrc) ?>" alt="<?= e($p['name']) ?>" loading="lazy">
                <span class="product-cat-pill"><?= e($p['category']) ?></span>
                <?php if ($p['status'] !== 'Active'): ?><span class="product-status-pill">নিষ্ক্রিয়</span><?php endif; ?>
            </div>
            <div class="product-body">
                <h3 class="product-name"><?= e($p['name']) ?></h3>
                <span class="muted small tabular"><?= e($p['company']) ?> · প্রতি <?= e($unitBn) ?> <?= Bn::num((int) $p['qty_per_unit']) ?> পিস · <?= $marginStr ?>% মার্জিন</span>
                <div class="product-stock">
                    <span class="muted small">বর্তমান স্টক</span>
                    <strong class="tabular"><?= e($stockBn) ?></strong>
                </div>
                <?php if ($p['reserved_pcs'] > 0): ?>
                    <div class="product-stock">
                        <span class="muted small">অর্ডারকৃত (লোড হয়নি)</span>
                        <strong class="tabular <?= $p['available_pcs'] < 0 ? 'is-danger' : '' ?>"><?= Bn::num((int) $p['reserved_pcs']) ?> পিস</strong>
                    </div>
                <?php endif; ?>
                <div class="product-prices">
                    <div class="price-box">
                        <span class="muted small">কোম্পানি মূল্য</span>
                        <?php if ($p['priced']): ?>
                            <strong class="tabular"><?= Bn::money((float) $p['company_price_unit']) ?></strong>
                            <span class="muted small tabular"><?= Bn::money((float) $p['company_price_pc']) ?>/পিস</span>
                        <?php else: ?>
                            <strong class="muted">লট নেই</strong>
                        <?php endif; ?>
                    </div>
                    <div class="price-box">
                        <span class="muted small">ডিলার মূল্য</span>
                        <?php if ($p['priced']): ?>
                            <strong class="tabular"><?= Bn::money((float) $p['dealer_price_unit']) ?></strong>
                            <span class="muted small tabular"><?= Bn::money((float) $p['dealer_price_pc']) ?>/পিস</span>
                        <?php else: ?>
                            <strong class="muted">—</strong>
                        <?php endif; ?>
                    </div>
                </div>
                <div class="card-actions">
                    <button type="button" class="btn btn-secondary btn-xs" data-product-edit>সম্পাদনা</button>
                    <button type="button" class="btn btn-danger-soft btn-xs" data-product-delete>মুছুন</button>
                </div>
            </div>
        </article>
    <?php endforeach; ?>
</section>

<div class="empty-state" id="productsEmpty" <?= $products ? 'hidden' : '' ?>>
    <p><?= $products ? 'খোঁজ বা ফিল্টারের সাথে কোনো পণ্য মিলছে না।' : 'এখনো কোনো পণ্য নেই। নতুন পণ্য যোগ করে লট গ্রহণ করুন।' ?></p>
</div>

<!-- Add / Edit Product Modal -->
<div class="modal-overlay" id="productModal" aria-hidden="true">
    <div class="modal-panel" role="dialog" aria-modal="true" aria-labelledby="productModalTitle">
        <div class="modal-head">
            <div>
                <h2 id="productModalTitle" class="section-title">নতুন পণ্য যোগ করুন</h2>
                <p class="section-subtitle">কোম্পানি মূল্য লট থেকে আসে · ডিলার মূল্য = কোম্পানি মূল্য + মার্জিন %</p>
            </div>
            <button type="button" class="icon-btn" data-modal-close aria-label="বন্ধ করুন">
                <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M18 6 6 18M6 6l12 12"/></svg>
            </button>
        </div>

        <form id="productForm" class="modal-form" enctype="multipart/form-data" novalidate>
            <input type="hidden" name="id" value="">
            <div class="modal-body">
                <div class="form-group">
                    <label for="prod_image">পণ্যের ছবি</label>
                    <label class="upload-zone" for="prod_image">
                        <img id="productImagePreview" alt="প্রিভিউ" hidden>
                        <div class="upload-placeholder" id="productImagePlaceholder">
                            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="17 8 12 3 7 8"/><line x1="12" y1="3" x2="12" y2="15"/></svg>
                            <span>ছবি আপলোড করতে ক্লিক করুন (PNG, JPG, WebP · সর্বোচ্চ ৩ MB)</span>
                        </div>
                    </label>
                    <input id="prod_image" name="image" type="file" accept="image/png,image/jpeg,image/webp" class="sr-only">
                </div>

                <div class="form-grid">
                    <div class="form-group span-2">
                        <label for="prod_name">পণ্যের নাম <span class="req">*</span></label>
                        <input id="prod_name" name="name" type="text" placeholder="যেমন: মিনারেল ওয়াটার ৫০০ মি.লি." maxlength="150" required>
                    </div>
                    <div class="form-group">
                        <label for="prod_company">কোম্পানি <span class="req">*</span></label>
                        <select id="prod_company" name="company_id" required>
                            <option value="">কোম্পানি নির্বাচন করুন</option>
                            <?php foreach ($companies as $c): ?>
                                <option value="<?= (int) $c['id'] ?>"><?= e($c['name']) ?></option>
                            <?php endforeach; ?>
                        </select>
                    </div>
                    <div class="form-group">
                        <label for="prod_category">ক্যাটাগরি <span class="req">*</span></label>
                        <select id="prod_category" name="category_id" required>
                            <option value="">ক্যাটাগরি নির্বাচন করুন</option>
                            <?php foreach ($categories as $cat): ?>
                                <option value="<?= (int) $cat['id'] ?>"><?= e($cat['name']) ?></option>
                            <?php endforeach; ?>
                        </select>
                    </div>
                    <div class="form-group">
                        <label for="prod_unit_type">ইউনিটের ধরন <span class="req">*</span></label>
                        <select id="prod_unit_type" name="unit_type" required>
                            <?php foreach ($unitTypes as $unit): ?>
                                <option value="<?= e($unit) ?>"><?= e(Bn::unitType($unit)) ?></option>
                            <?php endforeach; ?>
                        </select>
                    </div>
                    <div class="form-group">
                        <label for="prod_qty_per_unit">প্রতি ইউনিটে পিস <span class="req">*</span></label>
                        <input id="prod_qty_per_unit" name="quantity_per_unit" type="number" min="1" step="1" placeholder="যেমন: ২৪" required>
                    </div>
                    <div class="form-group">
                        <label for="prod_profit_margin">ডিলার মার্জিন (%) <span class="req">*</span></label>
                        <input id="prod_profit_margin" name="profit_margin" type="number" min="0" step="0.01" placeholder="যেমন: 8.5" required>
                    </div>
                    <div class="form-group">
                        <label for="prod_sku">SKU / কোড</label>
                        <input id="prod_sku" name="sku" type="text" maxlength="50" placeholder="ঐচ্ছিক">
                    </div>
                    <div class="form-group span-2" data-edit-only hidden>
                        <label for="prod_status">স্ট্যাটাস</label>
                        <select id="prod_status" name="status">
                            <option value="Active">সক্রিয়</option>
                            <option value="Inactive">নিষ্ক্রিয়</option>
                        </select>
                    </div>
                </div>
                <p class="muted small" id="productPricePreview" style="margin:10px 0 0"></p>
            </div>
            <div class="modal-error" data-form-error hidden></div>
            <div class="modal-foot">
                <button type="button" class="btn btn-secondary" data-modal-close>বাতিল</button>
                <button type="submit" class="btn btn-primary">পণ্য সংরক্ষণ করুন</button>
            </div>
        </form>
    </div>
</div>
<?php $this->endSection(); ?>
