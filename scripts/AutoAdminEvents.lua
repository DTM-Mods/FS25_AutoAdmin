-- Auto Admin: network events.
-- AutoAdminRequestEvent  client -> server   the admin screen: open / close / change a role / forget / setting
-- AutoAdminDataEvent     server -> client   the player list for the admin screen (+ the result of a request)
-- AutoAdminNoticeEvent   server -> client   a notification for one player ("admin rights restored", ...)
-- AutoAdminRevokeEvent   server -> clients  a player's admin rights were taken away
-- Author: Fennell

----------------------------------------------------------------------------------------------------------------
AutoAdminRequestEvent = {}
local AutoAdminRequestEvent_mt = Class(AutoAdminRequestEvent, Event)
InitEventClass(AutoAdminRequestEvent, "AutoAdminRequestEvent")

function AutoAdminRequestEvent.emptyNew()
    return Event.new(AutoAdminRequestEvent_mt)
end

function AutoAdminRequestEvent.new(action, entryId, value)
    local self = AutoAdminRequestEvent.emptyNew()
    self.action = action
    self.entryId = entryId
    self.value = value
    return self
end

function AutoAdminRequestEvent:writeStream(streamId, connection)
    streamWriteUInt8(streamId, self.action)
    streamWriteInt32(streamId, self.entryId)
    streamWriteUInt8(streamId, self.value)
end

function AutoAdminRequestEvent:readStream(streamId, connection)
    self.action = streamReadUInt8(streamId)
    self.entryId = streamReadInt32(streamId)
    self.value = streamReadUInt8(streamId)
    self:run(connection)
end

function AutoAdminRequestEvent:run(connection)
    if not connection:getIsServer() then
        AutoAdmin:onRequest(connection, self.action, self.entryId, self.value)
    end
end

----------------------------------------------------------------------------------------------------------------
AutoAdminDataEvent = {}
local AutoAdminDataEvent_mt = Class(AutoAdminDataEvent, Event)
InitEventClass(AutoAdminDataEvent, "AutoAdminDataEvent")

AutoAdminDataEvent.MAX_ENTRIES = 1000

function AutoAdminDataEvent.emptyNew()
    return Event.new(AutoAdminDataEvent_mt)
end

-- data = {canManage, rememberPasswordLogins, message, entries = {see AutoAdmin:buildList}}
function AutoAdminDataEvent.new(data)
    local self = AutoAdminDataEvent.emptyNew()
    self.data = data
    return self
end

function AutoAdminDataEvent:writeStream(streamId, connection)
    local data = self.data
    streamWriteBool(streamId, data.canManage)
    streamWriteBool(streamId, data.rememberPasswordLogins)
    streamWriteString(streamId, data.message)
    local count = math.min(#data.entries, AutoAdminDataEvent.MAX_ENTRIES)
    streamWriteUInt16(streamId, count)
    for i = 1, count do
        local e = data.entries[i]
        streamWriteInt32(streamId, e.id)
        streamWriteString(streamId, e.name)
        streamWriteUInt8(streamId, e.role)
        streamWriteBool(streamId, e.online)
        streamWriteBool(streamId, e.isAdminNow)
        streamWriteBool(streamId, e.isYou)
        streamWriteString(streamId, e.firstSeen)
        streamWriteString(streamId, e.lastSeen)
        streamWriteString(streamId, e.changed)
        streamWriteUInt8(streamId, e.changedBy)
        streamWriteString(streamId, e.changedByName)
        streamWriteBool(streamId, e.locked)
        streamWriteInt32(streamId, e.restored)
    end
end

function AutoAdminDataEvent:readStream(streamId, connection)
    local data = {entries = {}}
    data.canManage = streamReadBool(streamId)
    data.rememberPasswordLogins = streamReadBool(streamId)
    data.message = streamReadString(streamId)
    for _ = 1, streamReadUInt16(streamId) do
        local e = {}
        e.id = streamReadInt32(streamId)
        e.name = streamReadString(streamId)
        e.role = streamReadUInt8(streamId)
        e.online = streamReadBool(streamId)
        e.isAdminNow = streamReadBool(streamId)
        e.isYou = streamReadBool(streamId)
        e.firstSeen = streamReadString(streamId)
        e.lastSeen = streamReadString(streamId)
        e.changed = streamReadString(streamId)
        e.changedBy = streamReadUInt8(streamId)
        e.changedByName = streamReadString(streamId)
        e.locked = streamReadBool(streamId)
        e.restored = streamReadInt32(streamId)
        table.insert(data.entries, e)
    end
    self.data = data
    self:run(connection)
end

function AutoAdminDataEvent:run(connection)
    if connection:getIsServer() then
        AutoAdmin.onData(self.data)
    end
end

----------------------------------------------------------------------------------------------------------------
AutoAdminNoticeEvent = {}
local AutoAdminNoticeEvent_mt = Class(AutoAdminNoticeEvent, Event)
InitEventClass(AutoAdminNoticeEvent, "AutoAdminNoticeEvent")

function AutoAdminNoticeEvent.emptyNew()
    return Event.new(AutoAdminNoticeEvent_mt)
end

function AutoAdminNoticeEvent.new(key, arg, isWarning)
    local self = AutoAdminNoticeEvent.emptyNew()
    self.key = key
    self.arg = arg
    self.isWarning = isWarning
    return self
end

function AutoAdminNoticeEvent:writeStream(streamId, connection)
    streamWriteString(streamId, self.key)
    streamWriteString(streamId, self.arg)
    streamWriteBool(streamId, self.isWarning)
end

function AutoAdminNoticeEvent:readStream(streamId, connection)
    self.key = streamReadString(streamId)
    self.arg = streamReadString(streamId)
    self.isWarning = streamReadBool(streamId)
    self:run(connection)
end

function AutoAdminNoticeEvent:run(connection)
    if connection:getIsServer() then
        AutoAdmin.onNotice(self.key, self.arg, self.isWarning)
    end
end

----------------------------------------------------------------------------------------------------------------
AutoAdminRevokeEvent = {}
local AutoAdminRevokeEvent_mt = Class(AutoAdminRevokeEvent, Event)
InitEventClass(AutoAdminRevokeEvent, "AutoAdminRevokeEvent")

function AutoAdminRevokeEvent.emptyNew()
    return Event.new(AutoAdminRevokeEvent_mt)
end

function AutoAdminRevokeEvent.new(userId)
    local self = AutoAdminRevokeEvent.emptyNew()
    self.userId = userId
    return self
end

function AutoAdminRevokeEvent:writeStream(streamId, connection)
    streamWriteInt32(streamId, self.userId)
end

function AutoAdminRevokeEvent:readStream(streamId, connection)
    self.userId = streamReadInt32(streamId)
    self:run(connection)
end

function AutoAdminRevokeEvent:run(connection)
    if connection:getIsServer() then
        AutoAdmin.onRevoke(self.userId)
    end
end
