-- Retailers are global: any partner's SR and DSR can see and sell to any shop. partner_id stays only as optional
-- information (NULL = not tied to a partner).
USE `happybasic`;

ALTER TABLE `retailers` MODIFY COLUMN `partner_id` INT UNSIGNED NULL;
ALTER TABLE `retailers` ADD INDEX `idx_retailers_status_geo` (`status`, `lat`, `lng`);
