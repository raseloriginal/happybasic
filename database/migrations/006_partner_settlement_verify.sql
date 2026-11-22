-- Partner settlement verification: DSR note, partner-counted cash & verified damage.
USE `happybasic`;

ALTER TABLE `trip_settlements`
    ADD COLUMN `dsr_note` VARCHAR(255) NULL AFTER `cash_notes_json`,
    ADD COLUMN `partner_cash_received` DECIMAL(14, 2) NULL AFTER `dsr_note`,
    ADD COLUMN `partner_cash_diff` DECIMAL(14, 2) NULL AFTER `partner_cash_received`,
    ADD COLUMN `partner_damage_amount` DECIMAL(12, 2) NULL AFTER `partner_cash_diff`,
    ADD COLUMN `partner_damage_note` VARCHAR(255) NULL AFTER `partner_damage_amount`;
