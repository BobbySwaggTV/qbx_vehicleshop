return {
    commissionRate = 0.1, -- Percent that goes to sales person from a full car sale 10%
    finance = {
        paymentWarning = 10, -- time in minutes that player has to make payment before repo
        paymentInterval = 24, -- time in hours between payment being due
        cronSchedule = '*/10 * * * *', -- cron schedule for finance payment checks ref: https://coxdocs.dev/ox_lib/Modules/Cron/Server#cron-expression
        preventSelling = false, -- prevents players from using /transfervehicle if financed
    },
    saleTimeout = 60000, -- Delay between attempts to sell/gift a vehicle. Prevents abuse
    deleteUnpaidFinancedVehicle = false, -- true to delete unpaid vehicles from database, otherwise it will edit citizenid to hide from db select

    -- Imperial CAD Integration
    imperialCAD = {
        enable = true, -- Enable Imperial CAD integration
        autoRegister = true, -- Automatically register vehicles when purchased
    },

    ---@param src number Player Server ID
    ---@param plate string Vehicle Plate
    ---@param vehicle number Vehicle Entity ID
    giveKeys = function(src, plate, vehicle)
        exports.qbx_vehiclekeys:GiveKeys(src, vehicle)
    end,

    ---@param society string Society name
    ---@param amount number Amount to add
    ---@return boolean
    addSocietyFunds = function(society, amount) -- function to add funds to society
        if GetResourceState('Renewed-Banking'):find('started') then
            return exports['Renewed-Banking']:addAccountMoney(society, amount)
        else
            lib.print.error(('Renewed-Banking is needed for Society Funds and it\'s currently %s'):format(GetResourceState('Renewed-Banking')))
            return false
        end
    end,

    ---@param player any QBX Player object
    ---@param amount number Amount to add
    ---@param reason string? Reason for adding funds
    ---@return boolean
    addPlayerFunds = function(player, account, amount, reason)
        return player.Functions.AddMoney(account, amount, reason)
    end,

    ---@param player any QBX Player object
    ---@param amount number Amount to remove
    ---@param reason string? Reason for removing funds
    removePlayerFunds = function(player, account, amount, reason)
        return player.Functions.RemoveMoney(account, amount, reason)
    end,

    ---@param plate string Vehicle plate
    ---@param regExpDate string New registration expiration date
    ---@return boolean success
    renewVehicleRegistration = function(plate, regExpDate)
        if not GetResourceState('ImperialCAD'):find('started') then
            lib.print.warn('ImperialCAD is not started. Registration renewal skipped.')
            return false
        end

        local cleanPlate = plate:gsub("%s+", "")

        -- Note: Imperial CAD doesn't have an UpdateVehicle export
        -- Registration status is managed in the database
        -- Imperial CAD will show the vehicle info as initially registered
        lib.print.info(('Vehicle registration renewed in database for plate %s until %s'):format(cleanPlate, regExpDate))

        return true
    end,

    ---@param plate string Vehicle plate
    ---@param isExpired boolean Whether registration is expired
    ---@param playerSource number? Optional player source (if player is online)
    ---@return boolean success
    syncRegistrationStatusToImperialCAD = function(plate, isExpired, playerSource)
        if not GetResourceState('ImperialCAD'):find('started') then
            lib.print.warn('ImperialCAD is not started. Registration sync skipped.')
            return false
        end

        local cleanPlate = plate:gsub("%s+", "")

        -- Get vehicle data from database
        local result = MySQL.single.await('SELECT * FROM player_vehicles WHERE plate = ?', {cleanPlate})
        if not result then
            lib.print.warn(('Vehicle with plate %s not found in database'):format(cleanPlate))
            return false
        end

        -- Get player data - either from online player or fetch from database
        local playerData
        if playerSource then
            local player = exports.qbx_core:GetPlayer(playerSource)
            if player then
                playerData = player.PlayerData
            end
        end

        -- If player not online or no source provided, fetch from database
        if not playerData then
            local playerInfo = MySQL.single.await('SELECT discord FROM players WHERE citizenid = ?', {result.citizenid})
            if not playerInfo then
                lib.print.warn(('Player with citizenid %s not found in database'):format(result.citizenid))
                return false
            end
            playerData = {
                discord = playerInfo.discord
            }
        end

        -- Get vehicle info from Imperial CAD
        local success, vehicleInfo = pcall(exports["ImperialCAD"].CheckPlate, exports["ImperialCAD"], cleanPlate)

        if success and vehicleInfo then
            -- Vehicle exists in Imperial CAD
            lib.print.warn(('Vehicle with plate %s already exists in Imperial CAD'):format(cleanPlate))
            lib.print.warn('Imperial CAD DeleteVehicle endpoint is not available yet.')
            lib.print.info('To update registration status: 1) Delete the vehicle in Imperial CAD interface, 2) Run /syncreg again')
            return false
        end

        -- Vehicle doesn't exist, create it with current registration status
        local regStatus = isExpired and "Expired" or "Valid"

        local vehicleData = {
            users_discordID = playerData.discord or "",
            vehicle_plate = cleanPlate,
            vehicle_model = result.vehicle,
            vehicle_color = result.mods and json.decode(result.mods).color1 or "Unknown",
            vehicle_vin = result.vin or "",
            vehicle_registration = regStatus,
            vehicle_insurance = "None",
            vehicle_notes = ""
        }

        lib.print.info(('Creating vehicle in Imperial CAD with registration status: %s'):format(regStatus))

        local createSuccess = pcall(exports["ImperialCAD"].CreateVehicleAdvanced, exports["ImperialCAD"], vehicleData, function(created, res)
            if created then
                lib.print.info(('Successfully synced registration status (%s) to Imperial CAD for plate %s'):format(regStatus, cleanPlate))
            else
                lib.print.error(('Failed to sync registration to Imperial CAD: %s'):format(res or 'unknown error'))
            end
        end)

        if not createSuccess then
            lib.print.error('Failed to call CreateVehicleAdvanced export')
            return false
        end

        return true
    end,

    ---@param vehicle number Vehicle entity
    ---@param playerData table Player data
    ---@param modelName string? Vehicle model name (optional, will be derived from entity if not provided)
    ---@return boolean success
    registerVehicleImperialCAD = function(vehicle, playerData, modelName)
        if not GetResourceState('ImperialCAD'):find('started') then
            lib.print.warn('ImperialCAD is not started. Vehicle registration skipped.')
            return false
        end

        local plate = GetVehicleNumberPlateText(vehicle)
        local vehicleData = modelName and COREVEHICLES[modelName] or nil

        -- Ensure we have a valid model name
        if not modelName then
            lib.print.error('Model name is required for Imperial CAD registration')
            return false
        end

        -- Get vehicle colors
        local primaryColor, secondaryColor = GetVehicleColours(vehicle)
        local colorNames = {
            [0] = "Black", [1] = "Graphite Black", [2] = "Black Steel", [3] = "Dark Silver",
            [4] = "Silver", [5] = "Blue Silver", [6] = "Steel Gray", [7] = "Shadow Silver",
            [8] = "Stone Silver", [9] = "Midnight Silver", [10] = "Gun Metal", [11] = "Anthracite Gray",
            [27] = "Red", [28] = "Torino Red", [29] = "Formula Red", [30] = "Blaze Red",
            [31] = "Grace Red", [32] = "Garnet Red", [33] = "Sunset Red", [34] = "Cabernet Red",
            [35] = "Wine Red", [36] = "Candy Red", [37] = "Hot Pink", [38] = "Pfsiter Pink",
            [54] = "Dark Green", [55] = "Racing Green", [56] = "Sea Green", [57] = "Olive Green",
            [62] = "Dark Blue", [63] = "Midnight Blue", [64] = "Saxon Blue", [65] = "Mariner Blue",
            [66] = "Harbor Blue", [67] = "Diamond Blue", [68] = "Surf Blue", [69] = "Nautical Blue",
            [73] = "Racing Blue", [74] = "Light Blue", [88] = "Yellow", [89] = "Race Yellow",
            [90] = "Bronze", [91] = "Flur Yellow", [92] = "Lime Green", [94] = "Champagne",
            [95] = "Pueblo Beige", [96] = "Dark Ivory", [97] = "Choco Brown", [98] = "Golden Brown",
            [111] = "White", [112] = "Frost White", [134] = "Orange", [135] = "Pearlescent Orange",
            [137] = "Copper", [138] = "Brown", [141] = "Purple", [142] = "Spinnaker Purple"
        }
        local color = colorNames[primaryColor] or "Unknown"

        -- Generate random VIN (17 characters - alphanumeric excluding I, O, Q to match real VIN standards)
        local vinChars = "0123456789ABCDEFGHJKLMNPRSTUVWXYZ" -- Excludes I, O, Q per VIN standards
        local vin = ""
        for i = 1, 17 do
            local randomIndex = math.random(1, #vinChars)
            vin = vin .. vinChars:sub(randomIndex, randomIndex)
        end

        -- Get current date and add 1 year for registration expiration
        local regExpDate = os.date("%Y-%m-%d", os.time() + 31536000)

        -- Get vehicle display name (capitalize first letter of each word)
        local displayName = modelName:gsub("(%a)([%w_']*)", function(first, rest)
            return first:upper() .. rest:lower()
        end)

        local vehicleDataPayload = {
            vehicleData = {
                plate = plate:gsub("%s+", ""), -- Remove extra spaces
                model = displayName,
                Make = vehicleData and vehicleData.brand or "Unknown",
                color = color,
                year = tostring(os.date("%Y")),
                regState = "SA",
                regStatus = "Valid",
                regExpDate = regExpDate,
                vin = vin,
                stolen = false
            },
            vehicleInsurance = {
                hasInsurance = true,
                insuranceStatus = "Active",
                insurancePolicyNum = "INS" .. lib.string.random('1111111')
            },
            vehicleOwner = {
                ownerSSN = playerData.citizenid,
                ownerFirstName = playerData.charinfo.firstname,
                ownerLastName = playerData.charinfo.lastname,
                ownerGender = playerData.charinfo.gender == 0 and "Male" or "Female",
                ownerAddress = "Unknown",
                ownerCity = "Los Santos"
            }
        }

        lib.print.info(('Registering vehicle with Imperial CAD - Plate: %s, Model: %s, Owner: %s %s'):format(
            vehicleDataPayload.vehicleData.plate,
            vehicleDataPayload.vehicleData.model,
            playerData.charinfo.firstname,
            playerData.charinfo.lastname
        ))

        exports["ImperialCAD"]:CreateVehicleAdvanced(vehicleDataPayload, function(success, res)
            if success then
                lib.print.info(('Vehicle %s registered to Imperial CAD for %s %s'):format(plate, playerData.charinfo.firstname, playerData.charinfo.lastname))

                -- Retrieve the VIN from Imperial CAD after registration and store in database
                local vehicleId = Entity(vehicle).state.vehicleid
                if vehicleId then
                    local cleanPlate = plate:gsub("%s+", "")
                    -- Wait a moment for Imperial CAD to process the registration
                    SetTimeout(2000, function()
                        -- Use CheckPlate to get the actual VIN from Imperial CAD
                        exports["ImperialCAD"]:CheckPlate({
                            plate = cleanPlate
                        }, function(checkSuccess, checkRes)
                            if checkSuccess then
                                lib.print.info(('CheckPlate response for %s: %s'):format(cleanPlate, checkRes))
                                local result = json.decode(checkRes)
                                if result and result.response and result.response.vin then
                                    local retrievedVin = result.response.vin
                                    MySQL.update('UPDATE player_vehicles SET vin = ? WHERE id = ?', { retrievedVin, vehicleId }, function(affectedRows)
                                        if affectedRows > 0 then
                                            lib.print.info(('VIN stored in database for vehicle ID %s: %s'):format(vehicleId, retrievedVin))
                                        else
                                            lib.print.warn(('Database update failed for vehicle ID %s'):format(vehicleId))
                                        end
                                    end)
                                else
                                    lib.print.warn(('No VIN in response for plate %s. Response structure: %s'):format(cleanPlate, checkRes))
                                end
                            else
                                lib.print.error(('CheckPlate failed for %s: %s'):format(cleanPlate, checkRes))
                            end
                        end)
                    end)
                end
            else
                lib.print.error(('Failed to register vehicle %s to Imperial CAD: %s'):format(plate, res))
            end
        end)

        return true
    end,

    ---@param plate string Vehicle plate
    ---@param vehicleId number Vehicle ID from player_vehicles
    ---@return boolean success
    syncVINFromImperialCAD = function(plate, vehicleId)
        if not GetResourceState('ImperialCAD'):find('started') then
            lib.print.warn('ImperialCAD is not started. VIN sync skipped.')
            return false
        end

        -- Clean plate for search
        local cleanPlate = plate:gsub("%s+", "")

        -- Use CheckPlate to get vehicle data from Imperial CAD
        exports["ImperialCAD"]:CheckPlate({
            plate = cleanPlate
        }, function(success, res)
            if success then
                local result = json.decode(res)
                if result and result.response and result.response.vin then
                    local vin = result.response.vin
                    -- Update VIN in player_vehicles database
                    MySQL.update('UPDATE player_vehicles SET vin = ? WHERE id = ?', { vin, vehicleId }, function(affectedRows)
                        if affectedRows > 0 then
                            lib.print.info(('VIN synced from Imperial CAD for plate %s (ID: %s): %s'):format(cleanPlate, vehicleId, vin))
                        else
                            lib.print.warn(('Failed to update VIN in database for vehicle ID %s'):format(vehicleId))
                        end
                    end)
                else
                    lib.print.warn(('No VIN found in Imperial CAD response for plate %s'):format(cleanPlate))
                end
            else
                lib.print.warn(('Could not retrieve vehicle data from Imperial CAD for plate %s'):format(cleanPlate))
            end
        end)

        return true
    end,
}