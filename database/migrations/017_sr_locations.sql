-- GPS points of SRs while on duty (mobile app), shown on the partner's live map. Kept 90 days like dsr_locations.
USE `happybasic`;

CREATE TABLE IF NOT EXISTS `sr_locations` (
    `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `partner_id` INT UNSIGNED NOT NULL,
    `sr_id` INT UNSIGNED NOT NULL,
    `recorded_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `lat` DECIMAL(10, 7) NOT NULL,
    `lng` DECIMAL(10, 7) NOT NULL,
    `accuracy_m` SMALLINT UNSIGNED NULL,
    `battery` TINYINT UNSIGNED NULL,
    UNIQUE KEY `uq_sr_locations_point` (`sr_id`, `recorded_at`),
    INDEX `idx_sr_locations_time` (`recorded_at`),
    CONSTRAINT `fk_sr_locations_partner` FOREIGN KEY (`partner_id`) REFERENCES `partners` (`id`) ON DELETE CASCADE,
    CONSTRAINT `fk_sr_locations_sr` FOREIGN KEY (`sr_id`) REFERENCES `salesmen` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
