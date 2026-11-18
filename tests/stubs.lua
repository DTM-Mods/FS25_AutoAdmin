-- Stand-ins for the game, enough to run the server side of Auto Admin offline (tests/run.py, Lua 5.1 via lupa).
-- The user manager behaves like FS22's UserManager (addMasterUserByConnection -> addMasterUser -> isMasterUser).

g_currentModName = "FS25_AutoAdmin"
g_currentModDirectory = "mod/"
g_currentModSettingsDirectory = "modSettings/FS25_AutoAdmin/"

LOG = {}
local realPrint = print
function print(text)
    table.insert(LOG, tostring(text))
end

CLOCK_DATE = "2026-11-18 20:00"
function getDate(format)
    return CLOCK_DATE
end
function getUserProfileAppPath()
    return "profile/"
end

Utils = {}
function Utils.appendedFunction(old, new)
    return function(...)
        local a, b, c = old(...)
        new(...)
        return a, b, c
    end
end
function Utils.getNoNil(value, default)
    if value == nil then
        return default
    end
    return value
end

function Class(members, base)
    local mt = {__index = members}
    if base ~= nil then
        setmetatable(members, {__index = base})
    end
    members.superClass = function()
        return base
    end
    return mt
end

Event = {}
function Event.new(mt)
    return setmetatable({}, mt)
end
EVENT_CLASSES = {}
function InitEventClass(class, name)
    EVENT_CLASSES[name] = class
end

MessageDialog = {}
function MessageDialog.new(target, mt)
    return setmetatable({}, mt)
end

FSBaseMission = {INGAME_NOTIFICATION_OK = 1, INGAME_NOTIFICATION_CRITICAL = 2}
function FSBaseMission.onConnectionFinishedLoading(mission, connection) end
Mission00 = {}
function Mission00.loadMission00Finished(mission) end
PlayerInputComponent = {}
function PlayerInputComponent.registerGlobalPlayerActionEvents(component) end

MOD_LISTENERS = {}
function addModEventListener(listener)
    table.insert(MOD_LISTENERS, listener)
end

g_i18n = {}
function g_i18n:getText(key, modName)
    return (AA_TEXTS ~= nil and AA_TEXTS[key]) or key
end

----------------------------------------------------------------------------------------------------------------
-- XML files, in memory
----------------------------------------------------------------------------------------------------------------
FILES = {}
local handles, nextHandle = {}, 1

function fileExists(path)
    return FILES[path] ~= nil
end
function createFolder(path) end

local function open(path, data)
    local h = nextHandle
    nextHandle = nextHandle + 1
    handles[h] = {path = path, data = data}
    return h
end
function loadXMLFile(name, path)
    if FILES[path] == nil then
        return 0
    end
    local copy = {}
    for k, v in pairs(FILES[path]) do
        copy[k] = v
    end
    return open(path, copy)
end
function createXMLFile(name, path, root)
    return open(path, {})
end
function saveXMLFile(h)
    local copy = {}
    for k, v in pairs(handles[h].data) do
        copy[k] = v
    end
    FILES[handles[h].path] = copy
end
function delete(h)
    handles[h] = nil
end
function hasXMLProperty(h, key)
    for k in pairs(handles[h].data) do
        if k == key or k:sub(1, #key + 1) == key .. "#" or k:sub(1, #key + 1) == key .. "." then
            return true
        end
    end
    return false
end
local function getter(h, key)
    return handles[h].data[key]
end
local function setter(h, key, value)
    handles[h].data[key] = value
end
getXMLString, getXMLInt, getXMLBool = getter, getter, getter
setXMLString, setXMLInt, setXMLBool = setter, setter, setter

----------------------------------------------------------------------------------------------------------------
-- Network: connections record what they were sent; streams are plain lists
----------------------------------------------------------------------------------------------------------------
Connection = {}
Connection.__index = Connection
function Connection.new(isLocal)
    return setmetatable({sent = {}, isLocal = isLocal == true}, Connection)
end
function Connection:getIsServer()
    return false
end
function Connection:getIsLocal()
    return self.isLocal
end
function Connection:sendEvent(event)
    table.insert(self.sent, event)
end

BROADCASTS = {}
g_server = {}
function g_server:broadcastEvent(event)
    table.insert(BROADCASTS, event)
end

STREAM = nil
local function w(_, value)
    table.insert(STREAM.data, value)
end
local function r()
    STREAM.pos = STREAM.pos + 1
    return STREAM.data[STREAM.pos]
end
streamWriteUInt8, streamWriteUInt16, streamWriteInt32, streamWriteString, streamWriteBool = w, w, w, w, w
streamReadUInt8, streamReadUInt16, streamReadInt32, streamReadString, streamReadBool = r, r, r, r, r

----------------------------------------------------------------------------------------------------------------
-- Users and the user manager (FS22 behaviour)
----------------------------------------------------------------------------------------------------------------
User = {}
User.__index = User
local nextUserId = 10
function User.new(name, uniqueUserId, connection)
    nextUserId = nextUserId + 1
    return setmetatable({id = nextUserId, name = name, uniqueUserId = uniqueUserId, connection = connection,
        isMasterUser = false}, User)
end
function User:getId() return self.id end
function User:getNickname() return self.name end
function User:getUniqueUserId() return self.uniqueUserId end
function User:getConnection() return self.connection end
function User:getIsMasterUser() return self.isMasterUser end
function User:setIsMasterUser(value) self.isMasterUser = value end

UserManager = {}
local UserManager_mt = {__index = UserManager}
function UserManager.new()
    return setmetatable({users = {}, masterUsers = {}, isServer = true}, UserManager_mt)
end
function UserManager:getUsers() return self.users end
function UserManager:getUserByConnection(connection)
    for _, user in ipairs(self.users) do
        if user.connection == connection then
            return user
        end
    end
    return nil
end
function UserManager:getUserByUserId(id)
    for _, user in ipairs(self.users) do
        if user.id == id then
            return user
        end
    end
    return nil
end
function UserManager:addMasterUserByConnection(connection)
    local user = self:getUserByConnection(connection)
    if user ~= nil then
        self:addMasterUser(user)
    end
end
function UserManager:addMasterUser(user)
    table.insert(self.masterUsers, user)
    user:setIsMasterUser(true)
end
function UserManager:removeMasterUser(user)
    user:setIsMasterUser(false)
    for i, other in ipairs(self.masterUsers) do
        if other == user then
            table.remove(self.masterUsers, i)
            break
        end
    end
end

function newMission(isServer)
    g_currentMission = {
        userManager = UserManager.new(),
        missionDynamicInfo = {isMultiplayer = true},
        isServerFlag = isServer ~= false,
        notifications = {}
    }
    function g_currentMission:getIsServer() return self.isServerFlag end
    function g_currentMission:addIngameNotification(kind, text) table.insert(self.notifications, text) end
    return g_currentMission
end
