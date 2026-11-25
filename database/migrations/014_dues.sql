-- Partner due page: review of each unpaid order, plus money collected / goods taken back later.
USE `happybasic`;

ALTER TABLE `partners`
    ADD COLUMN `due_limit` DECIMAL(12, 2) NOT NULL DEFAULT 3000.00,
    ADD COLUMN `due_days` SMALLINT UNSIGNED NOT NULL DEFAULT 7;

CREATE TABLE IF NOT EXISTS `due_limits` (
    `partner_id` INT UNSIGNED NOT NULL,
    `retailer_id` INT UNSIGNED NOT NULL,
    `amount` DECIMAL(12, 2) NOT NULL,
    PRIMARY KEY (`partner_id`, `retailer_id`),
    CONSTRAINT `fk_due_limits_partner` FOREIGN KEY (`partner_id`) REFERENCES `partners` (`id`) ON DELETE CASCADE,
    CONSTRAINT `fk_due_limits_retailer` FOREIGN KEY (`retailer_id`) REFERENCES `retailers` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Approval holds for exactly this amount: if the DSR changes the due afterwards it needs approval again
CREATE TABLE IF NOT EXISTS `due_approvals` (
    `order_id` INT UNSIGNED NOT NULL PRIMARY KEY,
    `amount` DECIMAL(12, 2) NOT NULL,
    `approved_by` INT UNSIGNED NULL,
    `approved_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT `fk_due_approvals_order` FOREIGN KEY (`order_id`) REFERENCES `orders` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `due_entries` (
    `id` INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `partner_id` INT UNSIGNED NOT NULL,
    `order_id` INT UNSIGNED NOT NULL,
    `kind` ENUM('collect', 'return') NOT NULL,
    `amount` DECIMAL(12, 2) NOT NULL,
    `sr_oc` DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
    `detail_json` TEXT NULL,
    `created_by` INT UNSIGNED NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX `idx_due_entries_order` (`order_id`),
    INDEX `idx_due_entries_partner_time` (`partner_id`, `created_at`),
    CONSTRAINT `fk_due_entries_partner` FOREIGN KEY (`partner_id`) REFERENCES `partners` (`id`) ON DELETE RESTRICT,
    CONSTRAINT `fk_due_entries_order` FOREIGN KEY (`order_id`) REFERENCES `orders` (`id`) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
