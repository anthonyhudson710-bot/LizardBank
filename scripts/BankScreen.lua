-- GIANTS owns GUI input contexts, focus dispatch and cursor restoration.
BankScreen = {}
local BankScreen_mt = Class(BankScreen, ScreenElement)
local MOD_NAME = g_currentModName

function BankScreen.new(owner, customMt)
    local self = ScreenElement.new(nil, customMt or BankScreen_mt)
    self.owner = owner
    self.pages = {}
    self.pageIndex = 1
    return self
end

function BankScreen:onGuiSetupFinished()
    BankScreen:superClass().onGuiSetupFinished(self)
    local buttons = {self.backButton, self.previousButton, self.nextButton, self.refreshButton, self.policyButton}
    for index, button in ipairs(buttons) do
        FocusManager:linkElements(button, FocusManager.LEFT, buttons[(index - 2) % #buttons + 1])
        FocusManager:linkElements(button, FocusManager.RIGHT, buttons[index % #buttons + 1])
    end
end

function BankScreen:onOpen()
    BankScreen:superClass().onOpen(self)
    self.pageIndex = 1
    self:onClickRefresh()
    FocusManager:setFocus(self.refreshButton)
end

function BankScreen:onClose()
    self.pages = {}
    self.pageIndex = 1
    BankScreen:superClass().onClose(self)
end

function BankScreen:onClickBack()
    if self.isBackAllowed then
        self:changeScreen(nil)
    end
    return true
end

function BankScreen:onClickRefresh()
    if self.owner == nil then return true end
    local ok, result = pcall(function()
        local snapshot = self.owner:captureSnapshot()
        if self.policyButton ~= nil then
            local mode = snapshot.history and snapshot.history.mode or "standard"
            self.policyButton:setText(BankReport.getText(g_i18n, "lb_policyButton", MOD_NAME,
                BankReport.getText(g_i18n, "lb_mode_" .. mode, MOD_NAME)))
        end
        return BankReport.buildPages(snapshot, g_i18n, MOD_NAME)
    end)
    if ok then
        self.pages = result
    else
        -- Preserve neither stale figures nor a misleading successful timestamp.
        self.pages = {{title = BankReport.getText(g_i18n, "lb_title", MOD_NAME),
            text = BankReport.getText(g_i18n, "lb_error", MOD_NAME)}}
        Logging.error("[LizardBank] Report refresh failed: %s", tostring(result))
    end
    self.pageIndex = math.max(1, math.min(self.pageIndex, #self.pages))
    self:showPage()
    return true
end

function BankScreen:onClickPolicy()
    if self.owner ~= nil and type(self.owner.cyclePolicy) == "function" then self.owner:cyclePolicy() end
    return self:onClickRefresh()
end

function BankScreen:showPage()
    local page = self.pages[self.pageIndex]
    if page == nil then return end
    self.pageTitle:setText(page.title)
    self.reportText:setText(page.text)
    self.pageNumber:setText(BankReport.getText(g_i18n, "lb_page", MOD_NAME, self.pageIndex, #self.pages))
    -- Keep controls focusable at boundaries; a focused button disappearing or
    -- disabling after navigation can otherwise strand controller focus.
end

function BankScreen:onClickPrevious()
    self.pageIndex = math.max(1, self.pageIndex - 1)
    self:showPage()
    return true
end

function BankScreen:onClickNext()
    self.pageIndex = math.min(#self.pages, self.pageIndex + 1)
    self:showPage()
    return true
end

function BankScreen:delete()
    self.owner = nil
    self.pages = {}
    BankScreen:superClass().delete(self)
end
