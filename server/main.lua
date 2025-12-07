lib.versionCheck('Qbox-project/qbx_vehicleshop')
assert(lib.checkDependency('qbx_core', '1.17.2'), 'qbx_core v1.17.2 or higher is required')
assert(lib.checkDependency('qbx_vehicles', '1.4.1'), 'qbx_vehicles v1.4.1 or higher is required')

local config = require 'config.server'
local sharedConfig = require 'config.shared'
local financeStorage = require 'server.storage'
COREVEHICLES = exports.qbx_core:GetVehiclesByName()
local saleTimeout = {}
local testDrives = {}

---@param data {toVehicle: string}
RegisterNetEvent('qbx_vehicleshop:server:swapVehicle', function(data)
    if not CheckVehicleList(data.toVehicle) then return end
    TriggerClientEvent('qbx_vehicleshop:client:swapVehicle', -1, data)
end)

---@param vehicle string
RegisterNetEvent('qbx_vehicleshop:server:testDrive', function(vehicle)
    if not sharedConfig.enableTestDrive then return end
    local src = source

    if Player(src).state.isInTestDrive then
        return exports.qbx_core:Notify(src, locale('error.testdrive_alreadyin'), 'error')
    end

    local shopId = GetShopZone(src)
    local shop = sharedConfig.shops[shopId]
    if not shop then return end

    if not CheckVehicleList(vehicle, shopId) then
        return exports.qbx_core:Notify(src, locale('error.notallowed'), 'error')
    end

    local coords = GetClearSpawnArea(shop.vehicleSpawns)
    if not coords then
        return exports.qbx_core:Notify(src, locale('error.no_clear_spawn'), 'error')
    end

    local testDrive = shop.testDrive
    local plate = 'TEST'..lib.string.random('1111')

    local netId = SpawnVehicle(src, {
        modelName = vehicle,
        coords = coords,
        plate = plate
    })

    testDrives[src] = {
        netId = netId,
        endBehavior = testDrive.endBehavior,
        returnLocation = shop.returnLocation
    }

    Player(src).state:set('isInTestDrive', testDrive.limit, true)
    SetTimeout(testDrive.limit * 60000, function()
        Player(src).state:set('isInTestDrive', nil, true)
    end)
end)

---@param vehicle string
---@param playerId string|number
RegisterNetEvent('qbx_vehicleshop:server:customTestDrive', function(vehicle, playerId)
    local src = source
    local target = tonumber(playerId) --[[@as number]]

    if not exports.qbx_core:GetPlayer(target) then
        exports.qbx_core:Notify(src, locale('error.Invalid_ID'), 'error')
        return
    end

    if #(GetEntityCoords(GetPlayerPed(src)) - GetEntityCoords(GetPlayerPed(target))) < 3 then
        TriggerClientEvent('qbx_vehicleshop:client:testDrive', target, { vehicle = vehicle })
    else
        exports.qbx_core:Notify(src, locale('error.playertoofar'), 'error')
    end
end)

AddStateBagChangeHandler('isInTestDrive', nil, function(bagName, _, value)
    if value then return end

    local plySrc = GetPlayerFromStateBagName(bagName)
    if not plySrc then return end
    local testDrive = testDrives[plySrc]
    if not testDrive then return end
    local netId = testDrive.netId
    local endBehavior = testDrive.endBehavior
    if not netId or endBehavior == 'none' then return end

    local vehicle = NetworkGetEntityFromNetworkId(netId)

    if endBehavior == 'return' then
        local coords = testDrive.returnLocation
        local plyPed = GetPlayerPed(plySrc)
        if #(GetEntityCoords(plyPed) - coords) > 10 then -- don't teleport if they are standing near the spot
            SetEntityCoords(plyPed, coords.x, coords.y, coords.z, false, false, false, false)
        end
        if DoesEntityExist(vehicle) then
            DeleteEntity(vehicle)
        end
    elseif endBehavior == 'destroy' then
        if DoesEntityExist(vehicle) then
            DeleteEntity(vehicle)
        end
    end
    testDrives[plySrc] = nil
end)

AddEventHandler('onResourceStop', function (resourceName)
    if cache.resource ~= resourceName then return end

    for player, _ in pairs(testDrives) do
        Player(player).state:set('isInTestDrive', nil, true)
    end
end)

---@param vehicle string
RegisterNetEvent('qbx_vehicleshop:server:buyShowroomVehicle', function(vehicle)
    local src = source

    local shopId = GetShopZone(src)
    local shop = sharedConfig.shops[shopId]
    if not shop then return end

    if not CheckVehicleList(vehicle, shopId) then
        return exports.qbx_core:Notify(src, locale('error.notallowed'), 'error')
    end

    local coords = GetClearSpawnArea(shop.vehicleSpawns)
    if not coords then
        return exports.qbx_core:Notify(src, locale('error.no_clear_spawn'), 'error')
    end

    local player = exports.qbx_core:GetPlayer(src)
    local vehiclePrice = COREVEHICLES[vehicle].price
    if not RemoveMoney(src, vehiclePrice, 'vehicle-bought-in-showroom') then
        return exports.qbx_core:Notify(src, locale('error.notenoughmoney'), 'error')
    end

    local vehicleId = exports.qbx_vehicles:CreatePlayerVehicle({
        model = vehicle,
        citizenid = player.PlayerData.citizenid,
    })

    -- Set initial registration (1 year from purchase)
    local regExpDate = os.date("%Y-%m-%d", os.time() + 31536000)
    MySQL.update('UPDATE player_vehicles SET registration_status = ?, registration_expiry = ? WHERE id = ?', {
        true,
        regExpDate,
        vehicleId
    })

    exports.qbx_core:Notify(src, locale('success.purchased'), 'success')

    local netId = SpawnVehicle(src, {
        coords = coords,
        vehicleId = vehicleId
    })

    -- Auto-register with Imperial CAD if enabled
    if config.imperialCAD.enable and config.imperialCAD.autoRegister and netId then
        SetTimeout(1000, function() -- Small delay to ensure vehicle is fully spawned
            local veh = NetworkGetEntityFromNetworkId(netId)
            if veh and DoesEntityExist(veh) then
                config.registerVehicleImperialCAD(veh, player.PlayerData, vehicle)

                -- Auto-sync registration status (valid for new vehicles)
                SetTimeout(2000, function()
                    local plate = GetVehicleNumberPlateText(veh)
                    if plate then
                        config.syncRegistrationStatusToImperialCAD(plate, false)
                    end
                end)
            end
        end)
    end
end)

---@param src number
---@param target table
---@param price number
---@param downPayment number
---@return boolean success
function SellShowroomVehicleTransact(src, target, price, downPayment)
    local player = exports.qbx_core:GetPlayer(src)

    if not RemoveMoney(target.PlayerData.source, downPayment, 'vehicle-bought-in-showroom') then
        exports.qbx_core:Notify(src, locale('error.notenoughmoney'), 'error')
        return false
    end

    local commission = lib.math.round(price * config.commissionRate)
    config.addPlayerFunds(player, 'bank', commission, 'vehicle-commission')
    exports.qbx_core:Notify(src, locale('success.earned_commission', lib.math.groupdigits(commission)), 'success')

    config.addSocietyFunds(player.PlayerData.job.name, price)
    exports.qbx_core:Notify(target.PlayerData.source, locale('success.purchased'), 'success')

    return true
end

---@param vehicle string
---@param playerId string|number
RegisterNetEvent('qbx_vehicleshop:server:sellShowroomVehicle', function(vehicle, playerId)
    local src = source
    local targetPlayerId = tonumber(playerId) --[[@as number]]
    local target = exports.qbx_core:GetPlayer(targetPlayerId)

    if not target then
        return exports.qbx_core:Notify(src, locale('error.Invalid_ID'), 'error')
    end

    if #(GetEntityCoords(GetPlayerPed(src)) - GetEntityCoords(GetPlayerPed(target.PlayerData.source))) >= 3 then
        return exports.qbx_core:Notify(src, locale('error.playertoofar'), 'error')
    end

    local shopId = GetShopZone(target.PlayerData.source)
    local shop = sharedConfig.shops[shopId]
    if not shop then return end

    if not CheckVehicleList(vehicle, shopId) then
        return exports.qbx_core:Notify(src, locale('error.notallowed'), 'error')
    end

    local coords = GetClearSpawnArea(shop.vehicleSpawns)
    if not coords then
        return exports.qbx_core:Notify(src, locale('error.no_clear_spawn'), 'error')
    end

    local vehiclePrice = COREVEHICLES[vehicle].price
    local cid = target.PlayerData.citizenid

    if not SellShowroomVehicleTransact(src, target, vehiclePrice, vehiclePrice) then return end

    local vehicleId = exports.qbx_vehicles:CreatePlayerVehicle({
        model = vehicle,
        citizenid = cid,
    })

    -- Set initial registration (1 year from purchase)
    local regExpDate = os.date("%Y-%m-%d", os.time() + 31536000)
    MySQL.update('UPDATE player_vehicles SET registration_status = ?, registration_expiry = ? WHERE id = ?', {
        true,
        regExpDate,
        vehicleId
    })

    local netId = SpawnVehicle(targetPlayerId, {
        coords = coords,
        vehicleId = vehicleId
    })

    -- Auto-register with Imperial CAD if enabled
    if config.imperialCAD.enable and config.imperialCAD.autoRegister and netId then
        SetTimeout(1000, function() -- Small delay to ensure vehicle is fully spawned
            local veh = NetworkGetEntityFromNetworkId(netId)
            if veh and DoesEntityExist(veh) then
                config.registerVehicleImperialCAD(veh, target.PlayerData, vehicle)

                -- Auto-sync registration status (valid for new vehicles)
                SetTimeout(2000, function()
                    local plate = GetVehicleNumberPlateText(veh)
                    if plate then
                        config.syncRegistrationStatusToImperialCAD(plate, false)
                    end
                end)
            end
        end)
    end
end)

-- Transfer vehicle to player in passenger seat
lib.addCommand('transfervehicle', {
    help = locale('general.command_transfervehicle'),
    params = {
        {
            name = 'id',
            type = 'playerId',
            help = locale('general.command_transfervehicle_help')
        },
        {
            name = 'amount',
            type = 'number',
            help = locale('general.command_transfervehicle_amount'),
            optional = true
        }
    }
}, function(source, args)
    local buyerId = args.id
    local sellAmount = args.amount or 0

    if source == buyerId then
        return exports.qbx_core:Notify(source, locale('error.selftransfer'), 'error')
    end
    if saleTimeout[source] then
        return exports.qbx_core:Notify(source, locale('error.sale_timeout'), 'error')
    end
    if buyerId == 0 then
        return exports.qbx_core:Notify(source, locale('error.Invalid_ID'), 'error')
    end

    local ped = GetPlayerPed(source)
    local targetPed = GetPlayerPed(buyerId)
    if targetPed == 0 then
        return exports.qbx_core:Notify(source, locale('error.buyerinfo'), 'error')
    end

    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 then
        return exports.qbx_core:Notify(source, locale('error.notinveh'), 'error')
    end

    local vehicleId = Entity(vehicle).state.vehicleid or exports.qbx_vehicles:GetVehicleIdByPlate(GetVehicleNumberPlateText(vehicle))
    if not vehicleId then
        return exports.qbx_core:Notify(source, locale('error.notowned'), 'error')
    end

    local player = exports.qbx_core:GetPlayer(source)
    local target = exports.qbx_core:GetPlayer(buyerId)
    local row = exports.qbx_vehicles:GetPlayerVehicle(vehicleId)
    local isFinanced = sharedConfig.finance.enable and financeStorage.fetchIsFinanced(vehicleId)

    if not row then return end

    if config.finance.preventSelling and isFinanced then
        return exports.qbx_core:Notify(source, locale('error.financed'), 'error')
    end

    if row.citizenid ~= player.PlayerData.citizenid then
        return exports.qbx_core:Notify(source, locale('error.notown'), 'error')
    end

    if #(GetEntityCoords(ped) - GetEntityCoords(targetPed)) > 5.0 then
        return exports.qbx_core:Notify(source, locale('error.playertoofar'), 'error')
    end

    local targetcid = target.PlayerData.citizenid
    if not target then
        return exports.qbx_core:Notify(source, locale('error.buyerinfo'), 'error')
    end

    saleTimeout[source] = true

    SetTimeout(config.saleTimeout, function()
        saleTimeout[source] = false
    end)

    if isFinanced then
        local financeData = financeStorage.fetchFinancedVehicleEntityById(vehicleId)
        local confirmFinance = lib.callback.await('qbx_vehicleshop:client:confirmFinance', buyerId, financeData)
        if not confirmFinance then
            return exports.qbx_core:Notify(source, locale('error.buyerdeclined'), 'error')
        end
    end

    lib.callback('qbx_vehicleshop:client:confirmTrade', buyerId, function(approved)
        if not approved then
            exports.qbx_core:Notify(source, locale('error.buyerdeclined'), 'error')
            return
        end

        if sellAmount > 0 then
            local currencyType = FindChargeableCurrencyType(sellAmount, target.PlayerData.money.cash, target.PlayerData.money.bank)

            if not currencyType then
                return exports.qbx_core:Notify(source, locale('error.buyertoopoor'), 'error')
            end

            config.addPlayerFunds(player, currencyType, sellAmount, 'vehicle-sold-to-player')
            config.removePlayerFunds(target, currencyType, sellAmount, 'vehicle-bought-from-player')
        end

        exports.qbx_vehicles:SetPlayerVehicleOwner(row.id, targetcid)
        config.giveKeys(buyerId, row.plate, vehicle)

        local sellerMessage = sellAmount > 0 and locale('success.soldfor') .. lib.math.groupdigits(sellAmount) or locale('success.gifted')
        local buyerMessage = sellAmount > 0 and locale('success.boughtfor') .. lib.math.groupdigits(sellAmount) or locale('success.received_gift')

        exports.qbx_core:Notify(source, sellerMessage, 'success')
        exports.qbx_core:Notify(buyerId, buyerMessage, 'success')
        if isFinanced then
            SetHasFinanced(buyerId, true)
        end
    end, GetEntityModel(vehicle), sellAmount)
end)

-- Register vehicle with Imperial CAD
lib.addCommand('regveh', {
    help = 'Register your current vehicle with Imperial CAD',
}, function(source)
    if not config.imperialCAD.enable then
        return exports.qbx_core:Notify(source, 'Imperial CAD integration is disabled', 'error')
    end

    local ped = GetPlayerPed(source)
    local vehicle = GetVehiclePedIsIn(ped, false)

    if vehicle == 0 then
        return exports.qbx_core:Notify(source, locale('error.notinveh'), 'error')
    end

    local vehicleId = Entity(vehicle).state.vehicleid or exports.qbx_vehicles:GetVehicleIdByPlate(GetVehicleNumberPlateText(vehicle))
    if not vehicleId then
        return exports.qbx_core:Notify(source, locale('error.notowned'), 'error')
    end

    local player = exports.qbx_core:GetPlayer(source)
    local row = exports.qbx_vehicles:GetPlayerVehicle(vehicleId)

    if not row then
        return exports.qbx_core:Notify(source, locale('error.notowned'), 'error')
    end

    if row.citizenid ~= player.PlayerData.citizenid then
        return exports.qbx_core:Notify(source, locale('error.notown'), 'error')
    end

    local success = config.registerVehicleImperialCAD(vehicle, player.PlayerData, row.model)

    if success then
        exports.qbx_core:Notify(source, 'Vehicle successfully registered with Imperial CAD', 'success')
    else
        exports.qbx_core:Notify(source, 'Failed to register vehicle with Imperial CAD', 'error')
    end
end)

-- Sync VIN from Imperial CAD to database
lib.addCommand('syncvin', {
    help = 'Sync VIN from Imperial CAD to the vehicle database',
}, function(source)
    if not config.imperialCAD.enable then
        return exports.qbx_core:Notify(source, 'Imperial CAD integration is disabled', 'error')
    end

    local ped = GetPlayerPed(source)
    local vehicle = GetVehiclePedIsIn(ped, false)

    if vehicle == 0 then
        return exports.qbx_core:Notify(source, locale('error.notinveh'), 'error')
    end

    local plate = GetVehicleNumberPlateText(vehicle)
    local vehicleId = Entity(vehicle).state.vehicleid or exports.qbx_vehicles:GetVehicleIdByPlate(plate)

    if not vehicleId then
        return exports.qbx_core:Notify(source, locale('error.notowned'), 'error')
    end

    local player = exports.qbx_core:GetPlayer(source)
    local row = exports.qbx_vehicles:GetPlayerVehicle(vehicleId)

    if not row then
        return exports.qbx_core:Notify(source, locale('error.notowned'), 'error')
    end

    if row.citizenid ~= player.PlayerData.citizenid then
        return exports.qbx_core:Notify(source, locale('error.notown'), 'error')
    end

    local success = config.syncVINFromImperialCAD(plate, vehicleId)

    if success then
        exports.qbx_core:Notify(source, 'Syncing VIN from Imperial CAD...', 'success')
    else
        exports.qbx_core:Notify(source, 'Failed to sync VIN from Imperial CAD', 'error')
    end
end)

-- Sync registration status to Imperial CAD
lib.addCommand('syncreg', {
    help = 'Sync vehicle registration status from database to Imperial CAD',
}, function(source)
    if not config.imperialCAD.enable then
        return exports.qbx_core:Notify(source, 'Imperial CAD integration is disabled', 'error')
    end

    local ped = GetPlayerPed(source)
    local vehicle = GetVehiclePedIsIn(ped, false)

    if vehicle == 0 then
        return exports.qbx_core:Notify(source, locale('error.notinveh'), 'error')
    end

    local plate = GetVehicleNumberPlateText(vehicle)
    local vehicleId = Entity(vehicle).state.vehicleid or exports.qbx_vehicles:GetVehicleIdByPlate(plate)

    if not vehicleId then
        return exports.qbx_core:Notify(source, locale('error.notowned'), 'error')
    end

    local player = exports.qbx_core:GetPlayer(source)
    local row = exports.qbx_vehicles:GetPlayerVehicle(vehicleId)

    if not row then
        return exports.qbx_core:Notify(source, locale('error.notowned'), 'error')
    end

    if row.citizenid ~= player.PlayerData.citizenid then
        return exports.qbx_core:Notify(source, locale('error.notown'), 'error')
    end

    -- Get registration data from database
    local result = MySQL.single.await('SELECT registration_status, registration_expiry FROM player_vehicles WHERE id = ?', {vehicleId})

    if not result then
        return exports.qbx_core:Notify(source, 'Failed to get registration data', 'error')
    end

    -- Check if expired
    local isExpired = false
    if result.registration_expiry then
        local expYear, expMonth, expDay = tostring(result.registration_expiry):match("(%d+)-(%d+)-(%d+)")
        if expYear and expMonth and expDay then
            local expTime = os.time({year = tonumber(expYear) --[[@as integer]], month = tonumber(expMonth) --[[@as integer]], day = tonumber(expDay) --[[@as integer]]})
            local currentTime = os.time()
            isExpired = currentTime > expTime
        end
    end

    local success = config.syncRegistrationStatusToImperialCAD(plate, isExpired)

    if success then
        local status = isExpired and "Expired" or "Valid"
        exports.qbx_core:Notify(source, string.format('Syncing registration status (%s) to Imperial CAD...', status), 'success')
    else
        exports.qbx_core:Notify(source, 'Failed to sync registration status to Imperial CAD', 'error')
    end
end)

