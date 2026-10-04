-- as-tradingcards v2
-- These tables are also created automatically on resource start. Run this only if your DB user can't CREATE TABLE.

CREATE TABLE IF NOT EXISTS `ascard_prints` (
    `card_id` VARCHAR(64) NOT NULL,
    `printed` INT NOT NULL DEFAULT 0,
    PRIMARY KEY (`card_id`)
);

CREATE TABLE IF NOT EXISTS `ascard_collection` (
    `identifier` VARCHAR(64) NOT NULL,
    `card_id` VARCHAR(64) NOT NULL,
    `pulls` INT NOT NULL DEFAULT 1,
    `foils` INT NOT NULL DEFAULT 0,
    `first_pulled` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`identifier`, `card_id`)
);

CREATE TABLE IF NOT EXISTS `ascard_grading` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `identifier` VARCHAR(64) NOT NULL,
    `item` VARCHAR(64) NOT NULL,
    `metadata` LONGTEXT NOT NULL,
    `ready_at` INT NOT NULL,
    `collected` TINYINT(1) NOT NULL DEFAULT 0,
    PRIMARY KEY (`id`),
    KEY `identifier` (`identifier`)
);

CREATE TABLE IF NOT EXISTS `ascard_binder` (
    `binder_id` VARCHAR(40) NOT NULL,
    `card_id` VARCHAR(64) NOT NULL,
    `item` VARCHAR(64) NOT NULL,
    `metadata` LONGTEXT NOT NULL,
    `added_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`binder_id`, `card_id`)
);


-- v2.1: owners, stolen reports, market, auctions
CREATE TABLE IF NOT EXISTS `ascard_owners` (
    `serial` VARCHAR(64) NOT NULL,
    `identifier` VARCHAR(64) NOT NULL,
    `card_id` VARCHAR(64) NOT NULL,
    `pulled_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`serial`)
);

CREATE TABLE IF NOT EXISTS `ascard_stolen` (
    `serial` VARCHAR(64) NOT NULL,
    `identifier` VARCHAR(64) NOT NULL,
    `reported_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`serial`)
);

CREATE TABLE IF NOT EXISTS `ascard_sales` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `card_id` VARCHAR(64) NULL,
    `item` VARCHAR(64) NOT NULL,
    `title` VARCHAR(160) NOT NULL,
    `kind` VARCHAR(16) NOT NULL DEFAULT 'card',
    `price` INT NOT NULL,
    `ratio` DOUBLE NULL,
    `sold_at` INT NOT NULL,
    PRIMARY KEY (`id`),
    KEY `card_time` (`card_id`, `sold_at`)
);

CREATE TABLE IF NOT EXISTS `ascard_price_history` (
    `card_id` VARCHAR(64) NOT NULL,
    `at` INT NOT NULL,
    `price` INT NOT NULL,
    PRIMARY KEY (`card_id`, `at`),
    KEY `at` (`at`)
);

CREATE TABLE IF NOT EXISTS `ascard_price_alerts` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `identifier` VARCHAR(64) NOT NULL,
    `card_id` VARCHAR(64) NOT NULL,
    `dir` VARCHAR(8) NOT NULL,
    `price` INT NOT NULL,
    `created_at` INT NOT NULL,
    PRIMARY KEY (`id`),
    KEY `identifier` (`identifier`)
);

CREATE TABLE IF NOT EXISTS `ascard_market_prefs` (
    `identifier` VARCHAR(64) NOT NULL,
    `locker` VARCHAR(64) NULL,
    `watch` LONGTEXT NULL,
    PRIMARY KEY (`identifier`)
);

CREATE TABLE IF NOT EXISTS `ascard_auctions` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `seller` VARCHAR(64) NOT NULL,
    `seller_name` VARCHAR(80) NOT NULL,
    `seller_locker` VARCHAR(64) NULL,
    `item` VARCHAR(64) NOT NULL,
    `metadata` LONGTEXT NOT NULL,
    `card_id` VARCHAR(64) NULL,
    `serial` VARCHAR(64) NULL,
    `title` VARCHAR(160) NOT NULL,
    `kind` VARCHAR(16) NOT NULL DEFAULT 'card',
    `start_price` INT NOT NULL,
    `buy_now` INT NULL,
    `reserve` INT NULL,
    `fee` INT NOT NULL DEFAULT 0,
    `bid` INT NULL,
    `bidder` VARCHAR(64) NULL,
    `bidder_name` VARCHAR(80) NULL,
    `bidder_locker` VARCHAR(64) NULL,
    `bids` INT NOT NULL DEFAULT 0,
    `created_at` INT NOT NULL,
    `ends_at` INT NOT NULL,
    `status` VARCHAR(12) NOT NULL DEFAULT 'live',
    `final_price` INT NULL,
    `reminded` TINYINT(1) NOT NULL DEFAULT 0,
    `lot` LONGTEXT NULL,
    PRIMARY KEY (`id`),
    KEY `status` (`status`),
    KEY `seller` (`seller`),
    KEY `bidder` (`bidder`)
);

CREATE TABLE IF NOT EXISTS `ascard_bids` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `auction_id` INT NOT NULL,
    `bidder` VARCHAR(64) NOT NULL,
    `bidder_name` VARCHAR(80) NOT NULL,
    `amount` INT NOT NULL,
    `at` INT NOT NULL,
    PRIMARY KEY (`id`),
    KEY `auction` (`auction_id`),
    KEY `bidder` (`bidder`)
);

CREATE TABLE IF NOT EXISTS `ascard_payouts` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `identifier` VARCHAR(64) NOT NULL,
    `amount` INT NOT NULL,
    `reason` VARCHAR(120) NOT NULL,
    `created_at` INT NOT NULL,
    PRIMARY KEY (`id`),
    KEY `identifier` (`identifier`)
);

CREATE TABLE IF NOT EXISTS `ascard_deliveries` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `identifier` VARCHAR(64) NOT NULL,
    `item` VARCHAR(64) NOT NULL,
    `metadata` LONGTEXT NOT NULL,
    `title` VARCHAR(160) NOT NULL,
    `locker` VARCHAR(64) NULL,
    `status` VARCHAR(12) NOT NULL DEFAULT 'pending',
    `reason` VARCHAR(16) NOT NULL DEFAULT 'won',
    `created_at` INT NOT NULL,
    PRIMARY KEY (`id`),
    KEY `identifier` (`identifier`),
    KEY `status` (`status`)
);


-- v2.2 / v2.3: pop report, stock, offers, ratings, wantlist, pull log, release days
CREATE TABLE IF NOT EXISTS `ascard_pop` (
    `card_id` VARCHAR(64) NOT NULL,
    `variant` VARCHAR(40) NOT NULL,
    `grade` TINYINT NOT NULL,
    `count` INT NOT NULL DEFAULT 0,
    PRIMARY KEY (`card_id`, `variant`, `grade`)
);

CREATE TABLE IF NOT EXISTS `ascard_stock` (
    `item` VARCHAR(64) NOT NULL,
    `period` INT NOT NULL,
    `sold` INT NOT NULL DEFAULT 0,
    PRIMARY KEY (`item`)
);

CREATE TABLE IF NOT EXISTS `ascard_offers` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `auction_id` INT NOT NULL,
    `buyer` VARCHAR(64) NOT NULL,
    `buyer_name` VARCHAR(80) NOT NULL,
    `buyer_locker` VARCHAR(64) NULL,
    `amount` INT NOT NULL,
    `status` VARCHAR(12) NOT NULL DEFAULT 'pending',
    `created_at` INT NOT NULL,
    PRIMARY KEY (`id`),
    KEY `auction` (`auction_id`),
    KEY `buyer` (`buyer`)
);

CREATE TABLE IF NOT EXISTS `ascard_ratings` (
    `auction_id` INT NOT NULL,
    `seller` VARCHAR(64) NOT NULL,
    `buyer` VARCHAR(64) NOT NULL,
    `buyer_name` VARCHAR(80) NOT NULL,
    `score` TINYINT NOT NULL,
    `comment` VARCHAR(120) NULL,
    `created_at` INT NOT NULL,
    PRIMARY KEY (`auction_id`),
    KEY `seller` (`seller`)
);

CREATE TABLE IF NOT EXISTS `ascard_wants` (
    `identifier` VARCHAR(64) NOT NULL,
    `card_id` VARCHAR(64) NOT NULL,
    PRIMARY KEY (`identifier`, `card_id`),
    KEY `card` (`card_id`)
);

CREATE TABLE IF NOT EXISTS `ascard_pull_log` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `serial` VARCHAR(64) NOT NULL,
    `identifier` VARCHAR(64) NOT NULL,
    `name` VARCHAR(80) NOT NULL,
    `card_id` VARCHAR(64) NOT NULL,
    `item` VARCHAR(64) NOT NULL,
    `title` VARCHAR(160) NOT NULL,
    `value` INT NOT NULL,
    `pulled_at` INT NOT NULL,
    PRIMARY KEY (`id`),
    KEY `time` (`pulled_at`)
);

CREATE TABLE IF NOT EXISTS `ascard_release_sales` (
    `release_id` VARCHAR(64) NOT NULL,
    `identifier` VARCHAR(64) NOT NULL,
    `qty` INT NOT NULL DEFAULT 0,
    PRIMARY KEY (`release_id`, `identifier`)
);

-- lots (older installs; created automatically on start)
-- ALTER TABLE `ascard_auctions` ADD COLUMN `lot` LONGTEXT NULL;
-- ALTER TABLE `ascard_deliveries` ADD COLUMN `lot` LONGTEXT NULL;


-- v2.5: repacks, stats, appraisals, collection value history
CREATE TABLE IF NOT EXISTS `ascard_repack_pool` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `item` VARCHAR(64) NOT NULL,
    `metadata` LONGTEXT NOT NULL,
    `value` INT NOT NULL,
    `added_at` INT NOT NULL,
    PRIMARY KEY (`id`)
);

CREATE TABLE IF NOT EXISTS `ascard_stats` (
    `identifier` VARCHAR(64) NOT NULL,
    `packs` INT NOT NULL DEFAULT 0,
    `cards` INT NOT NULL DEFAULT 0,
    `spent` INT NOT NULL DEFAULT 0,
    `pulled_value` INT NOT NULL DEFAULT 0,
    `sold` INT NOT NULL DEFAULT 0,
    `auction_spent` INT NOT NULL DEFAULT 0,
    `auction_earned` INT NOT NULL DEFAULT 0,
    `repacks` INT NOT NULL DEFAULT 0,
    `best_title` VARCHAR(160) NULL,
    `best_value` INT NOT NULL DEFAULT 0,
    `best_card` VARCHAR(64) NULL,
    `best_item` VARCHAR(64) NULL,
    `best_at` INT NULL,
    `first_at` INT NULL,
    PRIMARY KEY (`identifier`)
);

CREATE TABLE IF NOT EXISTS `ascard_appraisals` (
    `ref` VARCHAR(24) NOT NULL,
    `identifier` VARCHAR(64) NOT NULL,
    `data` LONGTEXT NOT NULL,
    `created_at` INT NOT NULL,
    PRIMARY KEY (`ref`),
    KEY `identifier` (`identifier`)
);

CREATE TABLE IF NOT EXISTS `ascard_value_history` (
    `identifier` VARCHAR(64) NOT NULL,
    `day` INT NOT NULL,
    `value` INT NOT NULL,
    PRIMARY KEY (`identifier`, `day`)
);

-- v2.6: money logs, admin switches, box seals, serial history
CREATE TABLE IF NOT EXISTS `ascard_money_log` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `at` INT NOT NULL,
    `identifier` VARCHAR(64) NULL,
    `name` VARCHAR(80) NULL,
    `kind` VARCHAR(24) NOT NULL,
    `amount` INT NOT NULL,
    `detail` VARCHAR(200) NULL,
    PRIMARY KEY (`id`),
    KEY `at` (`at`),
    KEY `kind` (`kind`),
    KEY `identifier` (`identifier`)
);
CREATE TABLE IF NOT EXISTS `ascard_settings` (
    `k` VARCHAR(32) NOT NULL,
    `v` VARCHAR(64) NOT NULL,
    PRIMARY KEY (`k`)
);
CREATE TABLE IF NOT EXISTS `ascard_seals` (
    `seal` VARCHAR(16) NOT NULL,
    `item` VARCHAR(64) NOT NULL,
    `status` VARCHAR(10) NOT NULL DEFAULT 'sealed',
    `created_at` INT NOT NULL,
    `opened_at` INT NULL,
    PRIMARY KEY (`seal`)
);
CREATE TABLE IF NOT EXISTS `ascard_serial_events` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `serial` VARCHAR(64) NOT NULL,
    `kind` VARCHAR(16) NOT NULL,
    `detail` VARCHAR(160) NULL,
    `at` INT NOT NULL,
    PRIMARY KEY (`id`),
    KEY `serial` (`serial`)
);

-- v3: all tables (ascard_decks, ascard_rank, ascard_matches, ascard_tables, ascard_trader_*, ascard_shop_* ...) are created automatically by server/v2db.lua on start.
