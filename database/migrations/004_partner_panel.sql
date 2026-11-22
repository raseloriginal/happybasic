-- Partner panel + SR ordering (additive only; no existing rows are changed).
USE `happybasic`;

ALTER TABLE `delivery_men` ADD COLUMN `deleted_at` TIMESTAMP NULL DEFAULT NULL AFTER `status`;
ALTER TABLE `products` ADD COLUMN `deleted_at` TIMESTAMP NULL DEFAULT NULL AFTER `status`;

-- One trip per DSR per delivery day
ALTER TABLE `trips` ADD UNIQUE KEY `uq_trips_dsr_date` (`dsr_id`, `trip_date`);

-- Ordered qty (from SR orders) next to the loaded qty (dispatched_pcs) on the trip checklist
ALTER TABLE `trip_van_stocks` ADD COLUMN `ordered_pcs` INT UNSIGNED NOT NULL DEFAULT 0 AFTER `product_id`;

-- SR marks a day's orders complete; only then can they be assigned to a trip
CREATE TABLE IF NOT EXISTS `sr_order_days` (
    `sr_id` INT UNSIGNED NOT NULL,
    `order_date` DATE NOT NULL,
    `completed_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`sr_id`, `order_date`),
    CONSTRAINT `fk_sr_order_days_sr` FOREIGN KEY (`sr_id`) REFERENCES `salesmen` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
