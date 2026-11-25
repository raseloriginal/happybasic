-- Mobile app: push-notification device tokens and the downloadable APK releases.
USE `happybasic`;

CREATE TABLE IF NOT EXISTS `device_tokens` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    `user_id` INT UNSIGNED NOT NULL,
    `fcm_token` VARCHAR(255) NOT NULL,
    `platform` VARCHAR(20) NOT NULL DEFAULT 'android',
    `app_version` VARCHAR(20) NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY `uq_device_tokens_token` (`fcm_token`),
    INDEX `idx_device_tokens_user` (`user_id`),
    CONSTRAINT `fk_device_tokens_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `app_releases` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    `version_name` VARCHAR(20) NOT NULL,
    `version_code` INT UNSIGNED NOT NULL,
    `apk_path` VARCHAR(255) NOT NULL,
    `apk_size` INT UNSIGNED NOT NULL DEFAULT 0,
    `sha256` CHAR(64) NOT NULL,
    `notes` VARCHAR(500) NULL,
    `force_update` TINYINT(1) NOT NULL DEFAULT 0,
    `status` ENUM('active','inactive') NOT NULL DEFAULT 'active',
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY `uq_app_releases_code` (`version_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
