-- AltArmy TBC — DataStore module: mail.
-- Requires DataStore.lua (core) loaded first.

if not AltArmy or not AltArmy.DataStore then return end

local DS = AltArmy.DataStore
local GetCurrentCharTable = DS._GetCurrentCharTable
local DATA_VERSIONS = DS._DATA_VERSIONS

local MAIL_ICON_COIN = "Interface\\Icons\\INV_Misc_Coin_01"
local MAIL_ICON_NOTE = "Interface\\Icons\\INV_Misc_Note_01"
local ATTACHMENTS_MAX_SEND = 12

function DS:ScanMailbox(_self)
    local char = GetCurrentCharTable()
    if not char then return end
    if not GetInboxNumItems then return end
    char.Mails = char.Mails or {}
    for k in pairs(char.Mails) do char.Mails[k] = nil end
    local numItems = GetInboxNumItems()
    if numItems == 0 then
        char.lastMailCheck = time()
        char.dataVersions = char.dataVersions or {}
        char.dataVersions.mail = DATA_VERSIONS.mail
        return
    end
    if CheckInbox then CheckInbox() end
    for i = 1, numItems do
        local _, stationaryIcon, mailSender, mailSubject, mailMoney, _, daysLeft, numAttachments, _, wasReturned =
            GetInboxHeaderInfo(i)
        daysLeft = daysLeft or 30
        if numAttachments and numAttachments > 0 then
            for attachIndex = 1, ATTACHMENTS_MAX_SEND do
                local itemName, itemID, icon, count = GetInboxItem(i, attachIndex)
                if itemName and itemID then
                    local link = GetInboxItemLink and GetInboxItemLink(i, attachIndex)
                    table.insert(char.Mails, {
                        icon = icon or MAIL_ICON_NOTE,
                        itemID = itemID,
                        count = count or 1,
                        sender = mailSender,
                        link = link,
                        money = 0,
                        subject = mailSubject,
                        lastCheck = time(),
                        daysLeft = daysLeft,
                        returned = wasReturned,
                    })
                end
            end
        end
        local inboxText
        if GetInboxText then inboxText = GetInboxText(i) end
        if (mailMoney and mailMoney > 0) or (inboxText and inboxText ~= "") then
            local mailIcon = (mailMoney and mailMoney > 0) and MAIL_ICON_COIN or (stationaryIcon or MAIL_ICON_NOTE)
            table.insert(char.Mails, {
                icon = mailIcon,
                itemID = nil,
                count = nil,
                sender = mailSender,
                link = nil,
                money = mailMoney or 0,
                subject = mailSubject,
                text = inboxText,
                lastCheck = time(),
                daysLeft = daysLeft,
                returned = wasReturned,
            })
        end
    end
    char.lastMailCheck = time()
    char.lastUpdate = time()
    char.dataVersions = char.dataVersions or {}
    char.dataVersions.mail = DATA_VERSIONS.mail
end

function DS:GetNumMails(_self, char)
    if not char or not char.Mails then return 0 end
    return #char.Mails
end

function DS:GetMailInfo(_self, char, index)
    if not char or not char.Mails or not index or index < 1 or index > #char.Mails then
        return nil, nil, nil, nil, nil, nil, nil, nil
    end
    local data = char.Mails[index]
    if not data then return nil, nil, nil, nil, nil, nil, nil, nil end
    local daysLeft = data.daysLeft
    local lastCheck = data.lastCheck or 0
    if daysLeft and lastCheck then
        daysLeft = daysLeft - (time() - lastCheck) / 86400
    end
    return data.icon, data.count, data.link, data.money, data.subject, data.sender, daysLeft, data.returned
end

function DS:GetMailItemCount(_self, char, itemID)
    if not char or not char.Mails or not itemID then return 0 end
    local count = 0
    for _, v in ipairs(char.Mails) do
        if v.itemID == itemID then
            count = count + (v.count or 1)
        end
    end
    return count
end

function DS:GetMailboxLastVisit(_self, char)
    if not char then return 0 end
    return char.lastMailCheck or 0
end
