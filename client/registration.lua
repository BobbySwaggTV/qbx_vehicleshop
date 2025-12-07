local sharedConfig = require 'config.shared'

if not sharedConfig.registration.enable then return end

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

-- Create ox_lib point for interaction
local registrationPoint = lib.points.new({
    coords = sharedConfig.registration.zone,
    distance = 10,
})

function registrationPoint:onEnter()
    lib.showTextUI('[E] Vehicle Registration Renewal', {
        position = "left-center",
        icon = 'file-contract',
    })
end

function registrationPoint:onExit()
    lib.hideTextUI()
end

function registrationPoint:nearby()
    if self.currentDistance < 2.0 and IsControlJustPressed(0, 38) then -- E key
        OpenRegistrationMenu()
    end
end

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

            -- Check if registration is expired
            if veh.regExpDate and veh.regExpDate ~= 'Unknown' then
                local expYear, expMonth, expDay = veh.regExpDate:match("(%d+)-(%d+)-(%d+)")
                if expYear and expMonth and expDay then
                    local expTime = os.time({year = tonumber(expYear) --[[@as integer]], month = tonumber(expMonth) --[[@as integer]], day = tonumber(expDay) --[[@as integer]]})
                    local currentTime = os.time()
                    if currentTime > expTime then
                        statusColor = 'red'
                        statusText = 'Expired'
                    elseif (expTime - currentTime) < (30 * 24 * 60 * 60) then -- Less than 30 days
                        statusColor = 'yellow'
                        statusText = 'Expiring Soon'
                    end
                end
            end

            options[#options + 1] = {
                title = veh.model or 'Unknown Vehicle',
                description = string.format('Plate: %s | Expires: %s', veh.plate, veh.regExpDate or 'Unknown'),
                icon = 'car',
                iconColor = statusColor,
                metadata = {
                    {label = 'Status', value = statusText},
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
