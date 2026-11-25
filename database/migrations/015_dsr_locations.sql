-- GPS points of DSRs while on duty (live map and route history for the partner). Kept 90 days.
USE `happybasic`;

CREATE TABLE IF NOT EXISTS `dsr_locations` (
    `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `partner_id` INT UNSIGNED NOT NULL,
    `dsr_id` INT UNSIGNED NOT NULL,
    `recorded_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `lat` DECIMAL(10, 7) NOT NULL,
    `lng` DECIMAL(10, 7) NOT NULL,
    `accuracy_m` SMALLINT UNSIGNED NULL,
    `battery` TINYINT UNSIGNED NULL,
    UNIQUE KEY `uq_dsr_locations_point` (`dsr_id`, `recorded_at`),
    INDEX `idx_dsr_locations_time` (`recorded_at`),
    CONSTRAINT `fk_dsr_locations_partner` FOREIGN KEY (`partner_id`) REFERENCES `partners` (`id`) ON DELETE CASCADE,
    CONSTRAINT `fk_dsr_locations_dsr` FOREIGN KEY (`dsr_id`) REFERENCES `delivery_men` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
