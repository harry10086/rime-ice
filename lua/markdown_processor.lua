-- lua/markdown_processor.lua
-- Markdown 成对符号与代码块上屏后光标自动居中处理器
-- 实现机制:
--   1. 在 M.func 中拦截 Markdown 状态下的符号输入，阻止 punctuator 干扰
--   2. 通过轻量级原生模块 rime_cursor.dll (package.loadlib) 在内存中异步微调光标
--   3. 零子进程、零 cmd 弹窗、零轮询守护、零卡顿！

local M = {}

-- 成对符号与需要左移回退的光标步数映射表
local PAIR_OFFSETS = {
    ["****"] = 2,           -- 粗体 **|**
    ["**"] = 1,             -- 斜体 *|*
    ["******"] = 3,         -- 粗斜体 ***|***
    ["~~~~"] = 2,           -- 删除线 ~~|~~
    ["~~"] = 1,             -- 下标 ~|~
    ["===="] = 2,           -- 高亮 ==|==
    ["++"] = 1,             -- 下划线 +|+
    ["++++"] = 2,           -- 下划线 ++|++
    ["^^"] = 1,             -- 上标 ^|^
    ["^^^^"] = 2,           -- 上标 ^^|^^
    ["$$"] = 1,             -- 行内公式 $|$
    ["$$  $$"] = 3,         -- 块级公式 $$ | $$
    ["[]()"] = 3,           -- 超链接 [|]()
    ["![]()"] = 3,          -- 插入图片 ![|]()
    ["[[]]"] = 2,           -- 双链 [[|]]
    ["![[]]"] = 2,          -- 嵌入双链 ![[|]]
    ["[^1]"] = 1,           -- 脚注引用 [^|]
    ["``"] = 1,             -- 行内代码 `|`
    ["<kbd></kbd>"] = 6,    -- <kbd>|</kbd>
    ["<u></u>"] = 4,        -- <u>|</u>
    ["<!--  -->"] = 4,      -- <!-- | -->
}

local cursor_mod = nil
local cursor_mod_loaded = false

-- 加载原生光标移动模块 rime_cursor.dll
local function get_cursor_mod()
    if cursor_mod_loaded then return cursor_mod end
    cursor_mod_loaded = true

    local user_dir = nil
    pcall(function()
        if rime_api and rime_api.get_user_data_dir then
            user_dir = rime_api:get_user_data_dir()
        end
    end)
    if not user_dir or user_dir == "" then
        local appdata = os.getenv("APPDATA")
        if appdata and appdata ~= "" then
            user_dir = appdata .. "\\Rime"
        end
    end

    local search_paths = {}
    if user_dir then
        table.insert(search_paths, user_dir .. "\\others\\script\\rime_cursor.dll")
    end
    table.insert(search_paths, "others/script/rime_cursor.dll")

    for _, p in ipairs(search_paths) do
        local f = package.loadlib(p, "luaopen_rime_cursor")
        if f then
            local ok, mod = pcall(f)
            if ok and mod and type(mod.move_left) == "function" then
                cursor_mod = mod
                return cursor_mod
            end
        end
    end

    return nil
end

-- 获取给定上屏文本的光标回退步数
local function get_offset_for_text(text)
    if not text or text == "" then return 0 end
    if PAIR_OFFSETS[text] then
        return PAIR_OFFSETS[text]
    end
    -- 匹配代码块: ```lang  ``` 或 ```  ``` (回退到最后3个反引号之前)
    if #text >= 6 and text:sub(1, 3) == "```" and text:sub(-3) == "```" then
        return 3
    end
    return 0
end

-- 异步移动光标
local function move_cursor_left(offset)
    if not offset or offset <= 0 then return end
    local mod = get_cursor_mod()
    if mod and mod.move_left then
        pcall(mod.move_left, offset)
    end
end

function M.init(env)
    local config = env.engine.schema.config
    local ns = env.name_space:gsub("^*", "")
    if ns == "" then ns = "markdown" end
    env.enable_auto_cursor = config:get_bool(ns .. "/enable_auto_cursor")
    if env.enable_auto_cursor == nil then env.enable_auto_cursor = true end

    -- 预热加载原生模块
    get_cursor_mod()

    -- commit_notifier 监听所有上屏事件
    env.commit_notifier = env.engine.context.commit_notifier:connect(function(ctx)
        if not env.enable_auto_cursor then return end
        local commit_text = ctx:get_commit_text()
        if not commit_text or commit_text == "" then return end

        local offset = get_offset_for_text(commit_text)
        if offset and offset > 0 then
            move_cursor_left(offset)
        end
    end)
end

function M.fini(env)
    if env.commit_notifier then
        pcall(function() env.commit_notifier:disconnect() end)
    end
end

-- 按键处理器 (不拦截按键，由 key_binder/selector 正常处理翻页、选字及字符输入)
function M.func(key, env)
    return 2 -- kNoop
end

return M
