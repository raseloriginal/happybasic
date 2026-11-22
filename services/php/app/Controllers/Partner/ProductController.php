<?php

declare(strict_types=1);

namespace App\Controllers\Partner;

use App\Models\Product;
use App\Support\HttpError;
use Core\Request;
use Core\Response;

final class ProductController extends PartnerController
{
    private const MAX_IMAGE_BYTES = 3 * 1024 * 1024;
    private const IMAGE_TYPES = ['image/jpeg' => 'jpg', 'image/png' => 'png', 'image/webp' => 'webp'];

    public function index(): Response
    {
        $pid = $this->partnerId();

        return $this->view('partner.products', [
            'title' => 'পণ্য',
            'activeNav' => 'products',
            'products' => Product::forPartner($pid),
            'companies' => Product::companyOptions($pid),
            'categories' => Product::categoryOptions(),
            'unitTypes' => Product::UNIT_TYPES,
        ]);
    }

    public function store(Request $request): Response
    {
        return $this->action(function () use ($request): array {
            $data = $this->payload($request);
            $data['status'] = 'active';
            $data['image_path'] = $this->storeImage($request);
            $p = Product::present(Product::create($this->partnerId(), $data));
            $this->log('Created', 'Product', "Partner added product \"{$p['name']}\"");
            return ['message' => "\"{$p['name']}\" পণ্যটি যোগ হয়েছে। দর ও স্টক নির্ধারণে একটি লট গ্রহণ করুন।", 'product' => $p];
        });
    }

    /** POST (not PUT) so the multipart form can carry a new image. */
    public function update(Request $request, int $id): Response
    {
        return $this->action(function () use ($request, $id): array {
            $data = $this->payload($request);
            $data['status'] = $this->statusFrom($request);
            $data['image_path'] = $this->storeImage($request);
            $p = Product::present(Product::update($this->partnerId(), $id, $data));
            $this->log('Updated', 'Product', "Partner updated product \"{$p['name']}\"");
            return ['message' => "\"{$p['name']}\" পণ্যটি হালনাগাদ হয়েছে।", 'product' => $p];
        });
    }

    public function destroy(int $id): Response
    {
        return $this->action(function () use ($id): array {
            $row = Product::delete($this->partnerId(), $id);
            $this->log('Deleted', 'Product', "Partner deleted product \"{$row['name']}\"");
            return ['message' => "\"{$row['name']}\" পণ্যটি মুছে ফেলা হয়েছে।"];
        });
    }

    /** @return array<string, mixed> */
    private function payload(Request $request): array
    {
        $data = $this->check($request, [
            'name' => 'required|string|max:150',
            'sku' => 'nullable|string|max:50',
            'company_id' => 'required|integer',
            'category_id' => 'required|integer',
            'unit_type' => 'required|string|max:30',
            'quantity_per_unit' => 'required|integer',
            'profit_margin' => 'required|numeric',
            'mrp' => 'nullable|numeric',
        ], ['company_id.required' => 'অনুগ্রহ করে কোম্পানি নির্বাচন করুন।', 'category_id.required' => 'অনুগ্রহ করে ক্যাটাগরি নির্বাচন করুন।']);

        $qpu = (int) $data['quantity_per_unit'];
        if ($qpu < 1 || $qpu > 100000) {
            throw new HttpError('প্রতি ইউনিটে পিস সংখ্যা কমপক্ষে ১ হতে হবে।', 422, ['quantity_per_unit' => ['কমপক্ষে ১ হতে হবে।']]);
        }
        $margin = (float) $data['profit_margin'];
        if ($margin < 0 || $margin > 999) {
            throw new HttpError('ডিলার মার্জিন ০ থেকে ৯৯৯%-এর মধ্যে হতে হবে।', 422, ['profit_margin' => ['সঠিক মার্জিন দিন।']]);
        }

        $mrp = ($data['mrp'] ?? '') === '' || $data['mrp'] === null ? null : round((float) $data['mrp'], 2);
        if ($mrp !== null && ($mrp <= 0 || $mrp > 9999999)) {
            throw new HttpError('MRP সঠিক দিন (প্রতি পিস)।', 422, ['mrp' => ['সঠিক MRP দিন।']]);
        }

        return [
            'name' => (string) $data['name'],
            'sku' => $data['sku'] ?: null,
            'company_id' => (int) $data['company_id'],
            'category_id' => (int) $data['category_id'],
            'unit_type' => (string) $data['unit_type'],
            'qty_per_unit' => $qpu,
            'dealer_margin' => round($margin, 2),
            'mrp' => $mrp,
        ];
    }

    private function storeImage(Request $request): ?string
    {
        $file = $request->file('image');
        if ($file === null || ($file['error'] ?? UPLOAD_ERR_NO_FILE) === UPLOAD_ERR_NO_FILE) {
            return null;
        }
        if ($file['error'] !== UPLOAD_ERR_OK || !is_uploaded_file($file['tmp_name'])) {
            throw new HttpError('Image upload failed. Please try again.', 422, ['image' => ['Upload failed.']]);
        }
        if ($file['size'] > self::MAX_IMAGE_BYTES) {
            throw new HttpError('Image must be 3 MB or smaller.', 422, ['image' => ['Too large.']]);
        }
        $info = @getimagesize($file['tmp_name']);
        $ext = self::IMAGE_TYPES[$info['mime'] ?? ''] ?? null;
        if ($ext === null) {
            throw new HttpError('Image must be a JPG, PNG or WebP file.', 422, ['image' => ['Unsupported type.']]);
        }

        $dir = base_path('public/uploads/products');
        if (!is_dir($dir) && !mkdir($dir, 0775, true) && !is_dir($dir)) {
            throw new HttpError('Could not save the image.', 500);
        }
        $name = bin2hex(random_bytes(12)) . '.' . $ext;
        if (!move_uploaded_file($file['tmp_name'], $dir . '/' . $name)) {
            throw new HttpError('Could not save the image.', 500);
        }

        return 'uploads/products/' . $name;
    }
}
