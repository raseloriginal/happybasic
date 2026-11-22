-- HappyBasic Database Schema (Basic Core)
-- Engine: MySQL 8+ / MariaDB 10.4+ (XAMPP compatible)

CREATE DATABASE IF NOT EXISTS `happybasic`
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

USE `happybasic`;

-- ============================================================================
-- 1. AUTH & SYSTEM
-- ============================================================================

CREATE TABLE IF NOT EXISTS `users` (
    `id` INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `name` VARCHAR(100) NOT NULL,
    `email` VARCHAR(191) NULL UNIQUE,
    `phone` VARCHAR(30) NULL UNIQUE,
    `password` VARCHAR(255) NOT NULL,
    `role` ENUM('admin', 'partner', 'dealer', 'sr', 'dsr', 'retailer') NOT NULL DEFAULT 'partner',
    `status` ENUM('active', 'pending', 'inactive') NOT NULL DEFAULT 'active',
    `notif_seen_at` TIMESTAMP NULL DEFAULT NULL,
    `deleted_at` TIMESTAMP NULL DEFAULT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX `idx_users_role_status` (`role`, `status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `user_sessions` (
    `id` INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `user_id` INT UNSIGNED NOT NULL,
    `session_token` VARCHAR(128) NOT NULL UNIQUE,
    `device` VARCHAR(150) NULL,
    `ip_address` VARCHAR(45) NULL,
    `location` VARCHAR(100) NULL,
    `user_agent` VARCHAR(255) NULL,
    `last_active_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `expires_at` TIMESTAMP NULL DEFAULT NULL,
    `revoked_at` TIMESTAMP NULL DEFAULT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX `idx_user_sessions_user` (`user_id`, `revoked_at`),
    CONSTRAINT `fk_user_sessions_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `activity_logs` (
    `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `user_id` INT UNSIGNED NULL,
    `action` VARCHAR(50) NOT NULL,
    `module` VARCHAR(50) NOT NULL,
    `detail` VARCHAR(255) NOT NULL,
    `ip_address` VARCHAR(45) NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX `idx_activity_logs_module_time` (`module`, `created_at`),
    CONSTRAINT `fk_activity_logs_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================================
-- 2. MASTER ENTITIES (PARTNERS, DEALERS, COMPANIES, SR, DSR, RETAILERS)
-- ============================================================================

-- Distribution zones managed from Admin > Settings > Areas
CREATE TABLE IF NOT EXISTS `areas` (
    `id` INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `name` VARCHAR(100) NOT NULL UNIQUE,
    `status` ENUM('active', 'inactive') NOT NULL DEFAULT 'active',
    `deleted_at` TIMESTAMP NULL DEFAULT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `partners` (
    `id` INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `user_id` INT UNSIGNED NOT NULL UNIQUE,
    `area_id` INT UNSIGNED NOT NULL,
    `name` VARCHAR(150) NOT NULL,
    `phone` VARCHAR(30) NOT NULL,
    `tin` VARCHAR(50) NULL,
    `trade_license` VARCHAR(100) NULL,
    `nid` VARCHAR(50) NULL,
    `address` VARCHAR(255) NULL,
    `status` ENUM('active', 'pending', 'inactive') NOT NULL DEFAULT 'active',
    `deleted_at` TIMESTAMP NULL DEFAULT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX `idx_partners_area_status` (`area_id`, `status`),
    CONSTRAINT `fk_partners_area` FOREIGN KEY (`area_id`) REFERENCES `areas` (`id`) ON DELETE RESTRICT,
    CONSTRAINT `fk_partners_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `dealers` (
    `id` INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `partner_id` INT UNSIGNED NOT NULL,
    `user_id` INT UNSIGNED NOT NULL UNIQUE,
    `name` VARCHAR(150) NOT NULL,
    `phone` VARCHAR(30) NOT NULL,
    `tin` VARCHAR(50) NULL,
    `trade_license` VARCHAR(100) NULL,
    `nid` VARCHAR(50) NULL,
    `address` VARCHAR(255) NULL,
    `status` ENUM('active', 'inactive') NOT NULL DEFAULT 'active',
    `deleted_at` TIMESTAMP NULL DEFAULT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX `idx_dealers_partner_status` (`partner_id`, `status`),
    CONSTRAINT `fk_dealers_partner` FOREIGN KEY (`partner_id`) REFERENCES `partners` (`id`) ON DELETE RESTRICT,
    CONSTRAINT `fk_dealers_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Global company catalog (shared by all partners). A partner gets linked to a company
-- automatically when an SR is assigned (see partner_companies).
CREATE TABLE IF NOT EXISTS `companies` (
    `id` INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `name` VARCHAR(150) NOT NULL,
    `status` ENUM('active', 'inactive') NOT NULL DEFAULT 'active',
    `deleted_at` TIMESTAMP NULL DEFAULT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX `idx_companies_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Partner <-> Company connection, created when an SR is added.
-- ownership = owned  -> partner chosen directly
-- ownership = dealer -> partner derived from the dealer; profit shares live here
CREATE TABLE IF NOT EXISTS `partner_companies` (
    `id` INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `partner_id` INT UNSIGNED NOT NULL,
    `company_id` INT UNSIGNED NOT NULL,
    `ownership` ENUM('owned', 'dealer') NOT NULL DEFAULT 'owned',
    `dealer_id` INT UNSIGNED NULL,
    `dealer_profit_share` DECIMAL(5, 2) NULL,
    `partner_profit_share` DECIMAL(5, 2) NULL,
    `platform_fee_per_lakh` DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY `uq_partner_company` (`partner_id`, `company_id`),
    INDEX `idx_partner_companies_company` (`company_id`),
    CONSTRAINT `fk_pc_partner` FOREIGN KEY (`partner_id`) REFERENCES `partners` (`id`) ON DELETE RESTRICT,
    CONSTRAINT `fk_pc_company` FOREIGN KEY (`company_id`) REFERENCES `companies` (`id`) ON DELETE RESTRICT,
    CONSTRAINT `fk_pc_dealer` FOREIGN KEY (`dealer_id`) REFERENCES `dealers` (`id`) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Append-only fee changes; the row with the latest effective_from <= a moment is the rate then.
CREATE TABLE IF NOT EXISTS `platform_fee_history` (
    `id` INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `partner_id` INT UNSIGNED NOT NULL,
    `company_id` INT UNSIGNED NOT NULL,
    `fee_per_lakh` DECIMAL(10, 2) NOT NULL,
    `effective_from` DATETIME NOT NULL,
    `changed_by` INT UNSIGNED NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX `idx_pfh_lookup` (`partner_id`, `company_id`, `effective_from`),
    CONSTRAINT `fk_pfh_partner` FOREIGN KEY (`partner_id`) REFERENCES `partners` (`id`) ON DELETE RESTRICT,
    CONSTRAINT `fk_pfh_company` FOREIGN KEY (`company_id`) REFERENCES `companies` (`id`) ON DELETE RESTRICT,
    CONSTRAINT `fk_pfh_user` FOREIGN KEY (`changed_by`) REFERENCES `users` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 1 SR is strictly assigned to 1 Company (multiple SRs can belong to the same Company)
CREATE TABLE IF NOT EXISTS `salesmen` (
    `id` INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `partner_id` INT UNSIGNED NOT NULL,
    `company_id` INT UNSIGNED NOT NULL,
    `user_id` INT UNSIGNED NOT NULL UNIQUE,
    `code` VARCHAR(30) NULL UNIQUE,
    `name` VARCHAR(120) NOT NULL,
    `phone` VARCHAR(30) NOT NULL,
    `area` VARCHAR(120) NULL,
    `photo_path` VARCHAR(255) NULL DEFAULT NULL,
    `daily_target` DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
    `monthly_target` DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
    `oc_balance` DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
    `joining_date` DATE NULL,
    `status` ENUM('active', 'inactive') NOT NULL DEFAULT 'active',
    `deleted_at` TIMESTAMP NULL DEFAULT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX `idx_salesmen_partner_company` (`partner_id`, `company_id`, `status`),
    CONSTRAINT `fk_salesmen_partner` FOREIGN KEY (`partner_id`) REFERENCES `partners` (`id`) ON DELETE RESTRICT,
    CONSTRAINT `fk_salesmen_company` FOREIGN KEY (`company_id`) REFERENCES `companies` (`id`) ON DELETE RESTRICT,
    CONSTRAINT `fk_salesmen_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- SR marks a day's orders complete; only then can they be assigned to a trip
CREATE TABLE IF NOT EXISTS `sr_order_days` (
    `sr_id` INT UNSIGNED NOT NULL,
    `order_date` DATE NOT NULL,
    `completed_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`sr_id`, `order_date`),
    CONSTRAINT `fk_sr_order_days_sr` FOREIGN KEY (`sr_id`) REFERENCES `salesmen` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `delivery_men` (
    `id` INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `partner_id` INT UNSIGNED NOT NULL,
    `user_id` INT UNSIGNED NOT NULL UNIQUE,
    `code` VARCHAR(30) NULL UNIQUE,
    `name` VARCHAR(120) NOT NULL,
    `phone` VARCHAR(30) NOT NULL,
    `zone` VARCHAR(100) NULL,
    `vehicle_no` VARCHAR(60) NULL,
    `photo_path` VARCHAR(255) NULL DEFAULT NULL,
    `salary` DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
    `status` ENUM('active', 'inactive') NOT NULL DEFAULT 'active',
    `deleted_at` TIMESTAMP NULL DEFAULT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX `idx_delivery_men_partner_status` (`partner_id`, `status`),
    CONSTRAINT `fk_delivery_men_partner` FOREIGN KEY (`partner_id`) REFERENCES `partners` (`id`) ON DELETE RESTRICT,
    CONSTRAINT `fk_delivery_men_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `retailers` (
    `id` INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `partner_id` INT UNSIGNED NOT NULL,
    `created_by_sr_id` INT UNSIGNED NULL,
    `name` VARCHAR(150) NOT NULL,
    `phone` VARCHAR(30) NULL,
    `address` VARCHAR(255) NOT NULL,
    `lat` DECIMAL(10, 7) NOT NULL,
    `lng` DECIMAL(10, 7) NOT NULL,
    `due_balance` DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
    `status` ENUM('active', 'inactive') NOT NULL DEFAULT 'active',
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX `idx_retailers_partner_geo` (`partner_id`, `lat`, `lng`),
    CONSTRAINT `fk_retailers_partner` FOREIGN KEY (`partner_id`) REFERENCES `partners` (`id`) ON DELETE RESTRICT,
    CONSTRAINT `fk_retailers_sr` FOREIGN KEY (`created_by_sr_id`) REFERENCES `salesmen` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================================
-- 3. CATALOG & FIFO LOT INVENTORY
-- ============================================================================

CREATE TABLE IF NOT EXISTS `categories` (
    `id` INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `name` VARCHAR(120) NOT NULL,
    `slug` VARCHAR(140) NOT NULL UNIQUE,
    `status` ENUM('active', 'inactive') NOT NULL DEFAULT 'active',
    `deleted_at` TIMESTAMP NULL DEFAULT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Base Price (Dealer Price) = company_price + dealer_margin
CREATE TABLE IF NOT EXISTS `products` (
    `id` INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `partner_id` INT UNSIGNED NOT NULL,
    `company_id` INT UNSIGNED NOT NULL,
    `category_id` INT UNSIGNED NOT NULL,
    `sku` VARCHAR(50) NULL,
    `name` VARCHAR(150) NOT NULL,
    `image_path` VARCHAR(255) NULL,
    `unit_type` VARCHAR(30) NOT NULL DEFAULT 'Carton',
    `qty_per_unit` INT UNSIGNED NOT NULL DEFAULT 1,
    `company_price` DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
    `dealer_margin` DECIMAL(5, 2) NOT NULL DEFAULT 0.00,
    `base_price` DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
    `mrp` DECIMAL(12, 2) NULL DEFAULT NULL,
    `stock_pcs` INT UNSIGNED NOT NULL DEFAULT 0,
    `status` ENUM('active', 'inactive') NOT NULL DEFAULT 'active',
    `deleted_at` TIMESTAMP NULL DEFAULT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX `idx_products_partner_company` (`partner_id`, `company_id`, `status`),
    CONSTRAINT `fk_products_partner` FOREIGN KEY (`partner_id`) REFERENCES `partners` (`id`) ON DELETE RESTRICT,
    CONSTRAINT `fk_products_company` FOREIGN KEY (`company_id`) REFERENCES `companies` (`id`) ON DELETE RESTRICT,
    CONSTRAINT `fk_products_category` FOREIGN KEY (`category_id`) REFERENCES `categories` (`id`) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `lots` (
    `id` INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `partner_id` INT UNSIGNED NOT NULL,
    `company_id` INT UNSIGNED NOT NULL,
    `lot_code` VARCHAR(50) NOT NULL UNIQUE,
    `received_date` DATE NOT NULL,
    `total_value` DECIMAL(14, 2) NOT NULL DEFAULT 0.00,
    `notes` VARCHAR(255) NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX `idx_lots_partner_company_date` (`partner_id`, `company_id`, `received_date`),
    CONSTRAINT `fk_lots_partner` FOREIGN KEY (`partner_id`) REFERENCES `partners` (`id`) ON DELETE RESTRICT,
    CONSTRAINT `fk_lots_company` FOREIGN KEY (`company_id`) REFERENCES `companies` (`id`) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- FIFO stock tracking: consume rows ordered by (received_date, id) where remaining_pcs > 0
CREATE TABLE IF NOT EXISTS `lot_items` (
    `id` INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `lot_id` INT UNSIGNED NOT NULL,
    `product_id` INT UNSIGNED NOT NULL,
    `qty_units` INT UNSIGNED NOT NULL,
    `qty_pcs` INT UNSIGNED NOT NULL,
    `remaining_pcs` INT UNSIGNED NOT NULL,
    `company_price` DECIMAL(12, 2) NOT NULL,
    `company_price_per_pc` DECIMAL(12, 4) NOT NULL,
    `expire_date` DATE NOT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX `idx_lot_items_fifo` (`product_id`, `remaining_pcs`, `id`),
    CONSTRAINT `fk_lot_items_lot` FOREIGN KEY (`lot_id`) REFERENCES `lots` (`id`) ON DELETE CASCADE,
    CONSTRAINT `fk_lot_items_product` FOREIGN KEY (`product_id`) REFERENCES `products` (`id`) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================================
-- 4. TRIPS & VAN STOCK
-- ============================================================================

CREATE TABLE IF NOT EXISTS `trips` (
    `id` INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `trip_code` VARCHAR(40) NOT NULL UNIQUE,
    `partner_id` INT UNSIGNED NOT NULL,
    `dsr_id` INT UNSIGNED NOT NULL,
    `trip_date` DATE NOT NULL,
    `zone` VARCHAR(100) NULL,
    `status` ENUM('pending', 'dispatched', 'in_review', 'settled') NOT NULL DEFAULT 'pending',
    `dispatched_at` TIMESTAMP NULL DEFAULT NULL,
    `settled_at` TIMESTAMP NULL DEFAULT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX `idx_trips_partner_date_status` (`partner_id`, `trip_date`, `status`),    UNIQUE KEY `uq_trips_dsr_date` (`dsr_id`, `trip_date`),
    CONSTRAINT `fk_trips_partner` FOREIGN KEY (`partner_id`) REFERENCES `partners` (`id`) ON DELETE RESTRICT,
    CONSTRAINT `fk_trips_dsr` FOREIGN KEY (`dsr_id`) REFERENCES `delivery_men` (`id`) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- SRs assigned to a DSR trip (DSR sees only orders from these SRs)
CREATE TABLE IF NOT EXISTS `trip_srs` (
    `trip_id` INT UNSIGNED NOT NULL,
    `sr_id` INT UNSIGNED NOT NULL,
    PRIMARY KEY (`trip_id`, `sr_id`),
    CONSTRAINT `fk_trip_srs_trip` FOREIGN KEY (`trip_id`) REFERENCES `trips` (`id`) ON DELETE CASCADE,
    CONSTRAINT `fk_trip_srs_sr` FOREIGN KEY (`sr_id`) REFERENCES `salesmen` (`id`) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `trip_van_stocks` (
    `id` INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `trip_id` INT UNSIGNED NOT NULL,
    `product_id` INT UNSIGNED NOT NULL,
    `ordered_pcs` INT UNSIGNED NOT NULL DEFAULT 0,
    `dispatched_pcs` INT UNSIGNED NOT NULL DEFAULT 0,
    `delivered_pcs` INT UNSIGNED NOT NULL DEFAULT 0,
    `ready_sale_pcs` INT UNSIGNED NOT NULL DEFAULT 0,
    `returned_pcs` INT UNSIGNED NOT NULL DEFAULT 0,
    `base_rate_pc` DECIMAL(12, 4) NOT NULL,
    `is_checked` TINYINT(1) NOT NULL DEFAULT 0,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY `uq_trip_van_product` (`trip_id`, `product_id`),
    CONSTRAINT `fk_trip_van_trip` FOREIGN KEY (`trip_id`) REFERENCES `trips` (`id`) ON DELETE CASCADE,
    CONSTRAINT `fk_trip_van_product` FOREIGN KEY (`product_id`) REFERENCES `products` (`id`) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Links dispatched van stock to exact FIFO lot_items for accurate COGS and return restoration
CREATE TABLE IF NOT EXISTS `trip_stock_allocations` (
    `id` INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `trip_id` INT UNSIGNED NOT NULL,
    `lot_item_id` INT UNSIGNED NOT NULL,
    `product_id` INT UNSIGNED NOT NULL,
    `dispatched_pcs` INT UNSIGNED NOT NULL,
    `sold_pcs` INT UNSIGNED NOT NULL DEFAULT 0,
    `returned_pcs` INT UNSIGNED NOT NULL DEFAULT 0,
    `company_price_per_pc` DECIMAL(12, 4) NOT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX `idx_trip_alloc_trip_prod` (`trip_id`, `product_id`),
    CONSTRAINT `fk_trip_alloc_trip` FOREIGN KEY (`trip_id`) REFERENCES `trips` (`id`) ON DELETE CASCADE,
    CONSTRAINT `fk_trip_alloc_lot_item` FOREIGN KEY (`lot_item_id`) REFERENCES `lot_items` (`id`) ON DELETE RESTRICT,
    CONSTRAINT `fk_trip_alloc_product` FOREIGN KEY (`product_id`) REFERENCES `products` (`id`) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================================
-- 5. ORDERS & DELIVERY EXECUTION
-- ============================================================================

-- One order = 1 Company + 1 Retailer (+ 1 SR, or NULL SR when is_ready_sale = 1 at base price)
CREATE TABLE IF NOT EXISTS `orders` (
    `id` INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `order_code` VARCHAR(40) NOT NULL UNIQUE,
    `partner_id` INT UNSIGNED NOT NULL,
    `company_id` INT UNSIGNED NOT NULL,
    `sr_id` INT UNSIGNED NULL,
    `retailer_id` INT UNSIGNED NULL,
    `retailer_name_snapshot` VARCHAR(150) NOT NULL,
    `trip_id` INT UNSIGNED NULL,
    `order_date` DATE NOT NULL,
    `is_ready_sale` TINYINT(1) NOT NULL DEFAULT 0,
    `order_base_total` DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
    `order_sr_total` DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
    `order_oc` DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
    `delivered_base_total` DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
    `delivered_sr_total` DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
    `delivery_oc` DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
    `damage_amount` DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
    `paid_amount` DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
    `due_amount` DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
    `platform_fee_rate` DECIMAL(10, 2) NULL COMMENT 'Fee per lakh frozen when the order was created',
    `platform_fee_amount` DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
    `status` ENUM('pending', 'assigned', 'delivered', 'due', 'partial', 'cancelled') NOT NULL DEFAULT 'pending',
    `cancel_reason` VARCHAR(255) NULL,
    `notes` VARCHAR(255) NULL,
    `delivered_at` TIMESTAMP NULL DEFAULT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX `idx_orders_partner_date_status` (`partner_id`, `order_date`, `status`),
    INDEX `idx_orders_trip_retailer` (`trip_id`, `retailer_id`),
    INDEX `idx_orders_sr_date` (`sr_id`, `order_date`),
    CONSTRAINT `fk_orders_partner` FOREIGN KEY (`partner_id`) REFERENCES `partners` (`id`) ON DELETE RESTRICT,
    CONSTRAINT `fk_orders_company` FOREIGN KEY (`company_id`) REFERENCES `companies` (`id`) ON DELETE RESTRICT,
    CONSTRAINT `fk_orders_sr` FOREIGN KEY (`sr_id`) REFERENCES `salesmen` (`id`) ON DELETE SET NULL,
    CONSTRAINT `fk_orders_retailer` FOREIGN KEY (`retailer_id`) REFERENCES `retailers` (`id`) ON DELETE SET NULL,
    CONSTRAINT `fk_orders_trip` FOREIGN KEY (`trip_id`) REFERENCES `trips` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `order_items` (
    `id` INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `order_id` INT UNSIGNED NOT NULL,
    `product_id` INT UNSIGNED NOT NULL,
    `ordered_pcs` INT UNSIGNED NOT NULL,
    `delivered_pcs` INT UNSIGNED NOT NULL DEFAULT 0,
    `base_rate_pc` DECIMAL(12, 4) NOT NULL,
    `sr_rate_pc` DECIMAL(12, 4) NOT NULL,
    `mrp_pc` DECIMAL(12, 4) NULL DEFAULT NULL,
    `order_oc` DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
    `delivery_oc` DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
    `fifo_cost_total` DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX `idx_order_items_order` (`order_id`),
    CONSTRAINT `fk_order_items_order` FOREIGN KEY (`order_id`) REFERENCES `orders` (`id`) ON DELETE CASCADE,
    CONSTRAINT `fk_order_items_product` FOREIGN KEY (`product_id`) REFERENCES `products` (`id`) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Damaged items collected from retailers at delivery (deducted from retailer bill; Company bears cost)
CREATE TABLE IF NOT EXISTS `delivery_damages` (
    `id` INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `trip_id` INT UNSIGNED NOT NULL,
    `order_id` INT UNSIGNED NULL,
    `retailer_id` INT UNSIGNED NOT NULL,
    `company_id` INT UNSIGNED NOT NULL,
    `product_id` INT UNSIGNED NOT NULL,
    `qty_pcs` INT UNSIGNED NOT NULL,
    `amount` DECIMAL(12, 2) NOT NULL,
    `note` VARCHAR(255) NULL,
    `claimed_to_company` TINYINT(1) NOT NULL DEFAULT 0,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX `idx_delivery_damages_trip` (`trip_id`),
    INDEX `idx_delivery_damages_company_claim` (`company_id`, `claimed_to_company`),
    CONSTRAINT `fk_delivery_damages_trip` FOREIGN KEY (`trip_id`) REFERENCES `trips` (`id`) ON DELETE CASCADE,
    CONSTRAINT `fk_delivery_damages_order` FOREIGN KEY (`order_id`) REFERENCES `orders` (`id`) ON DELETE SET NULL,
    CONSTRAINT `fk_delivery_damages_retailer` FOREIGN KEY (`retailer_id`) REFERENCES `retailers` (`id`) ON DELETE RESTRICT,
    CONSTRAINT `fk_delivery_damages_company` FOREIGN KEY (`company_id`) REFERENCES `companies` (`id`) ON DELETE RESTRICT,
    CONSTRAINT `fk_delivery_damages_product` FOREIGN KEY (`product_id`) REFERENCES `products` (`id`) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Prior retailer dues collected by DSR during a trip
CREATE TABLE IF NOT EXISTS `retailer_due_collections` (
    `id` INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `trip_id` INT UNSIGNED NOT NULL,
    `retailer_id` INT UNSIGNED NOT NULL,
    `order_id` INT UNSIGNED NULL,
    `amount` DECIMAL(12, 2) NOT NULL,
    `note` VARCHAR(255) NULL,
    `collected_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX `idx_due_collections_trip_retailer` (`trip_id`, `retailer_id`),
    CONSTRAINT `fk_due_collections_trip` FOREIGN KEY (`trip_id`) REFERENCES `trips` (`id`) ON DELETE CASCADE,
    CONSTRAINT `fk_due_collections_retailer` FOREIGN KEY (`retailer_id`) REFERENCES `retailers` (`id`) ON DELETE RESTRICT,
    CONSTRAINT `fk_due_collections_order` FOREIGN KEY (`order_id`) REFERENCES `orders` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `trip_expenses` (
    `id` INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `trip_id` INT UNSIGNED NOT NULL,
    `dsr_id` INT UNSIGNED NOT NULL,
    `title` VARCHAR(150) NOT NULL,
    `category` VARCHAR(50) NOT NULL,
    `amount` DECIMAL(12, 2) NOT NULL,
    `note` VARCHAR(255) NULL,
    `expense_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX `idx_trip_expenses_trip` (`trip_id`),
    CONSTRAINT `fk_trip_expenses_trip` FOREIGN KEY (`trip_id`) REFERENCES `trips` (`id`) ON DELETE CASCADE,
    CONSTRAINT `fk_trip_expenses_dsr` FOREIGN KEY (`dsr_id`) REFERENCES `delivery_men` (`id`) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================================
-- 6. SETTLEMENTS & LEDGERS
-- ============================================================================

-- Net Payable = (delivered_sr_total + ready_sale_total + prior_due_collected) - damage_total - expense_total - new_due_total
CREATE TABLE IF NOT EXISTS `trip_settlements` (
    `id` INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `trip_id` INT UNSIGNED NOT NULL UNIQUE,
    `total_load_base` DECIMAL(14, 2) NOT NULL DEFAULT 0.00,
    `return_base` DECIMAL(14, 2) NOT NULL DEFAULT 0.00,
    `delivered_base_total` DECIMAL(14, 2) NOT NULL DEFAULT 0.00,
    `delivered_sr_total` DECIMAL(14, 2) NOT NULL DEFAULT 0.00,
    `ready_sale_total` DECIMAL(14, 2) NOT NULL DEFAULT 0.00,
    `prior_due_collected` DECIMAL(14, 2) NOT NULL DEFAULT 0.00,
    `delivery_oc_total` DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
    `damage_total` DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
    `expense_total` DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
    `new_due_total` DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
    `net_payable` DECIMAL(14, 2) NOT NULL DEFAULT 0.00,
    `cash_counted` DECIMAL(14, 2) NOT NULL DEFAULT 0.00,
    `cash_diff` DECIMAL(14, 2) NOT NULL DEFAULT 0.00,
    `cash_notes_json` JSON NULL,
    `dsr_note` VARCHAR(255) NULL,
    `partner_cash_received` DECIMAL(14, 2) NULL,
    `partner_cash_diff` DECIMAL(14, 2) NULL,
    `partner_damage_amount` DECIMAL(12, 2) NULL,
    `partner_damage_note` VARCHAR(255) NULL,
    `status` ENUM('submitted', 'approved', 'returned') NOT NULL DEFAULT 'submitted',
    `review_note` VARCHAR(255) NULL,
    `submitted_at` TIMESTAMP NULL DEFAULT NULL,
    `approved_by` INT UNSIGNED NULL,
    `approved_at` TIMESTAMP NULL DEFAULT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT `fk_trip_settlements_trip` FOREIGN KEY (`trip_id`) REFERENCES `trips` (`id`) ON DELETE RESTRICT,
    CONSTRAINT `fk_trip_settlements_approver` FOREIGN KEY (`approved_by`) REFERENCES `users` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- SR O/C settled separately from DSR cash handover (+Over payable to SR, -Commission deducted)
CREATE TABLE IF NOT EXISTS `sr_oc_ledger` (
    `id` INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `partner_id` INT UNSIGNED NOT NULL,
    `sr_id` INT UNSIGNED NOT NULL,
    `trip_id` INT UNSIGNED NULL,
    `entry_type` ENUM('delivery_oc', 'payout', 'adjustment') NOT NULL,
    `amount` DECIMAL(12, 2) NOT NULL,
    `note` VARCHAR(255) NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX `idx_sr_oc_ledger_sr_time` (`sr_id`, `created_at`),
    CONSTRAINT `fk_sr_oc_ledger_partner` FOREIGN KEY (`partner_id`) REFERENCES `partners` (`id`) ON DELETE RESTRICT,
    CONSTRAINT `fk_sr_oc_ledger_sr` FOREIGN KEY (`sr_id`) REFERENCES `salesmen` (`id`) ON DELETE RESTRICT,
    CONSTRAINT `fk_sr_oc_ledger_trip` FOREIGN KEY (`trip_id`) REFERENCES `trips` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Partner <-> Company debit/credit (lot purchases, company-borne damage claims, payments)
CREATE TABLE IF NOT EXISTS `company_ledger` (
    `id` INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `partner_id` INT UNSIGNED NOT NULL,
    `company_id` INT UNSIGNED NOT NULL,
    `ref_type` ENUM('lot_purchase', 'damage_claim', 'payment', 'adjustment') NOT NULL,
    `ref_id` INT UNSIGNED NULL,
    `debit` DECIMAL(14, 2) NOT NULL DEFAULT 0.00,
    `credit` DECIMAL(14, 2) NOT NULL DEFAULT 0.00,
    `note` VARCHAR(255) NULL,
    `entry_date` DATE NOT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX `idx_company_ledger_lookup` (`partner_id`, `company_id`, `entry_date`),
    CONSTRAINT `fk_company_ledger_partner` FOREIGN KEY (`partner_id`) REFERENCES `partners` (`id`) ON DELETE RESTRICT,
    CONSTRAINT `fk_company_ledger_company` FOREIGN KEY (`company_id`) REFERENCES `companies` (`id`) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
