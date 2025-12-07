local config = require 'config.server'
local sharedConfig = require 'config.shared'

if not sharedConfig.registration.enable then return end

-- Callback to get all player vehicles with registration info
lib.callback.register('qbx_vehicleshop:server:getPlayerVehicles', function(source)
    local player = exports.qbx_core:GetPlayer(source)
    if not player then return nil end

    local vehicles = MySQL.query.await('SELECT id, vehicle, plate, registration_status, registration_expiry FROM player_vehicles WHERE citizenid = ?', {
        player.PlayerData.citizenid
    })

    if not vehicles or #vehicles == 0 then return {} end

    -- Process registration info
    local vehiclesWithInfo = {}
    for i = 1, #vehicles do
        local veh = vehicles[i]
        local regExpDate = veh.registration_expiry or 'Unknown'
        local regStatus = veh.registration_status

        -- Check if registration is expired
        if regExpDate and regExpDate ~= 'Unknown' then
            local expYear, expMonth, expDay = tostring(regExpDate):match("(%d+)-(%d+)-(%d+)")
            if expYear and expMonth and expDay then
                local expTime = os.time({year = tonumber(expYear) --[[@as integer]], month = tonumber(expMonth) --[[@as integer]], day = tonumber(expDay) --[[@as integer]]})
                local currentTime = os.time()

                -- Auto-update status if expired
                if currentTime > expTime and regStatus == true then
                    MySQL.update('UPDATE player_vehicles SET registration_status = ? WHERE id = ?', {false, veh.id})
                    regStatus = false
                end
            end
        end

        vehiclesWithInfo[#vehiclesWithInfo + 1] = {
            id = veh.id,
            model = veh.vehicle,
            plate = veh.plate,
            regExpDate = regExpDate,
            regStatus = regStatus
        }
    end

    return vehiclesWithInfo
end)

-- Old callback for backwards compatibility (not used anymore)
lib.callback.register('qbx_vehicleshop:server:getVehicleRegistrationInfo', function(source, plate)
    local vehicleId = exports.qbx_vehicles:GetVehicleIdByPlate(plate)
    if not vehicleId then return nil end

    local vehicle = exports.qbx_vehicles:GetPlayerVehicle(vehicleId)
    if not vehicle then return nil end

    local player = exports.qbx_core:GetPlayer(source)
    if not player or vehicle.citizenid ~= player.PlayerData.citizenid then
        return nil
    end

    -- Get registration info from Imperial CAD if enabled
    local regExpDate = 'Unknown'
    if config.imperialCAD.enable then
        local cleanPlate = plate:gsub("%s+", "")
        exports["ImperialCAD"]:CheckPlate({
            plate = cleanPlate
        }, function(success, res)
            if success then
                local result = json.decode(res)
                if result and result.response and result.response.regExpDate then
                    regExpDate = result.response.regExpDate
                end
            end
        end)
        -- Wait a moment for the callback
        Wait(500)
    end

    return {
        model = vehicle.model,
        plate = plate,
        regExpDate = regExpDate
    }
end)

-- Event to renew registration
RegisterNetEvent('qbx_vehicleshop:server:renewRegistration', function(plate)
    local src = source
    local player = exports.qbx_core:GetPlayer(src)

    if not player then return end

    local vehicleId = exports.qbx_vehicles:GetVehicleIdByPlate(plate)
    if not vehicleId then
        return exports.qbx_core:Notify(src, 'Vehicle not found', 'error')
    end

    local vehicle = exports.qbx_vehicles:GetPlayerVehicle(vehicleId)
    if not vehicle then
        return exports.qbx_core:Notify(src, 'Vehicle not found', 'error')
    end

    if vehicle.citizenid ~= player.PlayerData.citizenid then
        return exports.qbx_core:Notify(src, 'You do not own this vehicle', 'error')
    end

    -- Check if player has enough money
    local cash = player.PlayerData.money.cash
    local bank = player.PlayerData.money.bank
    local cost = sharedConfig.registration.cost

    local currencyType
    if cash >= cost then
        currencyType = 'cash'
    elseif bank >= cost then
        currencyType = 'bank'
    else
        return exports.qbx_core:Notify(src, 'You do not have enough money', 'error')
    end

    -- Remove money
    if not config.removePlayerFunds(player, currencyType, cost, 'vehicle-registration-renewal') then
        return exports.qbx_core:Notify(src, 'Payment failed', 'error')
    end

    -- Calculate new expiration date (1 year from now)
    local newExpDate = os.date("%Y-%m-%d", os.time() + 31536000) --[[@as string]]

    -- Update database
    MySQL.update('UPDATE player_vehicles SET registration_status = ?, registration_expiry = ? WHERE id = ?', {
        true,
        newExpDate,
        vehicle.id
    })

    -- Update Imperial CAD if enabled
    if config.imperialCAD.enable then
        config.renewVehicleRegistration(plate, newExpDate)
    end

    exports.qbx_core:Notify(src, string.format('Vehicle registration renewed until %s', newExpDate), 'success')
end)
