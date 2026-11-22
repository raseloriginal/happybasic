-- Fee changes never rewrite the past: every change is a new history row (effective from that moment),
-- and each order freezes the rate it was created under (orders.platform_fee_rate).
CREATE TABLE IF NOT EXISTS `platform_fee_history` (
    `id` INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `partner_id` INT UNSIGNED NOT NULL,
    `company_id` INT UNSIGNED NOT NULL,
    `fee_per_lakh` DECIMAL(10, 2) NOT NULL,
    `effective_from` DATETIME NOT NULL,
    `changed_by` INT UNSIGNED NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX `idx_pfh_lookup` (`partner_id`, `company_id`, `effective_from`),
    CONSTRAINT `fk_pfh_partner` FOREIGN KEY (`partner_id`) REFERENCES `partners` (`id`) ON DELETE RESTRICT,
    CONSTRAINT `fk_pfh_company` FOREIGN KEY (`company_id`) REFERENCES `companies` (`id`) ON DELETE RESTRICT,
    CONSTRAINT `fk_pfh_user` FOREIGN KEY (`changed_by`) REFERENCES `users` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
INSERT INTO `platform_fee_history` (partner_id, company_id, fee_per_lakh, effective_from)
    SELECT partner_id, company_id, platform_fee_per_lakh, updated_at FROM partner_companies WHERE platform_fee_per_lakh > 0;
ALTER TABLE `orders`
    ADD COLUMN `platform_fee_rate` DECIMAL(10, 2) NULL COMMENT 'Fee per lakh frozen when the order was created' AFTER `due_amount`;
