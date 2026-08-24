--[[
双向词典释义滤镜 (dict_comment_filter.lua)

功能：
1. 输入中文字词时，在候选词 comment 中显示对应英文释义（基于 CC-CEDICT 词典）。
2. 输入英文单词时，在候选词 comment 中显示对应中文释义（基于 ECDICT 词典）。
3. 释义数量限制（按释义项个数截断，如保留前 2 条释义，超出追加省略号“…”）。
4. 安全 UTF-8 分割：杜绝全角标点字节碰撞导致的汉字乱码（黑框问号）。
5. 全局单例缓存（Singleton Cache）：多软件切换零延迟。
6. 与现有候选 comment（错音错字提示、Emoji、拆字编码等）无缝共存。
--]]

local M = {}

-- 全局单例缓存：避免每次切换应用/新建 Session 时重复解析大词典导致卡顿
local global_ecdict = nil
local global_cedict = nil
local is_dict_loaded = false

local function load_opencc_dict(name)
    local ok, obj = pcall(Opencc, name)
    if ok and obj then return obj end
    local ok2, obj2 = pcall(Opencc, "opencc/" .. name)
    if ok2 and obj2 then return obj2 end
    return nil
end

local function init_global_dicts()
    if is_dict_loaded then return end
    is_dict_loaded = true
    global_ecdict = load_opencc_dict("ecdict.json")
    global_cedict = load_opencc_dict("cedict.json")
end

local function is_english(s)
    if not s or s == "" then return false end
    return s:match("^[%a%-%'%s%.%d]+$") ~= nil
end

local function is_chinese(s)
    if not s or s == "" then return false end
    for i = 1, #s do
        if s:byte(i) > 127 then
            return true
        end
    end
    return false
end

-- 按照释义项个数截断，安全处理 UTF-8 字符
local function format_by_count(def_str, max_defs, max_length, is_en_to_zh)
    if not def_str or def_str == "" then return "" end

    -- 将全角分号、逗号、顿号安全替换为单字节 ASCII 分号，彻底杜绝 Lua 字符集字节碰撞撕裂汉字编码（如“里”字乱码）
    local safe_str = def_str:gsub("；", ";"):gsub("，", ";"):gsub("、", ";"):gsub(",", ";")
    local items = {}
    for item in safe_str:gmatch("([^;]+)") do
        local trimmed = item:gsub("^[%s\194\160]+", ""):gsub("[%s\194\160]+$", "")
        if trimmed ~= "" then
            table.insert(items, trimmed)
        end
    end

    local result = ""
    local has_more = false

    if #items == 0 then
        result = def_str
    elseif #items <= max_defs then
        result = table.concat(items, is_en_to_zh and "；" or "; ")
    else
        local selected = {}
        for i = 1, max_defs do
            table.insert(selected, items[i])
        end
        result = table.concat(selected, is_en_to_zh and "；" or "; ")
        has_more = true
    end

    -- 字符长度安全兜底（使用标准 UTF-8 字符计数与截断）
    if max_length and max_length > 0 then
        local ulen = utf8.len(result)
        if ulen and ulen > max_length then
            local byte_offset = utf8.offset(result, max_length + 1)
            if byte_offset then
                result = result:sub(1, byte_offset - 1)
                has_more = true
            end
        elseif not ulen and #result > max_length then
            result = result:sub(1, max_length)
            has_more = true
        end
    end

    if has_more then
        result = result .. "…"
    end

    return result
end

local function lookup(opencc_obj, key)
    if not opencc_obj or not key or key == "" then return nil end
    local ok, res = pcall(function() return opencc_obj:convert_word(key) end)
    if ok and res then
        if type(res) == "table" and #res > 0 then
            local joined = table.concat(res, " ")
            if joined ~= key and joined ~= "" then
                return joined
            end
        elseif type(res) == "string" and res ~= key and res ~= "" then
            return res
        end
    end

    local ok2, txt = pcall(function() return opencc_obj:convert_text(key) end)
    if ok2 and type(txt) == "string" and txt ~= key and txt ~= "" then
        return txt
    end
    return nil
end

function M.init(env)
    local config = env.engine.schema.config
    local ns = env.name_space:gsub("^*", "")
    if ns == "" then ns = "dict_comment_filter" end

    -- 开关配置
    env.enable_c2e = config:get_bool(ns .. "/enable_chinese_to_english")
    if env.enable_c2e == nil then env.enable_c2e = true end

    env.enable_e2c = config:get_bool(ns .. "/enable_english_to_chinese")
    if env.enable_e2c == nil then env.enable_e2c = true end

    -- 释义显示项数（默认保留前 2 条释义）
    env.max_defs = config:get_int(ns .. "/max_defs") or 2
    -- 最大字符长度安全兜底（默认 45 字符）
    env.max_length = config:get_int(ns .. "/max_length") or 45

    -- 释义前缀/后缀
    env.comment_prefix = config:get_string(ns .. "/comment_prefix") or " "
    env.comment_suffix = config:get_string(ns .. "/comment_suffix") or ""

    -- 确保全局单例字典已加载（仅在进程初次调用时加载一次）
    init_global_dicts()
    env.ecdict = global_ecdict
    env.cedict = global_cedict
end

function M.func(input, env)
    local context = env.engine.context
    -- 支持通过快捷键或方案菜单全局开关词典释义 (dict_comment)
    local is_dict_on = context:get_option("dict_comment")
    if is_dict_on == false then
        for cand in input:iter() do
            yield(cand)
        end
        return
    end

    for cand in input:iter() do
        local text = cand.text
        local raw_def = nil
        local is_e2c = false

        if env.enable_e2c and env.ecdict and is_english(text) then
            -- 英译中：优先转为小写查询，若未命中则查原词
            local lower_text = text:lower():gsub("^%s+", ""):gsub("%s+$", "")
            raw_def = lookup(env.ecdict, lower_text) or lookup(env.ecdict, text)
            is_e2c = true
        elseif env.enable_c2e and env.cedict and is_chinese(text) then
            -- 中译英
            local clean_text = text:gsub("^%s+", ""):gsub("%s+$", "")
            raw_def = lookup(env.cedict, clean_text)
            is_e2c = false
        end

        if raw_def and raw_def ~= "" then
            local formatted_def = format_by_count(raw_def, env.max_defs, env.max_length, is_e2c)
            if formatted_def ~= "" then
                local formatted = env.comment_prefix .. formatted_def .. env.comment_suffix
                if cand.comment and cand.comment ~= "" then
                    cand.comment = cand.comment .. formatted
                else
                    local prefix = env.comment_prefix:match("^%s*(.-)$") or ""
                    cand.comment = prefix .. formatted_def .. env.comment_suffix
                end
            end
        end

        yield(cand)
    end
end

return M
