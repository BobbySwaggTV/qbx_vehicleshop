-- Add registration columns to player_vehicles table
ALTER TABLE `player_vehicles`
ADD COLUMN `registration_status` BOOLEAN DEFAULT TRUE AFTER `vin`,
ADD COLUMN `registration_expiry` DATE DEFAULT NULL AFTER `registration_status`;
