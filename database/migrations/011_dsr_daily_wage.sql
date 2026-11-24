-- DSR wage model: daily wage x attendance (present = 1, half day = 0.5), partner can set a day manually,
-- plus short / over (bonus) adjustments next to advances and salary payments.
USE `happybasic`;

ALTER TABLE `delivery_men`
    ADD COLUMN `daily_wage` DECIMAL(12, 2) NOT NULL DEFAULT 0.00 AFTER `salary`;

ALTER TABLE `dsr_attendance`
    MODIFY COLUMN `checked_in_at` TIMESTAMP NULL DEFAULT NULL,
    ADD COLUMN `status` ENUM('present', 'half', 'absent', 'holiday') NOT NULL DEFAULT 'present' AFTER `work_date`,
    ADD COLUMN `source` ENUM('qr', 'manual') NOT NULL DEFAULT 'qr' AFTER `status`;

CREATE TABLE IF NOT EXISTS `dsr_adjustments` (
    `id` INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `partner_id` INT UNSIGNED NOT NULL,
    `dsr_id` INT UNSIGNED NOT NULL,
    `kind` ENUM('short', 'over') NOT NULL,
    `amount` DECIMAL(12, 2) NOT NULL,
    `adj_date` DATE NOT NULL,
    `note` VARCHAR(255) NULL,
    `created_by` INT UNSIGNED NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX `idx_dsr_adjustments_dsr_date` (`dsr_id`, `adj_date`),
    CONSTRAINT `fk_dsr_adjustments_partner` FOREIGN KEY (`partner_id`) REFERENCES `partners` (`id`) ON DELETE RESTRICT,
    CONSTRAINT `fk_dsr_adjustments_dsr` FOREIGN KEY (`dsr_id`) REFERENCES `delivery_men` (`id`) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
