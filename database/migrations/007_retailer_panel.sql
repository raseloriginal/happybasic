-- Retailer panel: retailer login (phone + password = phone), MRP on products, notification marker.
USE `happybasic`;

ALTER TABLE `users`
    MODIFY COLUMN `role` ENUM('admin', 'partner', 'dealer', 'sr', 'dsr', 'retailer') NOT NULL DEFAULT 'partner',
    ADD COLUMN `notif_seen_at` TIMESTAMP NULL DEFAULT NULL AFTER `status`;

-- MRP per piece (set by the partner on the product); frozen on each order line.
ALTER TABLE `products` ADD COLUMN `mrp` DECIMAL(12, 2) NULL DEFAULT NULL AFTER `base_price`;
ALTER TABLE `order_items` ADD COLUMN `mrp_pc` DECIMAL(12, 4) NULL DEFAULT NULL AFTER `sr_rate_pc`;

-- Orders placed before MRP existed keep mrp_pc NULL (no profit line is shown for them).
