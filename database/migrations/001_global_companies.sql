-- Companies become global; partner links move to partner_companies (created via SR assignment).
ALTER TABLE `companies` DROP FOREIGN KEY `fk_companies_partner`, DROP FOREIGN KEY `fk_companies_dealer`;
ALTER TABLE `companies` DROP INDEX `idx_companies_partner_status`,
    DROP COLUMN `partner_id`, DROP COLUMN `ownership`, DROP COLUMN `dealer_id`,
    DROP COLUMN `dealer_profit_share`, DROP COLUMN `partner_profit_share`,
    ADD INDEX `idx_companies_status` (`status`);
CREATE TABLE IF NOT EXISTS `partner_companies` (
    `id` INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `partner_id` INT UNSIGNED NOT NULL,
    `company_id` INT UNSIGNED NOT NULL,
    `ownership` ENUM('owned', 'dealer') NOT NULL DEFAULT 'owned',
    `dealer_id` INT UNSIGNED NULL,
    `dealer_profit_share` DECIMAL(5, 2) NULL,
    `partner_profit_share` DECIMAL(5, 2) NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY `uq_partner_company` (`partner_id`, `company_id`),
    INDEX `idx_partner_companies_company` (`company_id`),
    CONSTRAINT `fk_pc_partner` FOREIGN KEY (`partner_id`) REFERENCES `partners` (`id`) ON DELETE RESTRICT,
    CONSTRAINT `fk_pc_company` FOREIGN KEY (`company_id`) REFERENCES `companies` (`id`) ON DELETE RESTRICT,
    CONSTRAINT `fk_pc_dealer` FOREIGN KEY (`dealer_id`) REFERENCES `dealers` (`id`) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
