-- Add VIN column to player_vehicles table for Imperial CAD integration
-- This will only add the column if it doesn't already exist
ALTER TABLE `player_vehicles`
ADD COLUMN `vin` VARCHAR(17) DEFAULT NULL AFTER `plate`;
