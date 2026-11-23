-- Offline sync: every write the DSR app queues offline carries a unique op id (X-Op-Id).
-- The server stores the result, so a retried/duplicated op is answered from here instead of running twice.
USE `happybasic`;

CREATE TABLE IF NOT EXISTS `offline_ops` (
    `op_id` VARCHAR(64) NOT NULL PRIMARY KEY,
    `user_id` INT UNSIGNED NOT NULL,
    `path` VARCHAR(190) NOT NULL,
    `status_code` SMALLINT UNSIGNED NOT NULL,
    `response` MEDIUMTEXT NOT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX `idx_offline_ops_created` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
