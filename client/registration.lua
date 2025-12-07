local sharedConfig = require 'config.shared'

if not sharedConfig.registration.enable then return end

local dmvPed = nil

-- Create blip for DMV
if sharedConfig.registration.blip.enabled then
    local blip = AddBlipForCoord(sharedConfig.registration.zone.x, sharedConfig.registration.zone.y, sharedConfig.registration.zone.z)
    SetBlipSprite(blip, sharedConfig.registration.blip.sprite)
    SetBlipDisplay(blip, 4)
    SetBlipScale(blip, sharedConfig.registration.blip.scale)
    SetBlipColour(blip, sharedConfig.registration.blip.color)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(sharedConfig.registration.blip.label)
    EndTextCommandSetBlipName(blip)
end

-- Spawn DMV NPC
CreateThread(function()
    local pedModel = `a_m_y_business_01`
    RequestModel(pedModel)
    while not HasModelLoaded(pedModel) do
        Wait(0)
    end

    dmvPed = CreatePed(4, pedModel, sharedConfig.registration.zone.x, sharedConfig.registration.zone.y, sharedConfig.registration.zone.z - 1.0, sharedConfig.registration.npcHeading or 0.0, false, true)
    SetEntityInvincible(dmvPed, true)
    SetBlockingOfNonTemporaryEvents(dmvPed, true)
    FreezeEntityPosition(dmvPed, true)

    -- Add ox_target to the NPC
    exports.ox_target:addLocalEntity(dmvPed, {
        {
            name = 'dmv_registration',
            icon = 'fas fa-file-contract',
            label = 'Vehicle Registration Renewal',
            onSelect = function()
                OpenRegistrationMenu()
            end,
            distance = 2.5
        }
    })
end)

function OpenRegistrationMenu()
    -- Get player's vehicles from server
    lib.callback('qbx_vehicleshop:server:getPlayerVehicles', false, function(vehicles)
        if not vehicles or #vehicles == 0 then
            exports.qbx_core:Notify('You do not own any vehicles', 'error')
            return
        end

        local options = {}
        for i = 1, #vehicles do
            local veh = vehicles[i]
            local statusColor = 'green'
            local statusText = 'Valid'
            local timeRemaining = 'N/A'

            -- Check registration status from database
            if veh.regStatus == false or veh.regStatus == 0 then
                statusColor = 'red'
                statusText = 'Invalid'
                timeRemaining = 'Expired'
            elseif veh.regExpDate and veh.regExpDate ~= 'Unknown' then
                -- Convert to string if it's a number (timestamp)
                local dateStr = tostring(veh.regExpDate)
                
                -- Check if registration is expired or expiring soon
                local expYear, expMonth, expDay = dateStr:match("(%d+)-(%d+)-(%d+)")
                if expYear and expMonth and expDay then
                    local expTime = os.time({year = tonumber(expYear) --[[@as integer]], month = tonumber(expMonth) --[[@as integer]], day = tonumber(expDay) --[[@as integer]]})
                    local currentTime = os.time()
                    local timeDiff = expTime - currentTime

                    if currentTime > expTime then
                        statusColor = 'red'
                        statusText = 'Expired'
                        timeRemaining = 'Expired'
                    else
                        -- Calculate days remaining
                        local daysRemaining = math.floor(timeDiff / (24 * 60 * 60))

                        if daysRemaining < 30 then
                            statusColor = 'yellow'
                            statusText = 'Expiring Soon'
                        end

                        -- Format time remaining
                        if daysRemaining >= 365 then
                            local years = math.floor(daysRemaining / 365)
                            local days = daysRemaining % 365
                            timeRemaining = string.format('%d year%s, %d day%s', years, years > 1 and 's' or '', days, days ~= 1 and 's' or '')
                        elseif daysRemaining >= 30 then
                            local months = math.floor(daysRemaining / 30)
                            local days = daysRemaining % 30
                            timeRemaining = string.format('%d month%s, %d day%s', months, months > 1 and 's' or '', days, days ~= 1 and 's' or '')
                        else
                            timeRemaining = string.format('%d day%s', daysRemaining, daysRemaining ~= 1 and 's' or '')
                        end
                    end
                else
                    -- If date format doesn't match, try to handle timestamp
                    timeRemaining = 'Invalid Date Format'
                end
            end

            options[#options + 1] = {
                title = veh.model or 'Unknown Vehicle',
                description = string.format('Plate: %s | Expires: %s', veh.plate, veh.regExpDate and tostring(veh.regExpDate) or 'Unknown'),
                icon = 'car',
                iconColor = statusColor,
                metadata = {
                    {label = 'Status', value = statusText},
                    {label = 'Time Remaining', value = timeRemaining},
                    {label = 'Renewal Cost', value = '$' .. lib.math.groupdigits(sharedConfig.registration.cost)}
                },
                onSelect = function()
                    RenewRegistration(veh)
                end
            }
        end

        lib.registerContext({
            id = 'vehicle_registration_menu',
            title = 'Vehicle Registration Renewal',
            options = options
        })

        lib.showContext('vehicle_registration_menu')
    end)
end

function RenewRegistration(vehicleInfo)
    local alert = lib.alertDialog({
        header = 'Renew Registration',
        content = string.format(
            '**Vehicle:** %s  \n**Plate:** %s  \n**Current Expiration:** %s  \n\n**Renewal Cost:** $%s  \n\nRenew registration for 1 year?',
            vehicleInfo.model or 'Unknown',
            vehicleInfo.plate,
            vehicleInfo.regExpDate or 'Unknown',
            lib.math.groupdigits(sharedConfig.registration.cost)
        ),
        centered = true,
        cancel = true,
        labels = {
            confirm = 'Renew Registration',
            cancel = 'Cancel'
        }
    })

    if alert == 'confirm' then
        TriggerServerEvent('qbx_vehicleshop:server:renewRegistration', vehicleInfo.plate)
        -- Reopen menu after renewal
        SetTimeout(1000, function()
            OpenRegistrationMenu()
        end)
    else
        -- Just reopen the menu if cancelled
        OpenRegistrationMenu()
    end
end

-- Cleanup on resource stop
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    if dmvPed and DoesEntityExist(dmvPed) then
        DeleteEntity(dmvPed)
    end
end)
