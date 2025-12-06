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

    ---@param vehicle number Vehicle entity
    ---@param playerData table Player data
    ---@return boolean success
    registerVehicleImperialCAD = function(vehicle, playerData)
        if not GetResourceState('ImperialCAD'):find('started') then
            lib.print.warn('ImperialCAD is not started. Vehicle registration skipped.')
            return false
        end

        local plate = GetVehicleNumberPlateText(vehicle)
        local model = GetEntityModel(vehicle)
        local modelName = GetDisplayNameFromVehicleModel(model):lower()
        local vehicleData = COREVEHICLES[modelName]

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

        -- Generate random VIN (17 characters)
        local vin = lib.string.random('XXXXXXXXXXXXXXXXX'):upper()

        -- Get current date and add 1 year for registration expiration
        local regExpDate = os.date("%Y-%m-%d", os.time() + 31536000)

        local vehicleDataPayload = {
            vehicleData = {
                plate = plate:gsub("%s+", ""), -- Remove extra spaces
                model = modelName,
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

        exports["ImperialCAD"]:CreateVehicleAdvanced(vehicleDataPayload, function(success, res)
            if success then
                lib.print.info(('Vehicle %s registered to Imperial CAD for %s %s'):format(plate, playerData.charinfo.firstname, playerData.charinfo.lastname))
            else
                lib.print.error(('Failed to register vehicle %s to Imperial CAD: %s'):format(plate, res))
            end
        end)

        return true
    end,
}