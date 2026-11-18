-- Auto Admin: the server remembers every player's role and gives admins their admin rights back when they join.
--
-- Roles: SUPER ADMIN > ADMIN > MEMBER.
--   super admin  admin on every join; can't be demoted in the game (only in the server's file)
--   admin        admin on every join; a super admin can demote them to member, right away, even while online
--   member       no admin rights
-- Only super admins change roles (the admin screen, Left Alt + A by default); admins can look at the list.
-- No password is stored anywhere: the server keeps the players' unique user ids and their roles in
-- <server profile>/modSettings/FS25_AutoAdmin/admins.xml.
--
-- The admin password still works as in the base game. A member who logs in with it becomes an admin (unless a
-- super admin turned "Remember password logins" off). A member a super admin demoted is locked out: their
-- password login is undone a moment later. The very first password login on a server without a super admin
-- makes that player the super admin.
--
-- Game functions used (FS22 names, still in FS25; the server log shows which were found at start):
--   UserManager:addMasterUserByConnection / addMasterUser / removeMasterUser, User:getIsMasterUser,
--   FSBaseMission.onConnectionFinishedLoading (a player finished joining).
-- Author: Fennell

AutoAdmin = {}
AutoAdmin.modName = g_currentModName
AutoAdmin.modDirectory = g_currentModDirectory
AutoAdmin.settingsDirectory = g_currentModSettingsDirectory
AutoAdmin.FILENAME = "admins.xml"

AutoAdmin.ROLE = {MEMBER = 0, ADMIN = 1, SUPER = 2}
AutoAdmin.ROLE_KEYS = {[0] = "member", [1] = "admin", [2] = "superAdmin"}

-- who gave a player their role (shown in the admin screen)
AutoAdmin.BY = {NONE = 0, PASSWORD = 1, FIRST = 2, PLAYER = 3, FILE = 4, HOST = 5}

-- wait this long after a player finished loading before making them admin (their game is ready by then)
AutoAdmin.JOIN_DELAY = 3000
-- a locked-out member's password login is undone this long after it (after the game's own "granted" answer)
AutoAdmin.REVOKE_DELAY = 1500

local function log(text, ...)
    print(string.format("[AutoAdmin] " .. text, ...))
end

local function now()
    return getDate("%Y-%m-%d %H:%M")
end

function AutoAdmin.getText(key)
    return g_i18n:getText(key, AutoAdmin.modName)
end

----------------------------------------------------------------------------------------------------------------
-- Mission start / end
----------------------------------------------------------------------------------------------------------------

function AutoAdmin:loadMap(filename)
    self.players = {}
    self.byUniqueId = {}
    self.nextEntryId = 1
    self.settings = {rememberPasswordLogins = true}
    self.pending = {}
    self.subscribers = {}
    self.clock = 0
    self.granting = false
    self.clientData = nil

    local mission = g_currentMission
    self.isMultiplayer = mission ~= nil and mission.missionDynamicInfo ~= nil and mission.missionDynamicInfo.isMultiplayer == true
    self.isServer = mission ~= nil and mission:getIsServer()

    if self.isServer and self.isMultiplayer then
        self:loadFromFile()
        local um = mission.userManager
        log("server ready, %d players on the list (%s). Game functions: addMasterUserByConnection=%s addMasterUser=%s removeMasterUser=%s",
            #self.players, self:getFilename(), tostring(um ~= nil and um.addMasterUserByConnection ~= nil),
            tostring(um ~= nil and um.addMasterUser ~= nil), tostring(um ~= nil and um.removeMasterUser ~= nil))
    end
end

function AutoAdmin:deleteMap()
    self.pending = {}
    self.subscribers = {}
    self.clientData = nil
end

function AutoAdmin:update(dt)
    if not self.isServer or #self.pending == 0 then
        return
    end
    self.clock = self.clock + dt
    local due = {}
    for i = #self.pending, 1, -1 do
        local job = self.pending[i]
        if job.time <= self.clock then
            table.remove(self.pending, i)
            table.insert(due, 1, job)
        end
    end
    for _, job in ipairs(due) do
        if job.kind == "join" then
            self:onJoinDue(job.connection)
        elseif job.kind == "lockout" then
            self:onLockoutDue(job.connection)
        end
    end
end

function AutoAdmin:schedule(kind, connection, delay)
    table.insert(self.pending, {kind = kind, connection = connection, time = self.clock + delay})
end

----------------------------------------------------------------------------------------------------------------
-- The list (server only)
----------------------------------------------------------------------------------------------------------------

function AutoAdmin:getFilename()
    local dir = self.settingsDirectory
    if dir == nil or dir == "" then
        dir = getUserProfileAppPath() .. "modSettings/" .. self.modName .. "/"
    end
    return dir .. self.FILENAME, dir
end

function AutoAdmin.roleFromKey(key)
    for role, name in pairs(AutoAdmin.ROLE_KEYS) do
        if name == key then
            return role
        end
    end
    return AutoAdmin.ROLE.MEMBER
end

function AutoAdmin:addEntry(uniqueUserId, name)
    local entry = {
        id = self.nextEntryId,
        uniqueUserId = uniqueUserId,
        name = name or "?",
        role = AutoAdmin.ROLE.MEMBER,
        firstSeen = now(),
        lastSeen = "",
        changed = "",
        changedBy = AutoAdmin.BY.NONE,
        changedByName = "",
        locked = false,
        restored = 0
    }
    self.nextEntryId = self.nextEntryId + 1
    table.insert(self.players, entry)
    self.byUniqueId[uniqueUserId] = entry
    return entry
end

function AutoAdmin:getEntryById(id)
    for _, entry in ipairs(self.players) do
        if entry.id == id then
            return entry
        end
    end
    return nil
end

function AutoAdmin:getOrAddEntry(user)
    local uniqueUserId = user:getUniqueUserId()
    if uniqueUserId == nil or uniqueUserId == "" then
        return nil
    end
    local entry = self.byUniqueId[uniqueUserId]
    if entry == nil then
        entry = self:addEntry(uniqueUserId, user:getNickname())
    elseif user:getNickname() ~= nil and user:getNickname() ~= "" then
        entry.name = user:getNickname()
    end
    return entry
end

function AutoAdmin:hasSuperAdmin()
    for _, entry in ipairs(self.players) do
        if entry.role == AutoAdmin.ROLE.SUPER then
            return true
        end
    end
    return false
end

function AutoAdmin:setRole(entry, role, by, byName)
    entry.role = role
    entry.changed = now()
    entry.changedBy = by
    entry.changedByName = byName or ""
    -- a demoted player is locked out of the admin password; promoting them again lets them back in
    entry.locked = role == AutoAdmin.ROLE.MEMBER and by == AutoAdmin.BY.PLAYER
end

function AutoAdmin:loadFromFile()
    local filename = self:getFilename()
    if not fileExists(filename) then
        return
    end
    local xml = loadXMLFile("autoAdmin", filename)
    if xml == nil or xml == 0 then
        log("could not read %s", filename)
        return
    end
    self.settings.rememberPasswordLogins = Utils.getNoNil(getXMLBool(xml, "autoAdmin.settings#rememberPasswordLogins"), true)
    local i = 0
    while true do
        local key = string.format("autoAdmin.players.player(%d)", i)
        if not hasXMLProperty(xml, key) then
            break
        end
        local uniqueUserId = getXMLString(xml, key .. "#uniqueUserId")
        if uniqueUserId ~= nil and uniqueUserId ~= "" and self.byUniqueId[uniqueUserId] == nil then
            local entry = self:addEntry(uniqueUserId, getXMLString(xml, key .. "#name"))
            entry.role = AutoAdmin.roleFromKey(getXMLString(xml, key .. "#role"))
            entry.firstSeen = getXMLString(xml, key .. "#firstSeen") or ""
            entry.lastSeen = getXMLString(xml, key .. "#lastSeen") or ""
            entry.changed = getXMLString(xml, key .. "#changed") or ""
            entry.changedBy = getXMLInt(xml, key .. "#changedBy") or AutoAdmin.BY.FILE
            entry.changedByName = getXMLString(xml, key .. "#changedByName") or ""
            entry.locked = Utils.getNoNil(getXMLBool(xml, key .. "#locked"), false)
            entry.restored = getXMLInt(xml, key .. "#restored") or 0
        end
        i = i + 1
    end
    delete(xml)
end

function AutoAdmin:saveToFile()
    local filename, dir = self:getFilename()
    createFolder(dir)
    local xml = createXMLFile("autoAdmin", filename, "autoAdmin")
    if xml == nil or xml == 0 then
        log("could not write %s", filename)
        return
    end
    setXMLInt(xml, "autoAdmin#version", 1)
    setXMLBool(xml, "autoAdmin.settings#rememberPasswordLogins", self.settings.rememberPasswordLogins)
    for i, entry in ipairs(self.players) do
        local key = string.format("autoAdmin.players.player(%d)", i - 1)
        setXMLString(xml, key .. "#name", entry.name)
        setXMLString(xml, key .. "#role", AutoAdmin.ROLE_KEYS[entry.role])
        setXMLString(xml, key .. "#uniqueUserId", entry.uniqueUserId)
        setXMLString(xml, key .. "#firstSeen", entry.firstSeen)
        setXMLString(xml, key .. "#lastSeen", entry.lastSeen)
        setXMLString(xml, key .. "#changed", entry.changed)
        setXMLInt(xml, key .. "#changedBy", entry.changedBy)
        setXMLString(xml, key .. "#changedByName", entry.changedByName)
        setXMLBool(xml, key .. "#locked", entry.locked)
        setXMLInt(xml, key .. "#restored", entry.restored)
    end
    saveXMLFile(xml)
    delete(xml)
end

----------------------------------------------------------------------------------------------------------------
-- Admin rights (server only)
----------------------------------------------------------------------------------------------------------------

function AutoAdmin:getOnlineUser(uniqueUserId)
    for _, user in ipairs(g_currentMission.userManager:getUsers()) do
        if user:getUniqueUserId() == uniqueUserId then
            return user
        end
    end
    return nil
end

-- the game's own host (listen server) is never on the list: it is always admin
function AutoAdmin.isHostUser(user)
    local connection = user:getConnection()
    return connection == nil or connection:getIsLocal()
end

function AutoAdmin:grant(user)
    local um = g_currentMission.userManager
    self.granting = true
    if um.addMasterUserByConnection ~= nil and user:getConnection() ~= nil then
        um:addMasterUserByConnection(user:getConnection())
    elseif um.addMasterUser ~= nil then
        um:addMasterUser(user)
    else
        log("can't make %s admin: the game has no addMasterUser", tostring(user:getNickname()))
    end
    self.granting = false
end

function AutoAdmin:revoke(user)
    local um = g_currentMission.userManager
    if um.removeMasterUser ~= nil then
        um:removeMasterUser(user)
    else
        user:setIsMasterUser(false)
    end
    -- the game has no "admin removed" message: our event takes it away on every client too
    g_server:broadcastEvent(AutoAdminRevokeEvent.new(user:getId()))
end

function AutoAdmin:notify(user, key, arg, isWarning)
    local connection = user:getConnection()
    if connection ~= nil then
        connection:sendEvent(AutoAdminNoticeEvent.new(key, arg or "", isWarning == true))
    end
end

-- a player finished joining: remember them, and make admins admin (a moment later, see JOIN_DELAY)
function AutoAdmin.onConnectionFinishedLoading(mission, connection)
    local self = AutoAdmin
    if self.isServer and self.isMultiplayer and connection ~= nil then
        self:schedule("join", connection, AutoAdmin.JOIN_DELAY)
    end
end

function AutoAdmin:onJoinDue(connection)
    local user = g_currentMission.userManager:getUserByConnection(connection)
    if user == nil or AutoAdmin.isHostUser(user) then
        return
    end
    local entry = self:getOrAddEntry(user)
    if entry == nil then
        return
    end
    entry.lastSeen = now()
    if entry.role >= AutoAdmin.ROLE.ADMIN and not user:getIsMasterUser() then
        self:grant(user)
        entry.restored = entry.restored + 1
        log("%s joined: %s, admin rights given", entry.name, AutoAdmin.ROLE_KEYS[entry.role])
        self:notify(user, entry.role == AutoAdmin.ROLE.SUPER and "aa_notice_welcomeSuper" or "aa_notice_welcomeAdmin", entry.name)
    end
    self:saveToFile()
    self:pushToSubscribers()
end

-- somebody became admin: with the admin password (or our own grant, which is ignored here)
function AutoAdmin.onMasterUserAdded(userManager, user)
    local self = AutoAdmin
    if not self.isServer or not self.isMultiplayer or self.granting or user == nil or AutoAdmin.isHostUser(user) then
        return
    end
    local entry = self:getOrAddEntry(user)
    if entry == nil then
        return
    end
    if entry.role >= AutoAdmin.ROLE.ADMIN then
        return
    end
    if entry.locked then
        log("%s logged in with the admin password but was demoted by a super admin: undone", entry.name)
        self:schedule("lockout", user:getConnection(), AutoAdmin.REVOKE_DELAY)
        return
    end
    if not self:hasSuperAdmin() then
        self:setRole(entry, AutoAdmin.ROLE.SUPER, AutoAdmin.BY.FIRST)
        log("%s is the first super admin (first admin password login)", entry.name)
        self:notify(user, "aa_notice_firstSuper", entry.name)
    elseif self.settings.rememberPasswordLogins then
        self:setRole(entry, AutoAdmin.ROLE.ADMIN, AutoAdmin.BY.PASSWORD)
        log("%s logged in with the admin password: now an admin", entry.name)
        self:notify(user, "aa_notice_remembered", entry.name)
    else
        return
    end
    self:saveToFile()
    self:pushToSubscribers()
end

function AutoAdmin:onLockoutDue(connection)
    local user = g_currentMission.userManager:getUserByConnection(connection)
    if user ~= nil and user:getIsMasterUser() then
        local entry = self.byUniqueId[user:getUniqueUserId()]
        if entry ~= nil and entry.role == AutoAdmin.ROLE.MEMBER and entry.locked then
            self:revoke(user)
            self:notify(user, "aa_notice_lockedOut", "", true)
        end
    end
end

----------------------------------------------------------------------------------------------------------------
-- Requests from the admin screen (server only)
----------------------------------------------------------------------------------------------------------------

AutoAdmin.ACTION = {OPEN = 1, CLOSE = 2, SET_ROLE = 3, FORGET = 4, SET_REMEMBER = 5}

-- what the player behind `connection` may do: 0 nothing, 1 look, 2 change roles
function AutoAdmin:getAccess(connection)
    local user = g_currentMission.userManager:getUserByConnection(connection)
    if user == nil then
        return 0, nil, nil
    end
    if AutoAdmin.isHostUser(user) then
        return 2, user, nil
    end
    local entry = self.byUniqueId[user:getUniqueUserId()]
    if entry ~= nil and entry.role == AutoAdmin.ROLE.SUPER then
        return 2, user, entry
    end
    if user:getIsMasterUser() then
        return 1, user, entry
    end
    return 0, user, entry
end

function AutoAdmin:onRequest(connection, action, entryId, value)
    local access, user, senderEntry = self:getAccess(connection)
    if action == AutoAdmin.ACTION.CLOSE then
        self.subscribers[connection] = nil
        return
    end
    if access == 0 then
        connection:sendEvent(AutoAdminNoticeEvent.new("aa_error_notAdmin", "", true))
        return
    end
    if action == AutoAdmin.ACTION.OPEN then
        self.subscribers[connection] = true
        self:sendData(connection, "")
        return
    end
    if access < 2 then
        self:sendData(connection, "aa_error_superOnly")
        return
    end

    local byName = user:getNickname() or "?"
    local message = ""
    if action == AutoAdmin.ACTION.SET_REMEMBER then
        self.settings.rememberPasswordLogins = value == 1
        message = value == 1 and "aa_result_rememberOn" or "aa_result_rememberOff"
        log("%s turned remember password logins %s", byName, value == 1 and "on" or "off")
    else
        local entry = self:getEntryById(entryId)
        if entry == nil then
            self:sendData(connection, "aa_error_gone")
            return
        end
        if entry.role == AutoAdmin.ROLE.SUPER then
            self:sendData(connection, "aa_error_superFixed")
            return
        end
        local target = self:getOnlineUser(entry.uniqueUserId)
        if action == AutoAdmin.ACTION.FORGET then
            if entry.role ~= AutoAdmin.ROLE.MEMBER or target ~= nil then
                self:sendData(connection, "aa_error_forget")
                return
            end
            for i, other in ipairs(self.players) do
                if other == entry then
                    table.remove(self.players, i)
                    break
                end
            end
            self.byUniqueId[entry.uniqueUserId] = nil
            message = "aa_result_forgotten|" .. entry.name
            log("%s removed %s from the list", byName, entry.name)
        elseif action == AutoAdmin.ACTION.SET_ROLE then
            local role = math.max(AutoAdmin.ROLE.MEMBER, math.min(AutoAdmin.ROLE.SUPER, value))
            if role == entry.role then
                self:sendData(connection, "")
                return
            end
            self:setRole(entry, role, AutoAdmin.BY.PLAYER, byName)
            log("%s made %s %s", byName, entry.name, AutoAdmin.ROLE_KEYS[role])
            if role >= AutoAdmin.ROLE.ADMIN then
                message = (role == AutoAdmin.ROLE.SUPER and "aa_result_super|" or "aa_result_admin|") .. entry.name
                if target ~= nil and not target:getIsMasterUser() then
                    self:grant(target)
                end
                if target ~= nil then
                    self:notify(target, role == AutoAdmin.ROLE.SUPER and "aa_notice_promotedSuper" or "aa_notice_promoted", byName)
                end
            else
                message = "aa_result_member|" .. entry.name
                if target ~= nil and target:getIsMasterUser() then
                    self:revoke(target)
                    self:notify(target, "aa_notice_demoted", byName, true)
                end
            end
        end
    end
    self:saveToFile()
    self:sendData(connection, message)
    self:pushToSubscribers(connection)
end

-- the list as the admin screen shows it: super admins, admins, members; online first, then by name
function AutoAdmin:buildList(forConnection)
    local requester = forConnection ~= nil and g_currentMission.userManager:getUserByConnection(forConnection) or nil
    local requesterId = requester ~= nil and requester:getUniqueUserId() or nil
    local list = {}
    for _, entry in ipairs(self.players) do
        local user = self:getOnlineUser(entry.uniqueUserId)
        table.insert(list, {
            id = entry.id,
            name = entry.name,
            role = entry.role,
            online = user ~= nil,
            isAdminNow = user ~= nil and user:getIsMasterUser(),
            isYou = entry.uniqueUserId == requesterId,
            firstSeen = entry.firstSeen,
            lastSeen = entry.lastSeen,
            changed = entry.changed,
            changedBy = entry.changedBy,
            changedByName = entry.changedByName,
            locked = entry.locked,
            restored = entry.restored
        })
    end
    table.sort(list, AutoAdmin.compareEntries)
    return list
end

function AutoAdmin.compareEntries(a, b)
    if a.role ~= b.role then
        return a.role > b.role
    end
    if a.online ~= b.online then
        return a.online
    end
    return string.lower(a.name) < string.lower(b.name)
end

function AutoAdmin:sendData(connection, message)
    local access = self:getAccess(connection)
    if access == 0 then
        self.subscribers[connection] = nil
        return
    end
    connection:sendEvent(AutoAdminDataEvent.new({
        canManage = access == 2,
        rememberPasswordLogins = self.settings.rememberPasswordLogins,
        message = message or "",
        entries = self:buildList(connection)
    }))
end

-- everybody with the admin screen open sees changes right away
function AutoAdmin:pushToSubscribers(except)
    local um = g_currentMission.userManager
    for connection in pairs(self.subscribers) do
        if um:getUserByConnection(connection) == nil then
            self.subscribers[connection] = nil
        elseif connection ~= except then
            self:sendData(connection, "")
        end
    end
end

----------------------------------------------------------------------------------------------------------------
-- Client side
----------------------------------------------------------------------------------------------------------------

function AutoAdmin.showNotification(text, isWarning)
    if g_currentMission ~= nil and g_currentMission.addIngameNotification ~= nil then
        local kind = isWarning and FSBaseMission.INGAME_NOTIFICATION_CRITICAL or FSBaseMission.INGAME_NOTIFICATION_OK
        g_currentMission:addIngameNotification(kind, text)
    end
end

function AutoAdmin.formatMessage(message)
    if message == nil or message == "" then
        return ""
    end
    local key, arg = message:match("^([^|]+)|(.*)$")
    if key == nil then
        return AutoAdmin.getText(message)
    end
    return string.format(AutoAdmin.getText(key), arg)
end

function AutoAdmin.onNotice(key, arg, isWarning)
    local text = AutoAdmin.getText(key)
    if arg ~= nil and arg ~= "" then
        text = string.format(text, arg)
    end
    AutoAdmin.showNotification(text, isWarning)
end

-- the server took admin rights away from a player (a super admin demoted them, or a locked-out password login)
function AutoAdmin.onRevoke(userId)
    local mission = g_currentMission
    if mission == nil or mission.userManager == nil then
        return
    end
    local user = mission.userManager:getUserByUserId(userId)
    if user ~= nil and user:getIsMasterUser() then
        if mission.userManager.removeMasterUser ~= nil then
            mission.userManager:removeMasterUser(user)
        else
            user:setIsMasterUser(false)
        end
    end
    if userId == mission.playerUserId then
        mission.isMasterUser = false
        local menu = g_inGameMenu or mission.inGameMenu
        if menu ~= nil then
            if menu.onMasterUserRemoved ~= nil and user ~= nil then
                menu:onMasterUserRemoved(user)
            else
                menu.isMasterUser = false
                if menu.updateHasMasterRights ~= nil then
                    menu:updateHasMasterRights()
                end
            end
        end
        if AutoAdminDialog.isOpen() then
            AutoAdminDialog.instance:close()
        end
    end
end

function AutoAdmin.onData(data)
    AutoAdmin.clientData = data
    if AutoAdminDialog.instance ~= nil then
        AutoAdminDialog.instance:setData(data)
    end
end

function AutoAdmin.sendRequest(action, entryId, value)
    if g_client ~= nil then
        g_client:getServerConnection():sendEvent(AutoAdminRequestEvent.new(action, entryId or 0, value or 0))
    end
end

-- the key (Left Alt + A): open the admin screen
function AutoAdmin.onOpenKey()
    local mission = g_currentMission
    if mission == nil or g_gui:getIsGuiVisible() then
        return
    end
    if not AutoAdmin.isMultiplayer then
        AutoAdmin.showNotification(AutoAdmin.getText("aa_error_singleplayer"), true)
        return
    end
    if not (mission.isMasterUser or mission:getIsServer()) then
        AutoAdmin.showNotification(AutoAdmin.getText("aa_error_notAdmin"), true)
        return
    end
    AutoAdminDialog.show()
end

----------------------------------------------------------------------------------------------------------------
-- Game hooks
----------------------------------------------------------------------------------------------------------------

-- Class hooks dispatch through these handler fields, set again each time this file runs, so hooks left from an
-- earlier savegame call the current code.
FSBaseMission.autoAdminJoinHandler = AutoAdmin.onConnectionFinishedLoading
if UserManager ~= nil then
    UserManager.autoAdminAddedHandler = AutoAdmin.onMasterUserAdded
end
Mission00.autoAdminLoadedHandler = function(mission)
    if g_dedicatedServer == nil then
        AutoAdminDialog.register()
    end
end
PlayerInputComponent.autoAdminInputHandler = function(component)
    local _, eventId = g_inputBinding:registerActionEvent(InputAction.AUTOADMIN_OPEN, AutoAdmin, AutoAdmin.onOpenKey,
        false, true, false, true)
    if eventId ~= nil then
        g_inputBinding:setActionEventTextVisibility(eventId, false)
    end
end

if not FSBaseMission.autoAdminHooked then
    FSBaseMission.autoAdminHooked = true
    FSBaseMission.onConnectionFinishedLoading = Utils.appendedFunction(FSBaseMission.onConnectionFinishedLoading, function(...)
        if FSBaseMission.autoAdminJoinHandler ~= nil then
            FSBaseMission.autoAdminJoinHandler(...)
        end
    end)
    if UserManager ~= nil and UserManager.addMasterUser ~= nil then
        UserManager.addMasterUser = Utils.appendedFunction(UserManager.addMasterUser, function(...)
            if UserManager.autoAdminAddedHandler ~= nil then
                UserManager.autoAdminAddedHandler(...)
            end
        end)
    else
        print("[AutoAdmin] UserManager.addMasterUser not found: admin password logins are not remembered")
    end
    Mission00.loadMission00Finished = Utils.appendedFunction(Mission00.loadMission00Finished, function(...)
        if Mission00.autoAdminLoadedHandler ~= nil then
            Mission00.autoAdminLoadedHandler(...)
        end
    end)
    PlayerInputComponent.registerGlobalPlayerActionEvents = Utils.appendedFunction(
        PlayerInputComponent.registerGlobalPlayerActionEvents, function(...)
            if PlayerInputComponent.autoAdminInputHandler ~= nil then
                PlayerInputComponent.autoAdminInputHandler(...)
            end
        end)
end

addModEventListener(AutoAdmin)
