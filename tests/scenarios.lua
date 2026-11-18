-- Auto Admin server scenarios (tests/run.py). Returns the number of failed checks.

local failed, passed = 0, 0
local function check(cond, what)
    if cond then
        passed = passed + 1
    else
        failed = failed + 1
        print("FAIL: " .. what)
    end
end

local ROLE, ACTION = AutoAdmin.ROLE, AutoAdmin.ACTION

local function start()
    FILES_KEEP = FILES
    newMission(true)
    BROADCASTS = {}
    AutoAdmin:loadMap("map.xml")
    return g_currentMission.userManager
end

local function join(um, name, uid)
    local connection = Connection.new()
    local user = User.new(name, uid, connection)
    table.insert(um.users, user)
    FSBaseMission.onConnectionFinishedLoading(g_currentMission, connection)
    AutoAdmin:update(AutoAdmin.JOIN_DELAY + 1)
    return user, connection
end

local function leave(um, user)
    for i, other in ipairs(um.users) do
        if other == user then
            table.remove(um.users, i)
        end
    end
end

-- the game's admin password login (GetAdminEvent on the server)
local function passwordLogin(um, user)
    um:addMasterUserByConnection(user.connection)
    AutoAdmin:update(AutoAdmin.REVOKE_DELAY + 1)
end

local function lastSent(connection, class)
    for i = #connection.sent, 1, -1 do
        local event = connection.sent[i]
        if getmetatable(event).__index == class then
            return event
        end
    end
    return nil
end

local function entryFor(name)
    for _, entry in ipairs(AutoAdmin.players) do
        if entry.name == name then
            return entry
        end
    end
    return nil
end

local function request(connection, action, entryId, value)
    AutoAdmin:onRequest(connection, action, entryId or 0, value or 0)
    return lastSent(connection, AutoAdminDataEvent)
end

-- 1. the hook on UserManager.addMasterUser is installed
check(UserManager.autoAdminAddedHandler ~= nil, "addMasterUser handler set")

-- 2. players are remembered as members on join; nobody gets admin for free
local um = start()
local chris, chrisConn = join(um, "Chris", "uid-chris")
local steve, steveConn = join(um, "Steve", "uid-steve")
check(entryFor("Chris") ~= nil and entryFor("Chris").role == ROLE.MEMBER, "Chris on the list as member")
check(not chris:getIsMasterUser(), "a member does not get admin on join")

-- 3. the first password login makes the super admin, the next one an admin
passwordLogin(um, chris)
check(entryFor("Chris").role == ROLE.SUPER, "first password login = super admin")
check(entryFor("Chris").changedBy == AutoAdmin.BY.FIRST, "given by: first login")
check(lastSent(chrisConn, AutoAdminNoticeEvent).key == "aa_notice_firstSuper", "Chris told he is the first super admin")
passwordLogin(um, steve)
check(entryFor("Steve").role == ROLE.ADMIN, "next password login = admin")
check(steve:getIsMasterUser(), "Steve still admin after the login")

-- 4. the list is saved and comes back after a server restart; admins are admin again on join
local filename = AutoAdmin:getFilename()
check(FILES[filename] ~= nil, "admins.xml written")
check(FILES[filename]["autoAdmin.players.player(0)#role"] == "superAdmin", "Chris saved as superAdmin")
check(FILES[filename]["autoAdmin.players.player(0)#uniqueUserId"] == "uid-chris", "unique id saved")
um = start()
check(#AutoAdmin.players == 2, "2 players loaded after restart")
CLOCK_DATE = "2026-11-19 18:00"
chris, chrisConn = join(um, "Chris", "uid-chris")
steve, steveConn = join(um, "Steve", "uid-steve")
check(chris:getIsMasterUser(), "super admin made admin on join")
check(steve:getIsMasterUser(), "admin made admin on join")
check(entryFor("Steve").restored == 1, "restored counted")
check(entryFor("Steve").lastSeen == "2026-11-19 18:00", "last joined updated")
check(lastSent(steveConn, AutoAdminNoticeEvent).key == "aa_notice_welcomeAdmin", "welcome back notice")
check(entryFor("Steve").role == ROLE.ADMIN, "our own grant does not change the role")

-- 5. a member can't open the screen; an admin can look but not change
local bob, bobConn = join(um, "Bob", "uid-bob")
AutoAdmin:onRequest(bobConn, ACTION.OPEN, 0, 0)
check(lastSent(bobConn, AutoAdminNoticeEvent).key == "aa_error_notAdmin", "member refused")
local data = request(steveConn, ACTION.OPEN)
check(data ~= nil and data.data.canManage == false, "admin can look, not manage")
check(#data.data.entries == 3, "admin sees 3 players")
check(data.data.entries[1].name == "Chris" and data.data.entries[1].role == ROLE.SUPER, "super admins first")
data = request(steveConn, ACTION.SET_ROLE, entryFor("Bob").id, ROLE.ADMIN)
check(data.data.message == "aa_error_superOnly", "admin can't change roles")
check(entryFor("Bob").role == ROLE.MEMBER, "Bob still member")

-- 6. the super admin promotes Bob; Bob gets admin right away and every open screen updates
data = request(chrisConn, ACTION.OPEN)
check(data.data.canManage == true, "super admin can manage")
check(data.data.entries[1].isYou == true, "Chris sees himself marked")
steveConn.sent = {}
data = request(chrisConn, ACTION.SET_ROLE, entryFor("Bob").id, ROLE.ADMIN)
check(data.data.message == "aa_result_admin|Bob", "result: Bob is admin")
check(entryFor("Bob").role == ROLE.ADMIN, "Bob admin on the list")
check(bob:getIsMasterUser(), "Bob admin now")
check(lastSent(bobConn, AutoAdminNoticeEvent).key == "aa_notice_promoted", "Bob told")
check(lastSent(steveConn, AutoAdminDataEvent) ~= nil, "Steve's open screen updated")

-- 7. demoting: rights gone right away, and the password can't bring them back
BROADCASTS = {}
data = request(chrisConn, ACTION.SET_ROLE, entryFor("Bob").id, ROLE.MEMBER)
check(entryFor("Bob").role == ROLE.MEMBER and entryFor("Bob").locked, "Bob member and locked")
check(not bob:getIsMasterUser(), "Bob's admin rights removed")
check(#BROADCASTS == 1 and BROADCASTS[1].userId == bob:getId(), "revoke sent to every client")
check(lastSent(bobConn, AutoAdminNoticeEvent).key == "aa_notice_demoted", "Bob told he was demoted")
um:addMasterUserByConnection(bobConn)
check(bob:getIsMasterUser(), "password login works for a moment")
AutoAdmin:update(AutoAdmin.REVOKE_DELAY + 1)
check(not bob:getIsMasterUser(), "locked-out password login undone")
check(entryFor("Bob").role == ROLE.MEMBER, "Bob stays member")
check(lastSent(bobConn, AutoAdminNoticeEvent).key == "aa_notice_lockedOut", "Bob told he is locked out")

-- 8. promoting again unlocks
request(chrisConn, ACTION.SET_ROLE, entryFor("Bob").id, ROLE.ADMIN)
check(not entryFor("Bob").locked and bob:getIsMasterUser(), "promoted again: unlocked and admin")
request(chrisConn, ACTION.SET_ROLE, entryFor("Bob").id, ROLE.MEMBER)

-- 9. super admins can't be changed in the game, not even by another super admin
request(chrisConn, ACTION.SET_ROLE, entryFor("Steve").id, ROLE.SUPER)
check(entryFor("Steve").role == ROLE.SUPER, "Steve made super admin")
data = request(steveConn, ACTION.SET_ROLE, entryFor("Chris").id, ROLE.MEMBER)
check(data.data.message == "aa_error_superFixed", "super admin can't be demoted")
check(entryFor("Chris").role == ROLE.SUPER and chris:getIsMasterUser(), "Chris untouched")

-- 10. forgetting: only offline members
data = request(chrisConn, ACTION.FORGET, entryFor("Bob").id)
check(data.data.message == "aa_error_forget", "online member can't be forgotten")
leave(um, bob)
data = request(chrisConn, ACTION.FORGET, entryFor("Bob").id)
check(data.data.message == "aa_result_forgotten|Bob" and entryFor("Bob") == nil, "offline member forgotten")
data = request(chrisConn, ACTION.FORGET, entryFor("Steve").id)
check(entryFor("Steve") ~= nil, "super admin can't be forgotten")

-- 11. remember password logins off: a member's password login is only for this session
request(chrisConn, ACTION.SET_REMEMBER, 0, 0)
check(AutoAdmin.settings.rememberPasswordLogins == false, "setting off")
local dave = join(um, "Dave", "uid-dave")
passwordLogin(um, dave)
check(dave:getIsMasterUser() and entryFor("Dave").role == ROLE.MEMBER, "admin this session, still member")
um = start()
check(AutoAdmin.settings.rememberPasswordLogins == false, "setting saved")

-- 12. the listen-server host is never put on the list, and may manage
local hostConn = Connection.new(true)
local host = User.new("Host", "uid-host", hostConn)
table.insert(um.users, host)
um:addMasterUser(host)
check(entryFor("Host") == nil, "host not on the list")
check(AutoAdmin:getAccess(hostConn) == 2, "host may manage")

-- 13. the data event survives the trip over the network
local event = AutoAdminDataEvent.new({canManage = true, rememberPasswordLogins = false, message = "x|y",
    entries = AutoAdmin:buildList(nil)})
STREAM = {data = {}, pos = 0}
event:writeStream(STREAM, nil)
local copy = AutoAdminDataEvent.emptyNew()
local received
local oldOnData = AutoAdmin.onData
AutoAdmin.onData = function(d) received = d end
copy:readStream(STREAM, {getIsServer = function() return true end})
AutoAdmin.onData = oldOnData
check(received ~= nil and #received.entries == #AutoAdmin.players, "data event round trip")
check(received.entries[1].name == "Chris" and received.message == "x|y", "data event content")
check(STREAM.pos == #STREAM.data, "data event read all it wrote")

-- 14. the client side takes admin away from the demoted player
newMission(false)
local me = User.new("Me", "uid-me", nil)
g_currentMission.playerUserId = me.id
table.insert(g_currentMission.userManager.users, me)
g_currentMission.userManager:addMasterUser(me)
g_currentMission.isMasterUser = true
AutoAdmin.onRevoke(me.id)
check(not me:getIsMasterUser() and g_currentMission.isMasterUser == false, "client: admin removed locally")

print(string.format("%d checks passed, %d failed", passed, failed))
return failed
