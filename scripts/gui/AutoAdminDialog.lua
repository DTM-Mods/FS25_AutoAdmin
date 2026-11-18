-- Auto Admin: the admin screen (Left Alt + A). Lists every player the server has seen with their role.
-- Super admins promote / demote players and change the server setting; admins can only look.
-- Every change goes to the server (AutoAdminRequestEvent); the server answers with the new list (AutoAdminDataEvent),
-- which also reaches every other admin who has the screen open.
-- Author: Fennell

AutoAdminDialog = {}
local AutoAdminDialog_mt = Class(AutoAdminDialog, MessageDialog)

AutoAdminDialog.NAME = "AutoAdminDialog"

local ROLE = AutoAdmin.ROLE
local ACTION = AutoAdmin.ACTION

local function getText(key)
    return AutoAdmin.getText(key)
end

function AutoAdminDialog.new(target, customMt)
    local self = MessageDialog.new(target, customMt or AutoAdminDialog_mt)
    self.entries = {}
    self.data = nil
    self.selectedId = nil
    return self
end

function AutoAdminDialog.register()
    local dialog = AutoAdminDialog.new()
    g_gui:loadGui(AutoAdmin.modDirectory .. "gui/AutoAdminDialog.xml", AutoAdminDialog.NAME, dialog)
    AutoAdminDialog.instance = dialog
end

function AutoAdminDialog.show()
    if AutoAdminDialog.instance ~= nil then
        g_gui:showDialog(AutoAdminDialog.NAME)
    end
end

function AutoAdminDialog.isOpen()
    local dialog = AutoAdminDialog.instance
    return dialog ~= nil and dialog.aaIsOpen == true
end

function AutoAdminDialog:onGuiSetupFinished()
    AutoAdminDialog:superClass().onGuiSetupFinished(self)
    self.playerList:setDataSource(self)
    self.playerList:setDelegate(self)
    AutoAdminGui.applyStaticImages(self.dialogElement)
    AutoAdminGui.setIcon(self.detailAvatarIcon, "user")
    AutoAdminGui.setIcon(self.rememberPill, "solid")
end

function AutoAdminDialog:onOpen()
    AutoAdminDialog:superClass().onOpen(self)
    self.aaIsOpen = true
    self.data = nil
    self.entries = {}
    self.statusText:setText("")
    self:updateAll()
    self.playerList:reloadData()
    FocusManager:setFocus(self.playerList)
    AutoAdmin.sendRequest(ACTION.OPEN)
end

function AutoAdminDialog:onClose()
    AutoAdminDialog:superClass().onClose(self)
    self.aaIsOpen = false
    AutoAdmin.sendRequest(ACTION.CLOSE)
end

-- the server sent the list (on open, after every change)
function AutoAdminDialog:setData(data)
    if not self.aaIsOpen then
        return
    end
    self.data = data
    self.entries = data.entries
    local index = 1
    for i, entry in ipairs(self.entries) do
        if entry.id == self.selectedId then
            index = i
        end
    end
    self.playerList:reloadData()
    if #self.entries > 0 and self.playerList.setSelectedIndex ~= nil then
        self.playerList:setSelectedIndex(index)
    end
    self:setSelected(self.entries[index])
    if data.message ~= "" then
        self.statusText:setText(AutoAdmin.formatMessage(data.message))
    end
end

function AutoAdminDialog:getSelected()
    for _, entry in ipairs(self.entries) do
        if entry.id == self.selectedId then
            return entry
        end
    end
    return nil
end

function AutoAdminDialog:setSelected(entry)
    self.selectedId = entry ~= nil and entry.id or nil
    self:updateAll()
end

----------------------------------------------------------------------------------------------------------------
-- List
----------------------------------------------------------------------------------------------------------------

function AutoAdminDialog:getNumberOfItemsInSection(list, section)
    return #self.entries
end

local function getStatusText(entry)
    local parts = {}
    if entry.isYou then
        table.insert(parts, getText("aa_status_you"))
    end
    if entry.online then
        table.insert(parts, entry.isAdminNow and getText("aa_status_onlineAdmin") or getText("aa_status_online"))
    else
        table.insert(parts, getText("aa_status_offline"))
    end
    if entry.locked then
        table.insert(parts, getText("aa_status_locked"))
    end
    return table.concat(parts, "  ·  ")
end

local function splitDate(value)
    if value == nil or value == "" then
        return "-", ""
    end
    local day, time = value:match("^(%S+)%s+(%S+)$")
    return day or value, time or ""
end

function AutoAdminDialog:populateCellForItemInSection(list, section, index, cell)
    AutoAdminGui.applyStaticImages(cell)
    local entry = self.entries[index]
    if entry == nil then
        return
    end
    local roleColor = AutoAdminGui.ROLE_COLOR[entry.role]

    local tile = cell:getAttribute("avatarTile")
    AutoAdminGui.setIcon(tile, "tile")
    local icon = cell:getAttribute("avatarIcon")
    AutoAdminGui.setIcon(icon, AutoAdminGui.ROLE_ICON[entry.role])
    AutoAdminGui.setColor(icon, roleColor)

    local dot = cell:getAttribute("onlineDot")
    AutoAdminGui.setIcon(dot, "circle")
    AutoAdminGui.setColor(dot, entry.online and "online" or "offline")

    cell:getAttribute("name"):setText(entry.name)
    cell:getAttribute("sub"):setText(getStatusText(entry))

    local badgeBg = cell:getAttribute("badgeBg")
    AutoAdminGui.setIcon(badgeBg, "solid")
    AutoAdminGui.setColor(badgeBg, roleColor, 0.16)
    local badge = cell:getAttribute("badge")
    badge:setText(getText(AutoAdminGui.ROLE_TEXT[entry.role]))
    AutoAdminGui.setTextColor(badge, roleColor)

    local day, time = splitDate(entry.lastSeen)
    cell:getAttribute("lastDate"):setText(day)
    cell:getAttribute("lastTime"):setText(time)
end

function AutoAdminDialog:onListSelectionChanged(list, section, index)
    local entry = self.entries[index]
    if entry ~= nil and entry.id ~= self.selectedId then
        self:setSelected(entry)
    end
end

----------------------------------------------------------------------------------------------------------------
-- Header, details, setting, buttons
----------------------------------------------------------------------------------------------------------------

function AutoAdminDialog:updateAll()
    self:updateHeader()
    self:updateDetails()
    self:updateSetting()
    self:updateButtons()
end

function AutoAdminDialog:updateHeader()
    local counts = {[ROLE.SUPER] = 0, [ROLE.ADMIN] = 0, [ROLE.MEMBER] = 0}
    local online = 0
    for _, entry in ipairs(self.entries) do
        counts[entry.role] = (counts[entry.role] or 0) + 1
        if entry.online then
            online = online + 1
        end
    end
    local loaded = self.data ~= nil
    self.statSuper:setText(loaded and tostring(counts[ROLE.SUPER]) or "-")
    self.statAdmin:setText(loaded and tostring(counts[ROLE.ADMIN]) or "-")
    self.statMember:setText(loaded and tostring(counts[ROLE.MEMBER]) or "-")
    if loaded then
        self.subtitleText:setText(string.format(getText("aa_subtitle"), online, #self.entries))
    else
        self.subtitleText:setText(getText("aa_loading"))
    end
    self.loadingText:setVisible(not loaded)
    self.emptyText:setVisible(loaded and #self.entries == 0)
end

local function getChangedByText(entry)
    local by = entry.changedBy
    if by == AutoAdmin.BY.PASSWORD then
        return getText("aa_by_password")
    elseif by == AutoAdmin.BY.FIRST then
        return getText("aa_by_first")
    elseif by == AutoAdmin.BY.PLAYER then
        return entry.changedByName ~= "" and entry.changedByName or "-"
    elseif by == AutoAdmin.BY.FILE then
        return getText("aa_by_file")
    end
    return "-"
end

function AutoAdminDialog:updateDetails()
    local entry = self:getSelected()
    local hasEntry = entry ~= nil
    self.detailBox:setVisible(hasEntry)
    self.detailEmpty:setVisible(not hasEntry and self.data ~= nil and #self.entries > 0)
    if not hasEntry then
        return
    end
    local roleColor = AutoAdminGui.ROLE_COLOR[entry.role]
    AutoAdminGui.setIcon(self.detailAvatarIcon, AutoAdminGui.ROLE_ICON[entry.role])
    AutoAdminGui.setColor(self.detailAvatarIcon, roleColor)
    AutoAdminGui.setColor(self.detailAccent, roleColor)
    self.detailName:setText(entry.name)
    self.detailRole:setText(getText(AutoAdminGui.ROLE_TEXT[entry.role]))
    AutoAdminGui.setTextColor(self.detailRole, roleColor)

    self.valStatus:setText(getStatusText(entry))
    self.valFirstSeen:setText(entry.firstSeen ~= "" and entry.firstSeen or "-")
    self.valLastSeen:setText(entry.lastSeen ~= "" and entry.lastSeen or "-")
    self.valChanged:setText(entry.changed ~= "" and entry.changed or "-")
    self.valChangedBy:setText(getChangedByText(entry))
    self.valRestored:setText(tostring(entry.restored))

    local note = ""
    if entry.role == ROLE.SUPER then
        note = getText("aa_note_superFixed")
    elseif entry.locked then
        note = getText("aa_note_locked")
    end
    self.detailNote:setText(note)
end

function AutoAdminDialog:updateSetting()
    local data = self.data
    local on = data ~= nil and data.rememberPasswordLogins
    self.rememberPillText:setText(getText(on and "aa_on" or "aa_off"))
    AutoAdminGui.setColor(self.rememberPill, on and "green" or "off")
    AutoAdminGui.setTextColor(self.rememberPillText, on and "night" or "white")
    local canManage = data ~= nil and data.canManage
    self.rememberButton:setDisabled(not canManage)
    if data == nil then
        self.permissionNote:setText("")
    else
        self.permissionNote:setText(getText(canManage and "aa_note_super" or "aa_note_viewOnly"))
    end
end

local function setButton(button, separator, visible, text)
    button:setVisible(visible)
    button:setDisabled(not visible)
    if text ~= nil then
        button:setText(text)
    end
    if separator ~= nil then
        separator:setVisible(visible)
    end
end

function AutoAdminDialog:updateButtons()
    local entry = self:getSelected()
    local canManage = self.data ~= nil and self.data.canManage
    local primary, primaryText = false, nil
    local super = false
    local forget = false
    if canManage and entry ~= nil and entry.role ~= ROLE.SUPER then
        primary = true
        primaryText = getText(entry.role == ROLE.ADMIN and "aa_button_demote" or "aa_button_promote")
        super = true
        forget = entry.role == ROLE.MEMBER and not entry.online
    end
    setButton(self.primaryButton, self.primarySeparator, primary, primaryText)
    setButton(self.superButton, self.superSeparator, super, getText("aa_button_super"))
    setButton(self.forgetButton, self.forgetSeparator, forget, getText("aa_button_forget"))
    if self.buttonBox ~= nil and self.buttonBox.invalidateLayout ~= nil then
        self.buttonBox:invalidateLayout()
    end
end

----------------------------------------------------------------------------------------------------------------
-- Actions (each asks first; the server checks the rights again)
----------------------------------------------------------------------------------------------------------------

function AutoAdminDialog:confirm(text, action, entryId, value)
    self.pendingRequest = {action = action, entryId = entryId, value = value}
    YesNoDialog.show(self.onConfirmAnswer, self, text, getText("aa_title"))
end

function AutoAdminDialog:onConfirmAnswer(yes)
    local request = self.pendingRequest
    self.pendingRequest = nil
    if yes and request ~= nil then
        self.statusText:setText(getText("aa_sending"))
        AutoAdmin.sendRequest(request.action, request.entryId, request.value)
    end
end

function AutoAdminDialog:onClickPrimary()
    local entry = self:getSelected()
    if entry == nil or self.data == nil or not self.data.canManage or entry.role == ROLE.SUPER then
        return
    end
    if entry.role == ROLE.ADMIN then
        self:confirm(string.format(getText("aa_confirm_demote"), entry.name), ACTION.SET_ROLE, entry.id, ROLE.MEMBER)
    else
        self:confirm(string.format(getText("aa_confirm_promote"), entry.name), ACTION.SET_ROLE, entry.id, ROLE.ADMIN)
    end
end

function AutoAdminDialog:onClickSuper()
    local entry = self:getSelected()
    if entry == nil or self.data == nil or not self.data.canManage or entry.role == ROLE.SUPER then
        return
    end
    self:confirm(string.format(getText("aa_confirm_super"), entry.name), ACTION.SET_ROLE, entry.id, ROLE.SUPER)
end

function AutoAdminDialog:onClickForget()
    local entry = self:getSelected()
    if entry == nil or self.data == nil or not self.data.canManage or entry.role ~= ROLE.MEMBER or entry.online then
        return
    end
    self:confirm(string.format(getText("aa_confirm_forget"), entry.name), ACTION.FORGET, entry.id, 0)
end

function AutoAdminDialog:onClickRemember()
    if self.data == nil or not self.data.canManage then
        return
    end
    self.statusText:setText(getText("aa_sending"))
    AutoAdmin.sendRequest(ACTION.SET_REMEMBER, 0, self.data.rememberPasswordLogins and 0 or 1)
end

function AutoAdminDialog:onClickBack()
    self:close()
end
