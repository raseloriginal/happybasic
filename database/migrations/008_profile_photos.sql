-- Profile photo for DSR and SR (shown on their own map pin).
USE `happybasic`;

ALTER TABLE `delivery_men` ADD COLUMN `photo_path` VARCHAR(255) NULL DEFAULT NULL AFTER `vehicle_no`;
ALTER TABLE `salesmen` ADD COLUMN `photo_path` VARCHAR(255) NULL DEFAULT NULL AFTER `area`;
