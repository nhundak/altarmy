-- AltArmy TBC — DataStore module: mail.
-- Requires DataStore.lua (core) loaded first.

if not AltArmy or not AltArmy.DataStore then return end

local DS = AltArmy.DataStore
local DATA_VERSIONS = DS._DATA_VERSIONS

local MAIL_ICON_COIN = "Interface\\Icons\\INV_Misc_Coin_01"
local MAIL_ICON_NOTE = "Interface\\Icons\\INV_Misc_Note_01"
local ATTACHMENTS_MAX_SEND = 12
local MAIL_EXPIRY_DAYS = 30

-- Luacheck-friendly aliases (WoW API globals exist in-game; may be absent in tests)
local strsplit = _G.strsplit
local hooksecurefunc = _G.hooksecurefunc
local GetSendMailItem = _G.GetSendMailItem
local GetSendMailItemLink = _G.GetSendMailItemLink
local GetSendMailMoney = _G.GetSendMailMoney

local function Now()
    return (time and time()) or 0
end

local function NormalizeName(s)
    if not s or s == "" then return "" end
    return string.lower(s)
end

local function FindCharacterByName(realm, name)
    if not realm or not name or name == "" then return nil end
    local chars = DS.GetCharacters and DS:GetCharacters(realm) or nil
    if not chars then return nil end
    local wanted = NormalizeName(name)
    for charName, charTable in pairs(chars) do
        if NormalizeName(charName) == wanted then
            return charTable
        end
    end
    return nil
end

local function GetCurrentIdentity()
    local name = UnitName and UnitName("player") or nil
    local realm = GetRealmName and GetRealmName() or nil
    return name, realm
end

local function GetMailTable(char, index)
    if not char or not index or index < 1 then return nil end
    local mails = char.Mails or {}
    local cache = char.MailCache or {}
    if index <= #mails then
        return mails[index]
    end
    local j = index - #mails
    return cache[j]
end

function DS:ScanMailbox(_self)
    local getter = self and self._GetCurrentCharTable
    local char = getter and getter() or nil
    if not char then return end
    if not GetInboxNumItems then return end
    char.Mails = char.Mails or {}
    char.MailCache = char.MailCache or {}
    for k in pairs(char.Mails) do char.Mails[k] = nil end
    for k in pairs(char.MailCache) do char.MailCache[k] = nil end
    local numItems = GetInboxNumItems()
    if numItems == 0 then
        char.lastMailCheck = Now()
        char.dataVersions = char.dataVersions or {}
        char.dataVersions.mail = DATA_VERSIONS.mail
        return
    end
    if CheckInbox then CheckInbox() end
    for i = 1, numItems do
        local _, stationaryIcon, mailSender, mailSubject, mailMoney, _, daysLeft, numAttachments, _, wasReturned =
            GetInboxHeaderInfo(i)
        daysLeft = daysLeft or MAIL_EXPIRY_DAYS
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
                        lastCheck = Now(),
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
                lastCheck = Now(),
                daysLeft = daysLeft,
                returned = wasReturned,
            })
        end
    end
    char.lastMailCheck = Now()
    char.lastUpdate = Now()
    char.dataVersions = char.dataVersions or {}
    char.dataVersions.mail = DATA_VERSIONS.mail
end

function DS:GetNumMails(char)
    if not char then return 0 end
    local n = 0
    if char.Mails then n = n + #char.Mails end
    if char.MailCache then n = n + #char.MailCache end
    return n
end

function DS:GetMailInfo(char, index)
    local n = self:GetNumMails(char)
    if not char or not index or index < 1 or index > n then
        return nil, nil, nil, nil, nil, nil, nil, nil
    end
    local data = GetMailTable(char, index)
    if not data then return nil, nil, nil, nil, nil, nil, nil, nil end
    local daysLeft = data.daysLeft
    local lastCheck = data.lastCheck or 0
    if daysLeft and lastCheck then
        daysLeft = daysLeft - (Now() - lastCheck) / 86400
    end
    return data.icon, data.count, data.link, data.money, data.subject, data.sender, daysLeft, data.returned
end

function DS:GetMailItemCount(char, itemID)
    if not char or not itemID then return 0 end
    local count = 0
    if char.Mails then
        for _, v in ipairs(char.Mails) do
            if v.itemID == itemID then
                count = count + (v.count or 1)
            end
        end
    end
    if char.MailCache then
        for _, v in ipairs(char.MailCache) do
            if v.itemID == itemID then
                count = count + (v.count or 1)
            end
        end
    end
    return count
end

function DS:GetMailboxLastVisit(char)
    if not char then return 0 end
    return char.lastMailCheck or 0
end

function DS:GetMailMoneyTotal(char)
    if not char then return 0 end
    local total = 0
    if char.Mails then
        for _, v in ipairs(char.Mails) do
            local m = v and v.money
            if type(m) == "number" and m > 0 then
                total = total + m
            end
        end
    end
    if char.MailCache then
        for _, v in ipairs(char.MailCache) do
            local m = v and v.money
            if type(m) == "number" and m > 0 then
                total = total + m
            end
        end
    end
    return total
end

function DS:SaveMailToCache(char, money, body, subject, sender, returned)
    if not char then return end
    char.MailCache = char.MailCache or {}
    table.insert(char.MailCache, {
        icon = (money and money > 0) and MAIL_ICON_COIN or MAIL_ICON_NOTE,
        money = money or 0,
        text = body or "",
        subject = subject,
        sender = sender,
        lastCheck = Now(),
        daysLeft = MAIL_EXPIRY_DAYS,
        returned = returned or false,
    })
end

function DS:SaveMailAttachmentToCache(char, icon, itemID, link, count, sender, subject, returned)
    if not char or not itemID then return end
    char.MailCache = char.MailCache or {}
    table.insert(char.MailCache, {
        icon = icon or MAIL_ICON_NOTE,
        itemID = itemID,
        count = count or 1,
        sender = sender,
        subject = subject,
        link = link,
        money = 0,
        lastCheck = Now(),
        daysLeft = MAIL_EXPIRY_DAYS,
        returned = returned or false,
    })
end

-- ---------------------------------------------------------------------------
-- Local send/return prediction cache (no guild comm relay)
-- ---------------------------------------------------------------------------

local function CacheSentMailToAlt(recipient, subject, body)
    if not recipient or recipient == "" then return end
    if not GetSendMailItem then return end

    local recipientName = recipient
    if strsplit then
        recipientName = strsplit("-", recipient)
    end

    local _playerName, realm = GetCurrentIdentity()
    if not realm or realm == "" then return end

    local targetChar = FindCharacterByName(realm, recipientName)
    if not targetChar then return end

    for attachmentIndex = 1, ATTACHMENTS_MAX_SEND do
        local itemName, itemID, icon, count = GetSendMailItem(attachmentIndex)
        if itemName and itemID then
            local link = GetSendMailItemLink and GetSendMailItemLink(attachmentIndex) or nil
            DS:SaveMailAttachmentToCache(targetChar, icon, itemID, link, count, _playerName, subject, false)
        end
    end

    body = body or ""
    local money = GetSendMailMoney and GetSendMailMoney() or 0
    if (money and money > 0) or (body and body ~= "") then
        DS:SaveMailToCache(targetChar, money or 0, body, subject, _playerName, false)
    end
end

local function CacheReturnedMailToAlt(index)
    if not index or not GetInboxHeaderInfo then return end
    if not GetInboxItem then return end

    local _, stationaryIcon, mailSender, mailSubject, mailMoney, _, _, numAttachments = GetInboxHeaderInfo(index)
    if not mailSender or mailSender == "" then return end

    local senderName = mailSender
    if strsplit then
        senderName = strsplit("-", mailSender)
    end

    local _playerName, realm = GetCurrentIdentity()
    if not realm or realm == "" then return end

    local targetChar = FindCharacterByName(realm, senderName)
    if not targetChar then return end

    if numAttachments and numAttachments > 0 then
        for attachmentIndex = 1, ATTACHMENTS_MAX_SEND do
            local itemName, itemID, icon, count = GetInboxItem(index, attachmentIndex)
            if itemName and itemID then
                local link = GetInboxItemLink and GetInboxItemLink(index, attachmentIndex) or nil
                DS:SaveMailAttachmentToCache(
                    targetChar,
                    icon or stationaryIcon,
                    itemID,
                    link,
                    count,
                    _playerName,
                    mailSubject,
                    true
                )
            end
        end
    end

    local inboxText = GetInboxText and GetInboxText(index) or nil
    if (mailMoney and mailMoney > 0) or (inboxText and inboxText ~= "") then
        DS:SaveMailToCache(targetChar, mailMoney or 0, inboxText or "", mailSubject, _playerName, true)
    end
end

if hooksecurefunc then
    hooksecurefunc("SendMail", function(recipient, subject, body)
        CacheSentMailToAlt(recipient, subject, body)
    end)

    hooksecurefunc("ReturnInboxItem", function(index)
        CacheReturnedMailToAlt(index)
    end)
end
