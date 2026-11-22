-- Platform fee is set per partner+company connection (Platform Fees page), not on the global company.
ALTER TABLE `partner_companies`
    ADD COLUMN `platform_fee_per_lakh` DECIMAL(10, 2) NOT NULL DEFAULT 0.00 AFTER `partner_profit_share`;
UPDATE `partner_companies` pc JOIN `companies` c ON c.id = pc.company_id
    SET pc.platform_fee_per_lakh = c.platform_fee_per_lakh;
ALTER TABLE `companies` DROP COLUMN `platform_fee_per_lakh`;
