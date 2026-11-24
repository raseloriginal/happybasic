-- DSR monitoring: QR attendance (arrival), salary advances and salary payments.
-- Attendance is informational only; it does not change salary or advances.
USE `happybasic`;

ALTER TABLE `partners`
    ADD COLUMN `attendance_token` VARCHAR(64) NULL DEFAULT NULL,
    ADD COLUMN `office_lat` DECIMAL(10, 7) NULL DEFAULT NULL,
    ADD COLUMN `office_lng` DECIMAL(10, 7) NULL DEFAULT NULL,
    ADD COLUMN `office_radius_m` SMALLINT UNSIGNED NOT NULL DEFAULT 200,
    ADD COLUMN `duty_start` TIME NOT NULL DEFAULT '09:00:00',
    ADD UNIQUE KEY `uq_partners_attendance_token` (`attendance_token`);

CREATE TABLE IF NOT EXISTS `dsr_attendance` (
    `id` INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `partner_id` INT UNSIGNED NOT NULL,
    `dsr_id` INT UNSIGNED NOT NULL,
    `work_date` DATE NOT NULL,
    `checked_in_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `lat` DECIMAL(10, 7) NULL,
    `lng` DECIMAL(10, 7) NULL,
    `accuracy_m` INT UNSIGNED NULL,
    `distance_m` INT UNSIGNED NULL,
    `late_min` INT UNSIGNED NOT NULL DEFAULT 0,
    UNIQUE KEY `uq_dsr_attendance_day` (`dsr_id`, `work_date`),
    INDEX `idx_dsr_attendance_partner_day` (`partner_id`, `work_date`),
    CONSTRAINT `fk_dsr_attendance_partner` FOREIGN KEY (`partner_id`) REFERENCES `partners` (`id`) ON DELETE RESTRICT,
    CONSTRAINT `fk_dsr_attendance_dsr` FOREIGN KEY (`dsr_id`) REFERENCES `delivery_men` (`id`) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `dsr_advances` (
    `id` INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `partner_id` INT UNSIGNED NOT NULL,
    `dsr_id` INT UNSIGNED NOT NULL,
    `amount` DECIMAL(12, 2) NOT NULL,
    `given_on` DATE NOT NULL,
    `note` VARCHAR(255) NULL,
    `created_by` INT UNSIGNED NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX `idx_dsr_advances_dsr_date` (`dsr_id`, `given_on`),
    CONSTRAINT `fk_dsr_advances_partner` FOREIGN KEY (`partner_id`) REFERENCES `partners` (`id`) ON DELETE RESTRICT,
    CONSTRAINT `fk_dsr_advances_dsr` FOREIGN KEY (`dsr_id`) REFERENCES `delivery_men` (`id`) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `dsr_salary_payments` (
    `id` INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `partner_id` INT UNSIGNED NOT NULL,
    `dsr_id` INT UNSIGNED NOT NULL,
    `pay_month` CHAR(7) NOT NULL,
    `amount` DECIMAL(12, 2) NOT NULL,
    `paid_on` DATE NOT NULL,
    `note` VARCHAR(255) NULL,
    `created_by` INT UNSIGNED NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX `idx_dsr_salary_dsr_month` (`dsr_id`, `pay_month`),
    CONSTRAINT `fk_dsr_salary_partner` FOREIGN KEY (`partner_id`) REFERENCES `partners` (`id`) ON DELETE RESTRICT,
    CONSTRAINT `fk_dsr_salary_dsr` FOREIGN KEY (`dsr_id`) REFERENCES `delivery_men` (`id`) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
